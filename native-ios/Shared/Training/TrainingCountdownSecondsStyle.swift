import Foundation

// Static formatting only (paused timers and the App/Watch local timeline).
// Never pass this app-defined type to Text's TimeDataSource initializer.
struct TrainingCountdownSecondsStyle {
    var end: Date
    var minimumIntegerDigits = 1
    var suffix = "S"
    func formattedSeconds(_ remaining: TimeInterval) -> String {
        let digits = String(max(0, Int(ceil(remaining))))
        return String(repeating: "0", count: max(0, minimumIntegerDigits - digits.count)) + digits + suffix
    }
    func format(_ value: Date) -> String { formattedSeconds(end.timeIntervalSince(value)) }
    func discreteInput(after input: Date) -> Date? {
        let seconds = Int(ceil(end.timeIntervalSince(input)))
        return seconds > 0 ? end.addingTimeInterval(-Double(seconds - 1)) : nil
    }
    func discreteInput(before input: Date) -> Date? {
        if input > end { return end }
        return end.addingTimeInterval(-floor(end.timeIntervalSince(input)) - 0.000001)
    }
}
