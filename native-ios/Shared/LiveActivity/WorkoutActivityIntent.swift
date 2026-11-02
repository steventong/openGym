import AppIntents
import OSLog

/// The same intent metadata is compiled into the widget and the app. LiveActivityIntent
/// makes the system execute the action in the app process, using its account-scoped store.
struct WorkoutActivityIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "更新当前训练"
    static var isDiscoverable = false
    static var openAppWhenRun = false

    @Parameter(title: "训练操作") var command: String

    init() {}
    init(command: String) { self.command = command }

    @MainActor func perform() async throws -> some IntentResult {
        #if !WORKOUT_WIDGET
        await WorkoutActivityDiagnostics.$traceID.withValue(UUID().uuidString) {
            let started = ContinuousClock.now
            WorkoutActivityDiagnostics.record("intent.received", WorkoutActivityDiagnostics.environment())
            defer {
                WorkoutActivityDiagnostics.record("intent.finished", ["elapsed_ms": WorkoutActivityDiagnostics.elapsed(started),
                    "cancelled": String(Task.isCancelled)])
            }
            WorkoutActivityDiagnostics.record("runtime.access.begin")
            let store = WorkoutActivityRuntime.store
            WorkoutActivityDiagnostics.record("runtime.access.end", WorkoutActivityDiagnostics.state(store))
            let commandStarted = ContinuousClock.now
            let issue = store.performActivityCommand(command)
            WorkoutActivityDiagnostics.record("intent.command.end", ["accepted": String(issue == nil),
                "elapsed_ms": WorkoutActivityDiagnostics.elapsed(commandStarted)], failure: issue != nil)
            let remindersStarted = ContinuousClock.now
            WorkoutActivityDiagnostics.record("intent.reminders.begin", ["available": String(store.restNotifications != nil)])
            await store.restNotifications?.flush()
            WorkoutActivityDiagnostics.record("intent.reminders.end", ["elapsed_ms": WorkoutActivityDiagnostics.elapsed(remindersStarted)])
            let refreshStarted = ContinuousClock.now
            WorkoutActivityDiagnostics.record("intent.refresh.begin", ["available": String(store.liveActivity != nil)])
            await store.liveActivity?.flush(actionMessage: issue)
            WorkoutActivityDiagnostics.record("intent.refresh.end", ["elapsed_ms": WorkoutActivityDiagnostics.elapsed(refreshStarted)])
        }
        #else
        Logger(subsystem: "me.itwl.opengym", category: "LiveActivity")
            .error("LA event=intent.unexpected_widget_process; command was not executed")
        #endif
        return .result()
    }
}
