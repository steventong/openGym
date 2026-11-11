import SwiftUI

/// The same discoverable actions for live sessions and historical corrections.
struct ExerciseManagementControls: View {
    @Environment(\.inputCommitBuffer) private var inputBuffer
    let entries: [[String: Any]]
    let selected: Int
    var history = false
    var timerRunning = false
    var startRest: ((Int) -> Void)? = nil
    var showExerciseNote: (() -> Void)? = nil
    var menuTitle: LocalizedStringKey = "EXERCISE_MENU"
    var menuIcon = "ellipsis.circle"
    var menuIdentifier = "training-exercise-options"
    let change: (String, Int, Int, String?) -> Void
    @State private var replacing = false
    @State private var confirmRemoval = false
    @State private var pendingIndex = 0

    init(entries: [[String: Any]], selected: Int, history: Bool = false, timerRunning: Bool = false,
         startRest: ((Int) -> Void)? = nil, showExerciseNote: (() -> Void)? = nil, menuTitle: LocalizedStringKey = "EXERCISE_MENU",
         menuIcon: String = "ellipsis.circle", menuIdentifier: String = "training-exercise-options",
         change: @escaping (String, Int, Int, String?) -> Void) {
        self.entries = entries
        self.selected = selected
        self.history = history
        self.timerRunning = timerRunning
        self.startRest = startRest
        self.showExerciseNote = showExerciseNote
        self.menuTitle = menuTitle
        self.menuIcon = menuIcon
        self.menuIdentifier = menuIdentifier
        self.change = change
    }

