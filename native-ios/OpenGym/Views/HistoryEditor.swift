import SwiftUI

struct HistoryEditor: View {
    @Environment(GymStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var inputBuffer = InputCommitBuffer()
    let record: WorkoutRecord
    let unit: String
    @State private var form: HistoryForm
    @State private var restored = false
    @State private var detail: Exercise?
    @State private var error: String?
    @State private var deleting = false
    @State private var submitting = false
    @State private var confirmOverwrite = false
    @State private var exerciseNoteID: UUID?
    @State private var exerciseSheet: ExerciseSheet?
    private enum ExerciseSheet: String, Identifiable {
        case add, reorder
        var id: String { rawValue }
    }
    @State private var undoEntries: [HistoryEntryDraft]?
    @State private var undoExpected: [[String: Any]]?
    init(record: WorkoutRecord, unit: String) {
        self.record = record; self.unit = unit
        _form = State(initialValue: HistoryForm(original: record.raw, unit: unit))
    }
    private func textBinding(_ key: WritableKeyPath<HistoryForm, String>) -> Binding<String> {
        Binding(get: { form[keyPath: key] }, set: { form[keyPath: key] = $0; persist() })
    }
    private func persist() {
        inputBuffer.commitAll()
        guard restored else { return }
        if store.historyEdits[record.id] == nil && RecordPatch.equal(form.original,form.proposed) { return }
        store.keepHistoryEdit(original: form.original, proposed: form.proposed, unit: form.unit, form: form.fields)
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    workoutInformation
                    if form.entries.isEmpty {
                        Button(L10n.text("ADD_EXERCISE" /* 添加动作 */), systemImage: "plus") { inputBuffer.commitAll(); exerciseSheet = .add }
                            .accessibilityIdentifier("empty-history-add-exercise")
                    }
                    ForEach(Array(form.entries.enumerated()), id: \.element.id) { index, _ in
                        entryCard(index)
                    }
                }.padding(20)
            }.scrollDismissesKeyboard(.interactively)
                .disabled(submitting).background(GymTheme.background)
                .navigationTitle(L10n.text("EDIT_WORKOUT" /* 编辑训练 */)).navigationBarTitleDisplayMode(.inline)
                .keyboardDismissToolbar()
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { Button(L10n.text("TURN_OFF" /* 关闭 */)) { persist(); if store.localSaveError == nil { dismiss() } else { error = store.localSaveError } } }
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button(L10n.text("ADD_EXERCISE" /* 添加动作 */), systemImage: "plus") { inputBuffer.commitAll(); exerciseSheet = .add }
                                .accessibilityIdentifier("add-workout-exercise")
                            Button(L10n.text("REORDER_EXERCISES" /* 调整动作顺序 */), systemImage: "arrow.up.arrow.down") { inputBuffer.commitAll(); exerciseSheet = .reorder }
                                .disabled(form.entries.count < 2).accessibilityIdentifier("reorder-exercises")
                            Divider()
                            if let issue = store.localSaveError {
                                Button(L10n.text("SAVE_ERROR_DETAILS" /* 保存失败详情 */), systemImage: "exclamationmark.circle") { error = issue }
                                Button(L10n.text("RETRY_LOCAL_SAVE" /* 重试本机保存 */)) { persist() }
                            }
                            Button(submitting ? L10n.text("SUBMITTING" /* 提交中 */) : L10n.text("SAVE_AND_SUBMIT" /* 保存并提交 */)) { Task { await submit() } }.accessibilityIdentifier("save-history")
                            Button(L10n.text("OVERWRITE_WITH_LOCAL_EDITS" /* 用本机修改覆盖 */)) { persist(); confirmOverwrite = true }
                                .accessibilityIdentifier("overwrite-history")
                            Divider()
                            WorkoutPersonalActions(record:WorkoutRecord(raw:form.proposed)) { inputBuffer.commitAll(); deleting = true }
                        } label: { Image(systemName: store.localSaveError == nil ? "ellipsis.circle" : "exclamationmark.circle")
                            .foregroundStyle(store.localSaveError == nil ? GymTheme.green : .orange).frame(width: 44, height: 44) }.accessibilityLabel(L10n.text("RECORD_MENU" /* 记录菜单 */)).accessibilityIdentifier("history-record-menu").disabled(submitting)
                    }
                }
                .onAppear {
                    guard !restored else { return }
                    form = HistoryForm(original: record.raw, unit: unit, saved: store.historyEdits[record.id]); restored = true
                }
                .sheet(item: $detail) { ExerciseDetail(exercise: $0) }
                .sheet(item: $exerciseSheet) { action in
                    switch action {
                    case .add:
                        ExercisePicker(title: L10n.text("ADD_EXERCISE" /* 添加动作 */)) { exercise in
                            manageExercise(action: "add", index: form.selected, direction: 0, id: exercise.id)
                            exerciseSheet = nil
                        }
                    case .reorder:
                        ExerciseOrderSheet(entries: form.entries.map(\.value), save: reorderExercises)
                    }
                }
                .confirmationDialog(L10n.text("DELETE_THIS_WORKOUT" /* 删除训练记录？ */),isPresented:$deleting,titleVisibility:.visible) {
                    Button(L10n.text("DELETE" /* 删除 */),role:.destructive) {
                        Task {
                            if await store.deletePersonalWorkout(WorkoutRecord(raw:form.original)) { dismiss() }
                            else { error = store.editError }
                        }
                    }
                } message: {
                    Text(L10n.text("THIS_CANNOT_BE_UNDONE_OTHER_WORKOUTS_ARE_KEPT_AND_RELATED_PERSONAL_RECORDS" /* 删除后无法撤销；其他训练保留，并重新核对相关个人纪录。有本机编辑草稿时，请先保存并提交后再删除。 */))
                }
                .alert(L10n.text("YOUR_INPUT_HAS_BEEN_KEPT" /* 内容已保留 */), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button(L10n.text("GOT_IT" /* 知道了 */), role: .cancel) {} } message: { Text(error ?? "") }
                .confirmationDialog(L10n.text("OVERWRITE_WITH_LOCAL_EDITS" /* 用本机修改覆盖 */), isPresented: $confirmOverwrite, titleVisibility: .visible) {
                    Button(L10n.text("BACK_UP_AND_OVERWRITE" /* 备份后覆盖 */), role: .destructive) { Task { await submit(overwrite: true) } }
                        .accessibilityIdentifier("confirm-overwrite-history")
                } message: { Text(L10n.text("OVERWRITE_WORKOUT_AFTER_BACKUP" /* 先保存服务器快照，再以本机修改覆盖这条训练的冲突内容。其他记录保留；若此训练已删除，将重新创建。 */)) }
                .interactiveDismissDisabled(submitting || store.localSaveError != nil)
        }.tint(GymTheme.green)
            .environment(\.inputCommitBuffer, inputBuffer)
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { inputBuffer.commitAll() }
            }
            .onDisappear { inputBuffer.commitAll() }
    }
    private var workoutInformation: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.text("WORKOUT_INFORMATION" /* 训练信息 */)).font(.headline)
            BufferedTextField(L10n.text("WORKOUT_TITLE" /* 训练标题 */), text: textBinding(\.name)).textFieldStyle(.plain).stableInputLine().submitLabel(.done).onSubmit { GymKeyboard.dismiss() }.accessibilityIdentifier("history-name")
            DatePicker(L10n.text("DATE_AND_START_TIME" /* 日期和开始时间 */), selection: Binding(get: { form.date }, set: { inputBuffer.commitAll(); form.date = $0; persist() }), in: ...Date(), displayedComponents: [.date, .hourAndMinute]).environment(\.locale, L10n.locale)
            HStack { Text(L10n.text("DURATION_MIN" /* 时长（分钟） */)); Spacer(); BufferedTextField(L10n.text("MINUTES" /* 分钟 */), text: textBinding(\.minutes)).textFieldStyle(.plain).stableInputLine().submitLabel(.done).onSubmit { GymKeyboard.dismiss() }.keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 100) }
            BufferedTextField(L10n.text("SESSION_NOTE" /* 训练备注 */), text: textBinding(\.note), axis: .vertical).textFieldStyle(.plain).submitLabel(.done).onSubmit { GymKeyboard.dismiss() }.lineLimit(2...5).accessibilityIdentifier("history-note")
        }.gymCard()
    }
    private func exerciseManagement(_ index: Int) -> some View {
        ExerciseManagementControls(entries: form.entries.map(\.value), selected: index, history: true, showExerciseNote: { inputBuffer.commitAll(); exerciseNoteID = form.entries[index].id }, change: manageExercise)
    }
    private func reorderExercises(_ order: [Int], baseline: [[String: Any]]) throws {
        inputBuffer.commitAll()
        guard RecordPatch.equal(baseline, form.entries.map(\.value)) else { throw APIError.response(0, L10n.text("THE_EXERCISE_LIST_HAS_CHANGED_OPEN_THE_REORDER_SCREEN_AGAIN" /* 动作列表已变化，请重新打开顺序调整。 */)) }
        try form.reorderExercises(order)
        persist()
        if let issue = store.localSaveError { throw APIError.response(0, issue) }
    }
    private func manageExercise(action: String, index: Int, direction: Int, id: String?) {
        inputBuffer.commitAll()
        do { try form.manageExercise(action: action, index: index, direction: direction, id: id, state: store.state); persist() }
        catch { self.error = error.localizedDescription }
    }
    private func entryName(_ i: Int) -> String { store.exercise(form.entries[i].raw["id"] as? String ?? "")?.recordName ?? L10n.text("EXERCISE" /* 动作 */) }
    @ViewBuilder private func entryCard(_ i: Int) -> some View {
        if form.entries.indices.contains(i) {
            let entry = form.entries[i]
            let previous = store.previousExerciseReference(entry.raw, before: number(form.original["start"]), exclude: record.id)
            TrainingExerciseEditor(
                showingOptions: Binding(get: { exerciseNoteID == entry.id }, set: { showing in
                    if showing { exerciseNoteID = entry.id }
                    else if exerciseNoteID == entry.id { exerciseNoteID = nil }
                }), entries: form.entries.map(\.value), names: form.entries.indices.map(entryName),
                selected: .constant(i),
                rows: entry.sets.map { TrainingEditorRow(id: $0.id.uuidString, raw: $0.raw) },
                unit: form.unit, inputState: store.state.merging(["unit": form.unit]) { _, new in new }, previous: previous.text, previousNote: previous.note,
                note: Binding(get: { form.entries[i].raw["note"] as? String ?? "" }, set: { form.entries[i].raw["note"] = $0; persist() }),
                identifier: "history", allowsEntryNavigation: false, entryIdentity: entry.id.uuidString,
                showDetails: { inputBuffer.commitAll(); detail = store.exercise(entry.raw["id"] as? String ?? "") },
                addSet: { addSet(entry: i) },
                copySet: { index in
                    inputBuffer.commitAll()
                    do { try form.entries[i].copySet(at: index); persist() }
                    catch { self.error = error.localizedDescription }
                },
                removeSet: { removeSet(entry: i, setID: entry.sets[$0].id) },
                editSet: { editSet(entry: i, setID: entry.sets[$0].id, action: $1) },
                undoRemove: undoEntries != nil && RecordPatch.equal(undoExpected, form.entries.map(\.value)) ? {
                    inputBuffer.commitAll()
                    guard RecordPatch.equal(undoExpected, form.entries.map(\.value)) else { return }
                    if let undoEntries { form.entries = undoEntries; self.undoEntries = nil; persist() }
                } : nil,
                exerciseActions: { exerciseManagement(i) }
            ) { EmptyView() }
        }
    }
    private func editSet(entry: Int, setID: UUID, action: [String: Any]) {
        inputBuffer.commitAll()
        guard form.entries.indices.contains(entry), let index = form.entries[entry].sets.firstIndex(where: { $0.id == setID }) else { return }
        do {
            var inputState = store.state; inputState["unit"] = form.unit
            form.entries[entry].sets[index].raw = try TrainingInput.edit(row: form.entries[entry].sets[index].raw, action: action, target: form.entries[entry].raw["target"] as? [String: Any] ?? [:], state: inputState, editing: true)
            persist()
        } catch { self.error = error.localizedDescription }
    }
    private func addSet(entry: Int) {
        inputBuffer.commitAll()
        do { try form.entries[entry].addSet(); persist() }
        catch { self.error = error.localizedDescription }
    }
    private func removeSet(entry: Int, setID: UUID) {
        inputBuffer.commitAll()
        do {
            let before = form.entries
            try form.entries[entry].removeSet(id: setID)
            undoEntries = before; undoExpected = form.entries.map(\.value); persist()
        }
        catch { self.error = error.localizedDescription }
    }
    private func submit(overwrite: Bool = false) async {
        guard !submitting, !store.syncing else { return }
        submitting = true; defer { submitting = false }
        persist()
        guard TrainingInput.value(form.minutes) != nil else { error = L10n.text("ENTER_A_VALID_DURATION_YOUR_INPUT_HAS_BEEN_KEPT" /* 请填写有效的时长，输入内容已保留。 */); return }
        if await store.saveWorkout(original: form.original, proposed: form.proposed, expectedUnit: form.unit, overwrite: overwrite) { dismiss() }
        else { error = store.editError ?? store.localSaveError }
    }
}
