import Foundation
import Observation

extension Dictionary where Key == String, Value == Any {
    func coachObject(_ key: String) -> [String: Any] { self[key] as? [String: Any] ?? [:] }
    func coachObjects(_ key: String) -> [[String: Any]] { self[key] as? [[String: Any]] ?? [] }
    func coachText(_ key: String) -> String { self[key] as? String ?? "" }
}

@MainActor @Observable final class CoachSession {
    let store: GymStore
    let identity: String
    var configuration: [String: Any] = [:]
    var disclosure: [String: Any] = [:]
    var account: [String: Any] = [:]
    var status: [String: Any] = [:]
    var error: String?
    var loaded = false
    var busy = false
    var refreshing = false
    var draft = ""
    private var awaitingJob: String?
    init(store: GymStore) { self.store = store; identity = store.coachIdentity }
    var valid: Bool { identity == store.coachIdentity }
    var coach: [String: Any] { store.state.coachObject("coach") }
    var profile: [String: Any] { coach.coachObject("profile") }
    var enabled: Bool { configuration.coachObject("coach")["enabled"] as? Bool == true }
    var running: Bool { !status.coachObject("job").isEmpty }
    var pending: [String: Any]? { status["pending"] as? [String: Any] }
    var locked: Bool { busy || refreshing || !valid }
    var maxLength: Int { max(1,Int(number(status["maxMessageLen"])) == 0 ? 1000 : Int(number(status["maxMessageLen"]))) }
    var history: [[String: Any]] { coach.coachObjects("log").reversed() }
    var info: [String: Any] { presentation() }
    var hasConsent: Bool { info["consent"] as? Bool == true }
    var ready: Bool { enabled && hasConsent && !profile.isEmpty }
    var savedPending: [String: Any]? { guard let id = pending?.coachText("id") else { return nil }; return history.first { $0.coachText("proposalId") == id && $0.coachText("kind") != "revert" } }
    func presentation(_ proposal: [String: Any]? = nil, history: Bool = false) -> [String: Any] {
        var payload: [String: Any] = ["state":store.state,"history":history,"categories":disclosure["categories"] as? [String] ?? []]
        if let proposal { payload["proposal"] = proposal }
        return (try? WebRules.shared.call("coachInfo",payload:payload)) as? [String: Any] ?? [:]
    }
    func poll() async {
        while !Task.isCancelled && valid {
            await refresh()
            do { try await Task.sleep(for:.seconds(running || awaitingJob != nil ? 3 : 30)) } catch { return }
        }
    }
    func refresh() async {
        guard !refreshing, !busy, valid else { return }
        refreshing = true; defer { refreshing = false }
        do {
            configuration = try await store.coachRequest("api/config")
            if enabled {
                try await store.refreshCoachState()
                disclosure = try await store.coachRequest("api/coach/disclosure")
                account = try await store.coachRequest("api/coach/account")
                let next = try await store.coachRequest("api/coach/status")
                let last = next.coachObject("last")
                status = next
                if !running, pending == nil, !last.coachText("id").isEmpty,
                   ["failed","nochange"].contains(last.coachText("outcome")),
                   !coach.coachObjects("chat").contains(where: { $0.coachText("id") == "job-" + last.coachText("id") }) {
                    let text = last.coachText("outcome") == "failed" ? Self.jobError(last.coachText("errorClass")) : (last.coachText("reading").isEmpty ? "目前没有需要调整的内容。继续记录训练，之后再来复盘。" : last.coachText("reading"))
                    try await change("outcome",values:["last":last,"text":text],operationID:"outcome-"+last.coachText("id"))
                }
                if !running { awaitingJob = nil }
            } else { status = [:] }
            loaded = true; error = nil
        } catch APIError.busy { /* A background sync is still in progress; the next poll retries. */ }
        catch is CancellationError { }
        catch { if !Task.isCancelled { self.error = error.localizedDescription; loaded = true } }
    }
    @discardableResult
    func perform(_ work: () async throws -> Void) async -> Bool {
        guard !locked else { return false }
        busy = true; error = nil
        do { try await work(); busy = false; await refresh(); return true }
        catch is CancellationError { busy = false; return false }
        catch { busy = false; self.error = error.localizedDescription; return false }
    }
    func change(_ action: String, values: [String: Any] = [:], operationID: String = UUID().uuidString) async throws {
        try await store.waitForCoachIdle()
        guard valid else { throw CancellationError() }
        let expectedIdentity = identity
        var payload = values; payload["action"] = action; payload["operationId"] = operationID
        let result = await store.mutate(reportError:false,verify:{ source in
            (source.coachObject("coach")["nativeOperations"] as? [String])?.contains(operationID) == true
        }) { source in
            guard self.store.coachIdentity == expectedIdentity else { throw CancellationError() }
            if action == "profile", let original = values["originalProfile"] {
                guard RecordPatch.equal(source.coachObject("coach")["profile"] ?? [String:Any](),original) else { throw APIError.response(409,"训练问答已在其他设备更改，请重新打开后编辑。") }
            }
            var input = payload; input["state"] = source
            guard let next = try WebRules.shared.call("coachMutation",payload:input) as? [String: Any] else { throw APIError.invalidResponse }
            return next
        }
        guard result else { throw APIError.response(0,store.editError ?? "保存失败，请重试。") }
    }
    func agree() async -> Bool { await perform { try await change("consent") } }
    func saveProfile(_ value: [String: Any], original: [String: Any], create: Bool) async -> Bool {
        await perform {
            try await store.refreshCoachState()
            guard RecordPatch.equal(profile,original) else { throw APIError.response(409,"训练问答已在其他设备更改，请重新打开后编辑。") }
            try await change("profile",values:["profile":value,"originalProfile":original])
            if create { try await enqueue("api/coach/plan",body:["intake":value],text:nil) }
        }
    }
    func send() async {
        let message = draft.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !message.isEmpty, message.count <= maxLength, !running else { return }
        let isPlan = pending?.coachText("kind") == "create" || store.routines.isEmpty
        _ = await perform {
            try await enqueue(isPlan ? "api/coach/plan" : "api/coach/review",body:[isPlan ? "refine" : "note":message],text:message)
            draft = ""
        }
    }
    func ask(_ kind: String, routine: Routine? = nil) async {
        guard !running, pending == nil else { return }
        _ = await perform {
            if kind == "create" { try await enqueue("api/coach/plan",body:["intake":profile],text:"根据我的回答重新设计一份训练计划。") }
            else if kind == "debrief" {
                let workout = store.state.coachObjects("workouts").sorted { number($0["start"]) < number($1["start"]) }.last
                try await enqueue("api/coach/debrief",body:["workoutId":workout?["id"] ?? NSNull()],text:"帮我复盘上次训练。")
            } else {
                let note = routine.map { "只优化我的训练计划「\($0.name)」：动作选择、顺序、组数、次数范围和进阶方式；其他计划保持不变。" } ?? ""
                try await enqueue("api/coach/review",body:["note":note],text:note.isEmpty ? "请看看我的训练，告诉我哪些地方可以改进。" : note)
            }
        }
    }
    private func enqueue(_ path: String, body: [String: Any], text: String?) async throws {
        try await store.refreshCoachState()
        guard hasConsent, !profile.isEmpty else { throw APIError.response(0,"请先完成数据授权和训练问答。") }
        var body = body; body["lang"] = "zh"
        let result = try await store.coachRequest(path,method:"POST",body:body)
        status["job"] = result["job"]; awaitingJob = result.coachObject("job").coachText("id")
        if let text {
            try await change("chat",values:["message":["id":"request-"+(awaitingJob ?? UUID().uuidString),"role":"user","kind":"text","text":text]])
        }
    }
    func resolve(_ proposal: [String: Any], accepted: [String] = [], schedule: Bool = true, dismissed: Bool = false) async {
        let hash = info.coachText("planHash")
        _ = await perform {
            let current = try await store.coachRequest("api/coach/status")
            guard current.coachObject("pending").coachText("id") == proposal.coachText("id"), current.coachObject("job").isEmpty else { throw APIError.response(409,"待处理建议已改变，请刷新后重新查看。") }
            try await change("resolve",values:["proposal":proposal,"accepted":accepted,"schedule":schedule,"dismissed":dismissed,"planHash":hash],operationID:"resolve-"+proposal.coachText("id"))
            try await finishResolution(proposal)
        }
    }
    private func finishResolution(_ proposal: [String: Any]) async throws {
        let id = proposal.coachText("id")
        guard let record = history.first(where: { $0.coachText("proposalId") == id && $0.coachText("kind") != "revert" }) else { throw APIError.invalidResponse }
        let current = try await store.coachRequest("api/coach/status")
        // An old phone must never acknowledge a newer suggestion from another device.
        guard current.coachObject("pending").coachText("id") == id, current.coachObject("job").isEmpty else { status = current; return }
        let kind = record.coachText("kind"), decisions = record.coachObjects("decisions")
        let accepted = kind == "create" ? ["plan"] : kind == "debrief" ? ["debrief"] : decisions.filter { $0.coachText("status") == "accepted" }.map { $0.coachText("id") }
        do { _ = try await store.coachRequest("api/coach/pending/resolve",method:"POST",body:["proposalId":id,"accepted":accepted,"rejected":decisions.filter { $0.coachText("status") != "accepted" }.map { $0.coachText("id") },"dismissed":record["dismissed"] as? Bool ?? false]) }
        catch { throw APIError.response(0,"修改已保存，但建议状态尚未确认。请点「完成同步」，不会重复应用。") }
    }
    func retryResolution() async { if let pending { _ = await perform { try await finishResolution(pending) } } }
    func revert() async {
        let hash = info.coachText("planHash"), snapshot = coach.coachObjects("snapshots").last ?? [:]
        let op = "revert-"+snapshot.coachText("proposalId")+"-"+String(number(snapshot["at"]))
        _ = await perform { try await change("revert",values:["planHash":hash],operationID:op) }
    }
    static func jobError(_ code: String) -> String {
        ["timeout":"教练响应超时，请稍后重试。","auth":"AI 服务认证失败，请管理员检查配置。","provider":"AI 服务暂时无法响应，请稍后重试。","unusable":"教练返回的内容无法使用，请重新请求。","restart":"服务在生成过程中重启，请重新请求。","noworkout":"还没有可复盘的训练，请先完成一次训练。","cap":"已达到今日请求上限，请明天再试。","off":"服务器尚未启用 AI 教练。","consent":"请先确认数据使用说明。","busy":"教练正在处理请求，请稍候。","shared":"此服务账号仅限绑定用户使用，请联系管理员配置可共享的服务。","unprivileged":"服务器暂时无法安全运行教练，请联系管理员。","nostate":"无法读取训练数据，请同步后重试。","missing":"服务器教练配置不完整，请联系管理员。"] [code] ?? "教练暂时无法完成请求，请重试或联系管理员。"
    }
}
