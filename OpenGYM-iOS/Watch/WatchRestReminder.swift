import Foundation
import UserNotifications
import WatchKit
import OSLog

@MainActor final class WatchRestReminder: NSObject, UNUserNotificationCenterDelegate {
    var onError: ((String) -> Void)?

    private var snapshot = WatchTrainingSnapshot(generatedAt: .distantPast)
    private var foregroundActive = false
    private var workoutRunning = false
    private var authorizationStatus: UNAuthorizationStatus = .notDetermined
    private var notificationKey = ""
    private var notificationTask: Task<Void, Never>?
    private var hapticTask: Task<Void, Never>?
    private var haptic = WatchForegroundRestReminder()
    private static let logger = Logger(subsystem: "me.itwl.opengym.watchkitapp", category: "RestReminder")

    func start() {
        UNUserNotificationCenter.current().delegate = self
    }

    func update(_ snapshot: WatchTrainingSnapshot, workoutRunning: Bool) {
        self.snapshot = snapshot
        self.workoutRunning = workoutRunning
        scheduleNotification()
        scheduleHaptic()
    }

    func setForegroundActive(_ active: Bool) {
        foregroundActive = active
        scheduleHaptic()
        if active { clearDeliveredNotifications() }
    }

    func refreshAuthorization() {
        Task { [weak self] in
            let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
            guard let self, status != authorizationStatus else { return }
            authorizationStatus = status
            notificationKey = ""
            scheduleNotification()
        }
    }

    func flush() async {
        await notificationTask?.value
    }

    private func clearDeliveredNotifications() {
        // Include the companion's notification when it was mirrored onto the watch.
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["opengym.rest", "opengym.workout.rest"])
    }

    private func scheduleHaptic() {
        hapticTask?.cancel()
        hapticTask = nil
        guard let end = haptic.update(snapshot, active: foregroundActive, workoutRunning: workoutRunning, now: Date()),
              let key = haptic.key else { return }
        hapticTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(max(0, end.timeIntervalSinceNow))) }
            catch { return }
            guard !Task.isCancelled else { return }
            self?.deliverHaptic(key: key)
        }
    }

    private func deliverHaptic(key: String) {
        guard (foregroundActive && WKApplication.shared().applicationState == .active) || workoutRunning,
              haptic.consume(key: key, now: Date()) else { return }
        let delay = max(0, -(haptic.deadline?.timeIntervalSinceNow ?? 0))
        Self.logger.info("Rest completion haptic, delay_seconds=\(delay, privacy: .public)")
        WKInterfaceDevice.current().play(.notification)
        // Wait for a possible in-flight add before clearing the fallback. A newer rest
        // must retain its notification even if it arrives while this task is suspended.
        let scheduled = notificationTask
        Task { [weak self] in
            await scheduled?.value
            guard let self, haptic.key == key, haptic.didAlert else { return }
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["opengym.rest"])
            clearDeliveredNotifications()
        }
    }

    private func scheduleNotification() {
        let key = snapshot.restReminderKey ?? ""
        let usesWorkoutHaptic = workoutRunning
        let schedulingKey = "\(key)|workout=\(usesWorkoutHaptic)"
        guard schedulingKey != notificationKey else { return }
        notificationKey = schedulingKey
        let previous = notificationTask, current = snapshot
        previous?.cancel()
        notificationTask = Task { [weak self] in
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
            catch { self?.onError?(String(localized: "COULD_NOT_SET_A_REST_REMINDER_KEEP_AN_EYE_ON_THE_COUNTDOWN", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) }
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
        Task { @MainActor [weak self] in
            if let key { self?.deliverHaptic(key: key) }
        }
    }
}