    var body: some View {
        Menu {
            if entries.indices.contains(selected) {
                Button("SWAP_EXERCISE", systemImage: "arrow.triangle.2.circlepath") { inputBuffer?.commitAll(); pendingIndex = selected; replacing = true }
                if let showExerciseNote { Button("NOTES_AND_UNITS", systemImage: "note.text", action: showExerciseNote).accessibilityIdentifier("exercise-note-menu") }
                if let startRest {
                    Menu {
                        ForEach([30, 60, 90, 120, 180, 300], id: \.self) { seconds in Button(String(format: String(localized: "COUNT_SECOND", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(describing: seconds))) { startRest(seconds) } }
                    } label: { Label("SET_AND_START_REST", systemImage: "timer") }.disabled(timerRunning)
                }
                Section("SUPERSET") {
                    if selected > 0 { Button("MAKE_SUPERSET_WITH_PREVIOUS", systemImage: "link") { change("pair", selected, -1, nil) }.disabled(timerRunning) }
                    if selected + 1 < entries.count { Button("MAKE_SUPERSET_WITH_NEXT", systemImage: "link") { change("pair", selected, 1, nil) }.disabled(timerRunning) }
                    if entries[selected]["sg"] != nil { Button("MOVE_OUT_OF_THE_SUPERSET", systemImage: "minus.circle") { change("unpair", selected, 0, nil) }.disabled(timerRunning) }
                }
                Button("DELETE_EXERCISE", systemImage: "trash", role: .destructive) { pendingIndex = selected; confirmRemoval = true }
            }
        } label: {
            Image(systemName: menuIcon).font(.title2).frame(width: 48, height: 48).contentShape(Rectangle())
        }.font(.subheadline).buttonStyle(.borderless).accessibilityLabel(menuTitle).accessibilityIdentifier(menuIdentifier)
            .sheet(isPresented: $replacing) {
                TrainingReplacementPicker(history: history, currentID: entries.indices.contains(pendingIndex) ? entries[pendingIndex]["id"] as? String : nil) { exercise in
                    guard entries.indices.contains(pendingIndex) else { return }
                    change("replace", pendingIndex, 0, exercise.id)
                    replacing = false
                }
            }
            .confirmationDialog("REMOVE_THIS_EXERCISE", isPresented: $confirmRemoval, titleVisibility: .visible) {
                Button("REMOVE_EXERCISE_AND_SETS", role: .destructive) { change("remove", pendingIndex, 0, nil) }
                Button("CANCEL", role: .cancel) {}
            } message: { Text("THIS_EXERCISE_AND_ITS_SET_RECORDS_WILL_BE_REMOVED_FROM_THIS_WORKOUT") }
    }

}

/// Dragging edits only this sheet's snapshot. Apply the complete permutation once.
struct ExerciseOrderSheet: View {
    @Environment(GymStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var entries: [[String: Any]]
    private let history: Bool
    private let save: ([Int], [[String: Any]]) throws -> Void
    @State private var order: [Int]
    @State private var error: String?

    init(entries: [[String: Any]], history: Bool = false, save: @escaping ([Int], [[String: Any]]) throws -> Void) {
        _entries = State(initialValue: entries)
        self.history = history
        self.save = save
        _order = State(initialValue: Array(entries.indices))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(order, id: \.self) { index in
                        let entry = entries[index]
                        let id = entry["id"] as? String
                        let exercise = id.flatMap(store.exercise)
                        let snapshot = entry["muscleSnapshot"] as? [String: Any]
                        let name = exercise?.recordName ?? entry["n"] as? String ?? snapshot?["n"] as? String ?? id
                        HStack(spacing: 12) {
                            ExerciseThumbnail(id: id ?? "", size: 44)
                            VStack(alignment: .leading, spacing: 4) {
                                if let name { Text(name) } else { Text("EXERCISE") }
                                if history, let muscle = muscleLabel(for: exercise, snapshot: snapshot) {
                                    Text(muscle).font(.caption).foregroundStyle(GymTheme.muted)
                                }
                                if let group = entry["sg"] as? String, !group.isEmpty {
                                    Label("SUPERSET", systemImage: "link").font(.caption).foregroundStyle(GymTheme.green)
                                }
                            }
                        }.accessibilityIdentifier("exercise-order-row-\(index)")
                            .moveDisabled(entries.count < 2)
                    }.onMove { order.move(fromOffsets: $0, toOffset: $1) }
                }
            }.environment(\.editMode, .constant(.active))
                .navigationTitle(history ? Text("EXERCISE_LIST") : Text("REORDER_EXERCISES"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("CANCEL") { dismiss() } }
                    ToolbarItem(placement: .topBarTrailing) { ExplanationButton(title: "SUPERSET", message: "SEPARATING_EXERCISES_IN_A_SUPERSET_WILL_UNGROUP_THEM") }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("SAVE") {
                            do { try save(order, entries); dismiss() }
                            catch { self.error = error.localizedDescription }
                        }.accessibilityIdentifier("save-exercise-order")
                    }
                }
                .alert("COULD_NOT_SAVE_EXERCISE_ORDER", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                    Button("GOT_IT", role: .cancel) {}
                } message: { Text(error ?? "") }
        }.tint(GymTheme.green).presentationDragIndicator(.visible)
    }

    private func muscleLabel(for exercise: Exercise?, snapshot: [String: Any]?) -> String? {
        let candidates = [exercise?.target, (snapshot?["primaries"] as? [String])?.first,
                          (snapshot?["muscleGroups"] as? [String])?.first, exercise?.bodyPart, snapshot?["bp"] as? String]
        guard let muscle = candidates.compactMap({ $0 }).first(where: { !$0.isEmpty }) else { return nil }
        let key = muscle == "upper back" ? "upper-back" : muscle
        return String(localized: String.LocalizationValue(key), table: "Muscles", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
    }
}

@MainActor enum ExerciseOrder {
    static func apply(_ order: [Int], to active: [String: Any]) throws -> [String: Any] {
        guard let result = try WebRules.shared.call("manageTrainingExercises", payload: [
            "active": active, "action": "reorder", "order": order
        ]) as? [String: Any] else { throw APIError.invalidResponse }
        return result
    }
}

private struct TrainingReplacementPicker: View {
    let history: Bool
    let currentID: String?
    let replace: (Exercise) -> Void
    @State private var selected: Exercise?
    @State private var confirming = false
    var body: some View {
        ExercisePicker(title: "SWAP_EXERCISE", selectionIcon: "arrow.triangle.2.circlepath") { exercise in
            guard exercise.id != currentID else { return }
            selected = exercise; confirming = true
        }.confirmationDialog("REPLACE_THIS_EXERCISE", isPresented: $confirming, titleVisibility: .visible) {
            Button("SWAP_EXERCISE") { if let selected { replace(selected) } }
            Button("CANCEL", role: .cancel) { selected = nil }
        } message: {
            Text(LocalizedStringKey(history ? "SET_RECORDS_WILL_BE_KEPT_UNDER_THE_NEW_EXERCISE_VOLUME_AND_PERSONAL" : "COMPLETED_SETS_OR_SIDES_STAY_IN_PLACE_WITH_THE_NEW_EXERCISE_ADDED"))
        }
    }
}

