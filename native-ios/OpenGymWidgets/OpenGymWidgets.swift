import ActivityKit
import SwiftUI
import WidgetKit

@main struct OpenGymWidgets: WidgetBundle {
    var body: some Widget { WorkoutLiveActivity() }
}

struct WorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            WorkoutActivityView(context: context)
                .padding(16)
                .activityBackgroundTint(Color(white: 0.07))
                .activitySystemActionForegroundColor(.green)
                .widgetURL(URL(string: "opengym://workout"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.state.trainingName).font(.caption).foregroundStyle(.secondary).lineLimit(1).padding(.leading, 6)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.position).font(.caption).foregroundStyle(.secondary).padding(.trailing, 6)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    WorkoutActivityView(context: context, island: true).padding(.top, 2)
                }
            } compactLeading: {
                HStack(spacing: 4) {
                    Image(systemName: context.state.restEnd == nil ? "dumbbell.fill" : "timer")
                    Text(context.state.exercise.isEmpty ? context.state.trainingName : context.state.exercise)
                        .font(.caption2).lineLimit(1).frame(maxWidth: 72)
                }.foregroundStyle(.green)
            } compactTrailing: {
                if let end = context.state.restEnd {
                    RestCountdown(end: end).frame(width: 48)
                } else {
                    Text(context.state.compactSet).font(.caption.monospacedDigit()).foregroundStyle(.green)
                }
            } minimal: {
                Image(systemName: context.state.restEnd == nil ? "dumbbell.fill" : "timer").foregroundStyle(.green)
            }
            .widgetURL(URL(string: "opengym://workout"))
            .keylineTint(.green)
        }
    }
}

private struct WorkoutActivityView: View {
    let context: ActivityViewContext<WorkoutActivityAttributes>
    var island = false
    private var state: WorkoutActivityAttributes.ContentState { context.state }
    private var resting: Bool { state.restEnd != nil && !context.isStale }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !island { Text(state.trainingName).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(state.exercise.isEmpty ? "准备开始训练" : state.exercise).font(.headline).lineLimit(1)
                    Text((resting ? "接下来 · " : "") + state.setLabel).font(.subheadline).foregroundStyle(.green).lineLimit(1)
                }
                Spacer(minLength: 8)
                if let end = state.restEnd {
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(context.isStale ? "休息结束" : "组间休息").font(.caption).foregroundStyle(.secondary)
                        RestCountdown(end: end).font(.title2.bold()).frame(width: 76)
                    }
                }
            }
            HStack {
                Text(state.message.isEmpty ? state.detail : state.message)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                Spacer(minLength: 8)
                if let command = state.restCommand {
                    Button("结束休息", intent: WorkoutActivityIntent(command: command))
                        .font(.caption).buttonStyle(.bordered).controlSize(.small).tint(.green)
                }
                action.font(.caption.bold()).buttonStyle(.borderedProminent).controlSize(.small).tint(.green).foregroundStyle(.black)
            }
        }.foregroundStyle(.white)
    }

    @ViewBuilder private var action: some View {
        // Keep completion available even if the system delays the stale-date redraw at zero.
        if let command = state.command {
            Button(intent: WorkoutActivityIntent(command: command)) {
                Label(state.commandTitle, systemImage: state.commandTitle == "完成本组" ? "checkmark" : "arrow.right")
            }
        } else {
            Link(destination: URL(string: "opengym://workout")!) { Label("打开训练", systemImage: "arrow.up.right") }
        }
    }
}

private struct RestCountdown: View {
    let end: Date
    var body: some View {
        // System-rendered dates keep counting while the app is suspended and stop at zero.
        Text(timerInterval: min(Date(), end)...end, countsDown: true, showsHours: false)
            .monospacedDigit().foregroundStyle(.green)
    }
}
