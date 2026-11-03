import SwiftUI

/// The same discoverable actions for live sessions and historical corrections.
struct ExerciseManagementControls<AdditionalActions: View>: View {
    let entries: [[String: Any]]
    let selected: Int
    var history = false
    var timerRunning = false
    var startRest: ((Int) -> Void)? = nil
    var showExerciseNote: (() -> Void)? = nil
    var menuTitle = "动作管理"
    var menuIcon = "slider.horizontal.3"
    var menuIdentifier = "training-exercise-options"
    let additionalActions: () -> AdditionalActions
    let reorder: ([Int], [[String: Any]]) throws -> Void
    let change: (String, Int, Int, String?) -> Void
    @State private var picker: PickerAction?
    @State private var confirmRemoval = false
    @State private var pendingIndex = 0

    init(entries: [[String: Any]], selected: Int, history: Bool = false, timerRunning: Bool = false,
         startRest: ((Int) -> Void)? = nil, showExerciseNote: (() -> Void)? = nil, menuTitle: String = "动作管理",
         menuIcon: String = "slider.horizontal.3", menuIdentifier: String = "training-exercise-options",
         reorder: @escaping ([Int], [[String: Any]]) throws -> Void,
         @ViewBuilder additionalActions: @escaping () -> AdditionalActions = { EmptyView() },
         change: @escaping (String, Int, Int, String?) -> Void) {
        self.reorder = reorder
        self.entries = entries
        self.selected = selected
        self.history = history
        self.timerRunning = timerRunning
        self.startRest = startRest
        self.showExerciseNote = showExerciseNote
        self.menuTitle = menuTitle
        self.menuIcon = menuIcon
        self.menuIdentifier = menuIdentifier
        self.additionalActions = additionalActions
        self.change = change
    }

    private enum PickerAction: String, Identifiable {
        case add, replace, reorder
        var id: String { rawValue }
    }
    var body: some View {
        Menu {
            Button("添加动作", systemImage: "plus") { picker = .add }
            if entries.indices.contains(selected) {
                Button("更换动作", systemImage: "arrow.triangle.2.circlepath") { pendingIndex = selected; picker = .replace }
                if let showExerciseNote { Button("动作备注", systemImage: "note.text", action: showExerciseNote).accessibilityIdentifier("exercise-note-menu") }
                Button("顺序调整", systemImage: "arrow.up.arrow.down") { picker = .reorder }
                    .disabled(entries.count < 2).accessibilityIdentifier("reorder-exercises")
                if let startRest {
                    Menu {
                        ForEach([30, 60, 90, 120, 180, 300], id: \.self) { seconds in Button("\(seconds) 秒") { startRest(seconds) } }
                    } label: { Label("设置并开始休息", systemImage: "timer") }.disabled(timerRunning)
                }
                Section("超级组") {
                    if selected > 0 { Button("与上一个动作组合", systemImage: "link") { change("pair", selected, -1, nil) }.disabled(timerRunning) }
                    if selected + 1 < entries.count { Button("与下一个动作组合", systemImage: "link") { change("pair", selected, 1, nil) }.disabled(timerRunning) }
                    if entries[selected]["sg"] != nil { Button("移出超级组", systemImage: "minus.circle") { change("unpair", selected, 0, nil) }.disabled(timerRunning) }
                }
                Button("删除动作", systemImage: "trash", role: .destructive) { pendingIndex = selected; confirmRemoval = true }
            }
            additionalActions()
        } label: {
            Image(systemName: menuIcon).frame(width: 44, height: 44)
        }.font(.subheadline).buttonStyle(.borderless).accessibilityLabel(menuTitle).accessibilityIdentifier(menuIdentifier)
            .sheet(item: $picker) { action in
                if action == .reorder {
                    ExerciseOrderSheet(entries: entries, save: reorder)
                } else if action == .replace {
                    TrainingReplacementPicker(history: history, currentID: entries.indices.contains(pendingIndex) ? entries[pendingIndex]["id"] as? String : nil) { exercise in
                        guard entries.indices.contains(pendingIndex) else { return }
                        change("replace", pendingIndex, 0, exercise.id)
                        picker = nil
                    }
                } else {
                    ExercisePicker(title: "添加动作") { exercise in
                        change("add", selected, 0, exercise.id)
                        picker = nil
                    }
                }
            }
            .confirmationDialog("删除此动作？", isPresented: $confirmRemoval, titleVisibility: .visible) {
                Button("删除动作及其组记录", role: .destructive) { change("remove", pendingIndex, 0, nil) }
                Button("取消", role: .cancel) {}
            } message: { Text("将从本次训练移除此动作和已填写的组记录，原训练计划不受影响。") }
    }

}

