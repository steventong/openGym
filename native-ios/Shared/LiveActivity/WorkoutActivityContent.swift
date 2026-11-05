import SwiftUI
import WidgetKit

/// The same content is rendered by WidgetKit and the native layout checks.
struct WorkoutActivityContent: View {
    let state: WorkoutActivityAttributes.ContentState
    var island = false
    var systemDeadlinePassed = false

    private static func contentInsets(island: Bool) -> EdgeInsets {
        // Move space from above the island's button to below it so the whole
        // control clears the system's curved lower edge within the same budget.
        EdgeInsets(top: island ? 0 : 10, leading: 12,
            bottom: TrainingDisplayStyle.actionGap + (island ? 6 : 0), trailing: 12)
    }

    // WidgetKit places these same header views around the camera. All styling
    // stays here; the widget only supplies the system's expanded-region wrappers.
    var islandLeading: some View {
        exerciseTitle.padding(.leading, 12)
    }

    var islandTrailing: some View {
        exercisePosition.frame(height: 18, alignment: .bottom).padding(.trailing, 12)
    }

    private var exerciseTitle: some View {
        TrainingExerciseTitle(title: state.exercise.isEmpty
            ? L10n.format("READY_TO_START", language: state.language ?? L10n.language)
            : state.exercise)
    }

    private var exercisePosition: some View {
        TrainingExercisePosition(position: state.position,
            fontSize: 12, fontWeight: .medium, textColor: .white.opacity(0.9))
    }

    var body: some View {
        VStack(spacing: 0) {
            if !island {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    exerciseTitle
                    exercisePosition
                }.frame(height: 22).padding(.bottom, 4)
            }
            // Older activities may only contain the combined detail string.
            TrainingSetSummary(weight: state.setWeight ?? state.detail,
                detail: state.setWeight == nil ? "" : (state.setDetail ?? ""), label: state.setLabel,
                detailFontSize: 14, detailFontWeight: .medium, detailColor: .white.opacity(0.9), completionLabel: state.setCompletionLabel)
            Color.clear.frame(height: TrainingDisplayStyle.actionGap - (island ? 6 : 0)).accessibilityHidden(true)
            actionControl.accessibilityHint(state.message)
        }
        .padding(Self.contentInsets(island: island))
        .foregroundStyle(.white)
    }

    private var actionControl: some View {
        let rest = state.restEnd != nil && state.restCommand != nil
        let title = state.busyTitle ?? (rest ? L10n.format("END_REST" /* 结束休息 */, language: state.language ?? L10n.language) : state.commandTitle)
        let command = rest ? state.restCommand : state.command
        let symbol = state.busyTitle != nil ? "arrow.triangle.2.circlepath" : (rest ? "forward.end.fill" : "checkmark")
        return TrainingActionControl(title: title, symbol: symbol, timing: state.actionTiming,
            disabled: state.busyTitle != nil, tint: TrainingDisplayStyle.green,
            quietReady: !rest && command != nil && state.busyTitle == nil && state.setWeight != nil,
            language: state.language, systemDeadlinePassed: systemDeadlinePassed, countdownPresentation: .systemTimer) { label in
                if let command {
                    Button(intent: WorkoutActivityIntent(command: command)) { label }
                } else {
                    Link(destination: URL(string: "opengym://workout")!) { label }
                }
            }
    }
}
