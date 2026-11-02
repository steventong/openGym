import ActivityKit
import UIKit

@MainActor enum WorkoutActivityRuntime {
    /// Shared by app launch and a background LiveActivityIntent, including cold launches.
    static let store: GymStore = {
        let started = ContinuousClock.now
        WorkoutActivityDiagnostics.record("runtime.initialize.begin", ["version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            "build": Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown", "os": ProcessInfo.processInfo.operatingSystemVersionString])
        let store = GymStore()
        WorkoutActivityDiagnostics.record("runtime.offline.begin")
        store.prepareOfflineLaunch()
        WorkoutActivityDiagnostics.record("runtime.offline.end", WorkoutActivityDiagnostics.state(store))
        if let url = Bundle.main.url(forResource: "catalogue", withExtension: "json"),
           let data = try? Data(contentsOf: url), let list = try? JSONDecoder().decode([Exercise].self, from: data) {
            store.registerCatalogue(list)
        }
        store.restNotifications = RestNotifications(store: store)
        store.restNotifications?.publish()
        store.liveActivity = WorkoutActivityCoordinator(store: store)
        store.watchBridge = PhoneWatchBridge(store: store)
        var fields = WorkoutActivityDiagnostics.state(store)
        fields["catalogue_loaded"] = String(!store.exercises.isEmpty)
        fields["elapsed_ms"] = WorkoutActivityDiagnostics.elapsed(started)
        WorkoutActivityDiagnostics.record("runtime.initialize.end", fields)
        return store
    }()
}

@MainActor final class WorkoutActivityCoordinator {
    private weak var store: GymStore?
    private var worker: Task<Void, Never>?
    private var pending = false
    private var pendingTraces: Set<String> = []
    private var actionMessage: String?

    init(store: GymStore) { self.store = store }

