import Foundation

/// OpenAI Chat Completions 接口的请求格式，多数第三方服务与本地模型兼容。
enum OpenAIChat {
    static func body(_ request: AIRequest) -> [String: Any] {
        ["model": request.service.model, "stream": true, "messages": [["role": "system", "content": request.system]] + messages(request),
         "tools": request.tools.map { tool in
             ["type": "function", "function": ["name": tool.name, "description": tool.description, "parameters": tool.schema.json] as [String: Any]] as [String: Any]
         }]
    }

    private static func messages(_ request: AIRequest) -> [[String: Any]] {
        request.messages.flatMap { message -> [[String: Any]] in
            switch message.content {
            case let .user(text, context): return [["role": "user", "content": context + "\n\n" + text]]
            case let .assistant(turn):
                guard !turn.text.isEmpty || !turn.calls.isEmpty else { return [] }
                var item: [String: Any] = ["role": "assistant", "content": turn.text]
                if !turn.calls.isEmpty {
                    item["tool_calls"] = turn.calls.map { call in
                        ["id": call.id, "type": "function", "function": ["name": call.name, "arguments": call.arguments]] as [String: Any]
                    }
                }
                // 部分推理模型要求在工具循环中带回推理内容。
                if turn.origin == request.origin, let raw = turn.raw, let extra = (try? JSONSerialization.jsonObject(with: raw)) as? [String: Any] { item.merge(extra) { $1 } }
                return [item]
            case let .toolResults(results):
                return results.map { ["role": "tool", "tool_call_id": $0.callID, "content": $0.content] }
            }
        }
    }
}

struct OpenAIStreamDecoder: AIStreamDecoder {
    private struct Call { var id = "", name = "", arguments = "" }
    private var text = ""
    private var reasoning = ""
    private var calls: [Int: Call] = [:]
    private var finishReason: String?

    mutating func consume(_ event: [String: Any]) throws -> String? {
        if let error = event["error"], !(error is NSNull) {
            throw AIClientError.service((error as? [String: Any])?["message"] as? String ?? error as? String ?? aiText("AI_RESPONSE_INTERRUPTED"))
        }
        guard let choice = (event["choices"] as? [[String: Any]])?.first else { return nil }
        finishReason = choice["finish_reason"] as? String ?? finishReason
        guard let delta = choice["delta"] as? [String: Any] else { return nil }
        reasoning += delta["reasoning_content"] as? String ?? ""
        for item in delta["tool_calls"] as? [[String: Any]] ?? [] {
            let id = item["id"] as? String ?? ""
            // 少数服务不给序号：带新 id 的片段开始一个新调用，其余接在最后一个后面。
            let last = calls.keys.max() ?? -1
            let index = (item["index"] as? NSNumber)?.intValue ?? (!id.isEmpty && calls[last]?.id != id ? last + 1 : max(0, last))
            let function = item["function"] as? [String: Any] ?? [:]
            if !id.isEmpty { calls[index, default: Call()].id = id }
            if let name = function["name"] as? String, !name.isEmpty { calls[index, default: Call()].name = name }
            calls[index, default: Call()].arguments += function["arguments"] as? String ?? ""
        }
        guard let content = delta["content"] as? String else { return nil }
        text += content
        return content
    }

    func finish(origin: String) throws -> AIAssistantTurn {
        guard let finishReason else { throw AIClientError.interrupted }
        if finishReason == "content_filter" { throw AIClientError.refused }
        if finishReason == "length", !calls.isEmpty || text.isEmpty { throw AIClientError.truncated }
        guard !text.isEmpty || !calls.isEmpty else { throw AIClientError.interrupted }
        var turn = AIAssistantTurn(text: text)
        turn.calls = calls.keys.sorted().compactMap { calls[$0] }.map {
            AIToolCall(id: $0.id.isEmpty ? "call_" + UUID().uuidString : $0.id, name: $0.name, arguments: $0.arguments.isEmpty ? "{}" : $0.arguments)
        }
        if !reasoning.isEmpty {
            turn.raw = try JSONSerialization.data(withJSONObject: ["reasoning_content": reasoning])
            turn.origin = origin
        }
        return turn
    }
}
