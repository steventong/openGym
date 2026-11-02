import ActivityKit
import UIKit
import UserNotifications
import OSLog

@MainActor enum WorkoutActivityRuntime {
    /// Shared by app launch and a background LiveActivityIntent, including cold launches.
    static let store: GymStore = {
        let store = GymStore()
        store.prepareOfflineLaunch()
        if let url = Bundle.main.url(forResource: "catalogue", withExtension: "json"),
           let data = try? Data(contentsOf: url), let list = try? JSONDecoder().decode([Exercise].self, from: data) {
            store.registerCatalogue(list)
        }
        store.liveActivity = WorkoutActivityCoordinator(store: store)
        store.watchBridge = PhoneWatchBridge(store: store)
        return store
    }()
}

@MainActor final class WorkoutActivityCoordinator {
    private weak var store: GymStore?
    private var worker: Task<Void, Never>?
    private var pending = false
    private var actionMessage: String?
    private var scheduledRest: String?
    private var permissionRequested = false
    private let notifications = UNUserNotificationCenter.current()
    private let logger = Logger(subsystem: "me.itwl.opengym", category: "LiveActivity")
    static let reminderID = "opengym.workout.rest"

    init(store: GymStore) { self.store = store }

    func publish() {
        pending = true
        guard worker == nil else { return }
        worker = Task { [weak self] in
            // Coalesce set completion, rest calculation and the command receipt.
            await Task.yield()
            guard let self else { return }
            while pending { pending = false; await reconcile() }
            worker = nil
        }
    }

    func flush(actionMessage: String? = nil) async {
        self.actionMessage = actionMessage
        publish()
        await worker?.value
    }

    private func reconcile() async {
        guard let store else { return }
        // Permission is requested only in the foreground with an active workout.
        if store.draft != nil, UIApplication.shared.applicationState == .active, !permissionRequested {
            permissionRequested = true
            let settings = await notifications.notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                _ = try? await notifications.requestAuthorization(options: [.alert, .sound])
            }
        }
        let snapshot = store.watchSnapshot()
        var state = store.workoutActivityState()
        if let actionMessage { state?.message = actionMessage; self.actionMessage = nil }
        let attributes = snapshot.sessionID.map { WorkoutActivityAttributes(account: snapshot.account, sessionID: $0) }
        for activity in Activity<WorkoutActivityAttributes>.activities {
            if activity.attributes.sessionID != attributes?.sessionID || activity.attributes.account != attributes?.account || state == nil {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
        if let attributes, let state {
            let content = ActivityContent(state: state, staleDate: state.restEnd, relevanceScore: 1)
            let matches = Activity<WorkoutActivityAttributes>.activities.filter {
                $0.attributes.sessionID == attributes.sessionID && $0.attributes.account == attributes.account &&
                ($0.activityState == .active || $0.activityState == .stale)
            }
            if let activity = matches.first {
                if activity.content.state != state { await activity.update(content) }
                for extra in matches.dropFirst() { await extra.end(nil, dismissalPolicy: .immediate) }
                store.liveActivityIssue = nil
            } else if UIApplication.shared.applicationState == .active {
                if ActivityAuthorizationInfo().areActivitiesEnabled {
                    do {
                        _ = try Activity.request(attributes: attributes, content: content, pushType: nil)
                        store.liveActivityIssue = nil
                    } catch {
                        logger.error("Unable to start workout activity: \(error.localizedDescription)")
                        store.liveActivityIssue = "实时活动暂未启动，回到 App 后会重试。"
                    }
                } else { store.liveActivityIssue = "实时活动未开启，可在系统设置中允许 openGym 的实时活动。" }
            }
        } else { store.liveActivityIssue = nil }
        await updateReminder()
    }

    private func updateReminder() async {
        // Read fresh state after ActivityKit awaits, so deleting/skipping a rest cannot leave an old reminder.
        guard let store, let draft = store.draft, let end = store.restUntil, end > Date() else {
            notifications.removePendingNotificationRequests(withIdentifiers: [Self.reminderID])
            if store?.restUntil == nil { notifications.removeDeliveredNotifications(withIdentifiers: [Self.reminderID]) }
            scheduledRest = nil
            return
        }
        let key = "\(store.coachIdentity)|\(draft.id)|\(end.timeIntervalSince1970)"
        guard scheduledRest != key else { return }
        let content = UNMutableNotificationContent()
        content.title = "休息结束"
        let snapshot = store.watchSnapshot()
        content.body = "\(draft.name) · \(snapshot.exercise)。准备好后继续下一组。"
        content.sound = .default
        content.userInfo = ["openGymWorkout": true]
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, end.timeIntervalSinceNow), repeats: false)
        do {
            try await notifications.add(UNNotificationRequest(identifier: Self.reminderID, content: content, trigger: trigger))
            scheduledRest = key
        } catch { logger.error("Unable to schedule rest reminder: \(error.localizedDescription)") }
    }
}
