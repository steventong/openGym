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
