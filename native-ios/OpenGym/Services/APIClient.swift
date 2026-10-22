import Foundation
import Security

enum APIError: LocalizedError {
    case invalidServer, response(Int, String), invalidResponse, signIn, busy
    var errorDescription: String? {
        switch self {
        case .invalidServer: return "请输入有效的服务地址。远程服务需要 HTTPS；本机支持 http://localhost:8080。"
        case .response(401, _), .signIn: return "请先在设置中配对账号，或重新配对已过期的连接。"
        case .response(409, _): return "其他设备正在修改数据，请稍后重试。你的训练草稿仍保留在本机。"
        case let .response(_, message): return message
        case .invalidResponse: return "服务器返回了无法识别的数据。"
        case .busy: return "正在同步，请稍后重试。"
        }
    }
}

struct ServerAddress {
    let url: URL
    init(_ input: String) throws {
        let clean = input.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let u = URL(string: clean), let host = u.host, u.user == nil, u.password == nil,
              u.query == nil, u.fragment == nil, ["https", "http"].contains(u.scheme),
              u.scheme == "https" || ["localhost", "127.0.0.1", "::1"].contains(host) else { throw APIError.invalidServer }
        url = u
    }
    func endpoint(_ path: String) -> URL { url.appendingPathComponent(path) }
}

@MainActor final class APIClient {
    let address: ServerAddress
    var token: String?
    let session: URLSession
    init(address: ServerAddress, token: String? = nil, session: URLSession? = nil) {
        self.address = address; self.token = token
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.httpCookieAcceptPolicy = .never
        config.httpShouldSetCookies = false
        self.session = session ?? URLSession(configuration: config, delegate: NoRedirect(), delegateQueue: nil)
    }
    func request(_ path: String, method: String = "GET", body: [String: Any]? = nil) async throws -> [String: Any] {
        var request = URLRequest(url: address.endpoint(path)); request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body); request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard (200..<300).contains(http.statusCode) else { throw APIError.response(http.statusCode, json?["error"] as? String ?? "HTTP \(http.statusCode)") }
        guard let json else { throw APIError.invalidResponse }
        return json
    }
}
private final class NoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

enum CredentialStore {
    static func save(_ token: String, for server: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "openGym.native", kSecAttrAccount as String: server]
        let values: [String: Any] = [kSecValueData as String: Data(token.utf8), kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        if status == errSecItemNotFound {
            var add = query; values.forEach { add[$0] = $1 }
            guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else { throw APIError.response(0, "无法安全保存登录信息。") }
        } else if status != errSecSuccess { throw APIError.response(0, "无法更新登录信息（Keychain \(status)）。") }
    }
    static func read(for server: String) -> String? {
        let query: [String: Any] = [kSecClass as String:kSecClassGenericPassword, kSecAttrService as String:"openGym.native", kSecAttrAccount as String:server, kSecReturnData as String:true, kSecMatchLimit as String:kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
