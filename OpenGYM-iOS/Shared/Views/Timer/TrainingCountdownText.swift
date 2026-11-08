import SwiftUI

/// Live Activities use WidgetKit's native timer text. App and Watch seconds
/// tick only this leaf view, without rebuilding their enclosing control.
struct TrainingCountdownText: View {
    let end: Date
    var pausedRemaining: TimeInterval? = nil
    var minimumIntegerDigits = 1
    var suffix = "S"
    var presentation: TrainingCountdownPresentation = .seconds

    var body: some View {
        Group {
            if let pausedRemaining {
                Text(TrainingCountdownSecondsStyle(end: end, minimumIntegerDigits: minimumIntegerDigits, suffix: suffix)
                    .formattedSeconds(pausedRemaining))
            } else if presentation == .systemTimer {
                Text(timerInterval: Self.timerInterval(endingAt: end), countsDown: true, showsHours: false)
            } else {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(TrainingCountdownSecondsStyle(end: end,
                        minimumIntegerDigits: minimumIntegerDigits, suffix: suffix).format(context.date))
                }
            }
        }.monospacedDigit().contentTransition(.numericText(countsDown: true))
    }

    static func timerInterval(endingAt end: Date, now: Date = Date()) -> ClosedRange<Date> {
        now...max(now, end)
    }
}
