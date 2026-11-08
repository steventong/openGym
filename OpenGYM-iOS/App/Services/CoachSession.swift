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
                    let text = last.coachText("outcome") == "failed" ? Self.jobError(last.coachText("errorClass")) : (last.coachText("reading").isEmpty ? String(localized: "NO_CHANGES_NEEDED_RIGHT_NOW_KEEP_LOGGING_YOUR_WORKOUTS_AND_CHECK_BACK", bundle: AppLanguage.bundle, locale: AppLanguage.locale) : last.coachText("reading"))
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
                guard RecordPatch.equal(source.coachObject("coach")["profile"] ?? [String:Any](),original) else { throw APIError.response(409,String(localized: "YOUR_TRAINING_ANSWERS_CHANGED_ON_ANOTHER_DEVICE_REOPEN_THE_QUESTIONNAIRE_TO_EDIT", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) }
            }
            var input = payload; input["state"] = source
            guard let next = try WebRules.shared.call("coachMutation",payload:input) as? [String: Any] else { throw APIError.invalidResponse }
            return next
        }
        guard result else { throw APIError.response(0,store.editError ?? String(localized: "COULD_NOT_SAVE_TRY_AGAIN", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) }
    }
    func agree() async -> Bool { await perform { try await change("consent") } }
    func saveProfile(_ value: [String: Any], original: [String: Any], create: Bool) async -> Bool {
        await perform {
            try await store.refreshCoachState()
            guard RecordPatch.equal(profile,original) else { throw APIError.response(409,String(localized: "YOUR_TRAINING_ANSWERS_CHANGED_ON_ANOTHER_DEVICE_REOPEN_THE_QUESTIONNAIRE_TO_EDIT", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) }
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
            if kind == "create" { try await enqueue("api/coach/plan",body:["intake":profile],text:String(localized: "BUILD_A_NEW_TRAINING_PLAN_BASED_ON_MY_ANSWERS", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) }
            else if kind == "debrief" {
                let workout = store.state.coachObjects("workouts").sorted { number($0["start"]) < number($1["start"]) }.last
                try await enqueue("api/coach/debrief",body:["workoutId":workout?["id"] ?? NSNull()],text:String(localized: "HELP_ME_REVIEW_MY_LAST_WORKOUT", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
            } else {
                let note = routine.map { String(format: String(localized: "IMPROVE_ONLY_MY_ROUTINE_COUNT_EXERCISE_SELECTION_ORDER_SETS_REP_RANGES_AND", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(describing: $0.name)) } ?? ""
                try await enqueue("api/coach/review",body:["note":note],text:note.isEmpty ? String(localized: "REVIEW_MY_TRAINING_AND_SUGGEST_WHERE_I_CAN_IMPROVE", bundle: AppLanguage.bundle, locale: AppLanguage.locale) : note)
            }
        }
    }
    private func enqueue(_ path: String, body: [String: Any], text: String?) async throws {
        try await store.refreshCoachState()
        guard hasConsent, !profile.isEmpty else { throw APIError.response(0,String(localized: "COMPLETE_THE_DATA_CONSENT_AND_TRAINING_QUESTIONNAIRE_FIRST", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) }
        var body = body; body["lang"] = AppLanguage.language
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
            guard current.coachObject("pending").coachText("id") == proposal.coachText("id"), current.coachObject("job").isEmpty else { throw APIError.response(409,String(localized: "THE_PENDING_SUGGESTION_HAS_CHANGED_REFRESH_TO_REVIEW_IT_AGAIN", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) }
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
        catch { throw APIError.response(0,String(localized: "CHANGES_ARE_SAVED_BUT_THE_SUGGESTION_S_STATUS_IS_NOT_CONFIRMED_TAP", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) }
    }
    func retryResolution() async { if let pending { _ = await perform { try await finishResolution(pending) } } }
    func revert() async {
        let hash = info.coachText("planHash"), snapshot = coach.coachObjects("snapshots").last ?? [:]
        let op = "revert-"+snapshot.coachText("proposalId")+"-"+String(number(snapshot["at"]))
        _ = await perform { try await change("revert",values:["planHash":hash],operationID:op) }
    }
    static func jobError(_ code: String) -> String {
        ["timeout":String(localized: "THE_COACH_REQUEST_TIMED_OUT_TRY_AGAIN_LATER", bundle: AppLanguage.bundle, locale: AppLanguage.locale),"auth":String(localized: "AI_SERVICE_AUTHENTICATION_FAILED_ASK_YOUR_ADMINISTRATOR_TO_CHECK_THE_CONFIGURATION", bundle: AppLanguage.bundle, locale: AppLanguage.locale),"provider":String(localized: "THE_AI_SERVICE_IS_TEMPORARILY_UNAVAILABLE_TRY_AGAIN_LATER", bundle: AppLanguage.bundle, locale: AppLanguage.locale),"unusable":String(localized: "THE_COACH_RESPONSE_COULD_NOT_BE_USED_REQUEST_A_NEW_ONE", bundle: AppLanguage.bundle, locale: AppLanguage.locale),"restart":String(localized: "THE_SERVICE_RESTARTED_WHILE_GENERATING_A_RESPONSE_TRY_AGAIN", bundle: AppLanguage.bundle, locale: AppLanguage.locale),"noworkout":String(localized: "COMPLETE_A_WORKOUT_BEFORE_REQUESTING_A_REVIEW", bundle: AppLanguage.bundle, locale: AppLanguage.locale),"cap":String(localized: "YOU_VE_REACHED_TODAY_S_REQUEST_LIMIT_TRY_AGAIN_TOMORROW", bundle: AppLanguage.bundle, locale: AppLanguage.locale),"off":String(localized: "THE_AI_COACH_IS_NOT_ENABLED_ON_THIS_SERVER", bundle: AppLanguage.bundle, locale: AppLanguage.locale),"consent":String(localized: "REVIEW_AND_ACCEPT_THE_DATA_DISCLOSURE_FIRST", bundle: AppLanguage.bundle, locale: AppLanguage.locale),"busy":String(localized: "THE_COACH_IS_PROCESSING_YOUR_REQUEST_PLEASE_WAIT", bundle: AppLanguage.bundle, locale: AppLanguage.locale),"shared":String(localized: "THIS_SERVICE_ACCOUNT_IS_RESTRICTED_TO_ITS_OWNER_ASK_YOUR_ADMINISTRATOR_TO", bundle: AppLanguage.bundle, locale: AppLanguage.locale),"unprivileged":String(localized: "THE_SERVER_CANNOT_RUN_THE_COACH_SAFELY_RIGHT_NOW_CONTACT_YOUR_ADMINISTRATOR", bundle: AppLanguage.bundle, locale: AppLanguage.locale),"nostate":String(localized: "COULD_NOT_READ_WORKOUT_DATA_SYNC_AND_TRY_AGAIN", bundle: AppLanguage.bundle, locale: AppLanguage.locale),"missing":String(localized: "THE_SERVER_S_COACH_CONFIGURATION_IS_INCOMPLETE_CONTACT_YOUR_ADMINISTRATOR", bundle: AppLanguage.bundle, locale: AppLanguage.locale)] [code] ?? String(localized: "THE_COACH_COULD_NOT_COMPLETE_YOUR_REQUEST_RETRY_OR_CONTACT_YOUR_ADMINISTRATOR", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
    }
}
