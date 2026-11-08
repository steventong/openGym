import SwiftUI

/// Watch 只绑定展示模型、健康数据和操作，不再自行组装公共训练内容。
struct WatchTrainingView: View {
    let viewModel: TrainingViewModel
    let healthReport: HealthWorkoutReport?
    let onPrimaryAction: @MainActor () -> Void

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        let content = viewModel.content
        TrainingContentView(content: content, layout: .expanded,
            metrics: WatchTrainingMetricsView(report: healthReport),
            primaryAction: WatchPrimaryActionButton(action: content.action, perform: onPrimaryAction))
            .padding(.horizontal, 5)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .task(id: viewModel.protectionDeadline) {
                await viewModel.refreshAfterProtectionEnds()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { viewModel.refresh() }
            }
    }
}

// mock 数据只在预览入口注入，不创建真实 Store、不连接手机。
#Preview("训练中") {
    let content = TrainingContentData(exercise: "哑铃飞鸟", position: "第 1/3 个动作",
        summary: .init(weight: "5 kg", detail: "12 次", label: "第 1/3 组"),
        action: .init(title: "完成", symbol: "checkmark", status: .workout(startedAt: .now.addingTimeInterval(-45))),
        locale: AppLanguage.locale(for: "zh"))
    WatchTrainingView(viewModel: TrainingViewModel(content: content),
        healthReport: .init(id: "preview", state: .running, activeCalories: 128, totalCalories: 156, heartRate: 124),
        onPrimaryAction: {})
}

#Preview("休息中") {
    let content = TrainingContentData(exercise: "哑铃飞鸟", position: "第 1/3 个动作",
        summary: .init(weight: "5 kg", detail: "12 次", label: "第 1/3 组"),
        action: .init(title: "结束", symbol: "forward.end.fill", status: .rest(endsAt: .now.addingTimeInterval(75))),
        locale: AppLanguage.locale(for: "zh"))
    WatchTrainingView(viewModel: TrainingViewModel(content: content),
        healthReport: .init(id: "preview", state: .running, activeCalories: 128, totalCalories: 156, heartRate: 124),
        onPrimaryAction: {})
}
