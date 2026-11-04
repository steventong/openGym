import ActivityKit
import SwiftUI
import WidgetKit

@main struct OpenGymWidgets: WidgetBundle {
    var body: some Widget { WorkoutLiveActivity() }
}
struct WorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            WorkoutActivityContent(state: context.state, systemDeadlinePassed: context.isStale)
                .padding(12)
                .activityBackgroundTint(Color(white: 0.07))
                .activitySystemActionForegroundColor(.green)
                .widgetURL(URL(string: "opengym://workout"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.state.trainingName).font(.caption).foregroundStyle(.secondary).lineLimit(1).padding(.leading, 12)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.restEnd != nil ? L10n.format("REST_BETWEEN_SETS" /* 组间休息 */, language: context.state.language ?? L10n.language) : context.state.position)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        .frame(width: 76, alignment: .trailing).padding(.trailing, 12)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    WorkoutActivityContent(state: context.state, island: true, systemDeadlinePassed: context.isStale)
                        .padding(.top, 4)
                        // Keep the full-width control inside the island's curved edge.
                        .padding(.horizontal, 12)
                        .padding(.bottom, 10)
                }
            } compactLeading: {
                HStack(spacing: 4) {
                    Image(systemName: context.state.restEnd == nil ? "dumbbell.fill" : "timer").frame(width: 16)
                    Text(context.state.exercise.isEmpty ? context.state.trainingName : context.state.exercise)
                        .font(.caption2).lineLimit(1)
                }.foregroundStyle(.green)
            } compactTrailing: {
                if let end = context.state.restEnd {
                    TrainingCountdownText(end: end, presentation: .systemTimer).frame(width: 48)
                } else {
                    Text(context.state.compactSet).font(.caption.monospacedDigit()).foregroundStyle(.green)
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
            } minimal: {
                Image(systemName: context.state.restEnd == nil ? "dumbbell.fill" : "timer").foregroundStyle(.green)
            }
            .widgetURL(URL(string: "opengym://workout"))
            .keylineTint(.green)
        }
    }
}
