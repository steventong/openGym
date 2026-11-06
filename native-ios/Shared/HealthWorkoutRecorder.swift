import Foundation
import HealthKit

enum HealthWorkoutAccess {
    static let workout = HKObjectType.workoutType()
    static let energy = HKQuantityType(.activeEnergyBurned)
    static let restingEnergy = HKQuantityType(.basalEnergyBurned)
    static let heartRate = HKQuantityType(.heartRate)
    static func authorize(_ health: HKHealthStore) async throws {
        try await health.requestAuthorization(toShare: [workout, energy], read: [workout, energy, restingEnergy, heartRate])
        guard health.authorizationStatus(for: workout) == .sharingAuthorized else {
            throw NSError(domain: "OpenGymHealth", code: 1, userInfo: [NSLocalizedDescriptionKey: L10n.text("ALLOW_OPENGYM_TO_WRITE_WORKOUTS_IN_THE_HEALTH_APP" /* 请在健康 App 中允许 openGym 写入体能训练。 */)])
        }
    }
    static var configuration: HKWorkoutConfiguration {
        let value = HKWorkoutConfiguration()
        value.activityType = .traditionalStrengthTraining
        value.locationType = .indoor
        return value
    }
    static func metadata(_ request: HealthWorkoutRequest) -> [String: Any] {
        [HKMetadataKeySyncIdentifier: request.syncIdentifier, HKMetadataKeySyncVersion: 1,
         HKMetadataKeyWorkoutBrandName: request.title ?? "openGym"]
    }
    /// Used on older iOS and when collection could not run. Never invent energy samples.
    static func saveDuration(_ request: HealthWorkoutRequest, health: HKHealthStore) async throws {
        guard let end = request.end, request.phase == .finished else { return }
        let builder = HKWorkoutBuilder(healthStore: health, configuration: configuration, device: .local())
        try await builder.beginCollection(at: request.start)
        try await builder.addMetadata(metadata(request))
        try await builder.endCollection(at: end)
        guard try await builder.finishWorkout() != nil else {
            throw NSError(domain: "OpenGymHealth", code: 4, userInfo: [NSLocalizedDescriptionKey: L10n.text("APPLE_HEALTH_HAS_NOT_CONFIRMED_THE_SAVE_RETRY_SYNCING" /* Apple 健康尚未确认保存，请重试同步。 */)])
        }
    }
}

@available(iOS 26.0, *)
@MainActor final class HealthWorkoutRecorder: NSObject, HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate {
    private let health = HKHealthStore()
    private let journal: HealthWorkoutJournal
    private var ledger = HealthWorkoutLedger()
    private var loaded = false
    private var recovered = false
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var worker: Task<Void, Never>?
    private var queued = false
    private var collectionEnded = false
    var onReport: ((HealthWorkoutReport) -> Void)?
    var onSessionStateChange: (() -> Void)?
    var runningSessionID: String? { session?.state == .running ? ledger.activeID : nil }
    var currentReport: HealthWorkoutReport? { ledger.activeID.flatMap { ledger.reports[$0] } }

    init(name: String) { journal = HealthWorkoutJournal(name: name); super.init() }

