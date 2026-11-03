import SwiftUI
import UserNotifications
import HealthKitUI
@main struct OpenGymApp: App {
    @UIApplicationDelegateAdaptor(OpenGymAppDelegate.self) private var delegate
    private var store: GymStore { delegate.store }
    var body: some Scene {
        WindowGroup {
            RootView().environment(store).preferredColorScheme(.dark).tint(GymTheme.green)
                .task { await store.boot() }
        }
    }
}
@MainActor final class OpenGymAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    let store = WorkoutActivityRuntime.store
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        WorkoutActivityDiagnostics.record("app.launched", WorkoutActivityDiagnostics.environment())
        UNUserNotificationCenter.current().delegate = self
        return true
    }
    func applicationProtectedDataDidBecomeAvailable(_ application: UIApplication) {
        WorkoutActivityDiagnostics.record("app.protected_data.available", WorkoutActivityDiagnostics.environment())
    }
    func applicationProtectedDataWillBecomeUnavailable(_ application: UIApplication) {
        WorkoutActivityDiagnostics.record("app.protected_data.unavailable", WorkoutActivityDiagnostics.environment())
    }
    func applicationWillTerminate(_ application: UIApplication) {
        WorkoutActivityDiagnostics.record("app.terminating", WorkoutActivityDiagnostics.environment())
    }
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        if #available(iOS 26.0, *), options.shouldHandleActiveWorkoutRecovery { store.workoutHealth.retry() }
        return configuration
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        if notification.request.content.userInfo["openGymWorkout"] as? Bool == true {
            Task { @MainActor in WorkoutActivityDiagnostics.record("reminder.foreground_delivery") }
        }
        completionHandler([.banner, .list, .sound])
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        Task { @MainActor in
            if response.notification.request.content.userInfo["openGymWorkout"] as? Bool == true {
                WorkoutActivityDiagnostics.record("reminder.opened")
                self.store.selectedTab = 2
            }
            completionHandler()
        }
    }
}
struct RootView: View {
    @Environment(GymStore.self) private var store
    var body: some View {
        @Bindable var store = store
        // Stable selection values also serve notifications, Live Activities and workout actions.
        TabView(selection: $store.selectedTab) {
            Tab(value: 0) { HomeView() } label: {
                Label("首页", systemImage: "house").accessibilityIdentifier("tab-0")
            }
            Tab(value: 1) { PlanView() } label: {
                Label("计划", systemImage: "calendar").accessibilityIdentifier("tab-1")
            }
            Tab(value: 2) { WorkoutView() } label: {
                Label(store.draft == nil ? "开始" : "训练中",
                      systemImage: store.draft == nil ? "play.fill" : "figure.strengthtraining.traditional")
                    .accessibilityIdentifier("tab-workout")
            }.badge(store.localSaveError == nil ? nil : Text("!"))
            Tab(value: 3) { StatsView() } label: {
                Label("统计", systemImage: "chart.bar.xaxis").accessibilityIdentifier("tab-3")
            }
            Tab(value: 4) { LibraryView() } label: {
                Label("动作库", systemImage: "dumbbell").accessibilityIdentifier("tab-4")
            }
        }.id(store.coachIdentity)
            .background(GymTheme.background).foregroundStyle(.white)
            .background { LocalSaveStatus() }
            .sheet(isPresented:$store.showSettings) { SettingsView() }
            .sheet(item:$store.selectedExercise) { ExerciseDetail(exercise:$0) }
            .alert("openGym",isPresented:Binding(get:{store.error != nil},set:{if !$0 { store.error = nil }})) {
                Button("知道了",role:.cancel) { store.error = nil }
            } message: { Text(store.error ?? "") }
            .background { AppLifecycleObserver() }
            .onOpenURL { url in if url.scheme == "opengym", url.host == "workout" {
                WorkoutActivityDiagnostics.record("app.open_workout_link")
                store.selectedTab = 2
            } }
    }
}

private struct LocalSaveStatus: View {
    @Environment(GymStore.self) private var store
    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .onChange(of: store.localSaveError, initial: true) { _, issue in
                if let issue, store.error == nil { store.error = issue }
            }
    }
}

/// These observations must not invalidate the tab container or an open menu.
private struct AppLifecycleObserver: View {
    @Environment(GymStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .onChange(of:store.draft?.id,initial:true) { _,_ in updateWake() }
            .onChange(of:store.state["keepAwake"] as? Bool) { _,_ in updateWake() }
            .onChange(of:scenePhase, initial:true) { _, phase in
                WorkoutActivityDiagnostics.record("app.scene.changed", ["phase": String(describing: phase)])
                updateWake()
                if phase == .active {
                    store.restNotifications?.publish()
                    store.liveActivity?.publish()
                    store.workoutHealth.retry()
                }
            }

    }
    private func updateWake() { UIApplication.shared.isIdleTimerDisabled = scenePhase == .active && store.draft != nil && store.state["keepAwake"] as? Bool != false }
}

struct LocalSaveIssueIndicator: View {
    @Environment(GymStore.self) private var store
    var body: some View {
        if let issue = store.localSaveError {
            Button { store.error = issue } label: {
                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
                    .frame(width: 28, height: 28).background(.black, in: Circle())
            }.buttonStyle(.plain).accessibilityLabel("本机保存失败，查看详情")
                .accessibilityIdentifier("local-save-error")
        }
    }
}
