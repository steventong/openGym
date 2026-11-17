import Foundation

/// 服务器版留在本机的账号信息。存在即说明这台设备是从服务器版升级来的。
struct LegacyAccount {
    let server: String
    let user: String
    let name: String?

    static func find(in storage: LocalTrainingStorage) -> LegacyAccount? {
        guard let saved = try? storage.read(storage.root.appendingPathComponent("last-account.json")),
              let server = saved["server"] as? String, let user = saved["user"] as? String else { return nil }
        return LegacyAccount(server: server, user: user, name: saved["name"] as? String)
    }

    /// 服务器版每次同步后缓存在本机的整份资料。
    static func cachedDocument(for account: LegacyAccount, in storage: LocalTrainingStorage) -> [String: Any]? {
        let url = storage.folder(server: account.server, user: account.user).appendingPathComponent("profile.json")
        return (try? storage.read(url))?["state"] as? [String: Any]
    }
}

enum LegacyServer {
    /// 用旧的配对凭据最后读取一次服务器上的资料，并照旧留一份原始快照。
    /// 任何失败都返回 nil，由调用方改用本机缓存。
    @MainActor static func latestDocument(for account: LegacyAccount, storage: LocalTrainingStorage) async -> [String: Any]? {
        guard let token = CredentialStore.read(for: account.server), let address = try? ServerAddress(account.server) else { return nil }
        // 导入期间保存操作在等待，服务器不通时尽快改用本机缓存。
        guard let response = try? await APIClient(address: address, token: token, timeout: 8).request("api/data"),
              let document = response["state"] as? [String: Any] else { return nil }
        _ = try? storage.saveServerSnapshot(response, server: account.server, user: account.user)
        return document
    }
}

enum LegacyImport {
    /// 导入记录使用的版本时间：早于任何正常修改，另一台设备上更新过的同一条记录总是胜出。
    static let recordDate = Date(timeIntervalSince1970: 0)

    /// 数据库里已有的内容优先（可能是另一台已升级设备经 iCloud 同步来的更新版本），旧资料只补缺少的部分。
    static func merge(imported: [String: Any], into current: [String: Any]) -> [String: Any] {
        var result = StateDocument.settings(of: imported).merging(StateDocument.settings(of: current)) { _, existing in existing }
        for set in StateDocument.recordSets {
            let existing = StateDocument.records(of: set, in: current)
            let known = Set(existing.map(\.id))
            let added = StateDocument.records(of: set, in: imported).filter { !known.contains($0.id) }
            result[set.documentKey] = (existing + added).map(\.payload)
        }
        return StateDocument.canonical(result)
    }
}

/// 一次性迁移：服务器版的资料导入 Core Data 后，App 不再连接服务器。
extension GymStore {
    private static let legacyImportDoneKey = "legacyServerImport.done"

    var legacyImportPending: Bool {
        !defaults.bool(forKey: Self.legacyImportDoneKey) && LegacyAccount.find(in: localStorage) != nil
    }

    /// 每次启动最多尝试一次；保存操作会先等它结束，避免新修改写在导入之前。
    func importLegacyServerDataIfNeeded() async {
        if legacyImport == nil, legacyImportPending { legacyImport = Task { await self.importLegacyServerData() } }
        await legacyImport?.value
    }

    private func importLegacyServerData() async {
        guard let account = LegacyAccount.find(in: localStorage) else { return }
        syncing = true
        defer { syncing = false }
        // 先取服务器上的最新资料；取不到时用本机缓存的上次同步结果。
        var imported = await legacyDocumentSource(account, localStorage)
        if imported == nil { imported = LegacyAccount.cachedDocument(for: account, in: localStorage) }
        // 两者都没有时保持待导入，下次启动再试。
        guard let imported else { return }
        do {
            let merged = StateDocument.canonical(addingExerciseCopies(to: LegacyImport.merge(imported: imported, into: try repository.load())))
            try repository.save(merged, at: LegacyImport.recordDate)
            defaults.set(true, forKey: Self.legacyImportDoneKey)
            state = merged
            lastDocumentChange = Date()
        } catch { reportDatabaseFailure(error) }
    }
}
