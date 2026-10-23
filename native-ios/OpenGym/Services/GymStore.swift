import Foundation
import Observation

@MainActor @Observable final class GymStore {
    var exercises: [Exercise] = []
    var catalogueError: String?
    var state: [String: Any] = [:]
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
    var restUntil: Date?
    private var index: [String: Exercise] = [:]
    private var client: APIClient?
    private var loading = false
    init(client: APIClient? = nil, userID: String? = nil) { self.client = client; self.userID = userID }
    var unit: String { state["unit"] as? String ?? "kg" }
    var routines: [Routine] { (state["routines"] as? [[String: Any]] ?? []).filter { ($0["id"] as? String) != nil }.map { Routine(raw: $0) } }
    var workouts: [[String: Any]] { (state["workouts"] as? [[String: Any]] ?? []).sorted { number($0["start"]) > number($1["start"]) } }
    var bodyweights: [[String: Any]] { (state["bodyweight"] as? [[String: Any]] ?? []).sorted { ($0["d"] as? String ?? "") < ($1["d"] as? String ?? "") } }
    var todayRoutine: Routine? {
        let day = String(Calendar.current.component(.weekday, from: Date()) - 1)
        let week = state["week"] as? [String: Any] ?? [:]
        let plan = state["dayPlan"] as? [String: Any] ?? [:]
        let raw = plan[dayString()] ?? week[day]
        let id = raw as? String ?? (raw as? [String])?.first
        return routines.first { $0.id == id }
    }
    func exercise(_ id: String) -> Exercise? { index[id] }
    func mediaURL(_ id: String, video: Bool = false) -> URL? {
        guard let address = try? ServerAddress(serverURL), id.range(of: "^[0-9]{4,5}$", options: .regularExpression) != nil else { return nil }
        return address.endpoint("exercise-media/\(video ? "clip" : "still")/\(id).\(video ? "mp4" : "webp")")
    }
    func boot() async {
        do {
            guard let url = Bundle.main.url(forResource: "catalogue", withExtension: "json") else { throw APIError.invalidResponse }
            let list = try await Task.detached { try JSONDecoder().decode([Exercise].self, from: Data(contentsOf: url)) }.value
            exercises = list.sorted { $0.english < $1.english }; index = Dictionary(uniqueKeysWithValues: list.map { ($0.id, $0) })
        } catch { catalogueError = "动作库加载失败：\(error.localizedDescription)" }
        do {
            let address = try ServerAddress(serverURL)
            client = APIClient(address: address, token: CredentialStore.read(for: serverURL))
        } catch { self.error = error.localizedDescription }
        await refresh()
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
                if changed { restoreDraft() }
                lastSync = Date(); status = "已同步"
            } else { status = "服务已连接 · 尚未配对账号" }
        } catch {
            if case APIError.response(401, _) = error { userName = nil; status = "需要重新配对" }
            else { online = false; status = "连接失败 · 点击设置重试" }
        }
    }
    func pair(server: String, code: String) async {
        guard !syncing else { return }
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
            state = [:]; restoreDraft()
            let data = try await next.request("api/data")
            state = data["state"] as? [String: Any] ?? [:]
            online = true; lastSync = Date(); status = "已同步"; showSettings = false
        } catch { self.error = error.localizedDescription }
    }
    /// Rebase a narrow, idempotent operation onto the latest whole document; never replace unknown fields.
    func mutate(reportError: Bool = true, _ operation: ([String: Any]) throws -> [String: Any]) async -> Bool {
        editError = nil
        guard !syncing else { if reportError { error = APIError.busy.localizedDescription } else { editError = APIError.busy.localizedDescription }; return false }
        guard let client, client.token != nil, userID != nil else { if reportError { error = APIError.signIn.localizedDescription; showSettings = true } else { editError = APIError.signIn.localizedDescription }; return false }
        syncing = true; defer { syncing = false }
        do {
            for attempt in 0..<3 {
                let current = try await client.request("api/data")
                let source = current["state"] as? [String: Any] ?? ["unit":"kg", "routines":[], "workouts":[], "bodyweight":[], "week":[:]]
                let next = try operation(source)
                var body: [String: Any] = ["state": next, "baseRev": current["rev"] ?? 0]
                if let wid = source["_wid"] as? String { body["baseWid"] = wid }
                do {
                    _ = try await client.request("api/data", method: "PUT", body: body)
                    state = next; online = true; lastSync = Date(); status = "已同步"
                    if let canonical = try? await client.request("api/data"), let doc = canonical["state"] as? [String: Any] { state = doc }
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
        guard let draft, draft.completedSets > 0 else { error = "至少完成一组后再保存训练。"; return }
        let active = draft.activeJSON
        let saved = await mutate { source in
            guard (source["unit"] as? String ?? "kg") == draft.unit else { throw APIError.response(409, "服务端重量单位已改变。训练草稿已保留，请先恢复原单位。") }
            guard let result = try WebRules.shared.call("finishAdvanced",payload:["state":source,"active":active,"now":Date().timeIntervalSince1970*1000,"today":dayString()]) as? [String:Any] else { throw APIError.invalidResponse }
            return result
        }
        if saved { self.draft = nil; restUntil = nil; selectedTab = 3 }
    }
    func updateSet(entry: Int, set: Int, _ change: (inout TrainingSet) -> Void) {
        guard var d = draft, d.entries.indices.contains(entry), d.entries[entry].sets.indices.contains(set) else { return }
        change(&d.entries[entry].sets[set]); draft = d
    }
    private var draftURL: URL? {
        guard let userID else { return nil }
        let key = Data("\(serverURL)|\(userID)".utf8).base64EncodedString().replacingOccurrences(of: "/", with: "_")
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("draft-\(key).json")
    }
    private func persistDraft() {
        guard let url = draftURL else { return }
        do {
            try FileManager.default.createDirectory(at:url.deletingLastPathComponent(), withIntermediateDirectories:true)
            if let draft { try JSONEncoder().encode(draft).write(to:url, options:.atomic) }
            else if FileManager.default.fileExists(atPath:url.path) { try FileManager.default.removeItem(at:url) }
        } catch { self.error = "训练草稿保存失败：\(error.localizedDescription)" }
    }
    private func restoreDraft() {
        guard let url = draftURL else { return }
        if let data = try? Data(contentsOf:url), let saved = try? JSONDecoder().decode(TrainingDraft.self,from:data) { draft = saved }
    }
}
