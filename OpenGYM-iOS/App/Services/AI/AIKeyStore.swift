import Foundation
import Security

/// API key 的保存位置。正式运行使用钥匙串，测试和预览使用内存。
protocol AIKeyStore {
    func read(_ account: String) throws -> String?
    /// 传入 nil 即删除。
    func write(_ key: String?, account: String) throws
}

/// 设备解锁时可读，通过 iCloud 钥匙串在同一 Apple 账户的设备间同步；未开启 iCloud 钥匙串时只留在本机。
struct AIKeychain: AIKeyStore {
    static let service = "me.itwl.opengym.ai"

    private func query(_ account: String) -> [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: Self.service, kSecAttrAccount: account, kSecAttrSynchronizable: true]
    }
    func read(_ account: String) throws -> String? {
        var request = query(account), item: CFTypeRef?
        request[kSecReturnData] = true
        request[kSecMatchLimit] = kSecMatchLimitOne
        let status = SecItemCopyMatching(request as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { throw AIClientError.keychain(status) }
        return String(data: data, encoding: .utf8)
    }
    func write(_ key: String?, account: String) throws {
        guard let key, let data = key.data(using: .utf8) else {
            let status = SecItemDelete(query(account) as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw AIClientError.keychain(status) }
            return
        }
        let values: [CFString: Any] = [kSecValueData: data, kSecAttrAccessible: kSecAttrAccessibleWhenUnlocked]
        var status = SecItemUpdate(query(account) as CFDictionary, values as CFDictionary)
        if status == errSecItemNotFound { status = SecItemAdd(query(account).merging(values) { $1 } as CFDictionary, nil) }
        guard status == errSecSuccess else { throw AIClientError.keychain(status) }
    }
}

final class AIMemoryKeyStore: AIKeyStore {
    private var keys: [String: String] = [:]
    func read(_ account: String) throws -> String? { keys[account] }
    func write(_ key: String?, account: String) throws { keys[account] = key }
}
