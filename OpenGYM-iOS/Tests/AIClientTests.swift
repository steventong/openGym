import Security
import XCTest
@testable import OpenGYM

@MainActor final class AIClientTests: XCTestCase {
    private func json(_ data: Data?) throws -> [String: Any] { try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(data)) as? [String: Any]) }
    private func service(_ kind: AIProtocolKind, _ address: AIAddressKind = .official) throws -> AIService {
        AIService(slot: AIServiceSlot(kind: kind, address: address), baseURL: try AIBaseAddress(address == .official ? kind.officialAddress : "https://relay.example.com", kind: kind).url, model: "test-model")
    }
    private func request(_ service: AIService, _ messages: [AIMessage]) -> AIRequest {
        AIRequest(service: service, key: "secret", system: "system", tools: Array(AITool.all.prefix(2)), messages: messages)
    }

    // MARK: - 地址与设置

    func testBaseAddressNormalizesPathsAndRestrictsHTTP() throws {
        func url(_ text: String, _ kind: AIProtocolKind) throws -> String { try AIBaseAddress(text, kind: kind).url.absoluteString }
        XCTAssertEqual(try url("https://relay.example.com/", .anthropic), "https://relay.example.com/v1")
        XCTAssertEqual(try url("https://relay.example.com/anthropic", .anthropic), "https://relay.example.com/anthropic/v1")
        XCTAssertEqual(try url("https://relay.example.com/v1/messages", .anthropic), "https://relay.example.com/v1")
        XCTAssertEqual(try url("https://relay.example.com", .openai), "https://relay.example.com/v1")
        XCTAssertEqual(try url("https://relay.example.com/api/v4/chat/completions", .openai), "https://relay.example.com/api/v4")
        XCTAssertEqual(try url("http://192.168.1.4:11434", .openai), "http://192.168.1.4:11434/v1")
        XCTAssertEqual(try url("http://mac.local:8080/v1", .openai), "http://mac.local:8080/v1")
        for bad in ["", "relay.example.com", "http://relay.example.com", "http://172.32.0.1", "http://10.evil.com", "https://user:pass@relay.example.com", "https://relay.example.com?x=1", "ftp://10.0.0.1"] {
            XCTAssertThrowsError(try url(bad, .openai), bad)
        }
    }

    func testEveryServiceKeepsItsOwnKeyAndNewHostNeedsNewKey() throws {
        let suite = "ai-settings-" + UUID().uuidString, defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let keys = AIMemoryKeyStore(), settings = AISettings(defaults: defaults, keys: keys)
        XCTAssertFalse(settings.isConfigured)
        XCTAssertEqual(settings.model(settings.slot), "claude-opus-5-5")
        try settings.save(AIServiceSlot(), address: "", model: "claude-opus-5-5", newKey: " sk-official \n")
        XCTAssertTrue(settings.isConfigured)
        XCTAssertEqual(try keys.read("anthropic.official"), "sk-official")

        let custom = AIServiceSlot(kind: .anthropic, address: .custom)
        XCTAssertThrowsError(try settings.save(custom, address: "https://relay.example.com", model: "m", newKey: ""), "官方 key 不能用于自定义地址")
        XCTAssertEqual(settings.slot, AIServiceSlot(), "保存失败不切换服务")
        try settings.save(custom, address: "https://relay.example.com", model: "m", newKey: "relay-key")
        try settings.save(custom, address: "https://relay.example.com/v2", model: "m2", newKey: "")
        XCTAssertThrowsError(try settings.save(custom, address: "https://other.example.com", model: "m", newKey: ""))
        XCTAssertThrowsError(try settings.save(custom, address: "https://relay.example.com", model: " ", newKey: "k"))
        XCTAssertThrowsError(try settings.save(custom, address: "https://relay.example.com", model: "m", newKey: "a\nb"))

        let reopened = AISettings(defaults: defaults, keys: keys)
        XCTAssertEqual(reopened.slot, custom)
        XCTAssertEqual(reopened.model(custom), "m2")
        XCTAssertFalse(defaults.dictionaryRepresentation().values.contains { ($0 as? String)?.contains("relay-key") == true }, "key 不进入 UserDefaults")
        try reopened.removeKey(reopened.currentService())
        XCTAssertFalse(reopened.isConfigured)
        XCTAssertEqual(try keys.read("anthropic.official"), "sk-official")
    }

    /// 两台设备共用同步的 key，但各自设置了不同主机。
    func testSyncedKeyOnlyGoesToTheHostItWasSavedFor() throws {
        let names = (0..<2).map { _ in "ai-settings-" + UUID().uuidString }, keys = AIMemoryKeyStore()
        defer { names.forEach { UserDefaults.standard.removePersistentDomain(forName: $0) } }
        let phone = AISettings(defaults: UserDefaults(suiteName: names[0])!, keys: keys)
        let tablet = AISettings(defaults: UserDefaults(suiteName: names[1])!, keys: keys)
        let custom = AIServiceSlot(kind: .openai, address: .custom)
        try phone.save(custom, address: "https://one.example.com", model: "m", newKey: "key-one")
        try tablet.save(custom, address: "https://two.example.com", model: "m", newKey: "key-two")
        XCTAssertEqual(try phone.key(phone.currentService()), "key-one")
        XCTAssertEqual(try tablet.key(tablet.currentService()), "key-two")
        for address in ["http://127.0.0.1:1", "https://one.example.com:8443", "https://one.example.com.evil.test"] {
            XCTAssertThrowsError(try tablet.save(custom, address: address, model: "m", newKey: ""), address)
        }
        XCTAssertNoThrow(try tablet.save(custom, address: "https://ONE.example.com/v1", model: "m", newKey: ""), "同一主机直接使用已同步的 key")
        XCTAssertEqual(try tablet.key(tablet.currentService()), "key-one")
    }

    func testKeychainRoundTripsReplacesAndDeletes() throws {
        let keychain = AIKeychain(), account = "test." + UUID().uuidString
        defer { try? keychain.write(nil, account: account) }
        XCTAssertNil(try keychain.read(account))
        try keychain.write("one", account: account)
        try keychain.write("two", account: account)
        XCTAssertEqual(try keychain.read(account), "two")
        let synced: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: AIKeychain.service, kSecAttrAccount: account, kSecAttrSynchronizable: true]
        XCTAssertEqual(SecItemCopyMatching(synced as CFDictionary, nil), errSecSuccess, "key 参与 iCloud 钥匙串同步")
        try keychain.write(nil, account: account)
        XCTAssertNil(try keychain.read(account))
        XCTAssertNoThrow(try keychain.write(nil, account: account))
    }

    // MARK: - 请求

    func testAnthropicBodyReplaysRawOnlyToSameOriginAndMergesRoles() throws {
        let official = try service(.anthropic), relay = try service(.anthropic, .custom)
        let raw = try JSONSerialization.data(withJSONObject: [["type": "thinking", "thinking": "", "signature": "sig"], ["type": "tool_use", "id": "t1", "name": "list_routines", "input": [String: Any]()]])
        let origin = request(official, []).origin
        let messages = [
            AIMessage(content: .user(text: "hi", context: "ctx")),
            AIMessage(content: .assistant(AIAssistantTurn(text: "", calls: [AIToolCall(id: "t1", name: "list_routines", arguments: "{}")], raw: raw, origin: origin))),
            AIMessage(content: .toolResults([AIToolResult(callID: "t1", outcome: .declined, content: "no")])),
            AIMessage(content: .user(text: "again", context: "ctx2")),
        ]
        let body = AnthropicMessages.body(request(official, messages)), list = try XCTUnwrap(body["messages"] as? [[String: Any]])
        XCTAssertEqual(list.map { $0["role"] as? String }, ["user", "assistant", "user"])
        XCTAssertEqual((list[1]["content"] as? [[String: Any]])?.first?["signature"] as? String, "sig")
        let last = try XCTUnwrap(list[2]["content"] as? [[String: Any]])
        XCTAssertEqual(last.map { $0["type"] as? String }, ["tool_result", "text", "text"])
        XCTAssertEqual(last[0]["is_error"] as? Bool, true)
        XCTAssertNil(body["thinking"]); XCTAssertNil(body["temperature"])
        let other = try XCTUnwrap(AnthropicMessages.body(request(relay, messages))["messages"] as? [[String: Any]])
        XCTAssertEqual((other[1]["content"] as? [[String: Any]])?.map { $0["type"] as? String }, ["tool_use"], "换服务后不带思考签名")
    }

    func testOpenAIBodyUsesToolMessages() throws {
        let messages = [
            AIMessage(content: .user(text: "hi", context: "ctx")),
            AIMessage(content: .assistant(AIAssistantTurn(text: "", calls: [AIToolCall(id: "c1", name: "list_routines", arguments: "{}")]))),
            AIMessage(content: .toolResults([AIToolResult(callID: "c1", outcome: .completed, content: "ok")])),
        ]
        let body = OpenAIChat.body(request(try service(.openai), messages)), list = try XCTUnwrap(body["messages"] as? [[String: Any]])
        XCTAssertEqual(list.map { $0["role"] as? String }, ["system", "user", "assistant", "tool"])
        XCTAssertEqual(list[3]["tool_call_id"] as? String, "c1")
        XCTAssertEqual((body["tools"] as? [[String: Any]])?.count, 2)
    }

    func testHeadersFollowProtocol() throws {
        let anthropic = AIHTTPClient.urlRequest(try service(.anthropic), key: "k", path: "messages")
        XCTAssertEqual(anthropic.url?.absoluteString, "https://api.anthropic.com/v1/messages")
        XCTAssertEqual(anthropic.value(forHTTPHeaderField: "x-api-key"), "k")
        XCTAssertNil(anthropic.value(forHTTPHeaderField: "Authorization"))
        let openai = AIHTTPClient.urlRequest(try service(.openai), key: "k", path: "chat/completions")
        XCTAssertEqual(openai.value(forHTTPHeaderField: "Authorization"), "Bearer k")
        XCTAssertNil(openai.value(forHTTPHeaderField: "x-api-key"))
    }

    // MARK: - 流式解析

    private func decode(_ decoder: any AIStreamDecoder, _ events: [String]) throws -> (AIAssistantTurn, String) {
        var decoder = decoder, text = ""
        for event in events { text += try decoder.consume(json(Data(event.utf8))) ?? "" }
        return (try decoder.finish(origin: "o"), text)
    }

    func testAnthropicStreamCollectsTextToolsAndThinking() throws {
        let events = [
            #"{"type":"message_start","message":{}}"#,
            #"{"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":"","signature":""}}"#,
            #"{"type":"content_block_delta","index":0,"delta":{"type":"signature_delta","signature":"abc"}}"#,
            #"{"type":"content_block_start","index":1,"content_block":{"type":"text","text":""}}"#,
            #"{"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"看"}}"#,
            #"{"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"看"}}"#,
            #"{"type":"content_block_start","index":2,"content_block":{"type":"tool_use","id":"t","name":"get_routine","input":{}}}"#,
            #"{"type":"content_block_delta","index":2,"delta":{"type":"input_json_delta","partial_json":"{\"routine"}}"#,
            #"{"type":"content_block_delta","index":2,"delta":{"type":"input_json_delta","partial_json":"_id\":\"r\"}"}}"#,
        ]
        let (turn, text) = try decode(AnthropicStreamDecoder(), events + [#"{"type":"message_delta","delta":{"stop_reason":"tool_use"}}"#])
        XCTAssertEqual(text, "看看"); XCTAssertEqual(turn.text, "看看")
        XCTAssertEqual(turn.calls, [AIToolCall(id: "t", name: "get_routine", arguments: #"{"routine_id":"r"}"#)])
        let raw = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(turn.raw)) as? [[String: Any]])
        XCTAssertEqual(raw[0]["signature"] as? String, "abc")
        XCTAssertEqual((raw[2]["input"] as? [String: Any])?["routine_id"] as? String, "r")
        XCTAssertThrowsError(try decode(AnthropicStreamDecoder(), events), "没有结束原因视为中断")
        for reason in ["refusal", "max_tokens"] {
            XCTAssertThrowsError(try decode(AnthropicStreamDecoder(), events + [#"{"type":"message_delta","delta":{"stop_reason":"\#(reason)"}}"#]), reason)
        }
        XCTAssertThrowsError(try decode(AnthropicStreamDecoder(), [#"{"type":"error","error":{"type":"overloaded_error","message":"busy"}}"#]))
    }

    func testOpenAIStreamCollectsParallelToolCalls() throws {
        let (turn, text) = try decode(OpenAIStreamDecoder(), [
            #"{"choices":[{"delta":{"role":"assistant","content":"好"}}]}"#,
            #"{"choices":[{"delta":{"tool_calls":[{"index":0,"id":"a","function":{"name":"get_routine","arguments":""}}]}}]}"#,
            #"{"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\"routine_id\":\"r\"}"}}]}}]}"#,
            #"{"choices":[{"delta":{"tool_calls":[{"index":1,"id":"b","function":{"name":"list_routines","arguments":""}}]}}]}"#,
            #"{"choices":[{"delta":{},"finish_reason":"tool_calls"}]}"#,
            #"{"choices":[],"usage":{}}"#,
        ])
        XCTAssertEqual(text, "好")
        XCTAssertEqual(turn.calls, [AIToolCall(id: "a", name: "get_routine", arguments: #"{"routine_id":"r"}"#), AIToolCall(id: "b", name: "list_routines", arguments: "{}")])
        let (unindexed, _) = try decode(OpenAIStreamDecoder(), [
            #"{"choices":[{"delta":{"tool_calls":[{"id":"a","function":{"name":"list_routines","arguments":"{}"}}]}}]}"#,
            #"{"choices":[{"delta":{"tool_calls":[{"id":"b","function":{"name":"get_overview","arguments":"{}"}}]},"finish_reason":"stop"}]}"#,
        ])
        XCTAssertEqual(unindexed.calls.map(\.id), ["a", "b"])
        XCTAssertThrowsError(try decode(OpenAIStreamDecoder(), [#"{"choices":[{"delta":{"content":"half"}}]}"#]))
        XCTAssertThrowsError(try decode(OpenAIStreamDecoder(), [#"{"error":{"message":"bad"}}"#]))
    }

    // MARK: - 网络

    func testHTTPClientStreamsAndReportsErrors() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AIStubProtocol.self]
        let client = AIHTTPClient(configuration: configuration), call = request(try service(.openai), [AIMessage(content: .user(text: "hi", context: "ctx"))])
        AIStubProtocol.response = (200, "data: {\"choices\":[{\"delta\":{\"content\":\"你\"}}]}\n\ndata: {\"choices\":[{\"delta\":{\"content\":\"好\"},\"finish_reason\":\"stop\"}]}\n\ndata: [DONE]\n\n")
        var streamed = ""
        let turn = try await client.respond(to: call) { streamed += $0 }
        XCTAssertEqual(turn.text, "你好"); XCTAssertEqual(streamed, "你好")
        AIStubProtocol.response = (400, #"{"error":{"message":"unknown model"}}"#)
        do { _ = try await client.respond(to: call) { _ in }; XCTFail("应当失败") }
        catch AIClientError.http(let status, let message) { XCTAssertEqual(status, 400); XCTAssertEqual(message, "unknown model") }
        AIStubProtocol.response = (200, #"{"data":[{"id":"b"},{"id":"a"}]}"#)
        let models = try await client.models(call.service, key: "k")
        XCTAssertEqual(models, ["a", "b"])
    }
}

private final class AIStubProtocol: URLProtocol {
    nonisolated(unsafe) static var response: (status: Int, body: String) = (200, "")
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: Self.response.status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(Self.response.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
