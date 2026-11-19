import Foundation
import Observation

/// App 的状态与依赖。资料文档 `state` 来自本机 Core Data（经 iCloud 同步），
/// 读写流程见 GymStore+Storage.swift；这里只放状态、依赖对象和动作索引。
@MainActor @Observable final class GymStore {
    private(set) var exercises: [Exercise] = []
    var catalogueError: String?
    var state: [String: Any] = [:] {
        didSet {
            if !RecordPatch.equal(oldValue["lang"], state["lang"]) { AppLanguage.setLanguage(state["lang"] as? String) }
            // Workout, weight and sync metadata changes do not change exercise names or images.
            if !RecordPatch.equal(oldValue[StateDocument.customExercises], state[StateDocument.customExercises])
                || !RecordPatch.equal(oldValue[StateDocument.exerciseCopies], state[StateDocument.exerciseCopies]) { rebuildExerciseIndex() }
            publishTraining()
        }
    }
    /// 动作图片与视频的下载地址。动作文字随 App 内置，媒体按需从这里获取。
    var mediaServerURL: String
    /// 本机资料标识，只用来定位草稿、健康同步等本机文件。
    /// 从服务器版升级的用户沿用旧服务器地址和账号 ID，原有文件位置不变。
    var profileServer = LocalProfile.fresh.server
    var userID: String? { didSet { publishTraining() } }
    var userName: String?
    /// 迁移旧服务器资料期间为 true，页面据此暂停保存操作。
    var syncing = false { didSet { publishTraining() } }
    var error: String?
    var editError: String?
    /// 内存文档上次随数据库变化的时间；依赖整份资料的页面据此重新计算。
    var lastDocumentChange: Date?
    var selectedTab = 0
    var showSettings = false
    var selectedExercise: Exercise?
    var draft: TrainingDraft? {
        willSet {
            // A disappearing field must never write its old session's text into a new one.
            if draft?.id != newValue?.id { liveInputBuffer.discardAll() }
        }
        didSet { persistDraft(); publishTraining() }
    }
    @ObservationIgnored let liveInputBuffer = InputCommitBuffer()
    @ObservationIgnored var watchBridge: PhoneWatchBridge?
    @ObservationIgnored var liveActivity: WorkoutActivityCoordinator?
    var restNotifications: RestNotifications?
    /// 本机开关由手机持久化，并随训练快照下发给手表控制动作检测。
    var autoEndRestEnabled: Bool {
        didSet {
            defaults.set(autoEndRestEnabled, forKey: "watch.autoEndRest.enabled")
            publishTraining()
        }
    }
    @ObservationIgnored let defaults: UserDefaults
    var liveActivityIssue: String?
    var localSaveIssues: [String: String] = [:] { didSet { publishTraining() } }
    var localSaveError: String? {
        get { localSaveIssues.sorted { $0.key < $1.key }.first?.value }
        set { localSaveIssues["general"] = newValue }
    }
    var historyEdits: [String: [String: Any]] = [:]
    let localStorage: LocalTrainingStorage
    @ObservationIgnored let repository: StateRepository
    /// 仅正式容器有 iCloud 同步状态；内存库（测试、预览）为 nil。
    let cloudSync: CloudSyncMonitor?
    /// 读取旧服务器上的最新资料；测试中替换为固定数据。
    @ObservationIgnored var legacyDocumentSource: (LegacyAccount, LocalTrainingStorage) async -> [String: Any]? = LegacyServer.latestDocument
    @ObservationIgnored var storeObserver: NSObjectProtocol?
    @ObservationIgnored var storeReload: Task<Void, Never>?
    @ObservationIgnored lazy var healthSync = HealthWeightSync(store:self)
    @ObservationIgnored lazy var workoutHealth = WorkoutHealthSync(store: self)
    @ObservationIgnored lazy var historyHealth = HistoryHealthSync()
    var restUntil: Date? {
        get { guard let t = draft?.activeJSON["nativeRest"] as? [String: Any] else { return nil }; return Date(timeIntervalSince1970: number(t["end"])) }
        set { changeActive { raw in if let newValue { var rest = raw["nativeRest"] as? [String: Any] ?? [:]; rest["end"] = newValue.timeIntervalSince1970; raw["nativeRest"] = rest } else { raw.removeValue(forKey: "nativeRest") } } }
    }
    /// 旧草稿没有 phase 字段，按组间休息处理。
    var restPhase: TrainingActionStatus.RestPhase {
        (draft?.activeJSON["nativeRest"] as? [String: Any])?["phase"].flatMap { $0 as? String }.flatMap(TrainingActionStatus.RestPhase.init(rawValue:)) ?? .betweenSets
    }
    private var index: [String: Exercise] = [:]
    private var catalogue: [Exercise] = []
    private var catalogueIndex: [String: Exercise] = [:]
    private var catalogueMediaIDs: Set<String> = []
    /// 默认使用内存库，预览和测试不会碰到用户数据；正式容器只在 App 启动处传入。
    init(userID: String? = nil, storage: LocalTrainingStorage = LocalTrainingStorage(), defaults: UserDefaults = .standard,
         persistence: PersistenceController = PersistenceController(inMemory: true)) {
        self.userID = userID; self.localStorage = storage
        self.defaults = defaults
        self.repository = StateRepository(persistence: persistence)
        self.cloudSync = persistence.syncsWithCloud ? CloudSyncMonitor(container: persistence.container, defaults: defaults) : nil
        self.mediaServerURL = defaults.string(forKey: Self.mediaServerKey) ?? "http://localhost:8080"
        self.autoEndRestEnabled = defaults.bool(forKey: "watch.autoEndRest.enabled")
    }
    /// 沿用旧版保存服务器地址的键，升级后媒体地址无需重新填写。
    static let mediaServerKey = "serverURL"
    private func publishTraining() { restNotifications?.publish(); watchBridge?.publish(); liveActivity?.publish() }
    var profileIdentity: String { profileServer + "|" + (userID ?? "") }
    var unit: String { state["unit"] as? String ?? "kg" }
    var routines: [Routine] { (state["routines"] as? [[String: Any]] ?? []).filter { ($0["id"] as? String) != nil }.map { Routine(raw: $0) } }
    var workouts: [[String: Any]] {
        var list = state["workouts"] as? [[String: Any]] ?? []
        for (key, item) in historyEdits {
            guard let local = item["proposed"] as? [String: Any] else { continue }
            var display = local; display["id"] = key
            if let i = list.firstIndex(where: { WorkoutRecord.key($0) == key }) { list[i] = display }
            else { list.append(display) }
        }
        return list.sorted { number($0["start"]) > number($1["start"]) }
    }
    var bodyweights: [[String: Any]] { healthSync.localBodyweights(state) }
    var todayRoutine: Routine? {
        let day = String(Calendar.current.component(.weekday, from: Date()) - 1)
        let week = state["week"] as? [String: Any] ?? [:]
        let plan = state["dayPlan"] as? [String: Any] ?? [:]
        let raw = plan[dayString()] ?? week[day]
        let id = raw as? String ?? (raw as? [String])?.first
        return routines.first { $0.id == id }
    }
    func exercise(_ id: String) -> Exercise? { index[id] }
    /// 内置动作库中的原始条目，不受本地副本或自建动作影响。
    func catalogueExercise(_ id: String) -> Exercise? { catalogueIndex[id] }
    func registerCatalogue(_ list: [Exercise]) {
        let sorted = list.sorted { $0.english < $1.english }
        guard catalogue != sorted else { return }
        catalogue = sorted
        catalogueIndex = Dictionary(sorted.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        catalogueMediaIDs = Set(sorted.map(\.id))
        rebuildExerciseIndex()
        publishTraining()
    }
    private func rebuildExerciseIndex() {
        var customs: [Exercise] = []
        var positions: [String: Int] = [:]
        for raw in state[StateDocument.customExercises] as? [Any] ?? [] {
            guard let raw = raw as? [String: Any], let exercise = Exercise.custom(raw) else { continue }
            if let position = positions[exercise.id] { customs[position] = exercise }
            else { positions[exercise.id] = customs.count; customs.append(exercise) }
        }
        // 用过的动作库动作在资料里有一份副本：显示以副本为准，位置仍按动作库排序。
        var copies: [String: Exercise] = [:]
        for case let raw as [String: Any] in state[StateDocument.exerciseCopies] as? [Any] ?? [] {
            guard let exercise = Exercise.catalogueCopy(raw), positions[exercise.id] == nil else { continue }
            copies[exercise.id] = exercise
        }
        // Keep gym-specific IDs intact. Refresh from scratch so renamed/deleted exercises and
        // profile changes cannot retain a stale name from the previous document.
        var next = customs
        for exercise in catalogue where positions[exercise.id] == nil { next.append(copies.removeValue(forKey: exercise.id) ?? exercise) }
        next += copies.values.sorted { $0.english < $1.english }
        guard exercises != next else { return }
        exercises = next
        index = Dictionary(exercises.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
    }
    func hasCatalogueMedia(_ id: String) -> Bool {
        catalogueMediaIDs.contains(id) && (4...5).contains(id.utf8.count)
            && id.utf8.allSatisfy { (48...57).contains($0) }
    }
    func imageMediaID(_ id: String) -> String? {
        catalogueMediaID(id, file: exercise(id)?.imageFile, fileExtension: "webp")
    }
    func videoMediaID(_ id: String) -> String? {
        catalogueMediaID(id, file: exercise(id)?.videoFile, fileExtension: "mp4")
    }
    private func catalogueMediaID(_ id: String, file: String?, fileExtension suffix: String) -> String? {
        guard let file else { return hasCatalogueMedia(id) ? id : nil }
        let ending = "." + suffix
        guard file.hasSuffix(ending) else { return nil }
        let source = String(file.dropLast(ending.count))
        return hasCatalogueMedia(source) ? source : nil
    }
    func remoteImageURL(_ id: String) -> URL? {
        guard let source = imageMediaID(id) else { return nil }
        return (try? ServerAddress(mediaServerURL))?.endpoint("exercise-media/still/\(source).webp")
    }
    func videoURL(_ id: String) -> URL? {
        guard let source = videoMediaID(id) else { return nil }
        return ExerciseVideoCache.shared.cachedURL(for: source) ?? remoteVideoURL(id)
    }
    func remoteVideoURL(_ id: String) -> URL? {
        guard let source = videoMediaID(id) else { return nil }
        return (try? ServerAddress(mediaServerURL))?.endpoint("exercise-media/clip/\(source).mp4")
    }
    func addRoutine(name: String, exerciseIDs: [String]) async -> Bool {
        let id = UUID().uuidString
        return await mutate { source in
            var s = source; var items = s["routines"] as? [[String: Any]] ?? []
            if !items.contains(where: { $0["id"] as? String == id }) {
                items.append(["id":id, "name":name, "emoji":"barbell", "ex":exerciseIDs.map { ["id":$0, "sets":3, "reps":10, "weight":0] as [String: Any] }])
            }
            s["routines"] = items; return s
        }
    }
    func appendExercise(_ exercise: Exercise, to routineID: String) async -> Bool {
        await mutate { source in
            var s = source; var routines = s["routines"] as? [[String: Any]] ?? []
            guard let i = routines.firstIndex(where: { $0["id"] as? String == routineID }) else { throw APIError.response(404, String(localized: "THIS_ROUTINE_WAS_REMOVED_REFRESH_AND_TRY_AGAIN", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) }
            var list = routines[i]["ex"] as? [[String: Any]] ?? []
            if !list.contains(where: { $0["id"] as? String == exercise.id }) { list.append(["id":exercise.id,"sets":3,"reps":10,"weight":0]) }
            routines[i]["ex"] = list; s["routines"] = routines; return s
        }
    }
    func recordWeight(_ value: Double) async -> Bool {
        let day = dayString(), t = Date().timeIntervalSince1970 * 1000, expectedUnit = unit
        return await mutate { source in
            guard (source["unit"] as? String ?? "kg") == expectedUnit else { throw APIError.response(409, String(localized: "THE_WEIGHT_UNIT_CHANGED_ON_ANOTHER_DEVICE_REFRESH_AND_TRY_AGAIN", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) }
            var s = source; var list = s["bodyweight"] as? [[String: Any]] ?? []
            let row: [String: Any] = ["d":day,"w":value,"t":t]
            if let i = list.firstIndex(where: { $0["d"] as? String == day }) { list[i].merge(row) { _, new in new } } else { list.append(row) }
            s["bodyweight"] = list.sorted { ($0["d"] as? String ?? "") < ($1["d"] as? String ?? "") }; return s
        }
    }
    func start(_ routine: Routine) { start([routine]) }
    func start(_ selected: [Routine]) {
        guard !selected.isEmpty else { return }
        startSession(routineIDs: selected.map(\.id))
    }
    func startFreestyle() { startSession(routineIDs: []) }
    private func startSession(routineIDs: [String]) {
        guard draft == nil else { selectedTab = 2; return }
        do {
            let raw = try WebRules.shared.call("beginAdvanced",payload:["state":state,"ids":routineIDs,"id":UUID().uuidString,"now":Date().timeIntervalSince1970*1000,"day":dayString()]) as! [String:Any]
            draft = try TrainingDraft.fromWeb(raw,unit:unit);selectedTab = 2
            if persistDraft(), let draft { workoutHealth.begin(draft) }
        } catch { self.error = error.localizedDescription }
    }
    func finish() async {
        liveInputBuffer.commitAll()
        guard !syncing, let d = draft, d.completedSets > 0 else { error = String(localized: "COMPLETE_AT_LEAST_ONE_SET_BEFORE_SAVING_YOUR_WORKOUT", bundle: AppLanguage.bundle, locale: AppLanguage.locale); return }
        do { try TrainingInput.validate(d.activeJSON) } catch { self.error = error.localizedDescription; return }
        if d.activeJSON["nativeFinishAt"] == nil { changeActive { $0["nativeFinishAt"] = Date().timeIntervalSince1970 * 1000 } }
        guard persistDraft(), let snapshot = draft else { error = localSaveError; return }
        let active = TrainingInput.clean(snapshot.activeJSON) as! [String:Any]
        let finishAt = number(snapshot.activeJSON["nativeFinishAt"])
        guard workoutHealth.finish(snapshot, at: Date(timeIntervalSince1970: finishAt / 1000)) else { error = workoutHealth.status; return }
        var expected: [String:Any]?
        let saved = await mutate(verify: { source in
            guard let expected else { return false }
            return (source["workouts"] as? [[String:Any]] ?? []).contains { WorkoutRecord.key($0) == snapshot.id && RecordPatch.equal($0,expected) }
        }) { source in
            guard (source["unit"] as? String ?? "kg") == snapshot.unit else { throw APIError.response(409, String(localized: "THE_SERVER_S_WEIGHT_UNIT_CHANGED_YOUR_WORKOUT_DRAFT_IS_SAFE_ON", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) }
            // Calculate once with a frozen finish time. A lost response can safely be retried by ID.
            var without = source
            let existing = (source["workouts"] as? [[String:Any]] ?? []).first { $0["id"] as? String == snapshot.id }
            without["workouts"] = (source["workouts"] as? [[String:Any]] ?? []).filter { $0["id"] as? String != snapshot.id }
            let result = try WebRules.shared.call("finishAdvanced",payload:["state":without,"active":active,"now":finishAt,"today":dayString()]) as! [String:Any]
            let built = (result["workouts"] as? [[String:Any]])?.first { $0["id"] as? String == snapshot.id }
            guard let built else { throw APIError.invalidResponse }
            if let existing {
                for key in ["entries","start","end","name","note"] where !RecordPatch.equal(existing[key],built[key]) { throw APIError.response(409,String(localized: "THIS_WORKOUT_IS_ALREADY_SAVED_ON_THE_SERVER_WITH_DIFFERENT_DETAILS_YOUR", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) }
                expected = existing; return source
            }
            expected = built; return result
        }
        if saved {
            liveInputBuffer.commitAll()
            guard RecordPatch.equal(draft?.activeJSON,snapshot.activeJSON), let folder = accountFolder else { error = String(localized: "NEW_INPUT_WAS_ENTERED_WHILE_SUBMITTING_YOUR_LOCAL_DRAFT_HAS_BEEN_KEPT", bundle: AppLanguage.bundle, locale: AppLanguage.locale); return }
            do { try localStorage.write(["draft":try JSONSerialization.jsonObject(with:JSONEncoder().encode(snapshot))],to:folder.appendingPathComponent("archive/live-\(snapshot.id).json")) }
            catch { localSaveError = error.localizedDescription; return }
            self.draft = nil; selectedTab = 3
        }
    }
    func deleteCurrentWorkout() {
        liveInputBuffer.commitAll()
        guard !syncing, draft != nil else { return }
        guard let url = draftURL else { error = String(localized: "YOUR_ACCOUNT_COULD_NOT_BE_IDENTIFIED_THIS_WORKOUT_CANNOT_BE_DELETED", bundle: AppLanguage.bundle, locale: AppLanguage.locale); return }
        do {
            // Persist an empty document first: a failed write must keep the live input,
            // and an absent file would allow restoreDraft to adopt a legacy draft.
            if let draft, !workoutHealth.finish(draft, discard: true, at: Date()) { error = workoutHealth.status; return }
            try localStorage.write([:], to: url)
            draft = nil
            selectedTab = 2
        } catch {
            self.error = String(format: String(localized: "COULD_NOT_DELETE_THE_WORKOUT_IT_HAS_BEEN_KEPT_COUNT", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(describing: error.localizedDescription))
        }
    }
    func updateSet(entry: Int, set: Int, _ change: (inout TrainingSet) -> Void) {
        guard var d = draft, d.entries.indices.contains(entry), d.entries[entry].sets.indices.contains(set) else { return }
        change(&d.entries[entry].sets[set]); draft = d
    }
    private var draftURL: URL? {
        guard userID != nil else { return nil }
        return accountFolder?.appendingPathComponent("live-draft.json")
    }
    @discardableResult func persistDraft() -> Bool {
        liveInputBuffer.commitAll()
        let started = ContinuousClock.now
        var outcome = "failed"
        if WorkoutActivityDiagnostics.traceID != nil { WorkoutActivityDiagnostics.record("draft.save.begin", ["has_draft": String(draft != nil)]) }
        defer {
            if WorkoutActivityDiagnostics.traceID != nil {
                WorkoutActivityDiagnostics.record("draft.save.end", ["outcome": outcome, "elapsed_ms": WorkoutActivityDiagnostics.elapsed(started)])
            }
        }
        guard let url = draftURL else {
            outcome = draft == nil ? "no_draft" : "missing_account"
            if draft != nil {
                localSaveIssues["live"] = String(localized: "NO_ACCOUNT_IS_AVAILABLE_TO_SAVE_THIS_WORKOUT_DRAFT_LOCALLY", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
                WorkoutActivityDiagnostics.record("draft.save.failed", ["reason": "missing_account"], failure: true)
            }
            return draft == nil
        }
        do {
            let value: [String: Any]
            if let draft { value = ["draft": try JSONSerialization.jsonObject(with: JSONEncoder().encode(draft))] }
            else { value = [:] }
            try localStorage.write(value, to: url); if localSaveIssues["live"] != nil { localSaveIssues.removeValue(forKey:"live") }; outcome = "saved"; return true
        } catch {
            WorkoutActivityDiagnostics.record("draft.save.failed", WorkoutActivityDiagnostics.errorFields(error), failure: true)
            localSaveIssues["live"] = String(format: String(localized: "COULD_NOT_SAVE_THE_WORKOUT_DRAFT_ON_THIS_DEVICE_COUNT", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(describing: error.localizedDescription)); return false
        }
    }
    func restoreDraft() {
        let started = ContinuousClock.now
        var source = "none"
        WorkoutActivityDiagnostics.record("draft.restore.begin", ["has_account": String(userID != nil)])
        defer { WorkoutActivityDiagnostics.record("draft.restore.end", ["source": source, "has_draft": String(draft != nil),
            "save_error": String(localSaveError != nil), "elapsed_ms": WorkoutActivityDiagnostics.elapsed(started)]) }
        guard let url = draftURL else { source = "missing_account"; return }
        do {
            if let saved = try localStorage.read(url) {
                source = "account_storage"
                if let raw = saved["draft"] { draft = try JSONDecoder().decode(TrainingDraft.self, from: JSONSerialization.data(withJSONObject: raw)) }
                return
            }
            // Adopt pre-offline-client drafts without deleting the old copy.
            guard let userID else { return }
            let key = Data("\(profileServer)|\(userID)".utf8).base64EncodedString().replacingOccurrences(of: "/", with: "_")
            let old = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("draft-\(key).json")
            if FileManager.default.fileExists(atPath: old.path) { source = "legacy_storage"; draft = try JSONDecoder().decode(TrainingDraft.self, from: Data(contentsOf: old)) }
        } catch {
            WorkoutActivityDiagnostics.record("draft.restore.failed", WorkoutActivityDiagnostics.errorFields(error), failure: true)
            localSaveError = String(format: String(localized: "COULD_NOT_READ_THE_WORKOUT_DRAFT_THE_FILE_HAS_BEEN_KEPT_COUNT", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(describing: error.localizedDescription))
        }
    }
}
