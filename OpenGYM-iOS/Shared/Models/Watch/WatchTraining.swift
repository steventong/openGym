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
    var message = String(localized: "START_A_WORKOUT_ON_PHONE", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
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
    func primaryAction(commandState: WatchCommandState) -> WatchTrainingAction {
        switch commandState {
        case .sending: return .sending
        case .awaitingConfirmation: return .retry
        case .idle: break
        }
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

enum WatchTrainingAction: Equatable {
    case sending, retry, endRest, complete, next, finished
    var title: String {
        String(localized: String.LocalizationValue(titleKey), bundle: AppLanguage.bundle, locale: AppLanguage.locale)
    }
    var titleKey: String {
        switch self {
        case .sending: "CONFIRMING"
        case .retry: "RETRY_CONFIRMATION"
        case .endRest: "FINISH"
        case .complete: "COMPLETE"
        case .next: "NEXT_EXERCISE"
        case .finished: "WORKOUT_DONE"
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
