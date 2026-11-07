import Foundation
import Observation
import WatchConnectivity
import UserNotifications
import WatchKit
import HealthKit
import OSLog

@MainActor @Observable final class WatchRemoteStore: NSObject, WCSessionDelegate, UNUserNotificationCenterDelegate {
    var healthReport: HealthWorkoutReport?
    var healthStatus = ""
    var authorizingHealth = false
    @ObservationIgnored private let healthRecorder = HealthWorkoutRecorder(name: "watch-recorder")
    @ObservationIgnored private let healthStore = HKHealthStore()
    var snapshot = WatchTrainingSnapshot(generatedAt: .distantPast)
    var currentHealthReport: HealthWorkoutReport? {
        guard let sessionID = snapshot.sessionID, healthReport?.id == "\(snapshot.account):\(sessionID)" else { return nil }
        return healthReport
    }
    var reachable = false
    private(set) var reconnecting = false
    var sending = false
    var error: String?
    var notificationStatus: UNAuthorizationStatus = .notDetermined
    private(set) var pending: WatchTrainingCommand?
    @ObservationIgnored private var reminderKey = ""
    @ObservationIgnored private var timeout: Task<Void, Never>?
    @ObservationIgnored private var reminderTask: Task<Void, Never>?
    @ObservationIgnored private var foregroundReminderTask: Task<Void, Never>?
    @ObservationIgnored private var foregroundReminder = WatchForegroundRestReminder()
    @ObservationIgnored private var foregroundActive = false
    private static let reminderLog = Logger(subsystem: "me.itwl.opengym.watchkitapp", category: "RestReminder")
    @ObservationIgnored private var connectionTask: Task<Void, Never>?
    @ObservationIgnored private var connectionID: UUID?
    @ObservationIgnored private var preview = false

    /// Canvas uses isolated sample state and never reads saved workouts or connects.
    init(previewSnapshot: WatchTrainingSnapshot) {
        super.init()
        preview = true
        snapshot = previewSnapshot
        reachable = true
        if let sessionID = previewSnapshot.sessionID {
            healthReport = HealthWorkoutReport(id: "\(previewSnapshot.account):\(sessionID)", state: .running,
                activeCalories: 128, totalCalories: 156, heartRate: 124)
        }
    }

