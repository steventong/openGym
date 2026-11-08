import Foundation

/// 训练操作只有训练和组间休息两种状态；训练尚未开始计时时显示 00:00。
enum TrainingActionStatus: Equatable {
    case workout(startedAt: Date?)
    case rest(endsAt: Date)

    var titleKey: String {
        switch self {
        case .workout: return "TRAINING_STATUS_WORKOUT"
        case .rest: return "TRAINING_STATUS_REST"
        }
    }
}
