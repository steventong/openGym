import Foundation
import Security

enum APIError: LocalizedError {
    case invalidServer, response(Int, String), invalidResponse, signIn, busy
    var errorDescription: String? {
        switch self {
        case .invalidServer: return String(localized: "ENTER_A_VALID_SERVER_ADDRESS_REMOTE_SERVERS_REQUIRE_HTTPS_LOCAL_ACCESS_SUPPORTS", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
        case .response(401, _), .signIn: return String(localized: "PAIR_YOUR_ACCOUNT_IN_SETTINGS_OR_PAIR_AGAIN_IF_YOUR_CONNECTION_HAS", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
        case let .response(409, message): return message == "conflict" ? String(localized: "ANOTHER_DEVICE_IS_UPDATING_YOUR_DATA_TRY_AGAIN_SHORTLY_YOUR_WORKOUT_DRAFT", bundle: AppLanguage.bundle, locale: AppLanguage.locale) : message
        case let .response(_, message): return message
        case .invalidResponse: return String(localized: "THE_SERVER_RETURNED_DATA_THAT_COULD_NOT_BE_READ", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
        case .busy: return String(localized: "SYNC_IN_PROGRESS_TRY_AGAIN_SHORTLY", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
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
        guard (200..<300).contains(http.statusCode) else {
            let message: String
            if path.hasPrefix("api/coach/"), let code = json?["code"] as? String {
                message = CoachSession.jobError(code)
            } else { message = json?["error"] as? String ?? "HTTP \(http.statusCode)" }
            throw APIError.response(http.statusCode,message)
        }
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
            guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else { throw APIError.response(0, String(localized: "COULD_NOT_STORE_LOGIN_DETAILS_SECURELY", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) }
        } else if status != errSecSuccess { throw APIError.response(0, String(format: String(localized: "COULD_NOT_UPDATE_LOGIN_DETAILS_KEYCHAIN_COUNT", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(describing: status))) }
    }
    static func read(for server: String) -> String? {
        let query: [String: Any] = [kSecClass as String:kSecClassGenericPassword, kSecAttrService as String:"openGym.native", kSecAttrAccount as String:server, kSecReturnData as String:true, kSecMatchLimit as String:kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
