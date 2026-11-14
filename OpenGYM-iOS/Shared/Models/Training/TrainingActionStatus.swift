import Foundation

/// 训练操作只有训练和休息两种状态；训练尚未开始计时时显示 00:00。
/// 休息分组间休息和换动作前的准备，两者倒计时相同，只有标题和按钮文字不同。
enum TrainingActionStatus: Equatable {
    case workout(startedAt: Date?)
    case rest(endsAt: Date, phase: RestPhase = .betweenSets)

    /// 休息倒计时的用途；写入草稿的 `nativeRest.phase`，并随手表快照和 Live Activity 传递。
    enum RestPhase: String, Codable {
        /// 同一动作两组之间的休息。
        case betweenSets
        /// 上一个动作全部完成后，开始下一个动作前的准备。
        case exercisePrep
    }

    var titleKey: String {
        switch self {
        case .workout: return "TRAINING_STATUS_WORKOUT"
        case .rest(_, .betweenSets): return "TRAINING_STATUS_REST"
        case .rest(_, .exercisePrep): return "TRAINING_STATUS_EXERCISE_PREP"
        }
    }
}