    func accept(_ requests: [HealthWorkoutRequest]) {
        do {
            if !loaded { ledger = try journal.read(); loaded = true }
            var next = ledger
            for request in requests { next.merge(request) }
            try journal.write(next); ledger = next
            // A lost receipt is retried even when there is no remaining HealthKit work.
            for request in requests {
                if let report = ledger.reports[request.id], report.terminal { onReport?(report) }
            }
            queued = true
            guard worker == nil else { return }
            worker = Task { [weak self] in
                guard let self else { return }
                while queued {
                    queued = false
                    await recover()
                    for request in ledger.pending { await process(request) }
                }
                worker = nil
            }
        } catch {
            for request in requests { onReport?(HealthWorkoutReport(id: request.id, state: .failed, message: L10n.text("COULD_NOT_SAVE_HEALTH_SYNC_DATA_LOCALLY_COUNT" /* 健康同步本机保存失败：{0} */, error.localizedDescription))) }
        }
    }
    func stopFromWatch() {
        guard let id = ledger.activeID, var request = ledger.requests[id], request.phase == .running else { return }
        request.phase = .finished; request.end = max(request.start, Date()); accept([request])
    }
    func recover() async {
        guard !recovered else { return }; recovered = true
        do {
            guard let restored = try await health.recoverActiveWorkoutSession() else {
                if let id = ledger.activeID {
                    var interrupted = ledger.interruptedIDs ?? []; interrupted.insert(id); ledger.interruptedIDs = interrupted
                    ledger.activeID = nil; try journal.write(ledger)
                }
                return
            }
            guard let id = ledger.activeID, ledger.requests[id] != nil else {
                restored.end(); restored.associatedWorkoutBuilder().discardWorkout(); return
            }
            if ledger.reports[id]?.terminal == true { restored.end(); clearSession(); return }
            session = restored; session?.delegate = self
            builder = restored.associatedWorkoutBuilder(); builder?.delegate = self
            builder?.dataSource = HKLiveWorkoutDataSource(healthStore: health, workoutConfiguration: restored.workoutConfiguration)
            collectionEnded = builder?.endDate != nil
        } catch {
            // Retry recovery before creating a new session, including when protected data is locked.
            recovered = false
            for request in ledger.pending {
                onReport?(HealthWorkoutReport(id: request.id, state: .failed, message: L10n.text("WORKOUT_RECOVERY_IS_INCOMPLETE_UNLOCK_YOUR_DEVICE_AND_RETRY_COUNT" /* 运动恢复未完成，请解锁设备后重试：{0} */, error.localizedDescription)))
            }
        }
    }
    private func process(_ queuedRequest: HealthWorkoutRequest) async {
        guard let request = ledger.requests[queuedRequest.id], recovered, ledger.reports[request.id]?.terminal != true else { return }
        do {
            if request.phase == .discarded {
                if ledger.activeID == request.id { session?.end(); builder?.discardWorkout(); clearSession() }
                try report(HealthWorkoutReport(id: request.id, state: .discarded))
                return
            }
            if request.phase == .running {
                guard ledger.interruptedIDs?.contains(request.id) != true else {
                    try report(HealthWorkoutReport(id: request.id, state: .failed, message: L10n.text("ACTIVITY_TRACKING_WAS_INTERRUPTED_DURATION_WILL_SYNC_WHEN_YOU_FINISH_THE_WORKOUT" /* 运动采集已中断；结束训练后将同步时长。 */))); return
                }
                guard health.authorizationStatus(for: HealthWorkoutAccess.workout) == .sharingAuthorized else {
                    throw NSError(domain: "OpenGymHealth", code: 1, userInfo: [NSLocalizedDescriptionKey: L10n.text("OPEN_HEALTH_SYNC_SETTINGS_IN_OPENGYM_AND_ALLOW_ACCESS" /* 请打开 openGym 的健康同步设置并授权。 */)])
                }
                if ledger.activeID == request.id, session != nil { emitMetrics(); return }
                guard session == nil else {
                    throw NSError(domain: "OpenGymHealth", code: 2, userInfo: [NSLocalizedDescriptionKey: L10n.text("THE_PREVIOUS_WORKOUT_HAS_NOT_ENDED_CONNECT_IPHONE_AND_RETRY_SYNCING" /* 上一场训练尚未结束，请连接 iPhone 重试同步。 */)])
                }
                ledger.activeID = request.id; try journal.write(ledger)
                let next = try HKWorkoutSession(healthStore: health, configuration: HealthWorkoutAccess.configuration)
                session = next; next.delegate = self
                let live = next.associatedWorkoutBuilder(); builder = live; live.delegate = self
                live.dataSource = HKLiveWorkoutDataSource(healthStore: health, workoutConfiguration: next.workoutConfiguration)
                collectionEnded = false
                next.prepare()
                next.startActivity(with: request.start)
                try await live.beginCollection(at: request.start)
                try await live.addMetadata(HealthWorkoutAccess.metadata(request))
                try report(HealthWorkoutReport(id: request.id, state: .running))
            } else if ledger.activeID == request.id, let session, let builder, let end = request.end {
                if session.state != .stopped && session.state != .ended { session.stopActivity(with: end) }
                // stopActivity is asynchronous; allow final sensor samples to reach the builder.
                for _ in 0..<100 {
                    if session.state == .stopped || session.state == .ended { break }
                    try await Task.sleep(for: .milliseconds(50))
                }
                guard session.state == .stopped || session.state == .ended else {
                    throw NSError(domain: "OpenGymHealth", code: 3, userInfo: [NSLocalizedDescriptionKey: L10n.text("STOPPING_ACTIVITY_TRACKING_RETRY_SYNCING_SHORTLY" /* 正在停止运动采集，请稍后重试同步。 */)])
                }
                if !collectionEnded { try await builder.endCollection(at: end); collectionEnded = true }
                // The training may have been renamed since collection began.
                try await builder.addMetadata(HealthWorkoutAccess.metadata(request))
                guard let workout = try await builder.finishWorkout() else {
                    throw NSError(domain: "OpenGymHealth", code: 4, userInfo: [NSLocalizedDescriptionKey: L10n.text("APPLE_HEALTH_HAS_NOT_CONFIRMED_THE_SAVE_RETRY_SYNCING" /* Apple 健康尚未确认保存，请重试同步。 */)])
                }
                let calories = workout.statistics(for: HealthWorkoutAccess.energy)?.sumQuantity()?.doubleValue(for: .kilocalorie())
                let resting = workout.statistics(for: HealthWorkoutAccess.restingEnergy)?.sumQuantity()?.doubleValue(for: .kilocalorie())
                // Persist completion before releasing the live builder. Stable sync metadata protects replay after a crash.
                try report(HealthWorkoutReport(id: request.id, state: .saved, activeCalories: HealthWorkoutReport.metric(calories),
                    totalCalories: HealthWorkoutReport.totalCalories(active: calories, resting: resting)))
                session.end(); clearSession()
            } else {
                try await HealthWorkoutAccess.saveDuration(request, health: health)
                try report(HealthWorkoutReport(id: request.id, state: .saved, message: L10n.text("WORKOUT_DURATION_SYNCED_NO_LIVE_ACTIVITY_DATA_WAS_AVAILABLE_FOR_THIS_SESSION" /* 训练时长已同步；本次没有可用的实时运动数据。 */)))
            }
        } catch {
            // A session that failed before collection is usable must not block future retries.
            if request.phase == .running, ledger.activeID == request.id, ledger.reports[request.id]?.state != .running {
                session?.end(); builder?.discardWorkout(); clearSession()
            }
            try? report(HealthWorkoutReport(id: request.id, state: .failed, message: error.localizedDescription))
        }
    }
    private func clearSession() {
        session = nil; builder = nil; ledger.activeID = nil; collectionEnded = false
        try? journal.write(ledger)
    }
    private func report(_ value: HealthWorkoutReport) throws {
        var next = ledger; next.receive(value)
        try journal.write(next); ledger = next; onReport?(value)
    }
    private func emitMetrics() {
        guard let id = ledger.activeID, let builder, ledger.reports[id]?.terminal != true else { return }
        let energy = builder.statistics(for: HealthWorkoutAccess.energy)?.sumQuantity()?.doubleValue(for: .kilocalorie())
        let resting = builder.statistics(for: HealthWorkoutAccess.restingEnergy)?.sumQuantity()?.doubleValue(for: .kilocalorie())
        let heart = builder.statistics(for: HealthWorkoutAccess.heartRate)?.mostRecentQuantity()?.doubleValue(for: .count().unitDivided(by: .minute()))
        // Metrics are transient during a session. The terminal report is journaled once saved.
        onReport?(HealthWorkoutReport(id: id, state: .running, activeCalories: HealthWorkoutReport.metric(energy),
            totalCalories: HealthWorkoutReport.totalCalories(active: energy, resting: resting), heartRate: HealthWorkoutReport.metric(heart)))
    }
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        Task { @MainActor [weak self] in self?.emitMetrics() }
    }
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            guard let self, self.session === workoutSession, let id = self.ledger.activeID else { return }
            self.onReport?(HealthWorkoutReport(id: id, state: .failed, message: L10n.text("SYSTEM_WORKOUT_INTERRUPTED_COUNT" /* 系统训练已中断：{0} */, error.localizedDescription)))
            // An interrupted system workout must stop accumulating, even if the phone is unreachable.
            if var request = self.ledger.requests[id], request.phase == .running {
                request.phase = .finished; request.end = max(request.start, Date()); self.accept([request])
            }
        }
    }
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        Task { @MainActor [weak self] in
            guard let self, self.session === workoutSession else { return }
            self.onSessionStateChange?()
            guard let id = self.ledger.activeID,
                  (toState == .stopped || toState == .ended), var request = self.ledger.requests[id], request.phase == .running else { return }
            request.phase = .finished; request.end = max(request.start, date); self.accept([request])
        }
    }
}
