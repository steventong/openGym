import Observation
import UIKit
import UserNotifications

struct RestNotificationPermission {
    var authorization: UNAuthorizationStatus
    var alerts: Bool
    var canDeliver: Bool { [.authorized, .provisional, .ephemeral].contains(authorization) }
}

@MainActor protocol RestNotificationCenter {
    func permission() async -> RestNotificationPermission
    func authorize() async throws
    func add(_ request: UNNotificationRequest) async throws
    func clearDelivered()
    func cancel()
}

@MainActor struct SystemRestNotificationCenter: RestNotificationCenter {
    private let center = UNUserNotificationCenter.current()
    func permission() async -> RestNotificationPermission {
        let settings = await center.notificationSettings()
        return RestNotificationPermission(authorization: settings.authorizationStatus, alerts: settings.alertSetting == .enabled)
    }
    func authorize() async throws { _ = try await center.requestAuthorization(options: [.alert, .sound]) }
    func add(_ request: UNNotificationRequest) async throws { try await center.add(request) }
    func clearDelivered() {
        center.removeDeliveredNotifications(withIdentifiers: [RestNotifications.reminderID])
    }
    func cancel() {
        center.removePendingNotificationRequests(withIdentifiers: [RestNotifications.reminderID])
        clearDelivered()
    }
}

/// Schedules at rest start, independently of ActivityKit and foreground timer ticks.
@MainActor @Observable final class RestNotifications {
    static let reminderID = "opengym.workout.rest"
    static let preferenceKey = "restNotificationsEnabled"
    private(set) var enabled: Bool
    private(set) var busy = false
    private(set) var permission = RestNotificationPermission(authorization: .notDetermined, alerts: false)
    private(set) var issue: String?
    @ObservationIgnored private weak var store: GymStore?
    @ObservationIgnored private let center: any RestNotificationCenter
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let foreground: @MainActor () -> Bool
    @ObservationIgnored private var worker: Task<Void, Never>?
    @ObservationIgnored private var pending = false
    @ObservationIgnored private var pendingTraces: Set<String> = []
    @ObservationIgnored private var requestPermission = false
    @ObservationIgnored private var scheduledKey: String?

    init(store: GymStore, center: (any RestNotificationCenter)? = nil,
         defaults: UserDefaults = .standard, foreground: @escaping @MainActor () -> Bool = { UIApplication.shared.applicationState == .active }) {
        self.store = store; self.center = center ?? SystemRestNotificationCenter(); self.defaults = defaults; self.foreground = foreground
        enabled = defaults.object(forKey: Self.preferenceKey) as? Bool ?? true
    }

    var status: String {
        if let issue { return issue }
        if !enabled { return L10n.text("REST_END_REMINDERS_ARE_OFF" /* 已关闭休息结束提醒。 */) }
        switch permission.authorization {
        case .notDetermined: return L10n.text("ALLOW_NOTIFICATIONS_TO_RECEIVE_REST_END_REMINDERS" /* 尚未授权，请允许通知以接收休息结束提醒。 */)
        case .denied: return L10n.text("NOTIFICATIONS_ARE_BLOCKED_ALLOW_THEM_IN_SYSTEM_SETTINGS" /* 系统通知已关闭，请前往系统设置允许通知。 */)
        case .provisional: return L10n.text("NOTIFICATIONS_ARE_CURRENTLY_SILENT_ENABLE_BANNERS_AND_SOUND_IN_SYSTEM_SETTINGS" /* 当前为静默通知，请前往系统设置开启横幅和声音。 */)
        default: return permission.alerts ? L10n.text("NOTIFICATIONS_APPEAR_IN_THE_BACKGROUND_AND_ON_THE_LOCK_SCREEN_AND_ARE" /* 后台和锁屏时发送通知；打开 App 自动清除，App 内仅声音提醒。 */) : L10n.text("NOTIFICATION_BANNERS_ARE_OFF_ENABLE_THEM_IN_SYSTEM_SETTINGS" /* 系统横幅提醒已关闭，请前往系统设置开启。 */)
        }
    }

    func clearDelivered() { center.clearDelivered() }

    func setEnabled(_ value: Bool) async {
        issue = nil
        enabled = value; defaults.set(value, forKey: Self.preferenceKey)
        if !value { center.cancel(); scheduledKey = nil }
        requestPermission = value
        await flush()
    }

    func authorize() async { requestPermission = true; await flush() }

    func publish() {
        if let trace = WorkoutActivityDiagnostics.traceID { pendingTraces.insert(trace) }
        pending = true
        guard worker == nil else { return }
        worker = Task { [weak self] in
            await Task.yield()
            guard let self else { return }
            while pending {
                pending = false
                let traces = Array(pendingTraces); pendingTraces.removeAll()
                await reconcile(traces: traces)
            }
            worker = nil
        }
    }

