import Foundation

extension WatchTrainingSnapshot {
    /// 只投影展示值；当前操作与基础禁用由手表的命令状态机决定。
    func trainingContent(action: WatchTrainingAction, disabled: Bool) -> TrainingContentData {
        let language = language ?? AppLanguage.language
        let locale = AppLanguage.locale(for: language)
        let status: TrainingActionStatus
        if let restEnd {
            status = .rest(endsAt: restEnd)
        } else {
            status = .workout(startedAt: setStartedAt)
        }
        return TrainingContentData(exercise: exercise, position: exercisePosition,
            summary: displayedSet.map { .init(weight: $0.weight, detail: $0.detail, label: $0.label) },
            action: .init(title: String(localized: String.LocalizationValue(action.titleKey),
                bundle: AppLanguage.bundle(for: language), locale: locale),
                symbol: action.symbol, status: status, disabled: disabled, readyAt: actionReadyAt),
            locale: locale)
    }
}
