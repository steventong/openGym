import Foundation
import Security

enum APIError: LocalizedError {
    case invalidServer, response(Int, String), invalidResponse, noProfile
    var errorDescription: String? {
        switch self {
        case .invalidServer: return String(localized: "ENTER_A_VALID_SERVER_ADDRESS_REMOTE_SERVERS_REQUIRE_HTTPS_LOCAL_ACCESS_SUPPORTS", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
        case let .response(_, message): return message
        case .invalidResponse: return String(localized: "THE_SERVER_RETURNED_DATA_THAT_COULD_NOT_BE_READ", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
        case .noProfile: return String(localized: "COULD_NOT_SAVE_ON_THIS_DEVICE", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
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

/// 只在导入旧服务器资料时使用一次（LegacyServerImport.swift）；日常运行不联网读写资料。
@MainActor final class APIClient {
    let address: ServerAddress
    var token: String?
    let session: URLSession
    init(address: ServerAddress, token: String? = nil, session: URLSession? = nil, timeout: TimeInterval = 20) {
        self.address = address; self.token = token
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
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
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.response(http.statusCode, json?["error"] as? String ?? "HTTP \(http.statusCode)")
        }
        guard let json else { throw APIError.invalidResponse }
        return json
    }
}
private final class NoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

/// 服务器版保存在钥匙串里的配对凭据，只读。
enum CredentialStore {
    static func read(for server: String) -> String? {
        let query: [String: Any] = [kSecClass as String:kSecClassGenericPassword, kSecAttrService as String:"openGym.native", kSecAttrAccount as String:server, kSecReturnData as String:true, kSecMatchLimit as String:kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
