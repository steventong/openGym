import SwiftUI

/// 实时活动的空间适配，公共内容由同一个 TrainingContentView 绘制。
struct WorkoutActivityContent: View {
    let viewModel: TrainingViewModel
    let command: String?
    var island = false

    var body: some View {
        let content = viewModel.content
        TrainingContentView(content: content, layout: island ? .compactWithoutHeader : .compact,
            metrics: EmptyView(),
            primaryAction: WorkoutActivityPrimaryActionButton(action: content.action, command: command))
            .padding(EdgeInsets(top: island ? 0 : 10, leading: 12,
                bottom: TrainingDisplayStyle.actionGap + (island ? 6 : 0), trailing: 12))
    }
}
