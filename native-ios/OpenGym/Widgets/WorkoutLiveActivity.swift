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
            WorkoutActivityContent(state: context.state, systemDeadlinePassed: context.isStale)
                .activityBackgroundTint(Color(white: 0.07))
                .activitySystemActionForegroundColor(.green)
                .widgetURL(URL(string: "opengym://workout"))
        } dynamicIsland: { context in
            let content = WorkoutActivityContent(state: context.state, island: true, systemDeadlinePassed: context.isStale)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    content.islandLeading
                }
                DynamicIslandExpandedRegion(.trailing) {
                    content.islandTrailing
                }
                DynamicIslandExpandedRegion(.bottom) {
                    content
                }
            } compactLeading: {
                HStack(spacing: 4) {
                    brandMark.frame(width: 22, height: 16)
                    Text(context.state.exercise.isEmpty ? context.state.trainingName : context.state.exercise)
                        .font(.caption2).lineLimit(1)
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
                brandMark.frame(width: 22, height: 22)
            }
            .widgetURL(URL(string: "opengym://workout"))
            .keylineTint(.green)
        }
    }
}

#if DEBUG
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
#endif
