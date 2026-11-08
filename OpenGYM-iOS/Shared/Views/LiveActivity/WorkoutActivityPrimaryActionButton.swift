import SwiftUI
import AppIntents

/// 实时活动保留系统 Intent 交互；没有命令时仅显示同一份禁用内容。
struct WorkoutActivityPrimaryActionButton: View {
    let action: TrainingContentData.Action?
    let command: String?

    var body: some View {
        if let action {
            if let command {
                Button(intent: WorkoutActivityIntent(command: command)) {
                    TrainingActionLabel(title: action.title, symbol: action.symbol,
                        status: action.status, disabled: action.disabled, tint: TrainingDisplayStyle.green)
                }
            } else {
                TrainingActionLabel(title: action.title, symbol: action.symbol,
                    status: action.status, disabled: action.disabled, tint: TrainingDisplayStyle.green)
            }
        }
    }
}
