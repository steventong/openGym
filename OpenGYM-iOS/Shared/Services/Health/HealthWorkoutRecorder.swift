import Foundation
import HealthKit
import OSLog

enum HealthWorkoutAccess {
    private static let logger = Logger(subsystem: "me.itwl.opengym", category: "HealthSync")
    static let workout = HKObjectType.workoutType()
    static let energy = HKQuantityType(.activeEnergyBurned)
    static let restingEnergy = HKQuantityType(.basalEnergyBurned)
    static let heartRate = HKQuantityType(.heartRate)
    static func authorize(_ health: HKHealthStore) async throws {
        try await health.requestAuthorization(toShare: [workout, energy], read: [workout, energy, restingEnergy, heartRate])
        guard health.authorizationStatus(for: workout) == .sharingAuthorized else {
            throw NSError(domain: "OpenGymHealth", code: 1, userInfo: [NSLocalizedDescriptionKey: String(localized: "ALLOW_OPENGYM_TO_WRITE_WORKOUTS_IN_THE_HEALTH_APP", bundle: AppLanguage.bundle, locale: AppLanguage.locale)])
        }
    }
    static var configuration: HKWorkoutConfiguration {
        let value = HKWorkoutConfiguration()
        value.activityType = .traditionalStrengthTraining
        value.locationType = .indoor
        return value
    }
    /// Source identity only: never logs workout titles, times, metrics or user identifiers.
    static func logSavedWorkoutSource(_ workout: HKWorkout) {
        let revision: HKSourceRevision? = workout.sourceRevision
        let icons = Bundle.main.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any]
        let primary = icons?["CFBundlePrimaryIcon"] as? [String: Any]
        let iconName = primary?["CFBundleIconName"] as? String ?? "missing"
        let bundle = Bundle.main.bundleIdentifier ?? "unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        let sourceBundle = revision?.source.bundleIdentifier ?? "unavailable"
        let sourceVersion = revision?.version ?? "unavailable"
        let writerBundle = HKSource.default().bundleIdentifier
        logger.notice("HealthSync saved workout sourceBundle=\(sourceBundle, privacy: .public) sourceVersion=\(sourceVersion, privacy: .public) writerBundle=\(writerBundle, privacy: .public) appBundle=\(bundle, privacy: .public) appBuild=\(build, privacy: .public) iconName=\(iconName, privacy: .public)")
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
        guard let workout = try await builder.finishWorkout() else {
            throw NSError(domain: "OpenGymHealth", code: 4, userInfo: [NSLocalizedDescriptionKey: String(localized: "APPLE_HEALTH_HAS_NOT_CONFIRMED_THE_SAVE_RETRY_SYNCING", bundle: AppLanguage.bundle, locale: AppLanguage.locale)])
        }
        logSavedWorkoutSource(workout)
    }
}

