import AppIntents

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
        let store = WorkoutActivityRuntime.store
        let issue = store.performActivityCommand(command)
        await store.liveActivity?.flush(actionMessage: issue)
        #endif
        return .result()
    }
}
