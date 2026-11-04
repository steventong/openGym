import Foundation

/// One persisted deadline for the text-button handoff on every device.
/// A completed rest remains an explicit action until the user ends it.
struct TrainingActionTiming: Equatable {
    static let protectionDuration: TimeInterval = 5
    var restEnd: Date?
    var readyAt: Date?

    var isRestAction: Bool { restEnd != nil }
    func isProtected(at date: Date) -> Bool { readyAt.map { date < $0 } ?? false }
    func protectionSeconds(at date: Date) -> Int {
        max(0, Int(ceil(readyAt?.timeIntervalSince(date) ?? 0)))
    }
    static func deadline(after date: Date) -> Date { date.addingTimeInterval(protectionDuration) }
}
