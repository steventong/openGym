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
    var restSet: WatchTrainingSet?
    var displayedSet: WatchTrainingSet? { restEnd != nil ? (restSet ?? nextSet) : nextSet }
    var setCompletionLabel: String? {
        guard restEnd != nil, restSet != nil else { return nil }
        return String(localized: "COMPLETED", bundle: AppLanguage.bundle(for: language ?? AppLanguage.language), locale: AppLanguage.locale(for: language ?? AppLanguage.language))
    }
    var nextEntry: Int?
    var restEnd: Date?
    var restEntry: Int?
    var restExercise = ""
    var message = String(localized: "START_A_WORKOUT_ON_IPHONE", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
    var acknowledged: [String] = []
    var setStartedAt: Date? = nil
    var actionReadyAt: Date? = nil
    var actionTiming: TrainingActionTiming { .init(restEnd: restEnd, readyAt: actionReadyAt) }

    var restNotificationTitle: String {
        String(localized: "REST_NOTIFICATION_TITLE", bundle: AppLanguage.bundle(for: language ?? AppLanguage.language), locale: AppLanguage.locale(for: language ?? AppLanguage.language))
    }
    var restNotificationBody: String {
        let name = restExercise.isEmpty ? exercise : restExercise
        if let nextSet, restEntry == nil || nextSet.entry == restEntry {
            return String(format: String(localized: "REST_NOTIFICATION_NEXT_SET", bundle: AppLanguage.bundle(for: language ?? AppLanguage.language), locale: AppLanguage.locale(for: language ?? AppLanguage.language)), locale: AppLanguage.locale(for: language ?? AppLanguage.language), String(describing: name), String(describing: nextSet.label))
        }
        return String(format: String(localized: "COUNT_READY_FOR_YOUR_NEXT_SET", bundle: AppLanguage.bundle(for: language ?? AppLanguage.language), locale: AppLanguage.locale(for: language ?? AppLanguage.language)), locale: AppLanguage.locale(for: language ?? AppLanguage.language), String(describing: name))
    }

    var remainingRest: TimeInterval { max(0, restEnd?.timeIntervalSinceNow ?? 0) }
    var restReminderKey: String? {
        guard let sessionID, let restEnd else { return nil }
        return "\(account)|\(sessionID)|\(restEnd.timeIntervalSince1970)"
    }
    func isResting(at date: Date = Date()) -> Bool { restEnd.map { $0 > date } ?? false }
    func primaryAction(reachable: Bool, reconnecting: Bool, hasPending: Bool, sending: Bool, at date: Date = Date()) -> WatchTrainingAction {
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

/// Direct feedback has its own deadline; an active workout also permits background haptics.
struct WatchForegroundRestReminder {
    private(set) var key: String?
    private(set) var deadline: Date?
    private(set) var didAlert = false
    private var armed = false

    mutating func update(_ snapshot: WatchTrainingSnapshot, active: Bool, workoutRunning: Bool = false, now: Date) -> Date? {
        if key != snapshot.restReminderKey {
            key = snapshot.restReminderKey
            deadline = key == nil ? nil : snapshot.restEnd
            armed = false
            didAlert = false
        }
        if !active && !workoutRunning {
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
    case sending, retry, endRest, complete, next, finished
    var title: String {
        switch self {
        case .sending: String(localized: "CONFIRMING", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
        case .retry: String(localized: "RETRY_CONFIRMATION", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
        case .endRest: String(localized: "END_REST", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
        case .complete: String(localized: "COMPLETE_SET", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
        case .next: String(localized: "NEXT_EXERCISE", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
        case .finished: String(localized: "WORKOUT_DONE", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
        }
    }
    var symbol: String {
        switch self {
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
