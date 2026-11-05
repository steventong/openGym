import ActivityKit
import SwiftUI
import WidgetKit

@main struct OpenGymWidgets: WidgetBundle {
    var body: some Widget { WorkoutLiveActivity() }
}
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
