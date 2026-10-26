import SwiftUI

struct HistoryEditor: View {
    @Environment(GymStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let record: WorkoutRecord
    let unit: String
    @State private var form: HistoryForm
    @State private var restored = false
    @State private var pick = false
    @State private var error: String?
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
            List {
                Section("训练信息") {
                    TextField("训练名称", text: binding.name).accessibilityIdentifier("history-name")
                    DatePicker("日期和开始时间", selection: binding.date, in: ...Date(), displayedComponents: [.date, .hourAndMinute]).environment(\.locale, Locale(identifier: "zh_CN"))
                    HStack { Text("时长（分钟）"); Spacer(); TextField("分钟", text: binding.minutes).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 100) }
                    TextField("训练备注", text: binding.note, axis: .vertical).lineLimit(2...5).accessibilityIdentifier("history-note")
                }
                if !form.entries.isEmpty {
                    Section {
                        Picker("选择动作", selection: binding.selected) {
                            ForEach(form.entries.indices, id: \.self) { i in
                                Text("\(i + 1).\(entryName(i))").tag(i)
                            }
                        }.pickerStyle(.menu).accessibilityIdentifier("history-exercise-selector")
                    }
                    entryCard(form.selected)
                }
                Section { Button { pick = true } label: { Label("添加动作", systemImage: "plus.circle") } }
                Section {
                    if let issue = store.localSaveError { Text(issue).foregroundStyle(.orange); Button("重试本机保存") { persist() } }
                    else { Text(store.historyEdits[record.id] == nil ? "编辑后会自动保存到本机。" : "已保存到本机，右上角菜单可提交。离线或提交失败后可以再次提交。") }
                }.font(.caption)
            }.disabled(store.syncing)
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
                .sheet(isPresented: $pick) { ExercisePicker { ex in
                    form.entries.append(HistoryEntryDraft(["id": ex.id, "sets": [["w": 0, "r": 10, "done": true, "phase": "work"]]]))
                    form.selected = form.entries.count - 1; persist(); pick = false
                } }
                .alert("内容已保留", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("知道了", role: .cancel) {} } message: { Text(error ?? "") }
                .interactiveDismissDisabled(store.syncing || store.localSaveError != nil)
        }.tint(GymTheme.green)
    }
    private func entryName(_ i: Int) -> String { store.exercise(form.entries[i].raw["id"] as? String ?? "")?.recordName ?? "动作" }
    private func completed(_ i: Int) -> Bool { form.entries[i].sets.contains { rawCompleted($0.raw) } }
    @ViewBuilder private func entryCard(_ i: Int) -> some View {
        if form.entries.indices.contains(i) {
            Section {
                Text("\(i + 1).\(entryName(i))").font(.headline)
                TextField("动作备注", text: Binding(get: { form.entries[i].raw["note"] as? String ?? "" }, set: { form.entries[i].raw["note"] = $0; persist() }), axis: .vertical)
                ScrollView(.horizontal,showsIndicators:false) {
                    Text(store.previousExerciseText(form.entries[i].raw,before:number(form.original["start"]),exclude:record.id)).font(.caption).foregroundStyle(.secondary).lineLimit(1).fixedSize(horizontal:true,vertical:false)
                }
                ForEach(binding.entries[i].sets) { row in
                    let set = row.wrappedValue
                    VStack(alignment: .leading, spacing: 10) {
                        AdvancedSetEditor(row: set.raw, target: form.entries[i].raw["target"] as? [String: Any] ?? [:], unit: form.unit, identifier: set.id.uuidString) { action in
                            do {
                                row.wrappedValue.raw = try TrainingInput.edit(row: row.wrappedValue.raw, action: action, target: form.entries[i].raw["target"] as? [String: Any] ?? [:], state: store.state, editing: true)
                            } catch { self.error = error.localizedDescription }
                        }
                        Button("移除此组", role: .destructive) { form.entries[i].sets.removeAll { $0.id == set.id }; persist() }.buttonStyle(.borderless).font(.caption)
                    }
                }
                Button("添加普通组") {
                    let last = form.entries[i].sets.last?.raw ?? [:]
                    form.entries[i].sets.append(RawRow(raw: ["w": number(last["w"]), "r": max(1, number(last["r"] ?? 10)), "done": true, "phase": "work", "mode": "reps"])); persist()
                }.buttonStyle(.borderless)
                Button("移除此动作", role: .destructive) { form.entries.remove(at: i); form.selected = min(i, max(0, form.entries.count - 1)); persist() }.buttonStyle(.borderless)
            } header: { Text("动作 \(i + 1) / \(form.entries.count) · \(completed(i) ? "已练" : "待练")") }
        }
    }
    private func submit() async {
        persist()
        guard TrainingInput.value(form.minutes) != nil else { error = "请填写有效的时长，输入内容已保留。"; return }
        if await store.saveWorkout(original: form.original, proposed: form.proposed, expectedUnit: form.unit) { dismiss() }
        else { error = store.editError ?? store.localSaveError }
    }
}
