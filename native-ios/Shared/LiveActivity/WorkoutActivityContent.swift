import SwiftUI
import WidgetKit

/// The same content is rendered by WidgetKit and the native layout checks.
struct WorkoutActivityContent: View {
    let state: WorkoutActivityAttributes.ContentState
    var island = false
    var systemDeadlinePassed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !island {
                HStack {
                    Text(state.trainingName).lineLimit(1)
                    Spacer(minLength: 8)
                    Text(state.position).lineLimit(1)
                }.font(.caption).foregroundStyle(.secondary)
            }
            Text(state.exercise.isEmpty ? L10n.format("READY_TO_START", language: state.language ?? L10n.language) : state.exercise)
                .font(.headline).lineLimit(1).minimumScaleFactor(0.8)
            setSummary.font(.subheadline).lineLimit(1).minimumScaleFactor(0.75)
            actionControl.accessibilityHint(state.message)
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

    private var actionControl: some View {
        let rest = state.restEnd != nil && state.restCommand != nil
        let title = state.busyTitle ?? (rest ? L10n.format("END_REST" /* 结束休息 */, language: state.language ?? L10n.language) : state.commandTitle)
        let command = rest ? state.restCommand : state.command
        let symbol = state.busyTitle != nil ? "arrow.triangle.2.circlepath" : (rest ? "forward.end.fill" : "checkmark")
        return TrainingActionControl(title: title, symbol: symbol, timing: state.actionTiming,
            disabled: state.busyTitle != nil, tint: Color(red: 0.47, green: 0.89, blue: 0.42),
            readyHint: !rest && command != nil && state.busyTitle == nil && state.setWeight != nil
                ? L10n.format("READY_FOR_YOUR_NEXT_SET" /* 准备好后开始下一组 */, language: state.language ?? L10n.language) : nil,
            language: state.language, systemDeadlinePassed: systemDeadlinePassed) { label in
                if let command {
                    Button(intent: WorkoutActivityIntent(command: command)) { label }
                } else {
                    Link(destination: URL(string: "opengym://workout")!) { label }
                }
            }
    }
}
