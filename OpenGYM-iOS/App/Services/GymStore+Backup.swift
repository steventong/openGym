import Foundation

/// 资料备份：文档每次变化后（启动读取、本机修改、iCloud 导入）自动留一份 → 设置页可导出当前资料，或导入一份备份替换全部资料。
extension GymStore {
    /// 备份失败不影响已经保存的修改，只在设置页提示。
    func backUpDocument() {
        guard let dataBackup else { return }
        do {
            try dataBackup.save(state)
            if dataBackupIssue != nil { dataBackupIssue = nil }
        } catch {
            dataBackupIssue = String(format: String(localized: "COULD_NOT_SAVE_DATA_BACKUP_COUNT", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(describing: error.localizedDescription))
        }
    }

    func exportedBackup() throws -> Data { try DataBackup.encode(state) }

    /// 用备份替换全部资料。替换前必须先留下当前版本，留不下就不替换。
    func restoreBackup(_ document: [String: Any]) async throws {
        guard draft == nil, historyEdits.isEmpty else {
            throw APIError.response(0, String(localized: "SAVE_WORKOUT_AND_HISTORY_DRAFTS_BEFORE_IMPORTING_BACKUP", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
        }
        // 以数据库的最新内容为准，刚由 iCloud 导入的记录才会一起备份和替换。
        try reloadDocument()
        try dataBackup?.save(state)
        guard await mutate(reportError: false, { _ in document }) else {
            throw APIError.response(0, editError ?? String(localized: "COULD_NOT_SAVE_ON_THIS_DEVICE", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
        }
    }
}
