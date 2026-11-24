import Foundation

/// 界面文案取值，与其余页面使用同一套语言资源。
func aiText(_ key: String.LocalizationValue, _ arguments: String...) -> String {
    let format = String(localized: key, bundle: AppLanguage.bundle, locale: AppLanguage.locale)
    return arguments.isEmpty ? format : String(format: format, locale: AppLanguage.locale, arguments: arguments)
}

enum AIClientError: LocalizedError {
    case notConfigured, invalidAddress, missingModel, missingKey, invalidKey, keychain(OSStatus)
    case http(Int, String), service(String), interrupted, refused, truncated, tooManySteps
    var errorDescription: String? {
        switch self {
        case .notConfigured: aiText("AI_NOT_CONFIGURED")
        case .invalidAddress: aiText("AI_INVALID_ADDRESS")
        case .missingModel: aiText("AI_ENTER_MODEL")
        case .missingKey: aiText("AI_ENTER_API_KEY")
        case .invalidKey: aiText("AI_INVALID_API_KEY")
        case let .keychain(status): aiText("AI_KEYCHAIN_ERROR_COUNT", String(status))
        case .http(401, _), .http(403, _): aiText("AI_API_KEY_REJECTED")
        case .http(429, _): aiText("AI_RATE_LIMITED")
        case let .http(status, message): aiText("AI_HTTP_ERROR_COUNT_COUNT", String(status), message)
        case let .service(message): message
        case .interrupted: aiText("AI_RESPONSE_INTERRUPTED")
        case .refused: aiText("AI_RESPONSE_REFUSED")
        case .truncated: aiText("AI_RESPONSE_TRUNCATED")
        case .tooManySteps: aiText("AI_TOO_MANY_STEPS")
        }
    }
}

struct AIRequest {
    let service: AIService
    let key: String
    let system: String
    let tools: [AITool]
    let messages: [AIMessage]
    /// 原始回复只发回产生它的服务与同一套指令；任一改变都退回普通文字与工具记录。
    var origin: String { [service.slot.kind.rawValue, service.baseURL.absoluteString, AIPrompt.fingerprint].joined(separator: "|") }
}

/// 对话服务。测试用脚本化的实现代替网络。
@MainActor protocol AIResponder {
    func respond(to request: AIRequest, onText: @MainActor (String) -> Void) async throws -> AIAssistantTurn
}

/// 一次流式回复的解析状态。
protocol AIStreamDecoder {
    /// 处理一条事件，返回新增的可见文字。
    mutating func consume(_ event: [String: Any]) throws -> String?
    func finish(origin: String) throws -> AIAssistantTurn
}

@MainActor final class AIHTTPClient: AIResponder {
    private let session: URLSession

    init(configuration: URLSessionConfiguration = .ephemeral) {
        configuration.timeoutIntervalForRequest = 300
        configuration.timeoutIntervalForResource = 1800
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        session = URLSession(configuration: configuration, delegate: RedirectBlocker(), delegateQueue: nil)
    }

    func respond(to request: AIRequest, onText: @MainActor (String) -> Void) async throws -> AIAssistantTurn {
        let anthropic = request.service.slot.kind == .anthropic
        var call = Self.urlRequest(request.service, key: request.key, path: anthropic ? "messages" : "chat/completions")
        call.httpMethod = "POST"
        call.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        call.httpBody = try Self.encode(anthropic ? AnthropicMessages.body(request) : OpenAIChat.body(request))
        var decoder: any AIStreamDecoder = anthropic ? AnthropicStreamDecoder() : OpenAIStreamDecoder()
        let (bytes, response) = try await session.bytes(for: call)
        try await Self.check(response) { try await Self.collect(bytes) }
        for try await line in bytes.lines {
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if payload == "[DONE]" { break }
            guard let event = (try? JSONSerialization.jsonObject(with: Data(payload.utf8))) as? [String: Any] else { continue }
            if let text = try decoder.consume(event), !text.isEmpty { onText(text) }
        }
        try Task.checkCancellation()
        return try decoder.finish(origin: request.origin)
    }

    /// 服务支持的模型列表，用于设置页选择。
    func models(_ service: AIService, key: String) async throws -> [String] {
        let path = service.slot.kind == .anthropic ? "models?limit=100" : "models"
        let (data, response) = try await session.data(for: Self.urlRequest(service, key: key, path: path))
        try await Self.check(response) { data }
        guard let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let list = body["data"] as? [[String: Any]] else { throw AIClientError.interrupted }
        return list.compactMap { $0["id"] as? String }.sorted()
    }

    static func urlRequest(_ service: AIService, key: String, path: String) -> URLRequest {
        var request = URLRequest(url: URL(string: service.baseURL.absoluteString + "/" + path)!)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        switch service.slot.kind {
        case .anthropic:
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            // 第三方兼容服务普遍只认识旧版本号；用到的字段在两个版本中相同。
            request.setValue(service.slot.address == .official ? "2026-10-21" : "2023-06-01", forHTTPHeaderField: "anthropic-version")
            // 不少兼容服务只读取 Bearer。
            if service.slot.address == .custom { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        case .openai:
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    /// 键顺序固定，服务端的提示缓存才能命中。
    static func encode(_ body: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys, .withoutEscapingSlashes])
    }

    private static func collect(_ bytes: URLSession.AsyncBytes) async throws -> Data {
        var data = Data()
        for try await byte in bytes { data.append(byte); if data.count >= 20_000 { break } }
        return data
    }

    private static func check(_ response: URLResponse, body: () async throws -> Data) async throws {
        guard let http = response as? HTTPURLResponse else { throw AIClientError.interrupted }
        guard !(200..<300).contains(http.statusCode) else { return }
        throw AIClientError.http(http.statusCode, errorMessage(try await body()))
    }

    static func errorMessage(_ data: Data) -> String {
        let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let message = (body?["error"] as? [String: Any])?["message"] as? String ?? body?["error"] as? String
            ?? body?["message"] as? String ?? String(decoding: data, as: UTF8.self)
        return String(message.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300))
    }
}

/// 不跟随重定向：请求头带有 API key，不能转发到用户没有填写的主机。
private final class RedirectBlocker: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
