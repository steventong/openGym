import Foundation
import Observation

@MainActor @Observable final class GymStore {
    private(set) var exercises: [Exercise] = []
    var catalogueError: String?
    var state: [String: Any] = [:] {
        didSet {
            if !RecordPatch.equal(oldValue["lang"], state["lang"]) { AppLanguage.setLanguage(state["lang"] as? String) }
            // Workout, weight and sync metadata changes do not change exercise names or images.
            if !RecordPatch.equal(oldValue["customEx"],state["customEx"]) { rebuildExerciseIndex() }
            publishTraining()
        }
    }
    var serverURL = UserDefaults.standard.string(forKey: "serverURL") ?? "http://localhost:8080"
    var userName: String?
    var userID: String? { didSet { publishTraining() } }
    var online = false
    var syncing = false { didSet { publishTraining() } }
    var status = String(localized: "CONNECTING_TO_SERVER", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
    var error: String?
    var editError: String?
    var lastSync: Date?
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
    var liveActivityIssue: String?
    var localSaveIssues: [String: String] = [:] { didSet { publishTraining() } }
    var localSaveError: String? {
        get { localSaveIssues.sorted { $0.key < $1.key }.first?.value }
        set { localSaveIssues["general"] = newValue }
    }
    var historyEdits: [String: [String: Any]] = [:]
    let localStorage: LocalTrainingStorage
    @ObservationIgnored lazy var healthSync = HealthWeightSync(store:self)
    @ObservationIgnored lazy var workoutHealth = WorkoutHealthSync(store: self)
    var restUntil: Date? {
        get { guard let t = draft?.activeJSON["nativeRest"] as? [String: Any] else { return nil }; return Date(timeIntervalSince1970: number(t["end"])) }
        set { changeActive { raw in if let newValue { var rest = raw["nativeRest"] as? [String: Any] ?? [:]; rest["end"] = newValue.timeIntervalSince1970; raw["nativeRest"] = rest } else { raw.removeValue(forKey: "nativeRest") } } }
    }
    private var index: [String: Exercise] = [:]
    private var catalogue: [Exercise] = []
    private var thumbnailAssets: [String: String] = [:]
    private var client: APIClient?
    @ObservationIgnored private var loading = false
    @ObservationIgnored private var backgroundMutation = false
    init(client: APIClient? = nil, userID: String? = nil, storage: LocalTrainingStorage = LocalTrainingStorage()) { self.client = client; self.userID = userID; self.localStorage = storage }
    private func publishTraining() { restNotifications?.publish(); watchBridge?.publish(); liveActivity?.publish() }
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
    func registerCatalogue(_ list: [Exercise]) {
        let sorted = list.sorted { $0.english < $1.english }
        guard catalogue != sorted else { return }
        catalogue = sorted
        thumbnailAssets = Dictionary(uniqueKeysWithValues: sorted.compactMap { exercise in
            exercise.thumbnailAsset.map { (exercise.id, $0) }
        })
        rebuildExerciseIndex()
        publishTraining()
    }
    private func rebuildExerciseIndex() {
        var customs: [Exercise] = []
        var positions: [String: Int] = [:]
        for raw in state["customEx"] as? [Any] ?? [] {
            guard let raw = raw as? [String: Any], let exercise = Exercise.custom(raw) else { continue }
            if let position = positions[exercise.id] { customs[position] = exercise }
            else { positions[exercise.id] = customs.count; customs.append(exercise) }
        }
        // Keep gym-specific IDs intact. Refresh from scratch so renamed/deleted exercises and
        // account changes cannot retain a stale name from the previous document.
        let next = customs + catalogue.filter { positions[$0.id] == nil }
        guard exercises != next else { return }
        exercises = next
        index = Dictionary(exercises.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
    }
    func thumbnailAssetName(_ id: String) -> String? {
        thumbnailAssets[id]
    }
    func videoURL(_ id: String) -> URL? {
        guard thumbnailAssetName(id) != nil else { return nil }
        return ExerciseVideoCache.shared.cachedURL(for: id) ?? remoteVideoURL(id)
    }
    func remoteVideoURL(_ id: String) -> URL? {
        guard id.range(of: "^[0-9]{4,5}$", options: .regularExpression) != nil else { return nil }
        return (try? ServerAddress(serverURL))?.endpoint("exercise-media/clip/\(id).mp4")
    }
    func prepareOfflineLaunch() {
        do { client = APIClient(address:try ServerAddress(serverURL),token:CredentialStore.read(for:serverURL)) }
        catch { self.error = error.localizedDescription }
        restoreOfflineAccount()
        if userID == nil, let token = client?.token, let id = token.split(separator: ":").first, !id.isEmpty {
            // Upgrade path: old versions stored only the paired token and the live draft.
            userID = String(id); userName = String(localized: "OFFLINE_ACCOUNT", bundle: AppLanguage.bundle, locale: AppLanguage.locale); restoreLocalTraining()
        }
        healthSync.prepare()
    }
    func boot() async {
        do {
            guard let url = Bundle.main.url(forResource: "catalogue", withExtension: "json") else { throw APIError.invalidResponse }
            let list = try await Task.detached { try JSONDecoder().decode([Exercise].self, from: Data(contentsOf: url)) }.value
            registerCatalogue(list)
        } catch { catalogueError = String(format: String(localized: "COULD_NOT_LOAD_EXERCISE_LIBRARY_COUNT", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(describing: error.localizedDescription)) }
        do {
            let address = try ServerAddress(serverURL)
            client = APIClient(address: address, token: CredentialStore.read(for: serverURL))
        } catch { self.error = error.localizedDescription }
        if userID == nil { restoreOfflineAccount() }
        await refresh()
        await healthSync.resume()
        #if DEBUG
        if let i = ProcessInfo.processInfo.arguments.firstIndex(of: "-pairCode"), ProcessInfo.processInfo.arguments.count > i + 1 {
            await pair(server: serverURL, code: ProcessInfo.processInfo.arguments[i + 1])
        }
        #endif
    }
    func refresh() async {
        guard !loading, !syncing, !backgroundMutation, let client else { return }; loading = true; defer { loading = false }
        do {
            let health = try await client.request("api/health")
            online = health["ok"] as? Bool == true
            guard online else { throw APIError.response(503, String(localized: "SERVICE_TEMPORARILY_UNAVAILABLE", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) }
            if client.token != nil {
                let me = try await client.request("api/me")
                if let token = me["token"] as? String { try CredentialStore.save(token, for: serverURL); client.token = token }
                let user = me["user"] as? [String: Any] ?? [:]
                let changed = userID != user["id"] as? String
                if userName != user["name"] as? String { userName = user["name"] as? String }
                if changed { userID = user["id"] as? String }
                let result = try await client.request("api/data")
                try backupServerSnapshot(result, server: client.address.url.absoluteString)
                let next = result["state"] as? [String: Any] ?? [:]
                // Preserve server stamps too; only suppress a refresh when the complete document matches.
                if !NSDictionary(dictionary:state).isEqual(to:next) { state = next }
                if changed { restoreLocalTraining() }
                cacheProfile()
                lastSync = Date(); status = String(localized: "SYNCED", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
            } else { status = String(localized: "SERVER_CONNECTED_ACCOUNT_NOT_PAIRED", bundle: AppLanguage.bundle, locale: AppLanguage.locale) }
        } catch {
            if let issue = localSaveIssues["serverBackup"], error.localizedDescription == issue { status = issue; self.error = issue; return }
            if case APIError.response(401, _) = error { userName = nil; status = String(localized: "PAIR_AGAIN_TO_RECONNECT", bundle: AppLanguage.bundle, locale: AppLanguage.locale) }
            else { online = false; status = String(localized: "OFFLINE_USING_LOCAL_DATA", bundle: AppLanguage.bundle, locale: AppLanguage.locale) }
        }
    }
    func pair(server: String, code: String) async {
        guard !syncing && !loading && !backgroundMutation else { return }
        guard draft == nil else { error = String(localized: "FINISH_YOUR_CURRENT_WORKOUT_BEFORE_CHANGING_ACCOUNTS_OR_SERVERS", bundle: AppLanguage.bundle, locale: AppLanguage.locale); return }
        syncing = true; defer { syncing = false }
        do {
            let address = try ServerAddress(server)
            let next = APIClient(address: address)
            let result = try await next.request("api/pair/redeem", method: "POST", body: ["code": code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()])
            guard let token = result["token"] as? String, let user = result["user"] as? [String: Any], let id = user["id"] as? String else { throw APIError.invalidResponse }
            try CredentialStore.save(token, for: address.url.absoluteString)
            next.token = token
            client = next; serverURL = address.url.absoluteString
            UserDefaults.standard.set(serverURL, forKey: "serverURL")
            userID = id; userName = user["name"] as? String
            state = [:]; historyEdits = [:]; restoreLocalTraining()
            let data = try await next.request("api/data")
            try backupServerSnapshot(data, server: next.address.url.absoluteString)
            state = data["state"] as? [String: Any] ?? [:]
            online = true; lastSync = Date(); status = String(localized: "SYNCED", bundle: AppLanguage.bundle, locale: AppLanguage.locale); showSettings = false; cacheProfile()
            healthSync.prepare()
        } catch { self.error = error.localizedDescription }
    }
    /// Rebase a narrow, idempotent operation onto the latest whole document; never replace unknown fields.
    func mutate(reportError: Bool = true, background: Bool = false, verify: (([String: Any]) -> Bool)? = nil, _ operation: ([String: Any]) throws -> [String: Any]) async -> Bool {
        editError = nil
        guard !syncing && !loading && !backgroundMutation else { if reportError { error = APIError.busy.localizedDescription } else { editError = APIError.busy.localizedDescription }; return false }
        guard let client, client.token != nil, userID != nil else { if reportError { error = APIError.signIn.localizedDescription; showSettings = true } else { editError = APIError.signIn.localizedDescription }; return false }
        if background { backgroundMutation = true } else { syncing = true }
        defer { if background { backgroundMutation = false } else { syncing = false } }
        do {
            for attempt in 0..<3 {
                let current = try await client.request("api/data")
                try backupServerSnapshot(current, server: client.address.url.absoluteString)
                let source = current["state"] as? [String: Any] ?? ["unit":"kg", "routines":[], "workouts":[], "bodyweight":[], "week":[:]]
                let next = try operation(source)
                if RecordPatch.equal(source,next), verify?(source) != false { acceptSyncedState(source); cacheProfile(); return true }
                var body: [String: Any] = ["state": next, "baseRev": current["rev"] ?? 0]
                if let wid = source["_wid"] as? String { body["baseWid"] = wid }
                do {
                    _ = try await client.request("api/data", method: "PUT", body: body)
                    if let verify {
                        let canonical = try await client.request("api/data")
                        guard let doc = canonical["state"] as? [String: Any], verify(doc) else { throw APIError.response(0, String(localized: "THE_SERVER_HAS_NOT_CONFIRMED_THIS_SAVE_YOUR_LOCAL_DATA_IS_SAFE", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) }
                        acceptSyncedState(doc)
                    } else {
                        acceptSyncedState(next)
                        if let canonical = try? await client.request("api/data"), let doc = canonical["state"] as? [String: Any] { acceptSyncedState(doc) }
                    }
                    online = true; lastSync = Date(); status = String(localized: "SYNCED", bundle: AppLanguage.bundle, locale: AppLanguage.locale); cacheProfile()
                    return true
                } catch APIError.response(409, _) where attempt < 2 { continue }
            }
            throw APIError.response(409, "conflict")
        } catch { if reportError { self.error = error.localizedDescription } else { editError = error.localizedDescription }; return false }
    }
    private func acceptSyncedState(_ next: [String: Any]) {
        if !NSDictionary(dictionary: state).isEqual(to: next) { state = next }
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
        guard userName != nil else { showSettings = true; return }
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
            let key = Data("\(serverURL)|\(userID)".utf8).base64EncodedString().replacingOccurrences(of: "/", with: "_")
            let old = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("draft-\(key).json")
            if FileManager.default.fileExists(atPath: old.path) { source = "legacy_storage"; draft = try JSONDecoder().decode(TrainingDraft.self, from: Data(contentsOf: old)) }
        } catch {
            WorkoutActivityDiagnostics.record("draft.restore.failed", WorkoutActivityDiagnostics.errorFields(error), failure: true)
            localSaveError = String(format: String(localized: "COULD_NOT_READ_THE_WORKOUT_DRAFT_THE_FILE_HAS_BEEN_KEPT_COUNT", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(describing: error.localizedDescription))
        }
    }
}

extension GymStore {
    var coachIdentity: String { serverURL + "|" + (userID ?? "") }
    /// The paired session is the only credential used by the native Coach.
    func coachRequest(_ path: String, method: String = "GET", body: [String: Any]? = nil) async throws -> [String: Any] {
        guard let client, client.token != nil, userID != nil else { throw APIError.signIn }
        let identity = coachIdentity
        let result = try await client.request(path, method: method, body: body)
        guard identity == coachIdentity else { throw CancellationError() }
        return result
    }
    func waitForCoachIdle() async throws {
        for _ in 0..<50 {
            try Task.checkCancellation()
            if !loading && !syncing && !backgroundMutation { return }
            try await Task.sleep(for:.milliseconds(100))
        }
        throw APIError.busy
    }
    func refreshCoachState() async throws {
        try await waitForCoachIdle()
        guard !loading, !syncing, !backgroundMutation else { throw APIError.busy }
        loading = true; defer { loading = false }
        let result = try await coachRequest("api/data")
        try backupServerSnapshot(result, server: serverURL)
        guard let document = result["state"] as? [String: Any] else { throw APIError.invalidResponse }
        state = document; cacheProfile(); lastSync = Date()
    }
}
