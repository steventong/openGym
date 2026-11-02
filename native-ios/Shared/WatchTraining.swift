import Foundation

/// Small, versioned messages. The watch never receives credentials or the account's history.
struct WatchTrainingSnapshot: Codable, Equatable {
    var version = 1
    var generatedAt = Date()
    var account = ""
    var sessionID: String?
    var revision = ""
    var exercise = ""
    var exercisePosition = ""
    var nextSet: WatchTrainingSet?
    var nextEntry: Int?
    var restEnd: Date?
    var restEntry: Int?
    var restExercise = ""
    var message = "在 iPhone 开始训练"
    var acknowledged: [String] = []

    var remainingRest: TimeInterval { max(0, restEnd?.timeIntervalSinceNow ?? 0) }
    func isResting(at date: Date = Date()) -> Bool { restEnd.map { $0 > date } ?? false }
    func primaryAction(reachable: Bool, reconnecting: Bool, hasPending: Bool, sending: Bool, at date: Date = Date()) -> WatchTrainingAction {
        if !reachable && !reconnecting { return .connect }
        if hasPending { return sending ? .sending : .retry }
        if isResting(at: date) { return .endRest }
        if nextSet != nil { return .complete }
        if nextEntry != nil { return .next }
        return .finished
    }
    var payload: [String: Any] { ["snapshot": (try? JSONEncoder().encode(self)) ?? Data()] }
    static func decode(_ payload: [String: Any]) -> Self? {
        guard let data = payload["snapshot"] as? Data,
              let value = try? JSONDecoder().decode(Self.self, from: data), value.version == 1 else { return nil }
        return value
    }
}
enum WatchTrainingAction: Equatable {
    case connect, sending, retry, endRest, complete, next, finished
    var title: String {
        switch self {
        case .connect: "连接 iPhone"
        case .sending: "正在确认…"
        case .retry: "重试确认"
        case .endRest: "结束休息"
        case .complete: "完成训练"
        case .next: "下一个动作"
        case .finished: "训练已完成"
        }
    }
    var symbol: String {
        switch self {
        case .connect: "iphone.and.arrow.forward"
        case .sending, .retry: "arrow.clockwise"
        case .endRest: "forward.end.fill"
        case .next: "arrow.right"
        case .complete, .finished: "checkmark"
        }
    }
}
struct WatchTrainingSet: Codable, Equatable, Identifiable {
    var entry: Int
    var index: Int
    var side: String?
    var label: String
    var weight: String
    var detail: String
    var blockedReason: String?
    var id: String { "\(entry):\(index):\(side ?? "both")" }
}
struct WatchTrainingCommand: Codable, Equatable {
    var version = 1
    var id = UUID().uuidString
    var account: String
    var sessionID: String
    var revision: String
    var action: String
    var entry: Int
    var index: Int?
    var side: String?
    // Live Activity completion can survive rest-only changes while its UI catches up.
    // Watch commands and older Live Activity payloads retain strict revision checks.
    var activityRevision: String? = nil
    var payload: [String: Any] { ["command": (try? JSONEncoder().encode(self)) ?? Data()] }
    static func decode(_ payload: [String: Any]) -> Self? {
        guard let data = payload["command"] as? Data,
              let value = try? JSONDecoder().decode(Self.self, from: data), value.version == 1 else { return nil }
        return value
    }
}
