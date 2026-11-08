import Foundation

extension WorkoutActivityAttributes.ContentState {
    var trainingActionCommand: String? { restEnd == nil ? command : restCommand }

    /// 系统到期仅解除展示副本的保护，不修改原载荷或执行层的期限。
    func trainingContent(systemDeadlinePassed: Bool = false) -> TrainingContentData {
        let language = language ?? AppLanguage.language
        let locale = AppLanguage.locale(for: language)
        let bundle = AppLanguage.bundle(for: language)
        let status: TrainingActionStatus?
        if let restEnd {
            status = .rest(endsAt: restEnd)
        } else if setWeight != nil || setStartedAt != nil || command != nil {
            status = .workout(startedAt: setStartedAt)
        } else {
            status = nil
        }

        let action: TrainingContentData.Action?
        if let status {
            let title: String
            let symbol: String
            switch status {
            case .rest:
                title = String(localized: "FINISH", bundle: bundle, locale: locale)
                symbol = "forward.end.fill"
            case .workout:
                title = commandTitle
                symbol = "checkmark"
            }
            action = .init(title: title, symbol: symbol, status: status,
                disabled: busyTitle != nil || trainingActionCommand == nil,
                readyAt: systemDeadlinePassed ? nil : actionReadyAt, hint: message)
        } else {
            action = nil
        }

        return TrainingContentData(
            exercise: exercise.isEmpty ? String(localized: "READY_TO_START", bundle: bundle, locale: locale) : exercise,
            position: position,
            summary: .init(weight: setWeight ?? detail,
                detail: setWeight == nil ? "" : (setDetail ?? ""), label: setLabel),
            action: action, locale: locale)
    }
}
