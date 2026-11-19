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
    /// 下一组；休息时也显示它，刚完成的组由按钮切到休息倒计时来确认。
    var nextSet: WatchTrainingSet?
    var nextEntry: Int?
    var restEnd: Date?
    var restEntry: Int?
    var restExercise = ""
    /// 旧版本快照没有该字段，解码为 nil 时按组间休息处理。
    var restPhase: TrainingActionStatus.RestPhase? = nil
    var message = String(localized: "START_A_WORKOUT_ON_PHONE", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
    var acknowledged: [String] = []
    var setStartedAt: Date? = nil
    var actionReadyAt: Date? = nil
    var restStartedAt: Date? = nil
    var autoEndRestEnabled = false
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
    /// 空白草稿仍等待手机添加动作；有动作且没有后续操作时才进入结束页。
    var isFinished: Bool {
        sessionID != nil && !exercise.isEmpty && primaryAction(commandState: .idle) == .finished
    }
    func primaryAction(commandState: WatchCommandState) -> WatchTrainingAction {
        switch commandState {
        case .sending: return .sending
        case .awaitingConfirmation: return .retry
        case .idle: break
        }
        if actionTiming.isRestAction { return .endRest(restPhase ?? .betweenSets) }
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
    case sending, retry, complete, next, finished
    /// 结束休息并开始下一组，组间休息和换动作前的准备都用它。
    case endRest(TrainingActionStatus.RestPhase)

    /// 按钮文字与图标：setNumber 是下一组的组号，exerciseNumber 是下一个动作的序号（从 1 开始）。
    func label(setNumber: Int?, exerciseNumber: Int?, language: String) -> (title: String, symbol: String) {
        switch self {
        case .sending: return (TrainingActionTitle.text("CONFIRMING", language), "arrow.clockwise")
        case .retry: return (TrainingActionTitle.text("RETRY_CONFIRMATION", language), "arrow.clockwise")
        case .complete: return TrainingActionTitle.complete(set: setNumber, language: language)
        case .endRest(let phase): return TrainingActionTitle.endRest(phase, nextSet: setNumber, language: language)
        case .next: return TrainingActionTitle.next(exercise: exerciseNumber, language: language)
        case .finished: return (TrainingActionTitle.text("WORKOUT_DONE", language), "checkmark")
        }
    }
}
struct WatchTrainingSet: Codable, Equatable, Identifiable {
    var entry: Int
    var index: Int
    /// 按钮上的组号，与 label 的“第 N/总数 组”一致（左右两侧算同一组）。
    var number: Int
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
    /// 仅 resumeFromMotion 使用；手机验证后作为下一组实际起点，不作为接收时间。
    var detectedStartedAt: Date? = nil
    var payload: [String: Any] { ["command": (try? JSONEncoder().encode(self)) ?? Data()] }
    static func decode(_ payload: [String: Any]) -> Self? {
        guard let data = payload["command"] as? Data,
              let value = try? JSONDecoder().decode(Self.self, from: data), value.version == 1 else { return nil }
        return value
    }
}
