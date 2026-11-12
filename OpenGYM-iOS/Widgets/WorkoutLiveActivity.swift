import ActivityKit
import SwiftUI
import WidgetKit

struct WorkoutLiveActivity: Widget {
    private var brandMark: some View {
        Image("BrandMark").renderingMode(.original).resizable().scaledToFit()
            .accessibilityHidden(true)
    }

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            WorkoutActivityContent(viewModel: TrainingViewModel(content: context.state.trainingContent(systemDeadlinePassed: context.isStale)),
                command: context.state.trainingActionCommand)
                .activityBackgroundTint(Color(white: 0.07))
                .activitySystemActionForegroundColor(.green)
                .widgetURL(URL(string: "opengym://workout"))
        } dynamicIsland: { context in
            let viewModel = TrainingViewModel(content: context.state.trainingContent(systemDeadlinePassed: context.isStale))
            let content = viewModel.content
            let title = context.state.exercise.isEmpty ? context.state.trainingName : context.state.exercise
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    TrainingExerciseTitle(title: content.exercise).padding(.leading, 12)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    TrainingExercisePosition(position: content.position, fontWeight: .medium, textColor: .white.opacity(0.9))
                        .frame(height: 18, alignment: .bottom).padding(.trailing, 12)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    WorkoutActivityContent(viewModel: viewModel, command: context.state.trainingActionCommand, island: true)
                }
            } compactLeading: {
                HStack(spacing: 4) {
                    brandMark.frame(width: 22, height: 16)
                    Text(title).font(.caption2).lineLimit(1)
                }.foregroundStyle(.green)
            } compactTrailing: {
                if let end = context.state.restEnd {
                    TrainingCountdownText(end: end, presentation: .systemTimer)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 48, alignment: .trailing)
                } else {
                    Text(context.state.compactSet).font(.caption.monospacedDigit()).foregroundStyle(.green)
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
            } minimal: {
                if let end = context.state.restEnd {
                    TrainingCountdownText(end: end, presentation: .systemTimer)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .multilineTextAlignment(.center)
                } else {
                    Text(title)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.green)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                        .multilineTextAlignment(.center)
                }
            }
            .widgetURL(URL(string: "opengym://workout"))
            .keylineTint(.green)
        }
    }
}

#Preview("锁屏 · 训练与休息", as: .content,
    using: WorkoutActivityAttributes(account: "preview", sessionID: "preview")) {
    WorkoutLiveActivity()
} contentStates: {
    WorkoutActivityAttributes.ContentState.canvas(resting: false)
    WorkoutActivityAttributes.ContentState.canvas(resting: true)
}

#Preview("灵动岛 · 展开", as: .dynamicIsland(.expanded),
    using: WorkoutActivityAttributes(account: "preview", sessionID: "preview")) {
    WorkoutLiveActivity()
} contentStates: {
    WorkoutActivityAttributes.ContentState.canvas(resting: false)
    WorkoutActivityAttributes.ContentState.canvas(resting: true)
}

#Preview("灵动岛 · 最小", as: .dynamicIsland(.minimal),
    using: WorkoutActivityAttributes(account: "preview", sessionID: "preview")) {
    WorkoutLiveActivity()
} contentStates: {
    WorkoutActivityAttributes.ContentState.canvas(resting: false)
    WorkoutActivityAttributes.ContentState.canvas(resting: true)
}

private extension WorkoutActivityAttributes.ContentState {
    static func canvas(resting: Bool) -> Self {
        Self(trainingName: "胸部训练", exercise: "哑铃飞鸟", position: "第 1/1 个动作",
            setLabel: "第 1/3 组", compactSet: "1/3", detail: "5 kg · 12 次", message: "预览",
            restEnd: resting ? Date().addingTimeInterval(75) : nil, restExercise: "哑铃飞鸟",
            command: "preview", commandTitle: "完成本组", restCommand: resting ? "preview" : nil,
            setWeight: "5 kg", setDetail: "12 次", setCompletionLabel: resting ? "已完成" : nil,
            setStartedAt: resting ? nil : Date().addingTimeInterval(-45), language: "zh-Hans")
    }
}