#if os(watchOS)
/// Sensor execution only; training state and commands belong to the phone.
@MainActor final class HealthWorkoutRecorder: NSObject, HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate {
    private static let logger = Logger(subsystem: "me.itwl.opengym", category: "HealthSync")
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
            for request in requests { onReport?(HealthWorkoutReport(id: request.id, state: .failed, message: String(format: String(localized: "COULD_NOT_SAVE_HEALTH_SYNC_DATA_LOCALLY_COUNT", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(describing: error.localizedDescription)))) }
        }
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
                onReport?(HealthWorkoutReport(id: request.id, state: .failed, message: String(format: String(localized: "WORKOUT_RECOVERY_IS_INCOMPLETE_UNLOCK_YOUR_DEVICE_AND_RETRY_COUNT", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(describing: error.localizedDescription))))
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
                    try report(HealthWorkoutReport(id: request.id, state: .failed, message: String(localized: "ACTIVITY_TRACKING_WAS_INTERRUPTED_DURATION_WILL_SYNC_WHEN_YOU_FINISH_THE_WORKOUT", bundle: AppLanguage.bundle, locale: AppLanguage.locale))); return
                }
                guard health.authorizationStatus(for: HealthWorkoutAccess.workout) == .sharingAuthorized else {
                    throw NSError(domain: "OpenGymHealth", code: 1, userInfo: [NSLocalizedDescriptionKey: String(localized: "OPEN_HEALTH_SYNC_SETTINGS_IN_OPENGYM_AND_ALLOW_ACCESS", bundle: AppLanguage.bundle, locale: AppLanguage.locale)])
                }
                if ledger.activeID == request.id, session != nil { emitMetrics(); return }
                guard session == nil else {
                    throw NSError(domain: "OpenGymHealth", code: 2, userInfo: [NSLocalizedDescriptionKey: String(localized: "THE_PREVIOUS_WORKOUT_HAS_NOT_ENDED_CONNECT_IPHONE_AND_RETRY_SYNCING", bundle: AppLanguage.bundle, locale: AppLanguage.locale)])
                }
                ledger.activeID = request.id; try journal.write(ledger)
                let next = try HKWorkoutSession(healthStore: health, configuration: HealthWorkoutAccess.configuration)
                session = next; next.delegate = self
                let live = next.associatedWorkoutBuilder(); builder = live; live.delegate = self
                live.dataSource = HKLiveWorkoutDataSource(healthStore: health, workoutConfiguration: next.workoutConfiguration)
                collectionEnded = false
                next.prepare()
                guard let collectionStart = request.collectionStart(at: Date()) else { return }
                Self.logger.notice("Watch sensor session starting")
                next.startActivity(with: collectionStart)
                try await live.beginCollection(at: collectionStart)
                try await live.addMetadata(HealthWorkoutAccess.metadata(request))
                Self.logger.notice("Watch sensor collection started")
                try report(HealthWorkoutReport(id: request.id, state: .running))
            } else if ledger.activeID == request.id, let session, let builder, let end = request.end {
                // The phone may have finished while a delayed start was being delivered.
                // Do not save sensor data collected after that authoritative end time.
                if let joined = builder.startDate, end <= joined {
                    session.end(); builder.discardWorkout(); clearSession()
                    try await HealthWorkoutAccess.saveDuration(request, health: health)
                    try report(HealthWorkoutReport(id: request.id, state: .saved,
                        message: String(localized: "WORKOUT_DURATION_SYNCED_NO_LIVE_ACTIVITY_DATA_WAS_AVAILABLE_FOR_THIS_SESSION", bundle: AppLanguage.bundle, locale: AppLanguage.locale)))
                    return
                }
                if session.state != .stopped && session.state != .ended { session.stopActivity(with: end) }
                // stopActivity is asynchronous; allow final sensor samples to reach the builder.
                for _ in 0..<100 {
                    if session.state == .stopped || session.state == .ended { break }
                    try await Task.sleep(for: .milliseconds(50))
                }
                guard session.state == .stopped || session.state == .ended else {
                    throw NSError(domain: "OpenGymHealth", code: 3, userInfo: [NSLocalizedDescriptionKey: String(localized: "STOPPING_ACTIVITY_TRACKING_RETRY_SYNCING_SHORTLY", bundle: AppLanguage.bundle, locale: AppLanguage.locale)])
                }
                if !collectionEnded { try await builder.endCollection(at: end); collectionEnded = true }
                // The training may have been renamed since collection began.
                try await builder.addMetadata(HealthWorkoutAccess.metadata(request))
                guard let workout = try await builder.finishWorkout() else {
                    throw NSError(domain: "OpenGymHealth", code: 4, userInfo: [NSLocalizedDescriptionKey: String(localized: "APPLE_HEALTH_HAS_NOT_CONFIRMED_THE_SAVE_RETRY_SYNCING", bundle: AppLanguage.bundle, locale: AppLanguage.locale)])
                }
                HealthWorkoutAccess.logSavedWorkoutSource(workout)
                let calories = workout.statistics(for: HealthWorkoutAccess.energy)?.sumQuantity()?.doubleValue(for: .kilocalorie())
                let resting = workout.statistics(for: HealthWorkoutAccess.restingEnergy)?.sumQuantity()?.doubleValue(for: .kilocalorie())
                // Persist completion before releasing the live builder. Stable sync metadata protects replay after a crash.
                try report(HealthWorkoutReport(id: request.id, state: .saved, activeCalories: HealthWorkoutReport.metric(calories),
                    totalCalories: HealthWorkoutReport.totalCalories(active: calories, resting: resting)))
                session.end(); clearSession()
            } else {
                try await HealthWorkoutAccess.saveDuration(request, health: health)
                try report(HealthWorkoutReport(id: request.id, state: .saved, message: String(localized: "WORKOUT_DURATION_SYNCED_NO_LIVE_ACTIVITY_DATA_WAS_AVAILABLE_FOR_THIS_SESSION", bundle: AppLanguage.bundle, locale: AppLanguage.locale)))
            }
        } catch {
            // A session that failed before collection is usable must not block future retries.
            if request.phase == .running, ledger.activeID == request.id, ledger.reports[request.id]?.state != .running {
                session?.end(); builder?.discardWorkout(); clearSession()
            }
            Self.logger.error("Watch sensor command failed domain=\((error as NSError).domain, privacy: .public) code=\((error as NSError).code)")
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
            self.onReport?(HealthWorkoutReport(id: id, state: .failed, message: String(format: String(localized: "SYSTEM_WORKOUT_INTERRUPTED_COUNT", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(describing: error.localizedDescription))))
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

#endif
