import Foundation
import Observation

/// AI 服务的设置。协议、地址和模型只存本机 UserDefaults，API key 只存 `keys`（iCloud 钥匙串），都不进入资料文档。
@MainActor @Observable final class AISettings {
    private(set) var slot: AIServiceSlot
    /// 设置或 key 变化后递增，界面据此重新读取是否已配置。
    private(set) var revision = 0
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let keys: AIKeyStore

    init(defaults: UserDefaults, keys: AIKeyStore) {
        self.defaults = defaults
        self.keys = keys
        slot = AIServiceSlot(kind: defaults.string(forKey: "ai.protocol").flatMap(AIProtocolKind.init) ?? .anthropic,
                             address: defaults.string(forKey: "ai.address").flatMap(AIAddressKind.init) ?? .official)
    }

    func model(_ slot: AIServiceSlot) -> String {
        defaults.string(forKey: "ai.model.\(slot.storageKey)") ?? (slot.address == .official ? slot.kind.defaultModel : "")
    }
    func customAddress(_ kind: AIProtocolKind) -> String { defaults.string(forKey: "ai.url.\(kind.rawValue)") ?? "" }
    func hasKey(_ service: AIService) -> Bool { _ = revision; return ((try? keys.read(service.keyAccount)) ?? nil)?.isEmpty == false }
    func key(_ service: AIService) throws -> String {
        guard let key = try keys.read(service.keyAccount), !key.isEmpty else { throw AIClientError.notConfigured }
        return key
    }

    /// 由填写内容得到服务，地址或模型不合法时抛出错误。
    func service(_ slot: AIServiceSlot, address: String, model: String) throws -> AIService {
        let url = try slot.address == .official
            ? AIBaseAddress(slot.kind.officialAddress, kind: slot.kind).url
            : AIBaseAddress(address, kind: slot.kind).url
        return AIService(slot: slot, baseURL: url, model: model.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    func currentService() throws -> AIService {
        let service = try service(slot, address: customAddress(slot.kind), model: model(slot))
        guard !service.model.isEmpty else { throw AIClientError.notConfigured }
        return service
    }
    var isConfigured: Bool { _ = revision; return (try? currentService()).map(hasKey) ?? false }

    /// 保存并启用一套配置。`newKey` 为空表示沿用已保存的 key。
    func save(_ slot: AIServiceSlot, address: String, model: String, newKey: String) throws {
        let service = try service(slot, address: address, model: model)
        guard !service.model.isEmpty else { throw AIClientError.missingModel }
        let key = newKey.trimmingCharacters(in: .whitespacesAndNewlines)
        // 请求头只能是 ASCII 可见字符，粘贴内容混入换行或全角字符时直接指出。
        guard key.unicodeScalars.allSatisfy({ (33...126).contains($0.value) }) else { throw AIClientError.invalidKey }
        guard !key.isEmpty || hasKey(service) else { throw AIClientError.missingKey }
        if !key.isEmpty { try keys.write(key, account: service.keyAccount) }
        if slot.address == .custom { defaults.set(address.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "ai.url.\(slot.kind.rawValue)") }
        defaults.set(service.model, forKey: "ai.model.\(slot.storageKey)")
        defaults.set(slot.kind.rawValue, forKey: "ai.protocol")
        defaults.set(slot.address.rawValue, forKey: "ai.address")
        self.slot = slot
        revision += 1
    }
    func removeKey(_ service: AIService) throws {
        try keys.write(nil, account: service.keyAccount)
        revision += 1
    }
}