struct LiveExerciseManagement: View {
    @Environment(GymStore.self) private var store
    var entryIndex: Int? = nil
    var showExerciseNote: () -> Void
    var body: some View {
        if let draft = store.draft {
            let index = entryIndex ?? min(max(0, draft.activeJSON["cur"] as? Int ?? 0), max(0, draft.rawEntries.count - 1))
            ExerciseManagementControls(entries: draft.rawEntries, selected: index, timerRunning: store.workTimer != nil, startRest: { store.startExerciseRest(entry: index, seconds: Double($0)) }, showExerciseNote: showExerciseNote, menuIdentifier: "live-exercise-menu") { action, targetIndex, direction, id in
                store.manageLiveExercise(action: action, index: targetIndex, direction: direction, id: id)
            }
        }
    }
}

extension GymStore {
    func reorderLiveExercises(_ order: [Int], expectedEntries: [[String: Any]], sessionID: String) throws {
        liveInputBuffer.commitAll()
        guard var draft, draft.id == sessionID,
              draft.rawEntries.map({ $0["nativeViewID"] as? String }) == expectedEntries.map({ $0["nativeViewID"] as? String }) else {
            throw APIError.response(0, String(localized: "THE_EXERCISE_LIST_HAS_CHANGED_OPEN_THE_REORDER_SCREEN_AGAIN", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
        }
        if order != Array(draft.rawEntries.indices) {
            var raw = try ExerciseOrder.apply(order, to: draft.activeJSON)
            raw.removeValue(forKey: "nativeSetUndo")
            try draft.setActive(raw)
            self.draft = draft
        }
        if let issue = localSaveIssues["live"] { throw APIError.response(0, issue) }
    }

    func manageLiveExercise(action: String, index: Int, direction: Int = 0, id: String? = nil) {
        changeActive { raw in
            var payload: [String: Any] = ["active": raw, "state": state, "action": action, "index": index, "direction": direction]
            payload["id"] = id
            guard let updated = try WebRules.shared.call("manageTrainingExercises", payload: payload) as? [String: Any] else { throw APIError.invalidResponse }
            raw = updated
        }
    }
}

extension HistoryForm {
    @MainActor mutating func reorderExercises(_ order: [Int]) throws {
        var active = proposed; active["cur"] = selected
        let result = try ExerciseOrder.apply(order, to: active)
        guard let updated = result["entries"] as? [[String: Any]] else { throw APIError.invalidResponse }
        let existing = entries
        entries = order.enumerated().map { offset, index in
            var entry = existing[index]
            entry.raw = updated[offset]
            return entry
        }
        selected = result["cur"] as? Int ?? 0
    }
    @MainActor mutating func manageExercise(action: String, index: Int? = nil, direction: Int = 0, id: String? = nil, state: [String: Any]) throws {
        var active = proposed; active["cur"] = selected
        var payload: [String: Any] = ["active": active, "state": state, "history": true, "action": action, "index": index ?? selected, "direction": direction]
        payload["id"] = id
        guard let result = try WebRules.shared.call("manageTrainingExercises", payload: payload) as? [String: Any],
              let updated = result["entries"] as? [[String: Any]] else { throw APIError.invalidResponse }
        entries = updated.map(HistoryEntryDraft.init)
        selected = result["cur"] as? Int ?? 0
    }
}

struct RoutineExerciseReplacement: View {
    @Environment(\.inputCommitBuffer) private var inputBuffer
    @Environment(GymStore.self) private var store
    @Binding var slot: [String: Any]
    let routineID: String
    @State private var picking = false
    @State private var error: String?
    var body: some View {
        Button { inputBuffer?.commitAll(); picking = true } label: {
            Label("CHANGE", systemImage: "arrow.triangle.2.circlepath").font(.subheadline).frame(minHeight: 44)
        }.buttonStyle(.borderless).accessibilityIdentifier("replace-routine-exercise")
            .sheet(isPresented: $picking) {
                ExercisePicker(title: "SWAP_EXERCISE", selectionIcon: "arrow.triangle.2.circlepath") { exercise in
                    do {
                        guard let result = try WebRules.shared.call("replaceNativeRoutineExercise", payload: ["slot": slot, "id": exercise.id, "state": store.state, "rid": routineID]) as? [String: Any] else { throw APIError.invalidResponse }
                        slot = result; picking = false
                    } catch { self.error = error.localizedDescription; picking = false }
                }
            }
            .alert("COULD_NOT_REPLACE_EXERCISE", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("GOT_IT", role: .cancel) {}
            } message: { Text(error ?? "") }
    }
}
