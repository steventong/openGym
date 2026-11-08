import SwiftUI

struct TrainingExercisePagingHint: View {
    let name: String
    let previous: Bool
    let ready: Bool

    var body: some View {
        Text(verbatim: name)
            .font(.caption)
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .foregroundStyle(ready ? GymTheme.green : GymTheme.muted)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20).padding(.vertical, 8)
            .background(GymTheme.background)
            .accessibilityIdentifier(previous ? "previous-exercise-pull-hint" : "next-exercise-pull-hint")
            .allowsHitTesting(false)
    }
}
