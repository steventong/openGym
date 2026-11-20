import Foundation

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

/// 动作图片与视频的下载地址校验。
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