/// Dragging edits only this sheet's snapshot. Apply the complete permutation once.
struct ExerciseOrderSheet: View {
    @Environment(GymStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var entries: [[String: Any]]
    private let save: ([Int], [[String: Any]]) throws -> Void
    @State private var order: [Int]
    @State private var error: String?

    init(entries: [[String: Any]], save: @escaping ([Int], [[String: Any]]) throws -> Void) {
        _entries = State(initialValue: entries)
        self.save = save
        _order = State(initialValue: Array(entries.indices))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(order, id: \.self) { index in
                        let entry = entries[index]
                        HStack(spacing: 12) {
                            ExerciseThumbnail(id: entry["id"] as? String ?? "", size: 44)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(store.exercise(entry["id"] as? String ?? "")?.recordName ?? entry["id"] as? String ?? "动作")
                                if let group = entry["sg"] as? String, !group.isEmpty {
                                    Label("超级组", systemImage: "link").font(.caption).foregroundStyle(GymTheme.green)
                                }
                            }
                        }.accessibilityIdentifier("exercise-order-row-\(index)")
                    }.onMove { order.move(fromOffsets: $0, toOffset: $1) }
                } footer: {
                    Text("拖动右侧手柄调整顺序，点击保存后生效。拆开的超级组会解除组合。")
                }
            }.environment(\.editMode, .constant(.active))
                .navigationTitle("顺序调整").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") {
                            do { try save(order, entries); dismiss() }
                            catch { self.error = error.localizedDescription }
                        }.accessibilityIdentifier("save-exercise-order")
                    }
                }
                .alert("无法保存顺序", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                    Button("知道了", role: .cancel) {}
                } message: { Text(error ?? "") }
        }.tint(GymTheme.green).presentationDragIndicator(.visible)
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
        ExercisePicker(title: "更换动作", selectionIcon: "arrow.triangle.2.circlepath") { exercise in
            guard exercise.id != currentID else { return }
            selected = exercise; confirming = true
        }.confirmationDialog("更换此动作？", isPresented: $confirming, titleVisibility: .visible) {
            Button("更换动作") { if let selected { replace(selected) } }
            Button("取消", role: .cancel) { selected = nil }
        } message: {
            Text(history ? "组记录会保留，并归到新动作。提交后重新计算训练量与纪录。" : "已经完成的组或单侧会保留，新动作加入其后。未完成的动作会直接替换；仅修改本次训练。")
        }
    }
}

struct LiveExerciseManagement<WorkoutActions: View>: View {
    @Environment(GymStore.self) private var store
    var showExerciseNote: () -> Void
    @ViewBuilder let workoutActions: () -> WorkoutActions
    var body: some View {
        if let draft = store.draft {
            let index = min(max(0, draft.activeJSON["cur"] as? Int ?? 0), max(0, draft.rawEntries.count - 1))
            ExerciseManagementControls(entries: draft.rawEntries, selected: index, timerRunning: store.workTimer != nil, startRest: { store.startExerciseRest(entry: index, seconds: Double($0)) }, showExerciseNote: showExerciseNote, menuTitle: "训练菜单", menuIcon: "ellipsis.circle", menuIdentifier: "workout-menu", reorder: { order, baseline in
                try store.reorderLiveExercises(order, expectedEntries: baseline, sessionID: draft.id)
            }, additionalActions: workoutActions) { action, targetIndex, direction, id in
                store.manageLiveExercise(action: action, index: targetIndex, direction: direction, id: id)
            }
        }
    }
}

extension GymStore {
    func reorderLiveExercises(_ order: [Int], expectedEntries: [[String: Any]], sessionID: String) throws {
        guard var draft, draft.id == sessionID,
              draft.rawEntries.map({ $0["nativeViewID"] as? String }) == expectedEntries.map({ $0["nativeViewID"] as? String }) else {
            throw APIError.response(0, "动作列表已变化，请重新打开顺序调整。")
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
    @Environment(GymStore.self) private var store
    @Binding var slot: [String: Any]
    let routineID: String
    @State private var picking = false
    @State private var error: String?
    var body: some View {
        Button { picking = true } label: {
            Label("更换", systemImage: "arrow.triangle.2.circlepath").font(.subheadline).frame(minHeight: 44)
        }.buttonStyle(.borderless).accessibilityIdentifier("replace-routine-exercise")
            .sheet(isPresented: $picking) {
                ExercisePicker(title: "更换动作", selectionIcon: "arrow.triangle.2.circlepath") { exercise in
                    do {
                        guard let result = try WebRules.shared.call("replaceNativeRoutineExercise", payload: ["slot": slot, "id": exercise.id, "state": store.state, "rid": routineID]) as? [String: Any] else { throw APIError.invalidResponse }
                        slot = result; picking = false
                    } catch { self.error = error.localizedDescription; picking = false }
                }
            }
            .alert("无法更换动作", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("知道了", role: .cancel) {}
            } message: { Text(error ?? "") }
    }
}
