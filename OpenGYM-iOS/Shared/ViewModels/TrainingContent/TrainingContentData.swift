import Foundation

/// 共享训练界面的展示值，不包含 Store、平台命令或视图。
struct TrainingContentData: Equatable {
    struct Summary: Equatable {
        var weight: String
        var detail: String
        var label: String
    }

    struct Action: Equatable {
        var title: String
        var symbol: String
        var status: TrainingActionStatus
        var disabled = false
        var readyAt: Date? = nil
        var hint = ""
    }

    var exercise: String
    var position: String
    var summary: Summary?
    var action: Action?
    var locale: Locale

    /// 在展示副本中合并保护期，不改变数据源或执行层的绝对截止时间。
    func evaluated(at date: Date) -> Self {
        var result = self
        if let action {
            result.action?.disabled = action.disabled || TrainingActionTiming(readyAt: action.readyAt).isProtected(at: date)
        }
        return result
    }
}
