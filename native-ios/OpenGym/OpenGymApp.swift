import SwiftUI

@main struct OpenGymApp: App {
    @UIApplicationDelegateAdaptor(OpenGymAppDelegate.self) private var delegate
    private var store: GymStore { delegate.store }
    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(\.locale, AppLanguage.locale)
                .preferredColorScheme(.dark)
                .tint(GymTheme.green)
                .task { await store.boot() }
        }
    }
}
