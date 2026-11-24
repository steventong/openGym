import XCTest
@testable import OpenGYM

@MainActor private final class ScriptedResponder: AIResponder {
    var steps: [(AIRequest) async throws -> AIAssistantTurn] = []
    private(set) var requests: [AIRequest] = []
    func respond(to request: AIRequest, onText: @MainActor (String) -> Void) async throws -> AIAssistantTurn {
        requests.append(request)
        guard !steps.isEmpty else { throw AIClientError.interrupted }
        onText("…")
        return try await steps.removeFirst()(request)
    }
}

@MainActor final class AIChatTests: XCTestCase {
    private var root: URL!
    private var defaults: UserDefaults!
    private var suite: String!
    private var store: GymStore!
    private var responder: ScriptedResponder!
    private var chat: AIChatStore!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        suite = "ai-chat-" + UUID().uuidString
        defaults = UserDefaults(suiteName: suite)
        store = GymStore(userID: "local", storage: LocalTrainingStorage(root: root), defaults: defaults)
        _ = await store.mutate { _ in ["unit": "kg", "bodyweight": [["d": "2026-11-01", "w": 80, "t": 1]]] }
        try store.aiSettings.save(AIServiceSlot(), address: "", model: "m", newKey: "k")
        responder = ScriptedResponder()
        chat = AIChatStore(store: store, settings: store.aiSettings, responder: responder)
        chat.load()
    }
    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
        defaults.removePersistentDomain(forName: suite)
    }

    private func call(_ id: String, _ name: String, _ arguments: String = "{}") -> AIToolCall { AIToolCall(id: id, name: name, arguments: arguments) }
    private var weightChange: AIAssistantTurn {
        AIAssistantTurn(text: "", calls: [call("w", "log_body_weight", #"{"date":"2026-11-01","weight":79}"#)])
    }
    private var weight: Double { number((store.state["bodyweight"] as? [[String: Any]])?.first?["w"]) }
    private func send(_ text: String = "hi") { chat.input = text; chat.send() }
    private func wait(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<400 where !condition() { try? await Task.sleep(for: .milliseconds(5)) }
        XCTAssertTrue(condition(), file: file, line: line)
    }
    private var awaiting: Bool { if case .awaitingApproval = chat.phase { true } else { false } }
    private var failed: Bool { if case .failed = chat.phase { true } else { false } }
    private var results: [AIToolResult] { chat.messages.flatMap { message -> [AIToolResult] in
        guard case let .toolResults(list) = message.content else { return [] }
        return list
    } }

    func testQueriesRunWithoutConfirmationAndLoopContinues() async {
        responder.steps = [{ _ in AIAssistantTurn(text: "看看", calls: [self.call("a", "get_overview"), self.call("b", "list_routines")]) }, { _ in AIAssistantTurn(text: "好了") }]
        send()
        await wait { !chat.isBusy }
        XCTAssertEqual(results.map(\.outcome), [.completed, .completed])
        XCTAssertEqual(responder.requests.count, 2)
        XCTAssertEqual(responder.requests[1].messages.count, 3)
        XCTAssertEqual(chat.messages.last?.content, .assistant(AIAssistantTurn(text: "好了")))
    }

    func testEditWaitsForConfirmationThenSaves() async {
        responder.steps = [{ _ in self.weightChange }, { _ in AIAssistantTurn(text: "已改") }]
        send()
        await wait { awaiting }
        XCTAssertEqual(weight, 80, "确认前不写入")
        XCTAssertEqual(responder.requests.count, 1)
        chat.decide(.confirmed)
        chat.decide(.confirmed)
        await wait { !chat.isBusy }
        XCTAssertEqual(weight, 79)
        XCTAssertEqual(results.first?.outcome, .completed)
        XCTAssertEqual(results.first?.summary?.changes.first?.after, "79 kg")
    }

    func testDecliningTellsModelAndKeepsData() async {
        responder.steps = [{ _ in self.weightChange }, { _ in AIAssistantTurn(text: "好的，不改") }]
        send()
        await wait { awaiting }
        chat.decide(.declined)
        await wait { !chat.isBusy }
        XCTAssertEqual(weight, 80)
        XCTAssertEqual(results.first?.outcome, .declined)
        XCTAssertEqual(responder.requests.count, 2)
    }

    func testStoppingAtConfirmationClosesEveryCall() async {
        responder.steps = [{ _ in AIAssistantTurn(text: "", calls: self.weightChange.calls + [self.call("z", "get_overview")]) }]
        send()
        await wait { awaiting }
        chat.stop()
        await wait { !chat.isBusy }
        XCTAssertEqual(weight, 80)
        XCTAssertEqual(results.map(\.callID), ["w", "z"])
        XCTAssertEqual(Set(results.map(\.outcome)), [.cancelled])
        // 停止后可以继续对话。
        responder.steps = [{ _ in AIAssistantTurn(text: "继续") }]
        send()
        await wait { !chat.isBusy }
        XCTAssertFalse(failed)
    }

    func testInvalidToolCallIsReportedBackToModel() async {
        responder.steps = [{ _ in AIAssistantTurn(text: "", calls: [self.call("a", "log_body_weight", #"{"date":"x"}"#)]) }, { _ in AIAssistantTurn(text: "抱歉") }]
        send()
        await wait { !chat.isBusy }
        XCTAssertEqual(results.first?.outcome, .failed)
        XCTAssertEqual(results.first?.content.hasPrefix("Error:"), true)
        XCTAssertNil(results.first?.summary)
    }

    func testFailureCanBeRetriedWithoutDuplicatingMessage() async {
        responder.steps = [{ _ in throw AIClientError.http(500, "busy") }]
        send()
        await wait { failed }
        XCTAssertEqual(chat.messages.count, 1)
        responder.steps = [{ _ in AIAssistantTurn(text: "ok") }]
        chat.retry()
        await wait { !chat.isBusy }
        XCTAssertEqual(chat.messages.count, 2)
    }

    func testStoppingReplyKeepsVisibleText() async {
        responder.steps = [{ _ in try await Task.sleep(for: .seconds(30)); return AIAssistantTurn(text: "late") }]
        send()
        await wait { if case .responding("…") = chat.phase { true } else { false } }
        chat.stop()
        await wait { !chat.isBusy }
        XCTAssertEqual(chat.messages.last?.content, .assistant(AIAssistantTurn(text: "…")))
    }

    func testRunawayLoopStops() async {
        responder.steps = (0..<40).map { index in { _ in AIAssistantTurn(text: "", calls: [AIToolCall(id: "c\(index)", name: "get_overview", arguments: "{}")]) } }
        send()
        await wait { failed }
        XCTAssertEqual(responder.requests.count, AIChatStore.stepLimit)
    }

    func testConversationSurvivesRelaunchAndNewChatRemovesFiles() async throws {
        responder.steps = [{ _ in self.weightChange }]
        send()
        await wait { awaiting }
        // 等待确认时退出：重新打开后未完成的调用有结果，数据没有变化。
        let reopened = AIChatStore(store: store, settings: store.aiSettings, responder: responder)
        reopened.load()
        XCTAssertEqual(reopened.messages.count, 3)
        guard case let .toolResults(list) = reopened.messages[2].content else { return XCTFail("应补上结果") }
        XCTAssertEqual(list.map(\.outcome), [.cancelled])
        XCTAssertEqual(weight, 80)
        chat.stop()
        await wait { !chat.isBusy }
        chat.newChat()
        XCTAssertTrue(chat.messages.isEmpty)
        let files = try FileManager.default.contentsOfDirectory(atPath: XCTUnwrap(store.accountFolder).path)
        XCTAssertFalse(files.contains { $0.hasPrefix("ai-chat") })
    }

    func testNothingIsSentBeforeSetup() throws {
        try store.aiSettings.removeKey(store.aiSettings.currentService())
        send()
        XCTAssertTrue(chat.messages.isEmpty)
        XCTAssertTrue(responder.requests.isEmpty)
        XCTAssertEqual(chat.input, "hi", "输入保留")
    }

    func testKeyNeverEntersDocumentOrConversation() async throws {
        try store.aiSettings.save(AIServiceSlot(), address: "", model: "m", newKey: "sk-very-secret")
        responder.steps = [{ _ in AIAssistantTurn(text: "", calls: [self.call("a", "get_overview")]) }, { _ in AIAssistantTurn(text: "ok") }]
        send()
        await wait { !chat.isBusy }
        let stored = String(decoding: try JSONEncoder().encode(chat.messages), as: UTF8.self) + String(describing: store.state)
        XCTAssertFalse(stored.contains("sk-very-secret"))
        XCTAssertFalse(AIPrompt.system.contains("sk-"))
    }
}
