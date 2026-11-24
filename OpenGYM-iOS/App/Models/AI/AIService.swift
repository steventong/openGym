import Foundation

/// 对话服务使用的接口协议。
enum AIProtocolKind: String, Codable, CaseIterable, Identifiable {
    case anthropic, openai
    var id: String { rawValue }
    var officialAddress: String {
        switch self {
        case .anthropic: "https://api.anthropic.com/v1"
        case .openai: "https://api.openai.com/v1"
        }
    }
    var defaultModel: String {
        switch self {
        case .anthropic: "claude-opus-5-5"
        case .openai: "gpt-5"
        }
    }
}

enum AIAddressKind: String, Codable, CaseIterable, Identifiable {
    case official, custom
    var id: String { rawValue }
}

/// 一套独立的服务配置，决定地址与模型的保存位置。
struct AIServiceSlot: Hashable {
    var kind: AIProtocolKind = .anthropic
    var address: AIAddressKind = .official
    var storageKey: String { "\(kind.rawValue).\(address.rawValue)" }
}

/// 已确认可用的服务：请求只会发往 `baseURL`。
struct AIService: Equatable {
    let slot: AIServiceSlot
    let baseURL: URL
    let model: String
    /// API key 的保存位置。自定义地址按来源区分：key 会同步到其他设备，而每台设备的地址各自设置，key 只能发回它所属的主机。
    var keyAccount: String {
        guard slot.address == .custom else { return slot.storageKey }
        let port = baseURL.port.map { ":\($0)" } ?? ""
        return "\(slot.storageKey)|\(baseURL.scheme?.lowercased() ?? "")://\(baseURL.host()?.lowercased() ?? "")\(port)"
    }
}

/// 自定义地址校验。远程地址必须使用 HTTPS，本机与局域网地址可以使用 HTTP。
struct AIBaseAddress {
    let url: URL

    init(_ input: String, kind: AIProtocolKind) throws {
        let clean = Self.trimmed(input)
        guard let parts = URLComponents(string: clean), let scheme = parts.scheme?.lowercased(), let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              scheme == "https" || (scheme == "http" && Self.isLocal(host)) else { throw AIClientError.invalidAddress }
        // 粘贴完整接口地址时去掉末尾的接口路径。
        var base = clean
        for suffix in ["/chat/completions", "/messages", "/models"] where base.lowercased().hasSuffix(suffix) {
            base = Self.trimmed(String(base.dropLast(suffix.count)))
        }
        // Anthropic 的基础地址惯例不含版本段；OpenAI 兼容地址惯例已包含，只在没有路径时补上。
        let path = URLComponents(string: base)?.path ?? ""
        let needsVersion = kind == .anthropic ? !path.hasSuffix("/v1") : path.isEmpty
        guard let url = URL(string: needsVersion ? base + "/v1" : base) else { throw AIClientError.invalidAddress }
        self.url = url
    }

    private static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    static func isLocal(_ host: String) -> Bool {
        let name = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if name == "localhost" || name == "::1" || name.hasSuffix(".local") { return true }
        let labels = name.split(separator: ".", omittingEmptySubsequences: false)
        let octets = labels.compactMap { UInt8($0) }
        guard labels.count == 4, octets.count == 4 else { return false }
        switch (octets[0], octets[1]) {
        case (127, _), (10, _), (192, 168), (169, 254): return true
        case (172, 16...31): return true
        default: return false
        }
    }
}
