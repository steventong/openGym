import SwiftUI
struct RoutineEditor: View {
    @Environment(GymStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var inputBuffer = InputCommitBuffer()
    @State private var original: [String:Any]
    let expectedUnit: String
    @State private var name: String
    @State private var rows: [RawRow]
    @State private var pick = false
    @State private var sorting = false
    @State private var configuration: RawRow?
    @State private var discard = false
    @State private var confirmDelete = false
    @State private var deleting = false
    @State private var saving = false
    @State private var errorTitle = L10n.text("COULD_NOT_SAVE" /* 无法保存 */)
    @State private var error: String?
    init(routine:Routine,unit:String) {
        _original = State(initialValue: routine.raw); expectedUnit = unit
        _name = State(initialValue:routine.name); _rows = State(initialValue:routine.exercises.map { RawRow(raw:$0) })
    }
    private var proposed:[String:Any] { var r = original; r["name"] = name.trimmingCharacters(in:.whitespacesAndNewlines); r["ex"] = rows.map(\.raw); return r }
    private var dirty: Bool { inputBuffer.hasPending || !RecordPatch.equal(original,proposed) }
    var body: some View {
        NavigationStack {
            List {
                Section(L10n.text("ROUTINE_NAME" /* 计划名称 */)) { BufferedTextField(L10n.text("ROUTINE_NAME" /* 计划名称 */),text:$name).textFieldStyle(.plain).stableInputLine().submitLabel(.done).onSubmit { GymKeyboard.dismiss() }.accessibilityIdentifier("edit-routine-name") }
                Section {
                    ForEach($rows) { $row in
                        VStack(alignment:.leading,spacing:14) {
                            HStack {
                                ExerciseThumbnail(id:row.raw["id"] as? String ?? "",size:46)
                                Text(store.exercise(row.raw["id"] as? String ?? "")?.name ?? row.raw["id"] as? String ?? L10n.text("EXERCISE" /* 动作 */)).font(.headline)
                                Spacer()
                                RoutineExerciseReplacement(slot: $row.raw, routineID: original["id"] as? String ?? "")
                            }
                            if EditValidation.ordinaryConfig(row.raw) {
                                HStack {
                                    numeric(L10n.text("SETS" /* 组数 */),key:"sets",fallback:3,row:$row)
                                    numeric(L10n.text("REPS" /* 次数 */),key:"reps",fallback:10,row:$row)
                                    numeric(expectedUnit,key:"weight",fallback:0,row:$row)
                                }
                                Stepper(L10n.text("REST_BETWEEN_SETS_COUNT_SECONDS" /* 组间休息 {0} 秒 */, Int(number(row.raw["restSec"] ?? 90))),value:Binding(get:{Int(number(row.raw["restSec"] ?? 90))},set:{row.raw["restSec"] = $0}),in:0...900,step:15).font(.subheadline)
                            } else { Text(L10n.text("ADVANCED_SET_TYPES" /* 高级组型 */)).font(.caption).foregroundStyle(.secondary) }
                            Button { inputBuffer.commitAll(); configuration = rows.first { $0.id == row.id } } label: { Label(L10n.text("ADVANCED_SETS_AND_TIMERS" /* 高级组型与计时 */),systemImage:"slider.horizontal.3") }.buttonStyle(.borderless).accessibilityIdentifier("advanced-slot-\(row.raw["id"] as? String ?? "")")
                            if row.raw["sg"] != nil { Label(L10n.text("SUPERSET" /* 超级组 */),systemImage:"link").font(.caption).foregroundStyle(GymTheme.green) }
                            HStack {
                                if rows.last?.id != row.id { Button(L10n.text("MAKE_SUPERSET_WITH_NEXT" /* 与下一个组成超级组 */)) { group(row.id,"pair") }.font(.caption).buttonStyle(.borderless) }
                                if row.raw["sg"] != nil { Button(L10n.text("UNPAIR" /* 取消组合 */)) { group(row.id,"unpair") }.font(.caption).buttonStyle(.borderless) }
                            }
                            BufferedTextField(L10n.text("EXERCISE_NOTES" /* 动作备注 */),text:Binding(get:{row.raw["note"] as? String ?? ""},set:{row.raw["note"] = $0})).textFieldStyle(.plain).stableInputLine().submitLabel(.done).onSubmit { GymKeyboard.dismiss() }.font(.subheadline)
                            HStack {
                                Button { inputBuffer.commitAll(); sorting = true } label: { Label(L10n.text("REORDER_EXERCISES" /* 调整动作顺序 */), systemImage: "arrow.up.arrow.down").frame(minHeight: 48) }.disabled(rows.count < 2)
                                Spacer()
                                Button(role:.destructive) { inputBuffer.commitAll(); let id = row.id; rows.removeAll { $0.id == id } } label: { Image(systemName:"minus.circle") }.accessibilityLabel(L10n.text("REMOVE_EXERCISE" /* 移除动作 */))
                            }.font(.caption).buttonStyle(.borderless)
                        }.padding(.vertical,7)
                    }.onDelete { inputBuffer.commitAll(); rows.remove(atOffsets:$0) }
                    Button { inputBuffer.commitAll(); pick = true } label: { Label(L10n.text("ADD_EXERCISE" /* 添加动作 */),systemImage:"plus.circle.fill") }.accessibilityIdentifier("edit-add-exercise")
                } header: { Text(L10n.text("EXERCISE_COUNT" /* 动作 · {0} */, rows.count)) }
                Section {
                    Button(role:.destructive) { guard !saving, !deleting else { return }; confirmDelete = true } label: {
                        Label(deleting ? L10n.text("DELETING" /* 删除中 */) : L10n.text("DELETE_ROUTINE_A" /* 删除训练计划 */),systemImage:"trash")
                    }.accessibilityIdentifier("delete-routine")
                }
            }.navigationTitle(L10n.text("EDIT_ROUTINE" /* 编辑计划 */)).navigationBarTitleDisplayMode(.inline)
                .keyboardDismissToolbar()
                .toolbar {
                    ToolbarItem(placement:.topBarLeading) { Button(L10n.text("CANCEL" /* 取消 */)) { guard !saving, !deleting else { return }; inputBuffer.commitAll(); if dirty { discard = true } else { dismiss() } } }
                    ToolbarItem(placement:.topBarTrailing) { Button(saving ? L10n.text("SAVING" /* 正在保存 */) : L10n.text("SAVE" /* 保存 */)) { Task { await saveRoutine() } }.accessibilityIdentifier("save-routine-edit") }
                }
                .sheet(isPresented: $sorting) {
                    ExerciseOrderSheet(entries: rows.map(\.raw)) { order, baseline in
                        guard RecordPatch.equal(baseline, rows.map(\.raw)) else { throw APIError.response(0, L10n.text("THE_EXERCISE_LIST_HAS_CHANGED_OPEN_THE_REORDER_SCREEN_AGAIN" /* 动作列表已变化，请重新打开顺序调整。 */)) }
                        let result = try ExerciseOrder.apply(order, to: ["entries": rows.map(\.raw)])
                        guard let updated = result["entries"] as? [[String: Any]] else { throw APIError.invalidResponse }
                        let existing = rows
                        rows = order.enumerated().map { offset, index in
                            var row = existing[index]; row.raw = updated[offset]; return row
                        }
                    }
                }
                .sheet(item:$configuration) { selected in AdvancedConfigEditor(config:selected.raw,unit:expectedUnit) { updated in if let i = rows.firstIndex(where:{$0.id == selected.id}) { rows[i].raw = updated } } }
                .sheet(isPresented:$pick) { ExercisePicker { exercise in rows.append(RawRow(raw:["id":exercise.id,"sets":3,"reps":10,"weight":0,"restSec":90])); pick = false } }
                .alert(errorTitle,isPresented:Binding(get:{error != nil},set:{if !$0 { error = nil }})) { Button(L10n.text("GOT_IT" /* 知道了 */),role:.cancel) {} } message: { Text(error ?? "") }
                .confirmationDialog(L10n.text("DELETE_ROUTINE" /* 删除训练计划？ */),isPresented:$confirmDelete,titleVisibility:.visible) {
                    Button(L10n.text("DELETE_ROUTINE_A" /* 删除训练计划 */),role:.destructive) { Task { await deleteRoutine() } }
                    Button(L10n.text("CANCEL" /* 取消 */),role:.cancel) {}
                } message: {
                    Text(L10n.text("COUNT_AND_ITS_SCHEDULE_WILL_BE_DELETED_THIS_CANNOT_BE_UNDONE_YOUR" /* 将删除「{0}」及其排期，无法撤销。训练历史和正在进行的训练会保留。 */, original["name"] as? String ?? L10n.text("ROUTINES" /* 训练计划 */)) + (dirty ? L10n.text("YOUR_UNSAVED_CHANGES_WILL_BE_DISCARDED" /* 当前未保存的修改将被放弃。 */) : ""))
                }
                .confirmationDialog(L10n.text("DISCARD_UNSAVED_CHANGES" /* 放弃未保存的修改？ */),isPresented:$discard,titleVisibility:.visible) { Button(L10n.text("DISCARD_CHANGES" /* 放弃修改 */),role:.destructive) { dismiss() }; Button(L10n.text("KEEP_EDITING" /* 继续编辑 */),role:.cancel) {} }
                .interactiveDismissDisabled(dirty || saving || deleting)
        }.tint(GymTheme.green).environment(\.inputCommitBuffer, inputBuffer)
    }
    private func saveRoutine() async {
        inputBuffer.commitAll()
        guard !saving, !deleting, !store.syncing else { return }
        guard dirty else { dismiss(); return }
        saving = true; defer { saving = false }
        let snapshot = proposed
        if await store.saveRoutine(original: original, proposed: snapshot, expectedUnit: expectedUnit) {
            inputBuffer.commitAll()
            original = snapshot
            // Keep any edits entered while the request was in flight in this editor.
            if RecordPatch.equal(proposed, snapshot) { dismiss() }
        } else { errorTitle = L10n.text("COULD_NOT_SAVE" /* 无法保存 */); error = store.editError }
    }
    private func deleteRoutine() async {
        guard !saving, !deleting, let id = original["id"] as? String else { return }
        deleting = true; defer { deleting = false }
        if await store.deleteRoutine(id:id) { dismiss() }
        else { errorTitle = L10n.text("COULD_NOT_DELETE" /* 无法删除 */); error = store.editError }
    }
    private func group(_ id:UUID,_ operation:String,_ direction:Int = 0) {
        inputBuffer.commitAll()
        guard let i = rows.firstIndex(where:{$0.id == id}) else { return }
        do { let result = try WebRules.shared.call("planGroup",payload:["rows":rows.map(\.raw),"operation":operation,"index":i,"direction":direction]) as! [[String:Any]];rows = result.map { RawRow(raw:$0) } } catch { errorTitle = L10n.text("COULD_NOT_SAVE" /* 无法保存 */); self.error = error.localizedDescription }
    }
    private func numeric(_ title:String,key:String,fallback:Double,row:Binding<RawRow>) -> some View {
        VStack(alignment:.leading,spacing:5) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            BufferedNumberField(title,value:Binding(get:{number(row.wrappedValue.raw[key] ?? fallback)},set:{row.wrappedValue.raw[key] = $0})).textFieldStyle(.plain).stableInputLine().submitLabel(.done).onSubmit { GymKeyboard.dismiss() }.keyboardType(key == "weight" ? .decimalPad : .numberPad)
                .padding(9).background(.white.opacity(0.07),in:RoundedRectangle(cornerRadius:9)).accessibilityIdentifier("routine-\(key)-\(row.wrappedValue.raw["id"] as? String ?? "")")
        }
    }
}
struct ExercisePicker: View {
    @Environment(GymStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var searchReset = 0
    @State private var available:Set<String>?
    @State private var favouritesOnly = false
    @State private var trainedOnly = false
    @State private var customOnly = false
    @State private var bodyPart = ""
    @State private var equipment = ""
    @State private var limit = 60
    private let bodyParts = ["", "back", "cardio", "chest", "full body", "lower arms", "lower legs", "neck", "shoulders", "upper arms", "upper legs", "waist"]
    private var choices:[Exercise] {
        let favourites = store.favouriteIDs
        let trained = trainedOnly ? store.trainedExerciseIDs : []
        let customs = Set(store.customExercises.compactMap { $0["id"] as? String })
        let matching = store.exercises.filter {
            (search.isEmpty || $0.searchText.localizedCaseInsensitiveContains(search)) &&
            (!favouritesOnly || favourites.contains($0.id)) &&
            (!trainedOnly || trained.contains($0.id)) &&
            (!customOnly || customs.contains($0.id)) &&
            (bodyPart.isEmpty || $0.bodyPart == bodyPart) &&
            (equipment.isEmpty || $0.equipment == equipment) &&
            (available == nil || available!.contains($0.id))
        }
        return matching.filter {favourites.contains($0.id)} + matching.filter {!favourites.contains($0.id)}
    }
    private var equipments: [String] {
        [""] + Set(store.exercises.filter { bodyPart.isEmpty || $0.bodyPart == bodyPart }.map(\.equipment)).sorted()
    }
    var title = L10n.text("ADD_EXERCISE" /* 添加动作 */)
    var selectionIcon = "plus"
    let select:(Exercise)->Void
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    searchField
                    filters
                    let results = choices
                    HStack {
                        Text(L10n.text("COUNT_EXERCISES_FOUND" /* 找到 {0} 个动作 */, results.count))
                        Spacer()
                        if let error = store.catalogueError { StatusDetailButton(title: L10n.text("COULD_NOT_LOAD" /* 无法加载 */), message: error, warning: true) }
                        else { Label(L10n.text("EXERCISES" /* 动作库 */), systemImage: "checkmark.seal") }
                    }.font(.caption).foregroundStyle(GymTheme.muted)
                    if results.isEmpty {
                        EmptyCard(icon: "magnifyingglass", title: L10n.text("NO_EXERCISES_FOUND" /* 没有找到动作 */))
                        Button(L10n.text("CLEAR_SEARCH_AND_FILTERS" /* 清除搜索与筛选 */)) { resetFilters() }
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    LazyVStack(spacing: 10) {
                        ForEach(Array(results.prefix(limit))) { exercise in
                            Button { select(exercise) } label: {
                                ExerciseRow(exercise: exercise, accessoryIcon: selectionIcon)
                            }.buttonStyle(.plain)
                                .accessibilityIdentifier("pick-\(exercise.id)")
                        }
                        if results.count > limit { ExercisePageTrigger(limit: $limit, total: results.count).id(limit) }
                    }
                }.padding(20)
            }.background(GymTheme.background)
                .scrollDismissesKeyboard(.interactively)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(L10n.text("CANCEL" /* 取消 */)) { dismiss() } } }
                .onAppear { refreshEquipment() }
                .onChange(of: store.lastSync) { _, _ in refreshEquipment() }
                .onChange(of: search) { _, _ in limit = 60 }
                .onChange(of: bodyPart) { _, _ in limit = 60 }
                .onChange(of: equipment) { _, _ in limit = 60 }
                .onChange(of: favouritesOnly) { _, _ in limit = 60 }
                .onChange(of: trainedOnly) { _, _ in limit = 60 }
                .onChange(of: customOnly) { _, _ in limit = 60 }
        }.tint(GymTheme.green)
    }
    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(GymTheme.muted)
            CommittedSearchField(L10n.text("SEARCH_EXERCISES_MUSCLES" /* 搜索动作、肌群… */), text: $search, resetToken: searchReset).submitLabel(.search).onSubmit { GymKeyboard.dismiss() }
                .textFieldStyle(.plain).font(.system(size: 15)).autocorrectionDisabled()
                .accessibilityIdentifier("picker-search")
            if !search.isEmpty {
                Button { searchReset += 1; search = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.gray)
                }.accessibilityLabel(L10n.text("CLEAR_SEARCH" /* 清除搜索 */))
            }
        }.padding(.horizontal, 14).frame(height: 48)
            .background(Color(white: 0.16), in: RoundedRectangle(cornerRadius: 14))
    }
    private var filters: some View {
        VStack(alignment: .leading, spacing: 18) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(bodyParts, id: \.self) { item in
                        Pill(title: item.isEmpty ? L10n.text("ALL" /* 全部 */) : Vocabulary.label(item), selected: bodyPart == item) {
                            bodyPart = item; equipment = ""
                        }
                    }
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(equipments, id: \.self) { item in
                        Pill(title: item.isEmpty ? L10n.text("ANY_EQUIPMENT" /* 所有器械 */) : Vocabulary.label(item), selected: equipment == item) { equipment = item }
                    }
                }
            }
            HStack(spacing: 8) {
                Pill(title: L10n.text("FAVOURITES" /* 收藏 */), selected: favouritesOnly) { favouritesOnly.toggle() }
                Pill(title: L10n.text("PREVIOUSLY_TRAINED" /* 练过 */), selected: trainedOnly) { trainedOnly.toggle() }
                Pill(title: L10n.text("CUSTOM" /* 自定义 */), selected: customOnly) { customOnly.toggle() }
            }
        }
    }
    private func resetFilters() {
        searchReset += 1; search = ""; bodyPart = ""; equipment = ""; favouritesOnly = false; trainedOnly = false; customOnly = false; limit = 60
    }
    private func refreshEquipment() {
        if store.state["equipFilterOn"] as? Bool == true {
            available = ((try? store.personalInfo("equipment"))?["available"] as? [String]).map { Set($0) }
        } else { available = nil }
    }
}
