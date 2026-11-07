import SwiftUI
import UIKit

/// These observations must not invalidate the tab container or an open menu.
struct AppLifecycleObserver: View {
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
                    store.restNotifications?.clearDelivered()
                    store.restNotifications?.publish()
                    store.liveActivity?.publish()
                    store.workoutHealth.retry()
                }
            }

    }
    private func updateWake() { UIApplication.shared.isIdleTimerDisabled = scenePhase == .active && store.draft != nil && store.state["keepAwake"] as? Bool != false }
}
