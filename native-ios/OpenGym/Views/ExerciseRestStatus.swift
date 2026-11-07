import SwiftUI

struct ExerciseRestStatus: View {
    let end: Date

    var body: some View {
        // Keep deadline updates local, so they cannot disturb open editor menus.
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(spacing: 4) {
                HStack(spacing: 2) {
                    Image(systemName: "timer").accessibilityHidden(true)
                    Text("REST_BETWEEN_SETS")
                }
                Group {
                    if context.date >= end {
                        Text("ENDED")
                    } else {
                        Text(TrainingCountdownSecondsStyle(end: end).format(context.date))
                    }
                }.fontWeight(.semibold).monospacedDigit()
            }.font(.caption).foregroundStyle(GymTheme.green)
                .lineLimit(1).minimumScaleFactor(0.6)
                .accessibilityElement(children: .combine)
        }
    }
}
