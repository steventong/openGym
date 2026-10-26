import Foundation
import CryptoKit

/// Account-scoped documents. Atomic replacement keeps the prior file on a failed write;
/// a separately verified previous copy also permits recovery from a damaged latest file.
final class LocalTrainingStorage {
    let root: URL
    init(root: URL? = nil) {
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("OpenGymOffline", isDirectory: true)
    }
    func folder(server: String, user: String) -> URL {
        let digest = SHA256.hash(data: Data("\(server)|\(user)".utf8)).map { String(format: "%02x", $0) }.joined()
        return root.appendingPathComponent(digest, isDirectory: true)
    }
    func read(_ url: URL) throws -> [String: Any]? {
        let fm = FileManager.default, backup = url.appendingPathExtension("previous")
        guard fm.fileExists(atPath: url.path) || fm.fileExists(atPath: backup.path) else { return nil }
        for candidate in [url, backup] {
            if let data = try? Data(contentsOf: candidate), let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { return value }
        }
        throw APIError.response(0, "本地文件无法读取，原文件已保留，请勿卸载 App。")
    }
    func write(_ value: [String: Any], to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        // HealthKit-derived weight data can also appear in the cached profile. Keep the whole
        // local recovery area device-local instead of including it in an automatic cloud backup.
        var localRoot = root, options = URLResourceValues()
        options.isExcludedFromBackup = true
        try localRoot.setResourceValues(options)
        if let old = try? Data(contentsOf: url), (try? JSONSerialization.jsonObject(with: old)) != nil {
            try old.write(to: url.appendingPathExtension("previous"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        let handle = try FileHandle(forWritingTo: url); defer { try? handle.close() }
        try handle.synchronize()
    }
}

extension GymStore {
    var accountFolder: URL? { userID.map { localStorage.folder(server: serverURL, user: $0) } }
    var localHistoryURL: URL? { accountFolder?.appendingPathComponent("history-edits.json") }

    func cacheProfile() {
        guard let userID, let folder = accountFolder else { return }
        do {
            try localStorage.write(["state": state, "name": userName ?? ""], to: folder.appendingPathComponent("profile.json"))
            try localStorage.write(["server": serverURL, "user": userID, "name": userName ?? ""], to: localStorage.root.appendingPathComponent("last-account.json"))
            localSaveIssues.removeValue(forKey:"profile")
        } catch { localSaveIssues["profile"] = "本机保存失败：\(error.localizedDescription)" }
    }
    func restoreOfflineAccount() {
        do {
            guard let account = try localStorage.read(localStorage.root.appendingPathComponent("last-account.json")),
                  account["server"] as? String == serverURL, let id = account["user"] as? String else { return }
            userID = id; userName = account["name"] as? String
            let cached = try localStorage.read(localStorage.folder(server: serverURL, user: id).appendingPathComponent("profile.json"))
            state = cached?["state"] as? [String: Any] ?? [:]
            restoreLocalTraining()
            status = "已载入本机数据"
        } catch { localSaveError = error.localizedDescription }
    }
    func restoreLocalTraining() {
        do {
            if let url = localHistoryURL { historyEdits = try localStorage.read(url)?["edits"] as? [String: [String: Any]] ?? [:] }
            restoreDraft()
        } catch { localSaveError = error.localizedDescription }
    }
    @discardableResult func persistHistoryEdits() -> Bool {
        guard let url = localHistoryURL else { localSaveIssues["history"] = "尚未识别账号，无法安全保存本机草稿。"; return false }
        do { try localStorage.write(["edits": historyEdits], to: url); localSaveIssues.removeValue(forKey:"history"); return true }
        catch { localSaveIssues["history"] = "编辑内容仍在内存，但写入本机失败：\(error.localizedDescription)"; return false }
    }
    @discardableResult func keepHistoryEdit(original: [String: Any], proposed: [String: Any], unit: String, form: [String: Any]? = nil, submit: Bool = false) -> Bool {
        let key = WorkoutRecord.key(original)
        var item = historyEdits[key] ?? [:]
        let changed = !RecordPatch.equal(item["proposed"], proposed) || (form != nil && !RecordPatch.equal(item["form"], form))
        item["original"] = item["original"] ?? original
        item["proposed"] = proposed; item["unit"] = unit
        if let form { item["form"] = form }
        if changed || item["generation"] == nil {
            if let expected = item["expected"] { item["priorExpected"] = expected }
            item["generation"] = UUID().uuidString; item.removeValue(forKey: "expected"); item["submitted"] = false
        }
        if submit { item["submitted"] = true }
        item["updatedAt"] = Date().timeIntervalSince1970
        historyEdits[key] = item
        return persistHistoryEdits()
    }
    @discardableResult func archiveHistoryEdit(_ key: String, generation: String? = nil) -> Bool {
        guard let item = historyEdits[key], let folder = accountFolder else { return true }
        if let generation, item["generation"] as? String != generation { return false }
        do {
            // Keep successful and explicitly discarded input recoverable, separate from active drafts.
            let filename = "history-\(item["generation"] as? String ?? UUID().uuidString).json"
            try localStorage.write(item, to: folder.appendingPathComponent("archive").appendingPathComponent(filename))
            historyEdits.removeValue(forKey: key)
            if !persistHistoryEdits() { historyEdits[key] = item; return false }
            return true
        } catch { localSaveError = error.localizedDescription; return false }
    }
}
