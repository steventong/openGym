import Foundation

/// 保存训练后手机上展示的 Apple 健康写入进度，由健康账本里的请求和回执派生，不单独存储。
enum WorkoutHealthReceipt: Equatable {
    /// 结束请求已发出，手表还没有确认写入。
    case waiting
    case saved(activeCalories: Double?, message: String?)
    case failed(message: String?)

    /// 只有已结束的请求才有保存进度；结束之前留下的失败回执（如采集中断）已经过时，仍算等待。
    init?(request: HealthWorkoutRequest?, report: HealthWorkoutReport?) {
        guard let request, request.phase == .finished, let end = request.end else { return nil }
        switch report {
        case let report? where report.state == .saved:
            self = .saved(activeCalories: report.activeCalories, message: report.message)
        case let report? where report.state == .failed && report.updatedAt >= end:
            self = .failed(message: report.message)
        default:
            self = .waiting
        }
    }
}
