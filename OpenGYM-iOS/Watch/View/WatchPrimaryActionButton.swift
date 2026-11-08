import SwiftUI

/// Watch 的实际点击适配；显示数据和可用性已由共同 ViewModel 准备。
struct WatchPrimaryActionButton: View {
    let action: TrainingContentData.Action?
    let perform: @MainActor () -> Void

    var body: some View {
        if let action {
            Button { perform() } label: {
                TrainingActionLabel(title: action.title, symbol: action.symbol,
                    status: action.status, disabled: action.disabled, tint: TrainingDisplayStyle.green)
            }
            .accessibilityIdentifier("watch-primary-action")
        }
    }
}