    override init() {
        super.init()
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-remote-preview") {
            preview = true
            snapshot = WatchTrainingSnapshot(sessionID: "preview", exercise: String(localized: "BARBELL_BENCH_PRESS", bundle: AppLanguage.bundle, locale: AppLanguage.locale), exercisePosition: String(format: String(localized: "EXERCISE_COUNT_OF_COUNT", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(describing: 2), String(describing: 6)),
                nextSet: WatchTrainingSet(entry: 0, index: 1, label: String(localized: "SET_TWO_OF_FOUR", bundle: AppLanguage.bundle, locale: AppLanguage.locale), weight: "40 kg", detail: String(localized: "ONEZERO_REPS", bundle: AppLanguage.bundle, locale: AppLanguage.locale)),
                restEnd: Date().addingTimeInterval(75), restEntry: 0, restExercise: String(localized: "BARBELL_BENCH_PRESS", bundle: AppLanguage.bundle, locale: AppLanguage.locale), message: String(localized: "PREVIEW", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
            reachable = true
            notificationStatus = .authorized
            healthReport = HealthWorkoutReport(id: ":preview", state: .running, activeCalories: 128, totalCalories: 156, heartRate: 124)
            if ProcessInfo.processInfo.arguments.contains("-preview-short-rest") { snapshot.restEnd = Date().addingTimeInterval(12) }
            if ProcessInfo.processInfo.arguments.contains("-preview-training") { snapshot.restEnd = nil; snapshot.setStartedAt = Date().addingTimeInterval(-620) }
            if ProcessInfo.processInfo.arguments.contains("-preview-protected") { snapshot.actionReadyAt = TrainingActionTiming.deadline(after: Date()) }
            if ProcessInfo.processInfo.arguments.contains("-preview-disconnected") { reachable = false }
            if ProcessInfo.processInfo.arguments.contains("-preview-long-text") {
                snapshot.exercise = String(localized: "SEATED_SINGLE_ARM_DUMBBELL_SHOULDER_PRESS_ALTERNATING", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
                snapshot.nextSet?.label = String(localized: "SET_ONETWO_OF_ONETWO_RIGHT_WARM_UP", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
                snapshot.nextSet?.detail = String(localized: "ONETWO_REPS_THREE_REST_PAUSE_MINI_SETS", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
            }
            return
        }
        #endif
        if let data = UserDefaults.standard.data(forKey: "remote.snapshot"), let cached = try? JSONDecoder().decode(WatchTrainingSnapshot.self, from: data) { snapshot = cached; if let language = cached.language { AppLanguage.setLanguage(language) } }
        if let data = UserDefaults.standard.data(forKey: "remote.pending") { pending = try? JSONDecoder().decode(WatchTrainingCommand.self, from: data) }
    }
    func start() {
        guard !preview else { return }
        healthRecorder.onSessionStateChange = { [weak self] in
            self?.scheduleReminder()
            self?.scheduleForegroundReminder()
        }
        healthRecorder.onReport = { [weak self] report in self?.publishHealth(report) }
        healthRecorder.accept([])
        UNUserNotificationCenter.current().delegate = self
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }
    func refresh() {
        guard !preview, connectionTask == nil else { return }
        Task {
            let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
            if status != notificationStatus { notificationStatus = status; reminderKey = ""; scheduleReminder() }
        }
        let session = WCSession.default
        if session.activationState == .notActivated { start() }
        if !session.isReachable { reachable = false }
        // A wrist raise also refreshes the snapshot. Keep an already confirmed,
        // reachable connection usable while that refresh is in flight.
        // Initial connections and recovery still wait for a fresh phone reply.
        reconnecting = !reachable
        let id = UUID(); connectionID = id
        connectionTask = Task { [weak self] in
            // Give activation/transient reachability a short automatic recovery window.
            // Only a fresh phone reply re-enables training; never replay a completion here.
            for _ in 0..<3 {
                guard !Task.isCancelled, self?.connectionID == id else { return }
                if session.activationState == .activated && session.isReachable {
                    session.sendMessage(["request": "snapshot"], replyHandler: { [weak self] message in
                        Task { @MainActor in
                            guard let self, self.connectionID == id, WatchTrainingSnapshot.decode(message) != nil else { return }
                            self.receive(message)
                            self.reachable = true
                            self.finishConnection()
                        }
                    }, errorHandler: { _ in })
                }
                try? await Task.sleep(for: .seconds(2))
            }
            guard !Task.isCancelled, let self, self.connectionID == id else { return }
            self.reachable = false
            self.finishConnection()
        }
    }
    func setForegroundActive(_ active: Bool) {
        guard !preview else { return }
        foregroundActive = active
        scheduleForegroundReminder()
        if active {
            clearDeliveredRestNotifications()
            refresh()
        }
    }

    private func clearDeliveredRestNotifications() {
        // Include the companion's notification when it was mirrored onto the watch.
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["opengym.rest", "opengym.workout.rest"])
    }

    private var workoutHapticsAvailable: Bool {
        guard let sessionID = snapshot.sessionID else { return false }
        return healthRecorder.runningSessionID == "\(snapshot.account):\(sessionID)"
    }

    private func scheduleForegroundReminder() {
        foregroundReminderTask?.cancel()
        foregroundReminderTask = nil
        guard let end = foregroundReminder.update(snapshot, active: foregroundActive, workoutRunning: workoutHapticsAvailable, now: Date()),
              let key = foregroundReminder.key else { return }
        foregroundReminderTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(max(0, end.timeIntervalSinceNow))) }
            catch { return }
            guard !Task.isCancelled else { return }
            self?.deliverForegroundReminder(key: key)
        }
    }

    private func deliverForegroundReminder(key: String) {
        guard (foregroundActive && WKApplication.shared().applicationState == .active) || workoutHapticsAvailable,
              foregroundReminder.consume(key: key, now: Date()) else { return }
        let delay = max(0, -(foregroundReminder.deadline?.timeIntervalSinceNow ?? 0))
        Self.reminderLog.info("Rest completion haptic, delay_seconds=\(delay, privacy: .public)")
        WKInterfaceDevice.current().play(.notification)
        // Wait for a possible in-flight add before clearing the fallback. A newer rest
        // must retain its notification even if it arrives while this task is suspended.
        let scheduled = reminderTask
        Task { [weak self] in
            await scheduled?.value
            guard let self, self.foregroundReminder.key == key, self.foregroundReminder.didAlert else { return }
            let center = UNUserNotificationCenter.current()
            center.removePendingNotificationRequests(withIdentifiers: ["opengym.rest"])
            self.clearDeliveredRestNotifications()
        }
    }
    private func finishConnection() {
        connectionTask?.cancel(); connectionTask = nil; connectionID = nil; reconnecting = false
    }
    func primaryAction(at date: Date = Date()) -> WatchTrainingAction {
        snapshot.primaryAction(reachable: reachable, reconnecting: reconnecting,
            hasPending: pending != nil, sending: sending, at: date)
    }
    func isDisabled(_ action: WatchTrainingAction, includeProtection: Bool = true) -> Bool {
        if !reachable { return true }
        if includeProtection && snapshot.actionTiming.isProtected(at: Date()) { return true }
        switch action {
        case .sending, .finished: return true
        case .retry: return sending
        case .endRest: return snapshot.restEntry == nil
        case .complete: return snapshot.nextSet?.blockedReason != nil
        case .next: return false
        }
    }
    func performPrimaryAction() {
        let action = primaryAction()
        guard !isDisabled(action) else { return }
        #if DEBUG
        if preview {
            if action == .endRest { snapshot.restEnd = nil; snapshot.setStartedAt = Date() }
            else if action == .complete { snapshot.restEnd = Date().addingTimeInterval(12) }
            else { return }
            snapshot.actionReadyAt = TrainingActionTiming.deadline(after: Date())
            return
        }
        #endif
        switch action {
        case .retry: retry()
        case .endRest: endRest()
        case .complete: complete()
        case .next: nextExercise()
        case .sending, .finished: break
        }
    }
    func finishBackgroundDelivery() async {
        for _ in 0..<40 {
            if WCSession.default.activationState == .activated && !WCSession.default.hasContentPending { break }
            try? await Task.sleep(for: .milliseconds(250))
        }
        await reminderTask?.value
    }
    func complete() {
        guard pending == nil, !snapshot.actionTiming.isProtected(at: Date()), snapshot.restEnd == nil, let sessionID = snapshot.sessionID, let row = snapshot.nextSet, row.blockedReason == nil else { return }
        send(WatchTrainingCommand(account: snapshot.account, sessionID: sessionID, revision: snapshot.revision, action: "complete", entry: row.entry, index: row.index, side: row.side))
    }
    func endRest() {
        guard pending == nil, !snapshot.actionTiming.isProtected(at: Date()), snapshot.restEnd != nil,
              let sessionID = snapshot.sessionID, let entry = snapshot.restEntry else { return }
        send(WatchTrainingCommand(account: snapshot.account, sessionID: sessionID, revision: snapshot.revision, action: "skipRest", entry: entry))
    }
    func nextExercise() {
        guard pending == nil, let sessionID = snapshot.sessionID, let entry = snapshot.nextEntry else { return }
        send(WatchTrainingCommand(account: snapshot.account, sessionID: sessionID, revision: snapshot.revision, action: "next", entry: entry))
    }
    func retry() { if let pending { send(pending) } }
    private func send(_ command: WatchTrainingCommand) {
        guard !preview, !sending, WCSession.default.activationState == .activated else { return }
        reachable = WCSession.default.isReachable
        guard reachable else { refresh(); return }
        pending = command
        UserDefaults.standard.set(try? JSONEncoder().encode(command), forKey: "remote.pending")
        sending = true; error = nil
        timeout?.cancel()
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(12))
            guard !Task.isCancelled, self?.pending?.id == command.id else { return }
            self?.sending = false; self?.error = String(localized: "YOUR_PHONE_HAS_NOT_CONFIRMED_YET_YOU_CAN_RETRY_CONFIRMATION", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
            self?.reachable = false; self?.refresh()
        }
        WCSession.default.sendMessage(command.payload, replyHandler: { [weak self] message in
            Task { @MainActor in self?.receive(message) }
        }, errorHandler: { [weak self] _ in
            Task { @MainActor in
                guard self?.pending?.id == command.id else { return }
                self?.sending = false; self?.error = String(localized: "YOUR_PHONE_HAS_NOT_CONFIRMED_YET_YOU_CAN_RETRY_CONFIRMATION", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
                self?.reachable = false; self?.refresh()
            }
        })
    }
    private func receive(_ message: [String: Any]) {
        let requests = HealthWorkoutWire.requests(from: message).filter { $0.owner == .watch }
        if !requests.isEmpty {
            healthRecorder.accept(requests)
            if requests.contains(where: { $0.phase == .running }),
               healthStore.authorizationStatus(for: HealthWorkoutAccess.workout) == .notDetermined,
               WKApplication.shared().applicationState == .active {
                authorizeWorkout()
            }
        }
        if let incoming = WatchTrainingSnapshot.decode(message), incoming.generatedAt >= snapshot.generatedAt {
            if let language = incoming.language { AppLanguage.setLanguage(language) }
            snapshot = incoming
            UserDefaults.standard.set(try? JSONEncoder().encode(incoming), forKey: "remote.snapshot")
            if let pending, incoming.acknowledged.contains(pending.id) { clearPending(); error = nil; acknowledge() }
            else if let pending, incoming.sessionID != pending.sessionID || incoming.account != pending.account {
                clearPending(); error = String(localized: "THE_WORKOUT_CHANGED_UPDATED_TO_MATCH_YOUR_PHONE", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
            }
            scheduleReminder()
            scheduleForegroundReminder()
        }
        if let id = message["commandID"] as? String, id == pending?.id {
            let accepted = message["accepted"] as? Bool == true
            clearPending()
            error = accepted ? nil : message["error"] as? String ?? String(localized: "CHECK_THE_WORKOUT_ON_YOUR_PHONE", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
            if accepted { acknowledge() }
        }
    }
    func authorizeWorkout() {
        guard !authorizingHealth, HKHealthStore.isHealthDataAvailable() else { return }
        authorizingHealth = true
        Task {
            defer { authorizingHealth = false }
            do {
                try await HealthWorkoutAccess.authorize(healthStore)
                healthStatus = String(localized: "ACCESS_ALLOWED_WAITING_FOR_WORKOUT_SYNC_FROM_IPHONE", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
                healthRecorder.accept([]); refresh()
            } catch { healthStatus = error.localizedDescription }
        }
    }
    func stopHealthWorkout() { healthRecorder.stopFromWatch() }
    private func publishHealth(_ report: HealthWorkoutReport) {
        // Receipts for a previous workout must not replace the current workout's live display.
        let expected = "\(snapshot.account):\(snapshot.sessionID ?? "")"
        if report.id == expected || healthReport == nil || healthReport?.id == report.id {
            healthReport = report
            switch report.state {
            case .running: healthStatus = String(localized: "RECORDING_ACTIVITY", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
            case .saved: healthStatus = String(localized: "ACTIVITY_SAVED_SUBMIT_YOUR_SETS_ON_IPHONE", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
            case .discarded: healthStatus = String(localized: "ACTIVITY_RECORDING_CANCELLED", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
            case .failed: healthStatus = report.message ?? String(localized: "ACTIVITY_SYNC_FAILED_TRY_AGAIN", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
            }
        }
        scheduleReminder()
        scheduleForegroundReminder()
        guard WCSession.default.activationState == .activated else { return }
        let payload = HealthWorkoutWire.report(report)
        if WCSession.default.isReachable { WCSession.default.sendMessage(payload, replyHandler: nil, errorHandler: { _ in }) }
        if report.terminal || report.state == .failed {
            let queued = WCSession.default.outstandingUserInfoTransfers.contains {
                HealthWorkoutWire.report(from: $0.userInfo) == report
            }
            if !queued { WCSession.default.transferUserInfo(payload) }
        }
    }
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        Task { @MainActor [weak self] in self?.receive(userInfo) }
    }
    private func acknowledge() {
        WKInterfaceDevice.current().play(.success)
    }
    private func clearPending() {
        pending = nil; sending = false; timeout?.cancel()
        UserDefaults.standard.removeObject(forKey: "remote.pending")
    }
    func enableReminder() {
        Task {
            do { _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) }
            catch { self.error = String(localized: "COULD_NOT_ENABLE_REMINDERS_TRY_AGAIN_LATER", bundle: AppLanguage.bundle, locale: AppLanguage.locale) }
            notificationStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
            reminderKey = ""; scheduleReminder()
        }
    }
    private func scheduleReminder() {
        let key = snapshot.restReminderKey ?? ""
        let usesWorkoutHaptic = workoutHapticsAvailable
        let schedulingKey = "\(key)|workout=\(usesWorkoutHaptic)"
        guard schedulingKey != reminderKey else { return }
        reminderKey = schedulingKey
        let previous = reminderTask, current = snapshot
        previous?.cancel()
        reminderTask = Task {
            // Finish an in-flight add before replacing it, so an old rest cannot win a race.
            await previous?.value
            guard !Task.isCancelled else { return }
            let center = UNUserNotificationCenter.current()
            center.removePendingNotificationRequests(withIdentifiers: ["opengym.rest"])
            center.removeDeliveredNotifications(withIdentifiers: ["opengym.rest"])
            // A running workout owns the haptic, avoiding a second system alert.
            guard !usesWorkoutHaptic else { return }
            guard let end = current.restEnd, end.timeIntervalSinceNow > 0, current.sessionID != nil else { return }
            let content = UNMutableNotificationContent()
            content.title = current.restNotificationTitle
            content.body = current.restNotificationBody
            content.sound = .default
            content.userInfo = ["restKey": key]
            let request = UNNotificationRequest(identifier: "opengym.rest", content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, end.timeIntervalSinceNow), repeats: false))
            do { try await center.add(request) }
            catch { self.error = String(localized: "COULD_NOT_SET_A_REST_REMINDER_KEEP_AN_EYE_ON_THE_COUNTDOWN", bundle: AppLanguage.bundle, locale: AppLanguage.locale) }
        }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let isRest = notification.request.identifier == "opengym.rest"
            || notification.request.content.userInfo["openGymWorkout"] as? Bool == true
        guard isRest else { completionHandler([.banner]); return }
        let key = notification.request.content.userInfo["restKey"] as? String
        // Foreground rests never create a banner/list entry, including a late phone mirror.
        center.removeDeliveredNotifications(withIdentifiers: [notification.request.identifier])
        completionHandler([])
        Task { @MainActor in
            if let key { self.deliverForegroundReminder(key: key) }
        }
    }
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor [weak self] in self?.receive(session.receivedApplicationContext); self?.refresh() }
    }
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) { Task { @MainActor [weak self] in self?.refresh() } }
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) { Task { @MainActor [weak self] in self?.receive(applicationContext) } }
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) { Task { @MainActor [weak self] in self?.receive(message) } }
}
