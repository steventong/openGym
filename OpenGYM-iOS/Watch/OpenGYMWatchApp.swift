import SwiftUI

@main struct OpenGYMWatchApp: App {
    
    @WKApplicationDelegateAdaptor(WatchRemoteDelegate.self)
    private var delegate
    
    @Environment(\.scenePhase)
    private var scenePhase
    
    var body: some Scene {
        WindowGroup {
            WatchRootView(store: delegate.store)
                .environment(\.locale, AppLanguage.locale)
                .onChange(of: scenePhase, initial: true) { _, phase in
                    delegate.store.setForegroundActive(phase == .active)
                }
        }
    }
}
