import Foundation
import Observation

@MainActor @Observable final class GymStore {
    private(set) var exercises: [Exercise] = []
    var catalogueError: String?
    var state: [String: Any] = [:] { didSet { rebuildExerciseIndex() } }
    var serverURL = UserDefaults.standard.string(forKey: "serverURL") ?? "http://localhost:8080"
    var userName: String?
    var userID: String?
    var online = false
    var syncing = false
    var status = "正在连接服务…"
    var error: String?
    var editError: String?
    var lastSync: Date?
    var selectedTab = 0
    var showSettings = false
    var selectedExercise: Exercise?
    var draft: TrainingDraft? { didSet { persistDraft() } }
    var localSaveIssues: [String: String] = [:]
    var localSaveError: String? {
        get { localSaveIssues.sorted { $0.key < $1.key }.first?.value }
        set { localSaveIssues["general"] = newValue }
    }
    var historyEdits: [String: [String: Any]] = [:]
    let localStorage: LocalTrainingStorage
    @ObservationIgnored lazy var healthSync = HealthWeightSync(store:self)
    var restUntil: Date? {
        get { guard let t = draft?.activeJSON["nativeRest"] as? [String: Any] else { return nil }; return Date(timeIntervalSince1970: number(t["end"])) }
        set { changeActive { raw in if let newValue { var rest = raw["nativeRest"] as? [String: Any] ?? [:]; rest["end"] = newValue.timeIntervalSince1970; raw["nativeRest"] = rest } else { raw.removeValue(forKey: "nativeRest") } } }
    }
    private var index: [String: Exercise] = [:]
    private var catalogue: [Exercise] = []
    private var client: APIClient?
    private var loading = false
    init(client: APIClient? = nil, userID: String? = nil, storage: LocalTrainingStorage = LocalTrainingStorage()) { self.client = client; self.userID = userID; self.localStorage = storage }
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
        catalogue = list.sorted { $0.english < $1.english }
        rebuildExerciseIndex()
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
        exercises = customs + catalogue.filter { positions[$0.id] == nil }
        index = Dictionary(exercises.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
    }
    func mediaURL(_ id: String, video: Bool = false) -> URL? {
        guard let address = try? ServerAddress(serverURL), id.range(of: "^[0-9]{4,5}$", options: .regularExpression) != nil else { return nil }
        return address.endpoint("exercise-media/\(video ? "clip" : "still")/\(id).\(video ? "mp4" : "webp")")
    }
    func prepareOfflineLaunch() {
        do { client = APIClient(address:try ServerAddress(serverURL),token:CredentialStore.read(for:serverURL)) }
        catch { self.error = error.localizedDescription }
        restoreOfflineAccount()
        if userID == nil, let token = client?.token, let id = token.split(separator: ":").first, !id.isEmpty {
            // Upgrade path: old versions stored only the paired token and the live draft.
            userID = String(id); userName = "离线账号"; restoreLocalTraining()
        }
        healthSync.prepare()
    }
    func boot() async {
        do {
            guard let url = Bundle.main.url(forResource: "catalogue", withExtension: "json") else { throw APIError.invalidResponse }
            let list = try await Task.detached { try JSONDecoder().decode([Exercise].self, from: Data(contentsOf: url)) }.value
            registerCatalogue(list)
        } catch { catalogueError = "动作库加载失败：\(error.localizedDescription)" }
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
        guard !loading, !syncing, let client else { return }; loading = true; defer { loading = false }
        do {
            let health = try await client.request("api/health")
            online = health["ok"] as? Bool == true
            guard online else { throw APIError.response(503, "服务暂不可用。") }
            if client.token != nil {
                let me = try await client.request("api/me")
                if let token = me["token"] as? String { try CredentialStore.save(token, for: serverURL); client.token = token }
                let user = me["user"] as? [String: Any] ?? [:]
                let changed = userID != user["id"] as? String
                userName = user["name"] as? String; userID = user["id"] as? String
                let result = try await client.request("api/data")
                state = result["state"] as? [String: Any] ?? [:]
                if changed { restoreLocalTraining() }
                cacheProfile()
                lastSync = Date(); status = "已同步"
            } else { status = "服务已连接 · 尚未配对账号" }
        } catch {
            if case APIError.response(401, _) = error { userName = nil; status = "需要重新配对" }
            else { online = false; status = "离线 · 使用本机数据" }
        }
    }
    func pair(server: String, code: String) async {
        guard !syncing && !loading else { return }
        guard draft == nil else { error = "请先完成当前训练，再切换账号或服务。"; return }
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
            state = data["state"] as? [String: Any] ?? [:]
            online = true; lastSync = Date(); status = "已同步"; showSettings = false; cacheProfile()
            healthSync.prepare()
        } catch { self.error = error.localizedDescription }
    }
    /// Rebase a narrow, idempotent operation onto the latest whole document; never replace unknown fields.
    func mutate(reportError: Bool = true, verify: (([String: Any]) -> Bool)? = nil, _ operation: ([String: Any]) throws -> [String: Any]) async -> Bool {
        editError = nil
        guard !syncing && !loading else { if reportError { error = APIError.busy.localizedDescription } else { editError = APIError.busy.localizedDescription }; return false }
        guard let client, client.token != nil, userID != nil else { if reportError { error = APIError.signIn.localizedDescription; showSettings = true } else { editError = APIError.signIn.localizedDescription }; return false }
        syncing = true; defer { syncing = false }
        do {
            for attempt in 0..<3 {
                let current = try await client.request("api/data")
                let source = current["state"] as? [String: Any] ?? ["unit":"kg", "routines":[], "workouts":[], "bodyweight":[], "week":[:]]
                let next = try operation(source)
                if RecordPatch.equal(source,next), verify?(source) != false { state = source; cacheProfile(); return true }
                var body: [String: Any] = ["state": next, "baseRev": current["rev"] ?? 0]
                if let wid = source["_wid"] as? String { body["baseWid"] = wid }
                do {
                    _ = try await client.request("api/data", method: "PUT", body: body)
                    if let verify {
                        let canonical = try await client.request("api/data")
                        guard let doc = canonical["state"] as? [String: Any], verify(doc) else { throw APIError.response(0, "服务器尚未确认这次保存。本机内容已保留，可以重试。") }
                        state = doc
                    } else {
                        state = next
                        if let canonical = try? await client.request("api/data"), let doc = canonical["state"] as? [String: Any] { state = doc }
                    }
                    online = true; lastSync = Date(); status = "已同步"; cacheProfile()
                    return true
                } catch APIError.response(409, _) where attempt < 2 { continue }
            }
            throw APIError.response(409, "conflict")
        } catch { if reportError { self.error = error.localizedDescription } else { editError = error.localizedDescription }; return false }
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
            guard let i = routines.firstIndex(where: { $0["id"] as? String == routineID }) else { throw APIError.response(404, "这个计划已被移除，请刷新后重试。") }
            var list = routines[i]["ex"] as? [[String: Any]] ?? []
            if !list.contains(where: { $0["id"] as? String == exercise.id }) { list.append(["id":exercise.id,"sets":3,"reps":10,"weight":0]) }
            routines[i]["ex"] = list; s["routines"] = routines; return s
        }
    }
    func recordWeight(_ value: Double) async -> Bool {
        let day = dayString(), t = Date().timeIntervalSince1970 * 1000, expectedUnit = unit
        return await mutate { source in
            guard (source["unit"] as? String ?? "kg") == expectedUnit else { throw APIError.response(409, "重量单位在其他设备上发生变化，请刷新后重试。") }
            var s = source; var list = s["bodyweight"] as? [[String: Any]] ?? []
            let row: [String: Any] = ["d":day,"w":value,"t":t]
            if let i = list.firstIndex(where: { $0["d"] as? String == day }) { list[i].merge(row) { _, new in new } } else { list.append(row) }
            s["bodyweight"] = list.sorted { ($0["d"] as? String ?? "") < ($1["d"] as? String ?? "") }; return s
        }
    }
    func start(_ routine: Routine) { start([routine]) }
    func start(_ selected: [Routine]) {
        guard !selected.isEmpty else { return }
        guard draft == nil else { selectedTab = 2; return }
        guard userName != nil else { showSettings = true; return }
        do {
            let raw = try WebRules.shared.call("beginAdvanced",payload:["state":state,"ids":selected.map(\.id),"id":UUID().uuidString,"now":Date().timeIntervalSince1970*1000,"day":dayString()]) as! [String:Any]
            draft = try TrainingDraft.fromWeb(raw,unit:unit);selectedTab = 2
        } catch { self.error = error.localizedDescription }
    }
    func finish() async {
        guard !syncing, let d = draft, d.completedSets > 0 else { error = "至少完成一组后再保存训练。"; return }
        do { try TrainingInput.validate(d.activeJSON) } catch { self.error = error.localizedDescription; return }
        if d.activeJSON["nativeFinishAt"] == nil { changeActive { $0["nativeFinishAt"] = Date().timeIntervalSince1970 * 1000 } }
        guard persistDraft(), let snapshot = draft else { error = localSaveError; return }
        let active = TrainingInput.clean(snapshot.activeJSON) as! [String:Any]
        let finishAt = number(snapshot.activeJSON["nativeFinishAt"])
        var expected: [String:Any]?
        let saved = await mutate(verify: { source in
            guard let expected else { return false }
            return (source["workouts"] as? [[String:Any]] ?? []).contains { WorkoutRecord.key($0) == snapshot.id && RecordPatch.equal($0,expected) }
        }) { source in
            guard (source["unit"] as? String ?? "kg") == snapshot.unit else { throw APIError.response(409, "服务端重量单位已改变，训练草稿保留在本机。") }
            // Calculate once with a frozen finish time. A lost response can safely be retried by ID.
            var without = source
            let existing = (source["workouts"] as? [[String:Any]] ?? []).first { $0["id"] as? String == snapshot.id }
            without["workouts"] = (source["workouts"] as? [[String:Any]] ?? []).filter { $0["id"] as? String != snapshot.id }
            let result = try WebRules.shared.call("finishAdvanced",payload:["state":without,"active":active,"now":finishAt,"today":dayString()]) as! [String:Any]
            let built = (result["workouts"] as? [[String:Any]])?.first { $0["id"] as? String == snapshot.id }
            guard let built else { throw APIError.invalidResponse }
            if let existing {
                for key in ["entries","start","end","name","note"] where !RecordPatch.equal(existing[key],built[key]) { throw APIError.response(409,"同一训练已在服务端保存，但内容不同。本机草稿已保留，请核对。") }
                expected = existing; return source
            }
            expected = built; return result
        }
        if saved {
            guard RecordPatch.equal(draft?.activeJSON,snapshot.activeJSON), let folder = accountFolder else { error = "提交期间有新的输入，已保留本机草稿。"; return }
            do { try localStorage.write(["draft":try JSONSerialization.jsonObject(with:JSONEncoder().encode(snapshot))],to:folder.appendingPathComponent("archive/live-\(snapshot.id).json")) }
            catch { localSaveError = error.localizedDescription; return }
            self.draft = nil; selectedTab = 3
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
        guard let url = draftURL else { if draft != nil { localSaveIssues["live"] = "没有账号，训练草稿无法写入本机。" }; return draft == nil }
        do {
            let value: [String: Any]
            if let draft { value = ["draft": try JSONSerialization.jsonObject(with: JSONEncoder().encode(draft))] }
            else { value = [:] }
            try localStorage.write(value, to: url); localSaveIssues.removeValue(forKey:"live"); return true
        } catch { localSaveIssues["live"] = "训练草稿写入本机失败：\(error.localizedDescription)"; return false }
    }
    func restoreDraft() {
        guard let url = draftURL else { return }
        do {
            if let saved = try localStorage.read(url) {
                if let raw = saved["draft"] { draft = try JSONDecoder().decode(TrainingDraft.self, from: JSONSerialization.data(withJSONObject: raw)) }
                return
            }
            // Adopt pre-offline-client drafts without deleting the old copy.
            guard let userID else { return }
            let key = Data("\(serverURL)|\(userID)".utf8).base64EncodedString().replacingOccurrences(of: "/", with: "_")
            let old = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("draft-\(key).json")
            if FileManager.default.fileExists(atPath: old.path) { draft = try JSONDecoder().decode(TrainingDraft.self, from: Data(contentsOf: old)) }
        } catch { localSaveError = "训练草稿读取失败，文件已保留：\(error.localizedDescription)" }
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
            if !loading && !syncing { return }
            try await Task.sleep(for:.milliseconds(100))
        }
        throw APIError.busy
    }
    func refreshCoachState() async throws {
        try await waitForCoachIdle()
        guard !loading, !syncing else { throw APIError.busy }
        loading = true; defer { loading = false }
        let result = try await coachRequest("api/data")
        guard let document = result["state"] as? [String: Any] else { throw APIError.invalidResponse }
        state = document; cacheProfile(); lastSync = Date()
    }
}
