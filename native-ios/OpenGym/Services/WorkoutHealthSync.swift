import Foundation
import Observation
import HealthKit
import WatchConnectivity

@MainActor @Observable final class WorkoutHealthSync {
    private(set) var enabled: Bool
    private(set) var busy = false
    private(set) var status = L10n.text("WORKOUT_SYNC_IS_OFF" /* 未开启训练同步 */)
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
        do { ledger = try journal.read(); loaded = true; status = enabled ? L10n.text("ENABLED_FOR_YOUR_NEXT_WORKOUT" /* 已开启，下一次训练自动同步 */) : L10n.text("WORKOUT_SYNC_IS_OFF" /* 未开启训练同步 */) }
        catch { status = L10n.text("COULD_NOT_READ_HEALTH_SYNC_RECORDS_COUNT" /* 健康同步记录读取失败：{0} */, error.localizedDescription) }
    }
    func setEnabled(_ value: Bool) async {
        guard canChangeSetting else { status = L10n.text("FINISH_YOUR_CURRENT_WORKOUT_BEFORE_CHANGING_HEALTH_SYNC_SETTINGS" /* 请先结束当前训练，再更改健康同步设置。 */); return }
        if value {
            guard available else { status = L10n.text("HEALTH_DATA_IS_UNAVAILABLE_ON_THIS_DEVICE" /* 此设备不支持健康数据 */); return }
            busy = true; defer { busy = false }
            do { try await HealthWorkoutAccess.authorize(health) }
            catch { status = error.localizedDescription; return }
        }
        enabled = value; UserDefaults.standard.set(value, forKey: "health.workouts.enabled")
        status = value ? L10n.text("ENABLED_FOR_YOUR_NEXT_WORKOUT_ALLOW_ACCESS_ON_YOUR_WATCH_TOO_IF" /* 已开启，下一次训练自动同步；使用手表时也需在手表授权 */) : L10n.text("DISABLED_EXISTING_WORKOUT_RECORDS_ARE_KEPT" /* 已关闭，已有训练记录保留 */)
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
        catch { status = L10n.text("YOUR_WORKOUT_STARTED_BUT_HEALTH_SYNC_HAS_NOT_COUNT" /* 训练已开始，但健康同步尚未启动：{0} */, error.localizedDescription) }
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
        catch { status = L10n.text("COULD_NOT_SAVE_THE_HEALTH_SYNC_STOP_REQUEST_COUNT" /* 无法保存健康同步结束指令：{0} */, error.localizedDescription); return false }
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
            catch { status = L10n.text("COULD_NOT_RESTORE_THE_STOP_REQUEST_COUNT" /* 结束指令恢复失败：{0} */, error.localizedDescription); return }
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
                            message: request.phase == .running ? L10n.text("THIS_IOS_VERSION_SYNCS_WORKOUT_DURATION_WHEN_YOU_FINISH_WITHOUT_LIVE_METRICS" /* 当前 iOS 将在结束时同步训练时长，不采集实时指标。 */) : nil), owner: .phone)
                    } catch { receive(HealthWorkoutReport(id: request.id, state: .failed, message: error.localizedDescription), owner: .phone) }
                }
            }
            store?.watchBridge?.publish()
            store?.watchBridge?.sendHealthRequests()
            if let request = watchRequests.last(where: { $0.phase == .running }), ledger.reports[request.id]?.state != .running {
                status = L10n.text("WAITING_FOR_APPLE_WATCH_TO_START_TRACKING_ALLOW_ACCESS_ON_YOUR_WATCH" /* 等待 Apple Watch 开始运动采集；首次使用请在手表授权 */)
                if wakeWatch { await wakeWatchApp() }
            }
        }
    }
    private func wakeWatchApp() async {
        guard !wakingWatch else { return }; wakingWatch = true; defer { wakingWatch = false }
        do { try await health.startWatchApp(toHandle: HealthWorkoutAccess.configuration) }
        catch { status = L10n.text("WATCH_TRACKING_HAS_NOT_STARTED_OPEN_OPENGYM_ON_YOUR_WATCH_AND_TRY" /* 尚未启动手表运动采集，请打开手表上的 openGym 并重试：{0} */, error.localizedDescription) }
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
            case .running: status = accepted.message ?? (owner == .watch ? L10n.text("APPLE_WATCH_IS_RECORDING_YOUR_WORKOUT" /* Apple Watch 正在记录训练 */) : L10n.text("IPHONE_IS_RECORDING_YOUR_WORKOUT" /* iPhone 正在记录训练 */))
            case .saved: status = accepted.message ?? L10n.text("WORKOUT_SYNCED_TO_APPLE_HEALTH_AND_FITNESS" /* 训练已同步到 Apple 健康与健身 */)
            case .discarded: status = L10n.text("ACTIVITY_RECORDING_CANCELLED" /* 本次运动记录已取消 */)
            case .failed: status = accepted.message ?? L10n.text("WORKOUT_SYNC_INCOMPLETE_YOU_CAN_RETRY" /* 训练同步未完成，可重试 */)
            }
        } catch { status = L10n.text("COULD_NOT_SAVE_HEALTH_SYNC_CONFIRMATION_YOU_CAN_RETRY_COUNT" /* 健康同步回执保存失败，可重试：{0} */, error.localizedDescription) }
    }
    func report(for draft: TrainingDraft) -> HealthWorkoutReport? { ledger.reports[requestID(for: draft)] }
}
