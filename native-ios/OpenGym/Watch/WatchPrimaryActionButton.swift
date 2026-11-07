import SwiftUI

struct WatchPrimaryActionButton: View {
    let store: WatchRemoteStore
    let tint: Color

    var body: some View {
        let action = store.primaryAction()
        TrainingActionControl(title: action.title, symbol: action.symbol, timing: store.snapshot.actionTiming,
            disabled: store.isDisabled(action, includeProtection: false), tint: tint,
            quietReady: action == .complete, setStartedAt: store.snapshot.setStartedAt) { label in
                Button { store.performPrimaryAction() } label: { label }
            }.accessibilityIdentifier("watch-primary-action")
    }
}
