import Foundation

/// 主按钮的文字与图标，写明点下去作用于哪一组、哪个动作；手表和实时活动共用这一份规则。
/// 组号与“第 N/总数 组”标签一致，动作序号从 1 开始。
enum TrainingActionTitle {
    /// “完成第 N 组”。
    static func complete(set: Int?, language: String) -> (title: String, symbol: String) {
        (set.map { numbered("COMPLETE_SET_NUMBER", $0, language) } ?? text("COMPLETE", language), "checkmark")
    }

    /// 结束休息：组间休息与换动作前的准备都写“开始第 N 组”；
    /// 没有下一组（如动作做完后手动计时）时，组间休息写“继续训练”，准备写“开始”。
    static func endRest(_ phase: TrainingActionStatus.RestPhase, nextSet: Int?, language: String) -> (title: String, symbol: String) {
        if let nextSet { return (numbered("START_SET_NUMBER", nextSet, language), "play.fill") }
        return (text(phase == .exercisePrep ? "START" : "CONTINUE_WORKOUT", language), "play.fill")
    }

    /// 当前动作做完、尚未切换时，跳到“第 N 个动作”。
    static func next(exercise: Int?, language: String) -> (title: String, symbol: String) {
        (exercise.map { numbered("EXERCISE_NUMBER", $0, language) } ?? text("NEXT_EXERCISE", language), "arrow.right")
    }

    static func text(_ key: String, _ language: String) -> String {
        String(localized: String.LocalizationValue(key), bundle: AppLanguage.bundle(for: language), locale: AppLanguage.locale(for: language))
    }

    private static func numbered(_ key: String, _ number: Int, _ language: String) -> String {
        String(format: text(key, language), locale: AppLanguage.locale(for: language), String(describing: number))
    }
}
