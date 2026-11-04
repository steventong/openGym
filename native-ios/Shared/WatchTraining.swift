import Foundation

/// Small, versioned messages. The watch never receives credentials or the account's history.
struct WatchTrainingSnapshot: Codable, Equatable {
    var language: String? = nil
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
    var message = L10n.text("START_A_WORKOUT_ON_IPHONE" /* 在 iPhone 开始训练 */)
    var acknowledged: [String] = []
    var actionReadyAt: Date? = nil
    var actionTiming: TrainingActionTiming { .init(restEnd: restEnd, readyAt: actionReadyAt) }

    var remainingRest: TimeInterval { max(0, restEnd?.timeIntervalSinceNow ?? 0) }
    var restReminderKey: String? {
        guard let sessionID, let restEnd else { return nil }
        return "\(account)|\(sessionID)|\(restEnd.timeIntervalSince1970)"
    }
    func isResting(at date: Date = Date()) -> Bool { restEnd.map { $0 > date } ?? false }
    func primaryAction(reachable: Bool, reconnecting: Bool, hasPending: Bool, sending: Bool, at date: Date = Date()) -> WatchTrainingAction {
        if !reachable && !reconnecting { return .connect }
        if hasPending { return sending ? .sending : .retry }
        if actionTiming.isRestAction { return .endRest }
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

/// Foreground feedback has its own deadline; system notification delivery is only a fallback.
struct WatchForegroundRestReminder {
    private(set) var key: String?
    private(set) var deadline: Date?
    private(set) var didAlert = false
    private var armed = false

    mutating func update(_ snapshot: WatchTrainingSnapshot, active: Bool, now: Date) -> Date? {
        if key != snapshot.restReminderKey {
            key = snapshot.restReminderKey
            deadline = key == nil ? nil : snapshot.restEnd
            armed = false
            didAlert = false
        }
        if !active {
            armed = false
        } else if !didAlert, let deadline, deadline > now {
            armed = true
        }
        // Keep an already armed deadline across a same-rest refresh at expiry, but never
        // replay an expired rest when opening the app or returning from the background.
        return armed && !didAlert ? deadline : nil
    }

    mutating func consume(key: String, now: Date) -> Bool {
        guard self.key == key, armed, !didAlert, let deadline, now >= deadline else { return false }
        didAlert = true
        armed = false
        return true
    }
}
enum WatchTrainingAction: Equatable {
    case connect, sending, retry, endRest, complete, next, finished
    var title: String {
        switch self {
        case .connect: L10n.text("CONNECT_IPHONE" /* 连接 iPhone */)
        case .sending: L10n.text("CONFIRMING" /* 正在确认 */)
        case .retry: L10n.text("RETRY_CONFIRMATION" /* 重试确认 */)
        case .endRest: L10n.text("END_REST" /* 结束休息 */)
        case .complete: L10n.text("COMPLETE_SET" /* 完成本组 */)
        case .next: L10n.text("NEXT_EXERCISE" /* 下一个动作 */)
        case .finished: L10n.text("WORKOUT_DONE" /* 训练已完成 */)
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
