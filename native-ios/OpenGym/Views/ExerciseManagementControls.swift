import SwiftUI

/// The same discoverable actions for live sessions and historical corrections.
struct ExerciseManagementControls: View {
    let entries: [[String: Any]]
    let selected: Int
    var history = false
    var timerRunning = false
    var startRest: ((Int) -> Void)? = nil
    let change: (String, Int, Int, String?) -> Void
    @State private var picker: PickerAction?
    @State private var confirmRemoval = false
    @State private var pendingIndex = 0

    private enum PickerAction: String, Identifiable {
        case add, replace
        var id: String { rawValue }
    }
    var body: some View {
        Menu {
            Button("添加动作", systemImage: "plus") { picker = .add }
            if entries.indices.contains(selected) {
                Button("更换动作", systemImage: "arrow.triangle.2.circlepath") { pendingIndex = selected; picker = .replace }
                Button("上移", systemImage: "arrow.up") { change("move", selected, -1, nil) }.disabled(selected == 0)
                Button("下移", systemImage: "arrow.down") { change("move", selected, 1, nil) }.disabled(selected + 1 >= entries.count)
                if let startRest {
                    Menu("设置并开始休息") {
                        ForEach([30, 60, 90, 120, 180, 300], id: \.self) { seconds in Button("\(seconds) 秒") { startRest(seconds) } }
                    }.disabled(timerRunning)
                }
                Section("超级组") {
                    if selected > 0 { Button("与上一个动作组合") { change("pair", selected, -1, nil) }.disabled(timerRunning) }
                    if selected + 1 < entries.count { Button("与下一个动作组合") { change("pair", selected, 1, nil) }.disabled(timerRunning) }
                    if entries[selected]["sg"] != nil { Button("移出超级组") { change("unpair", selected, 0, nil) }.disabled(timerRunning) }
                }
                Button("删除动作", systemImage: "trash", role: .destructive) { pendingIndex = selected; confirmRemoval = true }
            }
        } label: {
            Image(systemName: "slider.horizontal.3").frame(width: 44, height: 44)
        }.font(.subheadline).buttonStyle(.borderless).accessibilityLabel("动作管理").accessibilityIdentifier("training-exercise-options")
            .sheet(item: $picker) { action in
                if action == .replace {
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

private struct TrainingReplacementPicker: View {
    let history: Bool
    let currentID: String?
    let replace: (Exercise) -> Void
    @State private var selected: Exercise?
    @State private var confirming = false
    var body: some View {
        ExercisePicker(title: "更换动作") { exercise in
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

struct LiveExerciseManagement: View {
    @Environment(GymStore.self) private var store
    var body: some View {
        if let draft = store.draft {
            let index = min(max(0, draft.activeJSON["cur"] as? Int ?? 0), max(0, draft.rawEntries.count - 1))
            ExerciseManagementControls(entries: draft.rawEntries, selected: index, timerRunning: store.workTimer != nil, startRest: { store.startExerciseRest(entry: index, seconds: Double($0)) }) { action, targetIndex, direction, id in
                store.manageLiveExercise(action: action, index: targetIndex, direction: direction, id: id)
            }
        }
    }
}

extension GymStore {
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
                ExercisePicker(title: "更换动作") { exercise in
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
