import Foundation
import Observation
import HealthKit
import WatchConnectivity

@MainActor @Observable final class WorkoutHealthSync {
    private(set) var enabled: Bool
    private(set) var busy = false
    private(set) var status = String(localized: "WORKOUT_SYNC_IS_OFF", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
    private(set) var current: HealthWorkoutReport?
    private(set) var ledger = HealthWorkoutLedger()
    private let journal: HealthWorkoutJournal
    private let health = HKHealthStore()
    private weak var store: GymStore?
    private let dispatch: (([HealthWorkoutRequest]) -> Void)?
    private var loaded = false
    private var recorder: AnyObject?
    private var retrying = false
    private var wakingWatch = false
    var available: Bool { HKHealthStore.isHealthDataAvailable() }
    var canChangeSetting: Bool { store?.draft == nil && !busy }

    init(store: GymStore, journal: HealthWorkoutJournal? = nil, dispatch: (([HealthWorkoutRequest]) -> Void)? = nil) {
        self.dispatch = dispatch
        self.store = store
        self.journal = journal ?? HealthWorkoutJournal(name: "phone-sync", root: store.localStorage.root.appendingPathComponent("HealthWorkouts"))
        enabled = UserDefaults.standard.bool(forKey: "health.workouts.enabled")
        load()
    }
    private func load() {
        guard !loaded else { return }
        do { ledger = try journal.read(); loaded = true; status = enabled ? String(localized: "ENABLED_FOR_YOUR_NEXT_WORKOUT", bundle: AppLanguage.bundle, locale: AppLanguage.locale) : String(localized: "WORKOUT_SYNC_IS_OFF", bundle: AppLanguage.bundle, locale: AppLanguage.locale) }
        catch { status = String(format: String(localized: "COULD_NOT_READ_HEALTH_SYNC_RECORDS_COUNT", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(describing: error.localizedDescription)) }
    }
    func setEnabled(_ value: Bool) async {
        guard canChangeSetting else { status = String(localized: "FINISH_YOUR_CURRENT_WORKOUT_BEFORE_CHANGING_HEALTH_SYNC_SETTINGS", bundle: AppLanguage.bundle, locale: AppLanguage.locale); return }
        if value {
            guard available else { status = String(localized: "HEALTH_DATA_IS_UNAVAILABLE_ON_THIS_DEVICE", bundle: AppLanguage.bundle, locale: AppLanguage.locale); return }
            busy = true; defer { busy = false }
            do { try await HealthWorkoutAccess.authorize(health) }
            catch { status = error.localizedDescription; return }
        }
        enabled = value; UserDefaults.standard.set(value, forKey: "health.workouts.enabled")
        status = value ? String(localized: "ENABLED_FOR_YOUR_NEXT_WORKOUT_ALLOW_ACCESS_ON_YOUR_WATCH_TOO_IF", bundle: AppLanguage.bundle, locale: AppLanguage.locale) : String(localized: "DISABLED_EXISTING_WORKOUT_RECORDS_ARE_KEPT", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
    }
    func authorize() async {
        guard available, !busy else { return }
        busy = true; defer { busy = false }
        do { try await HealthWorkoutAccess.authorize(health); retry() }
        catch { status = error.localizedDescription }
    }
    func requestID(for draft: TrainingDraft) -> String {
        "\(store?.watchSnapshot().account ?? ""):\(draft.id)"
    }
    func begin(_ draft: TrainingDraft) {
        guard enabled else { return }
        load(); guard loaded else { return }
        let session = WCSession.default
        let owner: HealthWorkoutRequest.Owner = WCSession.isSupported() && session.activationState == .activated && session.isPaired && session.isWatchAppInstalled ? .watch : .phone
        let request = HealthWorkoutRequest(id: requestID(for: draft), start: draft.start, owner: owner, title: draft.name)
        var next = ledger
        guard next.merge(request) else { retry(); return }
        do { try journal.write(next); ledger = next; current = nil; retry(wakeWatch: true) }
        catch { status = String(format: String(localized: "YOUR_WORKOUT_STARTED_BUT_HEALTH_SYNC_HAS_NOT_COUNT", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(describing: error.localizedDescription)) }
    }
    /// Persist the stop independently of server submission; retries keep the first end time and owner.
    @discardableResult func finish(_ draft: TrainingDraft, discard: Bool = false, at date: Date) -> Bool {
        load(); guard loaded else { return false }
        let id = requestID(for: draft)
        guard var request = ledger.requests[id] else { return true }
        request.phase = discard ? .discarded : .finished; request.end = max(request.start, date)
        request.title = draft.name
        var next = ledger; next.merge(request)
        do { try journal.write(next); ledger = next; retry(); return true }
        catch { status = String(format: String(localized: "COULD_NOT_SAVE_THE_HEALTH_SYNC_STOP_REQUEST_COUNT", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(describing: error.localizedDescription)); return false }
    }
    var watchRequests: [HealthWorkoutRequest] { ledger.pending.filter { $0.owner == .watch } }
    func retry(wakeWatch: Bool = false) {
        load(); guard loaded, !retrying else { return }
        // Crash between freezing the draft and dispatching the end must not restart collection.
        if let draft = store?.draft, let stamp = draft.activeJSON["nativeFinishAt"] as? Double,
           var request = ledger.requests[requestID(for: draft)], request.phase == .running {
            request.phase = .finished; request.end = max(request.start, Date(timeIntervalSince1970: stamp / 1000))
            request.title = draft.name
            var next = ledger; next.merge(request)
            do { try journal.write(next); ledger = next }
            catch { status = String(format: String(localized: "COULD_NOT_RESTORE_THE_STOP_REQUEST_COUNT", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(describing: error.localizedDescription)); return }
        }
        if let dispatch { dispatch(ledger.pending); return }
        retrying = true
        Task {
            defer { retrying = false }
            let pending = ledger.pending
            let local = pending.filter { $0.owner == .phone }
            if #available(iOS 26.0, *) {
                if recorder == nil {
                    let value = HealthWorkoutRecorder(name: "phone-recorder")
                    value.onReport = { [weak coordinator = self] in coordinator?.receive($0, owner: .phone) }; recorder = value
                }
                (recorder as? HealthWorkoutRecorder)?.accept(local)
            } else {
                for request in local {
                    do {
                        if request.phase == .finished { try await HealthWorkoutAccess.saveDuration(request, health: health) }
                        let state: HealthWorkoutReport.State = request.phase == .running ? .running : request.phase == .finished ? .saved : .discarded
                        receive(HealthWorkoutReport(id: request.id, state: state,
                            message: request.phase == .running ? String(localized: "THIS_IOS_VERSION_SYNCS_WORKOUT_DURATION_WHEN_YOU_FINISH_WITHOUT_LIVE_METRICS", bundle: AppLanguage.bundle, locale: AppLanguage.locale) : nil), owner: .phone)
                    } catch { receive(HealthWorkoutReport(id: request.id, state: .failed, message: error.localizedDescription), owner: .phone) }
                }
            }
            store?.watchBridge?.publish()
            store?.watchBridge?.sendHealthRequests()
            if let request = watchRequests.last(where: { $0.phase == .running }), ledger.reports[request.id]?.state != .running {
                status = String(localized: "WAITING_FOR_APPLE_WATCH_TO_START_TRACKING_ALLOW_ACCESS_ON_YOUR_WATCH", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
                if wakeWatch { await wakeWatchApp() }
            }
        }
    }
    private func wakeWatchApp() async {
        guard !wakingWatch else { return }; wakingWatch = true; defer { wakingWatch = false }
        do { try await health.startWatchApp(toHandle: HealthWorkoutAccess.configuration) }
        catch { status = String(format: String(localized: "WATCH_TRACKING_HAS_NOT_STARTED_OPEN_OPENGYM_ON_YOUR_WATCH_AND_TRY", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(describing: error.localizedDescription)) }
    }
    func receive(_ report: HealthWorkoutReport, owner: HealthWorkoutRequest.Owner) {
        guard ledger.requests[report.id]?.owner == owner else { return }
        let old = ledger.reports[report.id]
        var next = ledger; next.receive(report)
        guard let accepted = next.reports[report.id], accepted != old else { return }
        do {
            if accepted.state != old?.state || accepted.terminal { try journal.write(next) }
            ledger = next
            let activeID = store?.draft.map(requestID)
            let account = (store?.watchSnapshot().account ?? "") + ":"
            guard report.id == activeID || (activeID == nil && report.id.hasPrefix(account)) else { return }
            current = accepted
            switch accepted.state {
            case .running: status = accepted.message ?? (owner == .watch ? String(localized: "APPLE_WATCH_IS_RECORDING_YOUR_WORKOUT", bundle: AppLanguage.bundle, locale: AppLanguage.locale) : String(localized: "IPHONE_IS_RECORDING_YOUR_WORKOUT", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
            case .saved: status = accepted.message ?? String(localized: "WORKOUT_SYNCED_TO_APPLE_HEALTH_AND_FITNESS", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
            case .discarded: status = String(localized: "ACTIVITY_RECORDING_CANCELLED", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
            case .failed: status = accepted.message ?? String(localized: "WORKOUT_SYNC_INCOMPLETE_YOU_CAN_RETRY", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
            }
        } catch { status = String(format: String(localized: "COULD_NOT_SAVE_HEALTH_SYNC_CONFIRMATION_YOU_CAN_RETRY_COUNT", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(describing: error.localizedDescription)) }
    }
    func report(for draft: TrainingDraft) -> HealthWorkoutReport? { ledger.reports[requestID(for: draft)] }
}
