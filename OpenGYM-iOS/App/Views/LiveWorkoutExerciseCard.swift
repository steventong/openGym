import SwiftUI

struct LiveWorkoutExerciseCard: View {
    @Environment(GymStore.self) private var store
    let draft: TrainingDraft
    let index: Int
    @Binding var showingNote: Bool

    var body: some View {
        let entry = draft.rawEntries[index]
        let rows = entry["sets"] as? [[String: Any]] ?? []
        let previous = store.previousExerciseReference(entry, before: draft.start.timeIntervalSince1970 * 1000, exclude: draft.id)
        TrainingExerciseEditor(
            showingOptions: Binding(get: { showingNote && (store.draft?.activeJSON["cur"] as? Int ?? 0) == index }, set: { showingNote = $0 }),
            entries: draft.rawEntries, names: draft.rawEntries.map(exerciseName),
            selected: Binding(get: { index }, set: { store.selectLiveEntry($0) }),
            rows: rows.enumerated().map { TrainingEditorRow(id: $0.element["nativeViewID"] as? String ?? "\(draft.id)-\(index)-\($0.offset)", raw: $0.element, accessibilityIdentifier: "\(index)-\($0.offset)") },
            unit: draft.unit, inputState: store.state.merging(["unit": draft.unit]) { _, new in new }, previous: previous.text, previousNote: previous.note,
            note: Binding(get: { entry["note"] as? String ?? "" }, set: { store.setLiveNote(entry: index, text: $0) }),
            identifier: "live", showsEntryPosition: false, entryIdentity: "\(draft.id)-\(entry["nativeViewID"] as? String ?? String(index))", timerRunning: store.workTimer != nil,
            restUntil: store.restEntry == index ? store.restUntil : nil,
            startTimer: { store.startWorkTimer(entry: index, set: $0) },
            startRest: { store.startRest(entry: index, seconds: $1, set: $0) },
            showDetails: { store.selectedExercise = store.exercise(entry["id"] as? String ?? "") },
            addSet: { store.addLiveSet(entry: index) },
            copySet: { store.copyLiveSet(entry: index, set: $0) },
            removeSet: { store.removeLiveSet(entry: index, set: $0) },
            editSet: { store.liveRowAction(entry: index, set: $0, action: $1) },
            undoRemove: store.canUndoSetRemoval ? { store.undoSetRemoval() } : nil,
            exerciseActions: { LiveExerciseManagement(entryIndex: index, showExerciseNote: { store.liveInputBuffer.commitAll(); store.selectLiveEntry(index); showingNote = true }) }
        ) {
            if let timer = store.workTimer, timer["entry"] as? Int == index { WorkoutTimerCard(timer: timer) }
        }
    }

    private func exerciseName(_ entry: [String: Any]) -> String {
        store.exercise(entry["id"] as? String ?? "")?.recordName ?? String(localized: "CUSTOM_EXERCISE", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
    }
}
