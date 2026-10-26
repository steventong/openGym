import SwiftUI
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
@MainActor final class OpenGymAppDelegate: NSObject, UIApplicationDelegate {
    let store = GymStore()
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        store.prepareOfflineLaunch()
        return true
    }
}
struct RootView: View {
    @Environment(GymStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        @Bindable var store = store
        VStack(spacing:0) {
            Group {
                switch store.selectedTab {
                case 0: HomeView()
                case 1: PlanView()
                case 2: WorkoutView()
                case 3: StatsView()
                default: LibraryView()
                }
            }.frame(maxWidth:.infinity,maxHeight:.infinity)
            if let issue = store.localSaveError { Text(issue).font(.caption).foregroundStyle(.orange).padding(8).accessibilityIdentifier("local-save-error") }
            tabBar
        }.background(GymTheme.background).foregroundStyle(.white)
            .sheet(isPresented:$store.showSettings) { SettingsView() }
            .sheet(item:$store.selectedExercise) { ExerciseDetail(exercise:$0) }
            .alert("openGym",isPresented:Binding(get:{store.error != nil},set:{if !$0 { store.error = nil }})) {
                Button("知道了",role:.cancel) { store.error = nil }
            } message: { Text(store.error ?? "") }
            .onChange(of:scenePhase) { _, phase in if phase == .active { Task { await store.refresh(); await store.healthSync.resume() } } }
            .task { while !Task.isCancelled { try? await Task.sleep(for:.seconds(30)); if !Task.isCancelled { await store.refresh(); await store.healthSync.resume() } } }
    }
    private var tabBar: some View {
        HStack(alignment:.bottom,spacing:0) {
            tab(0,"首页","house")
            tab(1,"计划","calendar")
            Button { store.selectedTab = 2 } label: {
                VStack(spacing:5) {
                    Image(systemName:store.draft == nil ? "play.fill" : "pause.fill").font(.system(size:19)).foregroundStyle(.black)
                        .frame(width:54,height:54).background(GymTheme.green,in:Circle()).shadow(color:GymTheme.green.opacity(0.17),radius:14)
                    Text(store.draft == nil ? "开始" : "训练中").font(.system(size:10,weight:.medium)).foregroundStyle(GymTheme.green)
                }.frame(maxWidth:.infinity)
            }.accessibilityIdentifier("tab-workout")
            tab(3,"统计","chart.bar.xaxis")
            tab(4,"动作库","dumbbell")
        }.padding(.horizontal,8).padding(.top,10).padding(.bottom,5).background(Color(white:0.06))
    }
    private func tab(_ id: Int, _ name: String, _ icon: String) -> some View {
        Button { store.selectedTab = id } label: {
            VStack(spacing:7) { Image(systemName:icon).font(.system(size:20)); Text(name).font(.system(size:10,weight:.medium)) }
                .foregroundStyle(store.selectedTab == id ? GymTheme.green : GymTheme.muted).frame(maxWidth:.infinity).frame(height:53)
        }.accessibilityIdentifier("tab-\(id)")
    }
}
