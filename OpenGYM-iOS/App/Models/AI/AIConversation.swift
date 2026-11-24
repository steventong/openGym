import Foundation

/// 模型请求的一次工具调用。`arguments` 是模型给出的 JSON 原文，执行前才解析和校验。
struct AIToolCall: Codable, Equatable, Identifiable {
    let id: String
    let name: String
    let arguments: String
}

/// 确认卡片里的一行改动；新建没有 `before`，删除没有 `after`。
struct AIChange: Codable, Equatable {
    var label: String
    var before: String?
    var after: String?
}

struct AIProposalSummary: Codable, Equatable {
    var title: String
    var changes: [AIChange]
    var destructive = false
}

struct AIToolResult: Codable, Equatable {
    enum Outcome: String, Codable { case completed, declined, failed, cancelled }
    let callID: String
    let outcome: Outcome
    /// 回给模型的内容。
    let content: String
    /// 编辑类工具保留改动摘要，对话里可以回看改了什么。
    var summary: AIProposalSummary?
}

struct AIAssistantTurn: Codable, Equatable {
    var text: String
    var calls: [AIToolCall] = []
    /// 服务返回的原始内容。只有发回同一来源时才原样附带，思考内容与签名不能改动。
    var raw: Data?
    var origin: String?
}

struct AIMessage: Codable, Equatable, Identifiable {
    enum Content: Codable, Equatable {
        /// `context` 是发送时的日期、单位等背景，随消息固定下来，之后不再变化。
        case user(text: String, context: String)
        case assistant(AIAssistantTurn)
        case toolResults([AIToolResult])
    }
    var id = UUID().uuidString
    var content: Content
}

/// 对话记录的纯数据整理。
enum AITranscript {
    /// 中断后补齐没有结果的工具调用：接口要求每个调用都有对应结果。
    static func closingOpenCalls(_ messages: [AIMessage], content: String) -> [AIMessage] {
        var result = messages
        guard let turnIndex = result.lastIndex(where: { if case .assistant = $0.content { true } else { false } }),
              case let .assistant(turn) = result[turnIndex].content, !turn.calls.isEmpty else { return result }
        let next = turnIndex + 1
        var done: [AIToolResult] = []
        var existing = false
        if result.indices.contains(next), case let .toolResults(list) = result[next].content { done = list; existing = true }
        let missing = turn.calls.filter { call in !done.contains { $0.callID == call.id } }
        guard !missing.isEmpty else { return result }
        done += missing.map { AIToolResult(callID: $0.id, outcome: .cancelled, content: content) }
        if existing { result[next].content = .toolResults(done) }
        else { result.insert(AIMessage(content: .toolResults(done)), at: next) }
        return result
    }
}
