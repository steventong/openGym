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
                    Text(context.state.trainingName).font(.caption).foregroundStyle(.secondary).lineLimit(1).padding(.leading, 12)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.restEnd != nil ? (context.isStale ? "休息结束" : "组间休息") : context.state.position)
                        .font(.caption).foregroundStyle(.secondary).padding(.trailing, 12)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    WorkoutActivityView(context: context, island: true)
                        .padding(.top, 4)
                        // Keep the whole 44-point button inside the island's curved edge.
                        .padding(.horizontal, 12)
                        .padding(.bottom, 12)
                }
            } compactLeading: {
                HStack(spacing: 4) {
                    Image(systemName: context.state.restEnd == nil ? "dumbbell.fill" : "timer")
                    Text(context.state.exercise.isEmpty ? context.state.trainingName : context.state.exercise)
                        .font(.caption2).lineLimit(1)
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
            if !island {
                HStack {
                    Text(state.trainingName).lineLimit(1)
                    Spacer(minLength: 8)
                    if state.restEnd != nil { Text(context.isStale ? "休息结束" : "组间休息") }
                }.font(.caption).foregroundStyle(.secondary)
            }
            HStack(alignment: .firstTextBaseline) {
                Text(state.exercise.isEmpty ? "准备开始训练" : state.exercise).font(.headline).lineLimit(1)
                Spacer(minLength: 8)
                if let end = state.restEnd {
                    RestCountdown(end: end).font(.title2.bold())
                        .multilineTextAlignment(.trailing)
                        .frame(width: 76, alignment: .trailing)
                }
            }
            HStack(alignment: .center, spacing: 8) {
                setSummary.font(.subheadline).lineLimit(1).minimumScaleFactor(0.75)
                Spacer(minLength: 8)
                if let command = state.restCommand, !island || resting {
                    Button(intent: WorkoutActivityIntent(command: command)) {
                        Text("结束休息")
                            .font(.caption).fixedSize(horizontal: true, vertical: false)
                            .padding(.horizontal, 10).frame(minHeight: 44)
                            .background(.green.opacity(0.16), in: RoundedRectangle(cornerRadius: 12))
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain).foregroundStyle(.green)
                }
                if !island || !resting {
                    action.buttonStyle(.plain).foregroundStyle(.black)
                }
            }
            if !state.message.isEmpty {
                Text(state.message).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }.foregroundStyle(.white)
    }

    private var setSummary: Text {
        let label = Text(state.setLabel).foregroundColor(.green)
        if let weight = state.setWeight {
            return Text("\(label)  \(Text(weight).foregroundColor(.white))  \(Text(state.setDetail ?? "").foregroundColor(.secondary))")
        }
        // Preserve data from a still-running activity encoded by an older app version.
        if !state.detail.isEmpty { return Text("\(label)  \(Text(state.detail).foregroundColor(.secondary))") }
        return label
    }

    @ViewBuilder private var action: some View {
        // Keep completion available even if the system delays the stale-date redraw at zero.
        if let command = state.command {
            Button(intent: WorkoutActivityIntent(command: command)) {
                actionLabel(state.commandTitle, symbol: state.commandTitle == "完成本组" ? "checkmark" : "arrow.right")
            }
        } else {
            Link(destination: URL(string: "opengym://workout")!) { actionLabel("打开App", symbol: "arrow.up.right") }
        }
    }

    private func actionLabel(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.caption.bold()).fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 12).frame(minHeight: 44)
            .background(.green, in: RoundedRectangle(cornerRadius: 12))
            .contentShape(Rectangle())
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
