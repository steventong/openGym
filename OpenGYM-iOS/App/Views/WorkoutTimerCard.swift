import SwiftUI

struct WorkoutTimerCard: View {
    @Environment(GymStore.self) private var store
    let timer: [String: Any]

    var body: some View {
        let paused = timer["paused"] as? Bool == true
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(LocalizedStringKey(paused ? "TIMER_PAUSED" : "EXERCISE_TIMER"), systemImage: "stopwatch")
                Spacer()
                TrainingCountdownText(end: Date(timeIntervalSince1970: number(timer["end"])),
                    pausedRemaining: paused ? number(timer["remaining"]) : nil)
                    .font(.title2.monospacedDigit()).frame(width: 84, alignment: .trailing)
            }
            HStack {
                Button(LocalizedStringKey(paused ? "RESUME" : "PAUSE")) { store.pauseWorkTimer() }
                Spacer()
                Button("FINISH_EARLY_A") { store.finishWorkTimer() }
                Button("CANCEL", role: .cancel) { store.finishWorkTimer(cancel: true) }
            }.font(.subheadline)
        }.foregroundStyle(GymTheme.green).accessibilityIdentifier("work-timer")
    }
}
