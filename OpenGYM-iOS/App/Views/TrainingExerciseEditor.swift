import SwiftUI

/// Shared exercise page for an active session and a saved workout.
/// Owners provide persistence and the live-only timer controls.
struct TrainingExerciseEditor<ExerciseActions: View, Accessory: View>: View {
    @Environment(GymStore.self) private var store
    @Environment(\.inputCommitBuffer) private var inputBuffer
    @Binding var showingOptions: Bool
    let entries: [[String: Any]]
    let names: [String]
    @Binding var selected: Int
    let rows: [TrainingEditorRow]
    let unit: String
    var inputState: [String: Any] = [:]
    let previous: String
    var previousNote: String? = nil
    @Binding var note: String
    let identifier: String
    var showsEntryPosition = true
    var allowsEntryNavigation = true
    var entryIdentity: String? = nil
    var timerRunning = false
    var restUntil: Date? = nil
    var startTimer: ((Int) -> Void)? = nil
    var startRest: ((Int, Double) -> Void)? = nil
    let showDetails: () -> Void
    let addSet: () -> Void
    let copySet: (Int) -> Void
    let removeSet: (Int) -> Void
    let editSet: (Int, [String: Any]) -> Void
    var undoRemove: (() -> Void)? = nil
    @ViewBuilder let exerciseActions: () -> ExerciseActions
    @ViewBuilder let accessory: () -> Accessory
    @State private var unitError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if entries.indices.contains(selected) {
                TrainingExerciseCard(entry: entries[selected], name: names[selected], rows: rows,
                    unit: unit, inputState: inputState, previous: previous, previousNote: previousNote,
                    identifier: identifier, entryIdentity: entryIdentity ?? String(selected), timerRunning: timerRunning,
                    restUntil: restUntil, startTimer: startTimer, startRest: startRest, showDetails: showDetails,
                    addSet: addSet, copySet: copySet, removeSet: removeSet, editSet: editSet, undoRemove: undoRemove,
                    exerciseActions: exerciseActions, accessory: accessory)
                    .accessibilityActions {
                        if allowsEntryNavigation, selected > 0 {
                            Button("PREVIOUS_EXERCISE") { selectEntry(offset: -1) }
                        }
                        if allowsEntryNavigation, selected + 1 < entries.count {
                            Button("NEXT_EXERCISE") { selectEntry(offset: 1) }
                        }
                    }
                if showsEntryPosition {
                    ExercisePositionLabel(index: selected, count: entries.count)
                        .font(.caption.monospacedDigit()).foregroundStyle(GymTheme.muted)
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("\(identifier)-entry-position")
                }
            }
        }.sheet(isPresented: $showingOptions) {
            optionsSheet
        }.onChange(of: selected) { _, _ in showingOptions = false; unitError = nil }
    }

    private func selectEntry(offset: Int) {
        let next = selected + offset
        guard entries.indices.contains(next) else { return }
        inputBuffer?.commitAll()
        GymKeyboard.dismiss()
        selected = next
    }

    private var optionsSheet: some View {
        NavigationStack {
            Form {
                Section("NOTES_FOR_THIS_EXERCISE") {
                    BufferedTextField("ADD_NOTE", text: $note, axis: .vertical).textFieldStyle(.plain).submitLabel(.done).onSubmit { GymKeyboard.dismiss() }
                        .lineLimit(3...6).accessibilityIdentifier("\(identifier)-exercise-note")
                }
                if entries.indices.contains(selected), !rows.isEmpty,
                   (entries[selected]["target"] as? [String: Any])?["mode"] as? String != "cardio",
                   rows.contains(where: { $0.raw["mode"] as? String != "cardio" }) {
                    Section {
                        Picker("WEIGHT_UNIT_FOR_THIS_WORKOUT", selection: Binding(get: {
                            TrainingInput.weightUnit(rows.first?.raw ?? [:], fallback: unit)
                        }, set: { next in
                            inputBuffer?.commitAll()
                            do {
                                // Validate every row first so a switch cannot discard unfinished input.
                                for row in rows { try TrainingInput.validateWeightSwitch(row.raw) }
                                for index in rows.indices { editSet(index, ["action": "weightUnit", "unit": next]) }
                            } catch { unitError = error.localizedDescription }
                        })) {
                            Text("KG_KILOGRAMS").tag("kg")
                            Text("LB_POUNDS").tag("lb")
                        }.pickerStyle(.segmented).disabled(timerRunning)
                            .accessibilityIdentifier("\(identifier)-weight-unit")
                    } header: { HStack { Text("WEIGHT_UNIT_FOR_THIS_WORKOUT"); Spacer(); ExplanationButton(title: "WEIGHT_UNIT", message: "EXISTING_WEIGHTS_ARE_CONVERTED_AUTOMATICALLY_FOR_THIS_EXERCISE_ONLY") } }
                }
            }.navigationTitle("NOTES_AND_UNITS").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("DONE") { inputBuffer?.commitAll(); showingOptions = false } } }
                .alert("YOUR_WEIGHT_INPUT_HAS_BEEN_KEPT", isPresented: Binding(get: { unitError != nil }, set: { if !$0 { unitError = nil } })) {
                    Button("GOT_IT", role: .cancel) {}
                } message: { Text(unitError ?? "") }
        }.presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
    }
}
