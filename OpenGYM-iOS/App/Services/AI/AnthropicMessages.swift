import Foundation

/// Anthropic Messages 接口的请求格式。
enum AnthropicMessages {
    static func body(_ request: AIRequest) -> [String: Any] {
        ["model": request.service.model, "max_tokens": 32000, "stream": true,
         "system": [["type": "text", "text": request.system, "cache_control": ["type": "ephemeral"]] as [String: Any]],
         "tools": request.tools.map { ["name": $0.name, "description": $0.description, "input_schema": $0.schema.json] as [String: Any] },
         "messages": messages(request)]
    }

    private static func messages(_ request: AIRequest) -> [[String: Any]] {
        var result: [(role: String, content: [[String: Any]])] = []
        // 相邻的同角色消息合并：部分兼容服务要求两种角色严格交替。
        func add(_ role: String, _ content: [[String: Any]]) {
            guard !content.isEmpty else { return }
            if result.last?.role == role { result[result.count - 1].content += content } else { result.append((role, content)) }
        }
        for message in request.messages {
            switch message.content {
            case let .user(text, context):
                add("user", [["type": "text", "text": context], ["type": "text", "text": text]])
            case let .assistant(turn):
                add("assistant", assistant(turn, origin: request.origin))
            case let .toolResults(results):
                add("user", results.map {
                    ["type": "tool_result", "tool_use_id": $0.callID, "content": $0.content, "is_error": $0.outcome != .completed] as [String: Any]
                })
            }
        }
        // 缓存到最近一条用户消息，后续轮次复用此前的全部内容。
        if let last = result.indices.last, result[last].role == "user", let block = result[last].content.indices.last {
            result[last].content[block]["cache_control"] = ["type": "ephemeral"]
        }
        return result.map { ["role": $0.role, "content": $0.content] }
    }

    private static func assistant(_ turn: AIAssistantTurn, origin: String) -> [[String: Any]] {
        if turn.origin == origin, let raw = turn.raw, let blocks = (try? JSONSerialization.jsonObject(with: raw)) as? [[String: Any]] { return blocks }
        var blocks: [[String: Any]] = turn.text.isEmpty ? [] : [["type": "text", "text": turn.text]]
        blocks += turn.calls.map { call in
            let input = (try? JSONSerialization.jsonObject(with: Data(call.arguments.utf8))) as? [String: Any] ?? [:]
            return ["type": "tool_use", "id": call.id, "name": call.name, "input": input] as [String: Any]
        }
        return blocks
    }
}

struct AnthropicStreamDecoder: AIStreamDecoder {
    private var blocks: [Int: [String: Any]] = [:]
    private var inputs: [Int: String] = [:]
    private var stopReason: String?

    mutating func consume(_ event: [String: Any]) throws -> String? {
        let index = (event["index"] as? NSNumber)?.intValue ?? 0
        switch event["type"] as? String {
        case "content_block_start":
            blocks[index] = event["content_block"] as? [String: Any] ?? [:]
            return blocks[index]?["type"] as? String == "text" ? blocks[index]?["text"] as? String : nil
        case "content_block_delta":
            let delta = event["delta"] as? [String: Any] ?? [:]
            switch delta["type"] as? String {
            case "text_delta": append(delta["text"], to: "text", at: index); return delta["text"] as? String
            case "thinking_delta": append(delta["thinking"], to: "thinking", at: index)
            case "signature_delta": append(delta["signature"], to: "signature", at: index)
            case "input_json_delta": inputs[index, default: ""] += delta["partial_json"] as? String ?? ""
            default: break
            }
        case "message_delta":
            stopReason = (event["delta"] as? [String: Any])?["stop_reason"] as? String ?? stopReason
        case "error":
            throw AIClientError.service((event["error"] as? [String: Any])?["message"] as? String ?? aiText("AI_RESPONSE_INTERRUPTED"))
        default: break
        }
        return nil
    }

    private mutating func append(_ text: Any?, to key: String, at index: Int) {
        blocks[index, default: [:]][key] = (blocks[index]?[key] as? String ?? "") + (text as? String ?? "")
    }

    func finish(origin: String) throws -> AIAssistantTurn {
        guard let stopReason else { throw AIClientError.interrupted }
        if stopReason == "refusal" { throw AIClientError.refused }
        var turn = AIAssistantTurn(text: ""), raw: [[String: Any]] = []
        for index in blocks.keys.sorted() {
            guard var block = blocks[index] else { continue }
            switch block["type"] as? String {
            case "text":
                let text = block["text"] as? String ?? ""
                // 接口不接受空文字块。
                if text.isEmpty { continue }
                turn.text += text
            case "tool_use":
                let input = inputs[index].flatMap { $0.isEmpty ? nil : $0 } ?? "{}"
                // 参数不是有效 JSON 时保留原文，由工具校验把问题告诉模型。
                block["input"] = (try? JSONSerialization.jsonObject(with: Data(input.utf8))) as? [String: Any] ?? block["input"] ?? [String: Any]()
                turn.calls.append(AIToolCall(id: block["id"] as? String ?? UUID().uuidString, name: block["name"] as? String ?? "", arguments: input))
            default: break
            }
            raw.append(block)
        }
        // 截断的工具参数可能看起来完整，不能执行。
        if stopReason == "max_tokens" || stopReason == "model_context_window_exceeded", !turn.calls.isEmpty || turn.text.isEmpty { throw AIClientError.truncated }
        guard !turn.text.isEmpty || !turn.calls.isEmpty else { throw AIClientError.interrupted }
        turn.raw = try JSONSerialization.data(withJSONObject: raw, options: [.sortedKeys, .withoutEscapingSlashes])
        turn.origin = origin
        return turn
    }
}
