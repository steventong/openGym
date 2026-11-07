import SwiftUI

struct WorkoutMenuView: View {
    let draft: TrainingDraft
    let timerRunning: Bool
    let addExercise: () -> Void
    let reorderExercises: () -> Void
    let showDetails: () -> Void
    let finishWorkout: () -> Void
    let deleteWorkout: () -> Void

    var body: some View {
        Menu {
            Section {
                Button("ADD_EXERCISE", systemImage: "plus", action: addExercise)
                    .accessibilityIdentifier("add-workout-exercise")
                Button("REORDER_EXERCISES", systemImage: "arrow.up.arrow.down", action: reorderExercises)
                    .disabled(draft.rawEntries.count < 2).accessibilityIdentifier("reorder-exercises")
            }
            Section("WORKOUT") {
                Button("WORKOUT_DETAILS", systemImage: "note.text", action: showDetails)
                    .accessibilityIdentifier("workout-details-menu")
                Button("SAVE_AND_SUBMIT_WORKOUT_A", systemImage: "checkmark.circle", action: finishWorkout)
                    .disabled(draft.completedSets == 0 || timerRunning).accessibilityIdentifier("finish-workout")
                Button(role: .destructive, action: deleteWorkout) {
                    Label("DELETE_WORKOUT_A", systemImage: "trash")
                }.accessibilityIdentifier("delete-workout")
            }
        } label: {
            Label("WORKOUT_MENU", systemImage: "ellipsis")
        }.accessibilityIdentifier("workout-menu")
    }
}
