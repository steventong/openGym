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

/// Persist the start of the current set across refreshes and app relaunches.
enum TrainingSetClock {
    static func identity(_ raw: [String: Any]) -> String? {
        guard raw["nativeRest"] == nil,
              let entries = raw["entries"] as? [[String: Any]], !entries.isEmpty else { return nil }
        let entryIndex = min(max(0, raw["cur"] as? Int ?? 0), entries.count - 1)
        let entry = entries[entryIndex]
        guard let rows = entry["sets"] as? [[String: Any]],
              let index = rows.firstIndex(where: { $0["done"] as? Bool != true }) else { return nil }
        let row = rows[index]
        let sides = row["sides"] as? [String: [String: Any]]
        let side = sides.map { $0["L"]?["done"] as? Bool == true ? "R" : "L" } ?? "both"
        return "\(entry["nativeViewID"] as? String ?? String(entryIndex))|\(row["nativeViewID"] as? String ?? String(index))|\(side)"
    }

    static func update(_ raw: inout [String: Any], previous: [String: Any], now: Date) {
        guard identity(raw) != identity(previous) else { return }
        if identity(raw) != nil {
            let explicitStart = raw["nativeSetStartedAt"] as? Double
            if explicitStart == nil || explicitStart == previous["nativeSetStartedAt"] as? Double {
                raw["nativeSetStartedAt"] = now.timeIntervalSince1970
            }
        }
        else { raw.removeValue(forKey: "nativeSetStartedAt") }
    }

    static func minutesSeconds(_ interval: TimeInterval, roundUp: Bool = false) -> String {
        let seconds = max(0, Int(roundUp ? ceil(interval) : floor(interval)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