    func flush() async {
        let started = ContinuousClock.now
        WorkoutActivityDiagnostics.record("reminder.flush.begin", ["worker_active": String(worker != nil)])
        publish(); await worker?.value
        WorkoutActivityDiagnostics.record("reminder.flush.end", ["elapsed_ms": WorkoutActivityDiagnostics.elapsed(started),
            "has_issue": String(issue != nil), "cancelled": String(Task.isCancelled)])
    }

    private var currentKey: String? {
        guard enabled, let store, store.userID != nil, let draft = store.draft, let end = store.restUntil else { return nil }
        return "\(store.coachIdentity)|\(draft.id)|\(end.timeIntervalSince1970)"
    }

    private func reconcile(traces: [String]) async {
        if foreground() { clearDelivered() }
        let started = ContinuousClock.now
        WorkoutActivityDiagnostics.record("reminder.reconcile.begin", ["enabled": String(enabled)], traces: traces)
        defer { WorkoutActivityDiagnostics.record("reminder.reconcile.end", ["elapsed_ms": WorkoutActivityDiagnostics.elapsed(started)], traces: traces) }
        WorkoutActivityDiagnostics.record("reminder.permission.begin", traces: traces)
        permission = await center.permission()
        WorkoutActivityDiagnostics.record("reminder.permission.end", ["authorization": String(permission.authorization.rawValue),
            "alerts": String(permission.alerts)], traces: traces)
        let shouldRequest = requestPermission || (store?.draft != nil && foreground())
        requestPermission = false
        if enabled && shouldRequest && permission.authorization == .notDetermined {
            busy = true
            WorkoutActivityDiagnostics.record("reminder.authorization.begin", ["foreground": String(foreground())], traces: traces)
            do {
                try await center.authorize(); issue = nil
                WorkoutActivityDiagnostics.record("reminder.authorization.end", traces: traces)
            } catch {
                WorkoutActivityDiagnostics.record("reminder.authorization.failed", WorkoutActivityDiagnostics.errorFields(error), traces: traces, failure: true)
                issue = L10n.text("COULD_NOT_REQUEST_NOTIFICATION_ACCESS_COUNT" /* 通知授权失败：{0} */, error.localizedDescription)
            }
            busy = false
            permission = await center.permission()
        }
        // Read fresh state after every authorization await; a workout may have ended meanwhile.
        guard let key = currentKey, permission.canDeliver, let store, let end = store.restUntil else {
            let reason = !enabled ? "preference_disabled" : (!permission.canDeliver ? "permission_unavailable" : "no_current_rest")
            WorkoutActivityDiagnostics.record("reminder.cancel", ["reason": reason], traces: traces)
            center.cancel(); scheduledKey = nil
            return
        }
        if let scheduledKey, scheduledKey != key {
            WorkoutActivityDiagnostics.record("reminder.cancel", ["reason": "rest_changed"], traces: traces)
            center.cancel(); self.scheduledKey = nil
        }
        // Do not cancel a notification at its delivery deadline or replay an expired rest on launch.
        guard end > Date(), scheduledKey != key else {
            WorkoutActivityDiagnostics.record("reminder.schedule.skipped", ["reason": end <= Date() ? "rest_expired" : "already_scheduled"], traces: traces)
            return
        }
        let content = UNMutableNotificationContent()
        let snapshot = store.watchSnapshot()
        content.title = snapshot.restNotificationTitle
        content.body = snapshot.restNotificationBody
        content.sound = .default
        content.userInfo = ["openGymWorkout": true, "restKey": key]
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, end.timeIntervalSinceNow), repeats: false)
        do {
            WorkoutActivityDiagnostics.record("reminder.schedule.begin", ["rest": WorkoutActivityDiagnostics.fingerprint(key)], traces: traces)
            try await center.add(UNNotificationRequest(identifier: Self.reminderID, content: content, trigger: trigger))
            guard currentKey == key else {
                WorkoutActivityDiagnostics.record("reminder.schedule.superseded", traces: traces)
                center.cancel(); scheduledKey = nil; pending = true; pendingTraces.formUnion(traces); return
            }
            scheduledKey = key; issue = nil
            WorkoutActivityDiagnostics.record("reminder.schedule.end", traces: traces)
        } catch {
            WorkoutActivityDiagnostics.record("reminder.schedule.failed", WorkoutActivityDiagnostics.errorFields(error), traces: traces, failure: true)
            issue = L10n.text("COULD_NOT_SCHEDULE_REST_REMINDER_COUNT" /* 休息提醒安排失败：{0} */, error.localizedDescription)
        }
    }
}
