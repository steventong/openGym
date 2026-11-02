import Foundation
import Observation
import HealthKit
import WatchConnectivity

@MainActor @Observable final class WorkoutHealthSync {
    private(set) var enabled: Bool
    private(set) var busy = false
    private(set) var status = "未开启训练同步"
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
        do { ledger = try journal.read(); loaded = true; status = enabled ? "已开启，下一次训练自动同步" : "未开启训练同步" }
        catch { status = "健康同步记录读取失败：\(error.localizedDescription)" }
    }
    func setEnabled(_ value: Bool) async {
        guard canChangeSetting else { status = "请先结束当前训练，再更改健康同步设置。"; return }
        if value {
            guard available else { status = "此设备不支持健康数据"; return }
            busy = true; defer { busy = false }
            do { try await HealthWorkoutAccess.authorize(health) }
            catch { status = error.localizedDescription; return }
        }
        enabled = value; UserDefaults.standard.set(value, forKey: "health.workouts.enabled")
        status = value ? "已开启，下一次训练自动同步；使用手表时也需在手表授权" : "已关闭，已有训练记录保留"
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
        let request = HealthWorkoutRequest(id: requestID(for: draft), start: draft.start, owner: owner)
        var next = ledger
        guard next.merge(request) else { retry(); return }
        do { try journal.write(next); ledger = next; current = nil; retry(wakeWatch: true) }
        catch { status = "训练已开始，但健康同步尚未启动：\(error.localizedDescription)" }
    }
    /// Persist the stop independently of server submission; retries keep the first end time and owner.
    @discardableResult func finish(_ draft: TrainingDraft, discard: Bool = false, at date: Date) -> Bool {
        load(); guard loaded else { return false }
        let id = requestID(for: draft)
        guard var request = ledger.requests[id] else { return true }
        request.phase = discard ? .discarded : .finished; request.end = max(request.start, date)
        var next = ledger; next.merge(request)
        do { try journal.write(next); ledger = next; retry(); return true }
        catch { status = "无法保存健康同步结束指令：\(error.localizedDescription)"; return false }
    }
    var watchRequests: [HealthWorkoutRequest] { ledger.pending.filter { $0.owner == .watch } }
    func retry(wakeWatch: Bool = false) {
        load(); guard loaded, !retrying else { return }
        // Crash between freezing the draft and dispatching the end must not restart collection.
        if let draft = store?.draft, let stamp = draft.activeJSON["nativeFinishAt"] as? Double,
           var request = ledger.requests[requestID(for: draft)], request.phase == .running {
            request.phase = .finished; request.end = max(request.start, Date(timeIntervalSince1970: stamp / 1000))
            var next = ledger; next.merge(request)
            do { try journal.write(next); ledger = next }
            catch { status = "结束指令恢复失败：\(error.localizedDescription)"; return }
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
                            message: request.phase == .running ? "当前 iOS 将在结束时同步训练时长，不采集实时指标。" : nil), owner: .phone)
                    } catch { receive(HealthWorkoutReport(id: request.id, state: .failed, message: error.localizedDescription), owner: .phone) }
                }
            }
            store?.watchBridge?.publish()
            store?.watchBridge?.sendHealthRequests()
            if let request = watchRequests.last(where: { $0.phase == .running }), ledger.reports[request.id]?.state != .running {
                status = "等待 Apple Watch 开始运动采集；首次使用请在手表授权"
                if wakeWatch { await wakeWatchApp() }
            }
        }
    }
    private func wakeWatchApp() async {
        guard !wakingWatch else { return }; wakingWatch = true; defer { wakingWatch = false }
        do { try await health.startWatchApp(toHandle: HealthWorkoutAccess.configuration) }
        catch { status = "尚未启动手表运动采集，请打开手表上的 openGym 并重试：\(error.localizedDescription)" }
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
            case .running: status = accepted.message ?? (owner == .watch ? "Apple Watch 正在记录训练" : "iPhone 正在记录训练")
            case .saved: status = accepted.message ?? "训练已同步到 Apple 健康与健身"
            case .discarded: status = "本次运动记录已取消"
            case .failed: status = accepted.message ?? "训练同步未完成，可重试"
            }
        } catch { status = "健康同步回执保存失败，可重试：\(error.localizedDescription)" }
    }
    func report(for draft: TrainingDraft) -> HealthWorkoutReport? { ledger.reports[requestID(for: draft)] }
}
