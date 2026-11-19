import CoreData
import Foundation

/// 本机资料标识。新安装使用固定值；从服务器版升级时沿用旧账号，草稿等本机文件的位置不变。
struct LocalProfile {
    let server: String
    let user: String
    static let fresh = LocalProfile(server: "local", user: "local")
}

/// 资料文档的读写流程：
/// 启动时从 Core Data 读出整份文档 → 页面与规则只读 `state` → 所有修改经 `mutate` 写回变化的记录
/// → iCloud 导入其他设备的变更后，数据库发出通知，这里重新读取文档。
extension GymStore {
    /// 全新资料的文档骨架，与规则引擎默认值一致。
    static let emptyDocument: [String: Any] = ["unit": "kg", "routines": [], "workouts": [], "bodyweight": [], "week": [String: Any]()]

    /// 同步完成的冷启动准备：确定本机资料标识，读出文档、训练草稿和历史编辑。
    func prepareOfflineLaunch() {
        let legacy = LegacyAccount.find(in: localStorage)
        profileServer = legacy?.server ?? LocalProfile.fresh.server
        userID = legacy?.user ?? LocalProfile.fresh.user
        userName = legacy?.name
        do {
            state = try repository.load()
            clearDatabaseFailure()
        } catch { reportDatabaseFailure(error) }
        restoreLocalTraining()
        observeStoreChanges()
        healthSync.prepare()
    }

    func boot() async {
        do {
            guard let url = Bundle.main.url(forResource: "catalogue", withExtension: "json") else { throw CocoaError(.fileNoSuchFile) }
            let list = try await Task.detached { try JSONDecoder().decode([Exercise].self, from: Data(contentsOf: url)) }.value
            registerCatalogue(list)
        } catch { catalogueError = String(format: String(localized: "COULD_NOT_LOAD_EXERCISE_LIBRARY_COUNT", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(describing: error.localizedDescription)) }
        if userID == nil { prepareOfflineLaunch() }
        await healthSync.resume()
    }

    /// 重新读取本机数据库。iCloud 的变更会自动合入，这里服务于下拉刷新。
    @discardableResult func refresh() async -> Result<Void, Error> {
        do { try reloadDocument(); return .success(()) }
        catch { reportDatabaseFailure(error); return .failure(error) }
    }

    func reloadDocument() throws {
        let next = try repository.load()
        clearDatabaseFailure()
        guard !StateDocument.same(state, next) else { return }
        state = next
        lastDocumentChange = Date()
    }

    /// 所有资料修改的唯一入口：在当前文档上执行一次修改，把变化的记录写入 Core Data，成功后才更新内存文档。
    /// `verify` 是调用方对结果的确认条件，不满足时不保存。
    func mutate(reportError: Bool = true, verify: (([String: Any]) -> Bool)? = nil, _ operation: ([String: Any]) throws -> [String: Any]) async -> Bool {
        editError = nil
        func fail(_ message: String) -> Bool {
            if reportError { error = message } else { editError = message }
            return false
        }
        do {
            // 还没有任何设置的全新资料，第一次保存时补上文档骨架；已有资料原样交给修改操作。
            let source = StateDocument.settings(of: state).isEmpty ? Self.emptyDocument.merging(state) { _, existing in existing } : state
            let next = StateDocument.canonical(addingExerciseCopies(to: try operation(source)))
            guard verify?(next) != false else {
                throw APIError.response(0, String(localized: "COULD_NOT_SAVE_ON_THIS_DEVICE", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
            }
            // 只有与数据库中不同的记录才会真正写入。
            try repository.save(next)
            if !StateDocument.same(state, next) {
                state = next
                lastDocumentChange = Date()
            }
            return true
        } catch { return fail(error.localizedDescription) }
    }

    /// iCloud 把其他设备的变更写进数据库后重新读取文档。本机自己的保存也会触发通知，由事务作者过滤掉。
    func observeStoreChanges() {
        guard storeObserver == nil else { return }
        storeObserver = NotificationCenter.default.addObserver(forName: .NSPersistentStoreRemoteChange, object: repository.coordinator, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleStoreReload() }
        }
    }

    private func scheduleStoreReload() {
        // 一次导入会连续发出多条通知，合并成一次读取。
        storeReload?.cancel()
        storeReload = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, let self, !self.syncing, self.repository.consumeForeignChanges() else { return }
            do { try self.reloadDocument() } catch { self.reportDatabaseFailure(error) }
        }
    }

    /// 只在确有错误标记时才改动，避免没有变化的读取也触发界面、手表和实时活动刷新。
    func clearDatabaseFailure() {
        if localSaveIssues["database"] != nil { localSaveIssues.removeValue(forKey: "database") }
    }

    func reportDatabaseFailure(_ error: Error) {
        localSaveIssues["database"] = String(format: String(localized: "COULD_NOT_READ_LOCAL_DATABASE_COUNT", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(describing: error.localizedDescription))
    }

    /// 设置页保存动作媒体地址：校验后立即生效并记住。
    func saveMediaServer(_ input: String) throws {
        mediaServerURL = try ServerAddress(input).url.absoluteString
        defaults.set(mediaServerURL, forKey: Self.mediaServerKey)
    }
}
