import SwiftUI

/// Hosts one Button/Intent/Link; ownership of the action stays with its platform.
/// Only the protection deadline refreshes this container. Seconds update in Text.
struct TrainingActionControl<Content: View>: View {
    var title: String
    var symbol: String
    var timing: TrainingActionTiming
    var disabled = false
    var tint: Color = .green
    var scale: CGFloat = 1
    var quietReady = false
    var setStartedAt: Date? = nil
    var language: String? = nil
    // ActivityKit's stale date is the protection deadline. Its system-rendered
    // state must unlock the archived view even when Date() was evaluated earlier.
    // Command execution still checks the persisted absolute deadline.
    var systemDeadlinePassed = false
    @ViewBuilder var control: (TrainingActionLabel) -> Content
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var evaluatedAt = Date()

    var body: some View {
        let protected = !systemDeadlinePassed && timing.isProtected(at: max(evaluatedAt, Date()))
        let unavailable = disabled || protected
        control(TrainingActionLabel(title: title, symbol: symbol,
            protectionEnd: protected ? timing.readyAt : nil,
            disabled: unavailable, tint: tint, scale: scale,
            restEnd: timing.restEnd, quietReady: quietReady, setStartedAt: setStartedAt, language: language))
            .buttonStyle(.plain).disabled(unavailable)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: unavailable)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: title)
            #if !WORKOUT_WIDGET
            .task(id: timing.readyAt) {
                evaluatedAt = Date()
                guard let end = timing.readyAt, end > evaluatedAt else { return }
                do { try await Task.sleep(for: .seconds(max(0, end.timeIntervalSinceNow))) }
                catch { return }
                guard !Task.isCancelled else { return }
                evaluatedAt = Date()
            }
            .onChange(of: scenePhase) { _, phase in if phase == .active { evaluatedAt = Date() } }
            #endif
    }
}
