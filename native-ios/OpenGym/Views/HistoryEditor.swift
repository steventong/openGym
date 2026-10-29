import SwiftUI

struct HistoryEditor: View {
    @Environment(GymStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let record: WorkoutRecord
    let unit: String
    @State private var form: HistoryForm
    @State private var restored = false
    @State private var detail: Exercise?
    @State private var error: String?
    @State private var undoEntries: [HistoryEntryDraft]?
    @State private var undoExpected: [[String: Any]]?
    init(record: WorkoutRecord, unit: String) {
        self.record = record; self.unit = unit
        _form = State(initialValue: HistoryForm(original: record.raw, unit: unit))
    }
    private var binding: Binding<HistoryForm> {
        Binding(get: { form }, set: { form = $0; persist() })
    }
    private func persist() {
        guard restored else { return }
        if store.historyEdits[record.id] == nil && RecordPatch.equal(form.original,form.proposed) { return }
        store.keepHistoryEdit(original: form.original, proposed: form.proposed, unit: form.unit, form: form.fields)
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("训练信息").font(.headline)
                        TextField("训练名称", text: binding.name).accessibilityIdentifier("history-name")
                        DatePicker("日期和开始时间", selection: binding.date, in: ...Date(), displayedComponents: [.date, .hourAndMinute]).environment(\.locale, Locale(identifier: "zh_CN"))
                        HStack { Text("时长（分钟）"); Spacer(); TextField("分钟", text: binding.minutes).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 100) }
                        TextField("训练备注", text: binding.note, axis: .vertical).lineLimit(2...5).accessibilityIdentifier("history-note")
                    }.gymCard()
                    ExerciseManagementControls(entries: form.entries.map(\.value), selected: form.selected, history: true) { action, index, direction, id in
                        do { try form.manageExercise(action: action, index: index, direction: direction, id: id, state: store.state); persist() }
                        catch { self.error = error.localizedDescription }
                    }
                    if !form.entries.isEmpty { entryCard(form.selected) }
                    VStack(alignment: .leading, spacing: 8) {
                        if let issue = store.localSaveError { Text(issue).foregroundStyle(.orange); Button("重试本机保存") { persist() } }
                        else { Text(store.historyEdits[record.id] == nil ? "编辑后会自动保存到本机。" : "已保存到本机，右上角菜单可提交。离线或提交失败后可以再次提交。") }
                    }.font(.caption)
                }.padding(20)
            }.scrollDismissesKeyboard(.interactively).background(GymTheme.background).disabled(store.syncing)
                .navigationTitle("编辑训练记录").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { Button("关闭") { persist(); if store.localSaveError == nil { dismiss() } else { error = store.localSaveError } }.disabled(store.syncing) }
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button("保存并提交") { Task { await submit() } }.accessibilityIdentifier("save-history")
                        } label: { Image(systemName: "ellipsis.circle").frame(width: 44, height: 44) }.disabled(store.syncing).accessibilityLabel("记录菜单")
                    }
                }
                .onAppear {
                    guard !restored else { return }
                    form = HistoryForm(original: record.raw, unit: unit, saved: store.historyEdits[record.id]); restored = true
                }
                .sheet(item: $detail) { ExerciseDetail(exercise: $0) }
                .alert("内容已保留", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("知道了", role: .cancel) {} } message: { Text(error ?? "") }
                .interactiveDismissDisabled(store.syncing || store.localSaveError != nil)
        }.tint(GymTheme.green)
    }
    private func entryName(_ i: Int) -> String { store.exercise(form.entries[i].raw["id"] as? String ?? "")?.recordName ?? "动作" }
    @ViewBuilder private func entryCard(_ i: Int) -> some View {
        if form.entries.indices.contains(i) {
            let entry = form.entries[i]
            TrainingExerciseEditor(
                entries: form.entries.map(\.value), names: form.entries.indices.map(entryName),
                selected: binding.selected,
                rows: entry.sets.map { TrainingEditorRow(id: $0.id.uuidString, raw: $0.raw) },
                unit: form.unit, inputState: store.state.merging(["unit": form.unit]) { _, new in new }, previous: store.previousExerciseText(entry.raw, before: number(form.original["start"]), exclude: record.id),
                note: Binding(get: { form.entries[i].raw["note"] as? String ?? "" }, set: { form.entries[i].raw["note"] = $0; persist() }),
                identifier: "history",
                showDetails: { detail = store.exercise(entry.raw["id"] as? String ?? "") },
                addSet: { addSet(entry: i) },
                copySet: { index in
                    do { try form.entries[i].copySet(at: index); persist() }
                    catch { self.error = error.localizedDescription }
                },
                removeSet: { removeSet(entry: i, setID: entry.sets[$0].id) },
                editSet: { editSet(entry: i, setID: entry.sets[$0].id, action: $1) },
                undoRemove: undoEntries != nil && RecordPatch.equal(undoExpected, form.entries.map(\.value)) ? {
                    if let undoEntries { form.entries = undoEntries; self.undoEntries = nil; persist() }
                } : nil
            ) { EmptyView() }
        }
    }
    private func editSet(entry: Int, setID: UUID, action: [String: Any]) {
        guard form.entries.indices.contains(entry), let index = form.entries[entry].sets.firstIndex(where: { $0.id == setID }) else { return }
        do {
            var inputState = store.state; inputState["unit"] = form.unit
            form.entries[entry].sets[index].raw = try TrainingInput.edit(row: form.entries[entry].sets[index].raw, action: action, target: form.entries[entry].raw["target"] as? [String: Any] ?? [:], state: inputState, editing: true)
            persist()
        } catch { self.error = error.localizedDescription }
    }
    private func addSet(entry: Int) {
        do { try form.entries[entry].addSet(); persist() }
        catch { self.error = error.localizedDescription }
    }
    private func removeSet(entry: Int, setID: UUID) {
        do {
            let before = form.entries
            try form.entries[entry].removeSet(id: setID)
            undoEntries = before; undoExpected = form.entries.map(\.value); persist()
        }
        catch { self.error = error.localizedDescription }
    }
    private func submit() async {
        persist()
        guard TrainingInput.value(form.minutes) != nil else { error = "请填写有效的时长，输入内容已保留。"; return }
        if await store.saveWorkout(original: form.original, proposed: form.proposed, expectedUnit: form.unit) { dismiss() }
        else { error = store.editError ?? store.localSaveError }
    }
}
