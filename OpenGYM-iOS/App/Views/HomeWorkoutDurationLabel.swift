import SwiftUI

struct HomeWorkoutDurationLabel: View {
    let start: Date

    var body: some View {
        // Reserve a stable trailing slot so ticking digits never move the title.
        Text(verbatim: "00:00:00").hidden()
            .overlay(alignment: .trailing) {
                TimelineView(.periodic(from: start, by: 1)) { context in
                    let elapsed = max(0, Int(context.date.timeIntervalSince(start)))
                    let duration = Duration.seconds(elapsed).formatted(.time(pattern: .hourMinuteSecond))
                    Text(duration)
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .accessibilityLabel("SESSION_LENGTH")
                        .accessibilityValue(duration)
                }
            }
            .font(.system(size: 12, weight: .medium).monospacedDigit())
            .fixedSize()
            .accessibilityIdentifier("home-workout-duration")
    }
}