    func publish() {
        if let trace = WorkoutActivityDiagnostics.traceID { pendingTraces.insert(trace) }
        if WorkoutActivityDiagnostics.traceID != nil {
            WorkoutActivityDiagnostics.record("activity.publish.queued", ["coalesced": String(worker != nil)])
        }
        pending = true
        guard worker == nil else { return }
        worker = Task { [weak self] in
            // Coalesce set completion, rest calculation and the command receipt.
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

    func flush(actionMessage: String? = nil) async {
        let started = ContinuousClock.now
        WorkoutActivityDiagnostics.record("activity.flush.begin", ["worker_active": String(worker != nil), "has_action_message": String(actionMessage != nil)])
        self.actionMessage = actionMessage
        publish()
        await worker?.value
        WorkoutActivityDiagnostics.record("activity.flush.end", ["elapsed_ms": WorkoutActivityDiagnostics.elapsed(started), "cancelled": String(Task.isCancelled)])
    }

    private func reconcile(traces: [String]) async {
        let started = ContinuousClock.now
        WorkoutActivityDiagnostics.record("activity.reconcile.begin", WorkoutActivityDiagnostics.environment(), traces: traces)
        defer { WorkoutActivityDiagnostics.record("activity.reconcile.end", ["elapsed_ms": WorkoutActivityDiagnostics.elapsed(started)], traces: traces) }
        guard let store else {
            WorkoutActivityDiagnostics.record("activity.reconcile.skipped", ["reason": "store_released"], traces: traces)
            return
        }
        let snapshot = store.watchSnapshot()
        var state = store.workoutActivityState()
        if let actionMessage { state?.message = actionMessage; self.actionMessage = nil }
        var fields = WorkoutActivityDiagnostics.state(store, snapshot: snapshot)
        fields["has_content"] = String(state != nil)
        fields["activities"] = String(Activity<WorkoutActivityAttributes>.activities.count)
        fields["activities_enabled"] = String(ActivityAuthorizationInfo().areActivitiesEnabled)
        fields["activity_states"] = Activity<WorkoutActivityAttributes>.activities.map { String(describing: $0.activityState) }.joined(separator: ",")
        fields["published_command"] = WorkoutActivityDiagnostics.publishedCommand(state?.command)
        fields["published_rest_command"] = WorkoutActivityDiagnostics.publishedCommand(state?.restCommand)
        fields["content_bytes"] = String(state.flatMap { try? JSONEncoder().encode($0).count } ?? 0)
        WorkoutActivityDiagnostics.record("activity.content.projected", fields, traces: traces)
        let attributes = snapshot.sessionID.map { WorkoutActivityAttributes(account: snapshot.account, sessionID: $0) }
        for activity in Activity<WorkoutActivityAttributes>.activities {
            if activity.attributes.sessionID != attributes?.sessionID || activity.attributes.account != attributes?.account || state == nil {
                let activityID = WorkoutActivityDiagnostics.fingerprint(activity.id)
                let reason = state == nil ? "no_content" : (activity.attributes.account != attributes?.account ? "account_mismatch" : "session_mismatch")
                WorkoutActivityDiagnostics.record("activity.end.begin", ["activity": activityID, "reason": reason], traces: traces)
                await activity.end(nil, dismissalPolicy: .immediate)
                WorkoutActivityDiagnostics.record("activity.end.end", ["activity": activityID], traces: traces)
            }
        }
        if let attributes, let state {
            let content = ActivityContent(state: state, staleDate: state.restEnd, relevanceScore: 1)
            let matches = Activity<WorkoutActivityAttributes>.activities.filter {
                $0.attributes.sessionID == attributes.sessionID && $0.attributes.account == attributes.account &&
                ($0.activityState == .active || $0.activityState == .stale)
            }
            if let activity = matches.first {
                let activityID = WorkoutActivityDiagnostics.fingerprint(activity.id)
                if activity.content.state != state {
                    let updateStarted = ContinuousClock.now
                    WorkoutActivityDiagnostics.record("activity.update.begin", ["activity": activityID, "state": String(describing: activity.activityState)], traces: traces)
                    await activity.update(content)
                    WorkoutActivityDiagnostics.record("activity.update.end", ["activity": activityID,
                        "elapsed_ms": WorkoutActivityDiagnostics.elapsed(updateStarted), "content_matches": String(activity.content.state == state)], traces: traces)
                } else {
                    WorkoutActivityDiagnostics.record("activity.update.skipped", ["activity": activityID, "reason": "unchanged_content"], traces: traces)
                }
                for extra in matches.dropFirst() {
                    WorkoutActivityDiagnostics.record("activity.end.begin", ["activity": WorkoutActivityDiagnostics.fingerprint(extra.id), "reason": "duplicate_activity"], traces: traces)
                    await extra.end(nil, dismissalPolicy: .immediate)
                    WorkoutActivityDiagnostics.record("activity.end.end", ["activity": WorkoutActivityDiagnostics.fingerprint(extra.id)], traces: traces)
                }
                store.liveActivityIssue = nil
            } else if UIApplication.shared.applicationState == .active {
                if ActivityAuthorizationInfo().areActivitiesEnabled {
                    do {
                        WorkoutActivityDiagnostics.record("activity.request.begin", traces: traces)
                        let activity = try Activity.request(attributes: attributes, content: content, pushType: nil)
                        WorkoutActivityDiagnostics.record("activity.request.end", ["activity": WorkoutActivityDiagnostics.fingerprint(activity.id)], traces: traces)
                        store.liveActivityIssue = nil
                    } catch {
                        WorkoutActivityDiagnostics.record("activity.request.failed", WorkoutActivityDiagnostics.errorFields(error), traces: traces, failure: true)
                        store.liveActivityIssue = "实时活动暂未启动，回到 App 后会重试。"
                    }
                } else {
                    WorkoutActivityDiagnostics.record("activity.request.skipped", ["reason": "activities_disabled"], traces: traces)
                    store.liveActivityIssue = "实时活动未开启，可在系统设置中允许 openGym 的实时活动。"
                }
            } else {
                WorkoutActivityDiagnostics.record("activity.request.skipped", ["reason": "no_matching_activity_in_background"], traces: traces)
            }
        } else {
            WorkoutActivityDiagnostics.record("activity.reconcile.skipped", ["reason": "no_content"], traces: traces)
            store.liveActivityIssue = nil
        }
    }
}
