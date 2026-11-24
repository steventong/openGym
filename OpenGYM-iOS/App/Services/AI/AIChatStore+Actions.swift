import Foundation

extension AIChatStore {
    // MARK: - 用户操作

    func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSend, let store else { return }
        messages.append(AIMessage(content: .user(text: text, context: Self.context(store))))
        input = ""
        save()
        run()
    }

    /// 失败后从现有记录继续，不重复添加用户消息。
    func retry() {
        guard case .failed = phase, settings.isConfigured else { return }
        run()
    }

    /// 停止当前一轮；等待确认的修改按未执行处理。
    func stop() {
        guard isBusy else { return }
        task?.cancel()
        if case let .awaitingApproval(approval) = phase { approval.decide(.cancelled) }
    }

    func decide(_ decision: AIApprovalDecision) {
        guard case let .awaitingApproval(approval) = phase else { return }
        approval.decide(decision)
    }

    func newChat() {
        guard !isBusy else { return }
        messages = []
        phase = .idle
        guard let file else { return }
        // 连同自动保留的上一份副本一起删除，旧对话不留在本机。
        for url in [file, file.appendingPathExtension("previous")] { try? FileManager.default.removeItem(at: url) }
    }

    // MARK: - 本机保存

    private var file: URL? { store?.accountFolder?.appendingPathComponent("ai-chat.json") }

    /// 首次打开时读取；上次在工具执行中退出的，补上结果使对话可以继续。
    func load() {
        guard !loaded, let file, let store else { return }
        loaded = true
        guard let saved = try? store.localStorage.read(file), let list = saved["messages"],
              let data = try? JSONSerialization.data(withJSONObject: list), let decoded = try? JSONDecoder().decode([AIMessage].self, from: data) else { return }
        messages = AITranscript.closingOpenCalls(decoded, content: "The app was closed before this finished. It may or may not have been saved; read the data again to check.")
    }

    private func save() {
        guard let file, let store, let data = try? JSONEncoder().encode(messages), let list = try? JSONSerialization.jsonObject(with: data) else { return }
        do {
            try store.localStorage.write(["messages": list], to: file)
            if store.localSaveIssues["ai"] != nil { store.localSaveIssues.removeValue(forKey: "ai") }
        } catch { store.localSaveIssues["ai"] = error.localizedDescription }
    }

    // MARK: - 对话循环

    private static func context(_ store: GymStore) -> String {
        "[Context: \(dayString()) \(AIToolbox.time(Date())), weekday \(Calendar.current.component(.weekday, from: Date()) - 1) (0 is Sunday), weight unit \(store.unit), app language \(AppLanguage.language)]"
    }

    private func run() {
        phase = .responding("")
        task = Task { [weak self] in await self?.converse() }
    }

    private func converse() async {
        do {
            for _ in 0..<Self.stepLimit {
                let turn = try await respond()
                messages.append(AIMessage(content: .assistant(turn)))
                save()
                if turn.calls.isEmpty { phase = .idle; return }
                for call in turn.calls {
                    try Task.checkCancellation()
                    try await perform(call)
                }
                try Task.checkCancellation()
                phase = .responding("")
            }
            throw AIClientError.tooManySteps
        } catch {
            finishInterrupted(error)
        }
    }

    private func respond() async throws -> AIAssistantTurn {
        let service = try settings.currentService()
        let request = AIRequest(service: service, key: try settings.key(service), system: AIPrompt.system, tools: AITool.all, messages: messages)
        let turn = try await responder.respond(to: request) { text in
            if case let .responding(previous) = phase { phase = .responding(previous + text) }
        }
        try Task.checkCancellation()
        return turn
    }

    private func finishInterrupted(_ error: Error) {
        let cancelled = Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled
        // 停止时保留已经看到的文字；出错的半截回复不保留，重试会重新生成。
        if cancelled, case let .responding(text) = phase, !text.isEmpty {
            messages.append(AIMessage(content: .assistant(AIAssistantTurn(text: text))))
        }
        messages = AITranscript.closingOpenCalls(messages, content: "The user stopped before this ran. Nothing was changed.")
        save()
        phase = cancelled ? .idle : .failed(error.localizedDescription)
    }

    // MARK: - 工具

    private func perform(_ call: AIToolCall) async throws {
        guard let store else { throw CancellationError() }
        phase = .runningTool(call.name)
        do {
            switch try AIToolbox(store: store).prepare(call) {
            case let .answer(value):
                record(AIToolResult(callID: call.id, outcome: .completed, content: try AIToolbox.encode(value)))
            case let .proposal(proposal):
                try await carryOut(proposal, call: call)
            }
        } catch let error where !(error is CancellationError) {
            record(AIToolResult(callID: call.id, outcome: .failed, content: "Error: " + error.localizedDescription))
        }
    }

    private func carryOut(_ proposal: AIProposal, call: AIToolCall) async throws {
        switch await approval(for: proposal, callID: call.id) {
        case .cancelled:
            throw CancellationError()
        case .declined:
            record(AIToolResult(callID: call.id, outcome: .declined, content: "The user declined this change. Nothing was saved.", summary: proposal.summary))
        case .confirmed:
            phase = .runningTool(call.name)
            do {
                let value = try await proposal.apply()
                record(AIToolResult(callID: call.id, outcome: .completed, content: try AIToolbox.encode(value), summary: proposal.summary))
            } catch {
                record(AIToolResult(callID: call.id, outcome: .failed, content: "Error: " + error.localizedDescription, summary: proposal.summary))
            }
        }
    }

    private func approval(for proposal: AIProposal, callID: String) async -> AIApprovalDecision {
        await withCheckedContinuation { continuation in
            var pending: CheckedContinuation<AIApprovalDecision, Never>? = continuation
            phase = .awaitingApproval(AIPendingApproval(callID: callID, summary: proposal.summary) { decision in
                // 连续点击只生效一次。
                pending?.resume(returning: decision)
                pending = nil
            })
        }
    }

    /// 同一轮回复的所有工具结果放在一条消息里。
    private func record(_ result: AIToolResult) {
        if let last = messages.indices.last, case let .toolResults(list) = messages[last].content {
            messages[last].content = .toolResults(list + [result])
        } else {
            messages.append(AIMessage(content: .toolResults([result])))
        }
        save()
    }
}
