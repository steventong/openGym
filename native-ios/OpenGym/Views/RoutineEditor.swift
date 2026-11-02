import SwiftUI
struct RoutineEditor: View {
    @Environment(GymStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let original: [String:Any]
    let expectedUnit: String
    @State private var name: String
    @State private var rows: [RawRow]
    @State private var pick = false
    @State private var configuration: RawRow?
    @State private var discard = false
    @State private var confirmDelete = false
    @State private var deleting = false
    @State private var errorTitle = "无法保存"
    @State private var error: String?
    init(routine:Routine,unit:String) {
        original = routine.raw; expectedUnit = unit
        _name = State(initialValue:routine.name); _rows = State(initialValue:routine.exercises.map { RawRow(raw:$0) })
    }
    private var proposed:[String:Any] { var r = original; r["name"] = name.trimmingCharacters(in:.whitespacesAndNewlines); r["ex"] = rows.map(\.raw); return r }
    private var dirty: Bool { !RecordPatch.equal(original,proposed) }
    var body: some View {
        NavigationStack {
            List {
                Section("计划名称") { TextField("计划名称",text:$name).accessibilityIdentifier("edit-routine-name") }
                Section {
                    ForEach($rows) { $row in
                        VStack(alignment:.leading,spacing:14) {
                            HStack {
                                ExerciseThumbnail(id:row.raw["id"] as? String ?? "",size:46)
                                Text(store.exercise(row.raw["id"] as? String ?? "")?.name ?? row.raw["id"] as? String ?? "动作").font(.headline)
                                Spacer()
                                RoutineExerciseReplacement(slot: $row.raw, routineID: original["id"] as? String ?? "")
                            }
                            if EditValidation.ordinaryConfig(row.raw) {
                                HStack {
                                    numeric("组数",key:"sets",fallback:3,row:$row)
                                    numeric("次数",key:"reps",fallback:10,row:$row)
                                    numeric(expectedUnit,key:"weight",fallback:0,row:$row)
                                }
                                Stepper("组间休息 \(Int(number(row.raw["restSec"] ?? 90))) 秒",value:Binding(get:{Int(number(row.raw["restSec"] ?? 90))},set:{row.raw["restSec"] = $0}),in:0...900,step:15).font(.subheadline)
                            } else { Text("已配置高级组型，可在下方调整参数。").font(.caption).foregroundStyle(.secondary) }
                            Button { configuration = row } label: { Label("高级组型与计时",systemImage:"slider.horizontal.3") }.buttonStyle(.borderless).accessibilityIdentifier("advanced-slot-\(row.raw["id"] as? String ?? "")")
                            if row.raw["sg"] != nil { Label("超级组",systemImage:"link").font(.caption).foregroundStyle(GymTheme.green) }
                            HStack {
                                if rows.last?.id != row.id { Button("与下一动作组成超级组") { group(row.id,"pair") }.font(.caption).buttonStyle(.borderless) }
                                if row.raw["sg"] != nil { Button("解除超级组") { group(row.id,"unpair") }.font(.caption).buttonStyle(.borderless) }
                            }
                            TextField("动作备注",text:Binding(get:{row.raw["note"] as? String ?? ""},set:{row.raw["note"] = $0})).font(.subheadline)
                            HStack {
                                Button { shift(row.id,-1) } label: { Label("上移",systemImage:"arrow.up").frame(minWidth:72,minHeight:48).contentShape(Rectangle()) }.disabled(rows.first?.id == row.id)
                                Button { shift(row.id,1) } label: { Label("下移",systemImage:"arrow.down").frame(minWidth:72,minHeight:48).contentShape(Rectangle()) }.disabled(rows.last?.id == row.id)
                                Spacer()
                                Button(role:.destructive) { let id = row.id; rows.removeAll { $0.id == id } } label: { Image(systemName:"minus.circle") }.accessibilityLabel("移除动作")
                            }.font(.caption).buttonStyle(.borderless)
                        }.padding(.vertical,7)
                    }.onMove { rows.move(fromOffsets:$0,toOffset:$1) }.onDelete { rows.remove(atOffsets:$0) }
                    Button { pick = true } label: { Label("添加动作",systemImage:"plus.circle.fill") }.accessibilityIdentifier("edit-add-exercise")
                } header: { Text("动作 · \(rows.count)") } footer: { Text("保存后更新计划。正在进行的训练草稿不受影响。") }
                Section {
                    Button(role:.destructive) { confirmDelete = true } label: {
                        Label(deleting ? "删除中…" : "删除训练计划",systemImage:"trash")
                    }.disabled(store.syncing || deleting).accessibilityIdentifier("delete-routine")
                } footer: { Text("删除计划及其排期，保留训练历史和正在进行的训练。") }
            }.navigationTitle("编辑计划").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement:.topBarLeading) { Button("取消") { if dirty { discard = true } else { dismiss() } }.disabled(store.syncing) }
                    ToolbarItem(placement:.topBarTrailing) { Button(store.syncing && !deleting ? "保存中…" : "保存") { Task { if await store.saveRoutine(original:original,proposed:proposed,expectedUnit:expectedUnit) { dismiss() } else { errorTitle = "无法保存"; error = store.editError } } }.disabled(store.syncing || deleting || !dirty).accessibilityIdentifier("save-routine-edit") }
                }
                .sheet(item:$configuration) { selected in AdvancedConfigEditor(config:selected.raw,unit:expectedUnit) { updated in if let i = rows.firstIndex(where:{$0.id == selected.id}) { rows[i].raw = updated } } }
                .sheet(isPresented:$pick) { ExercisePicker { exercise in rows.append(RawRow(raw:["id":exercise.id,"sets":3,"reps":10,"weight":0,"restSec":90])); pick = false } }
                .alert(errorTitle,isPresented:Binding(get:{error != nil},set:{if !$0 { error = nil }})) { Button("知道了",role:.cancel) {} } message: { Text(error ?? "") }
                .confirmationDialog("删除训练计划？",isPresented:$confirmDelete,titleVisibility:.visible) {
                    Button("删除训练计划",role:.destructive) { Task { await deleteRoutine() } }
                    Button("取消",role:.cancel) {}
                } message: {
                    Text("将删除「\(original["name"] as? String ?? "训练计划")」及其排期，无法撤销。训练历史和正在进行的训练会保留。" + (dirty ? "当前未保存的修改将被放弃。" : ""))
                }
                .confirmationDialog("放弃未保存的修改？",isPresented:$discard,titleVisibility:.visible) { Button("放弃修改",role:.destructive) { dismiss() }; Button("继续编辑",role:.cancel) {} }
                .interactiveDismissDisabled(dirty || store.syncing)
        }.tint(GymTheme.green)
    }
    private func deleteRoutine() async {
        guard !deleting, let id = original["id"] as? String else { return }
        deleting = true; defer { deleting = false }
        if await store.deleteRoutine(id:id) { dismiss() }
        else { errorTitle = "无法删除"; error = store.editError }
    }
    private func shift(_ id:UUID,_ direction:Int) { group(id,"move",direction) }
    private func group(_ id:UUID,_ operation:String,_ direction:Int = 0) {
        guard let i = rows.firstIndex(where:{$0.id == id}) else { return }
        do { let result = try WebRules.shared.call("planGroup",payload:["rows":rows.map(\.raw),"operation":operation,"index":i,"direction":direction]) as! [[String:Any]];rows = result.map { RawRow(raw:$0) } } catch { errorTitle = "无法保存"; self.error = error.localizedDescription }
    }
    private func numeric(_ title:String,key:String,fallback:Double,row:Binding<RawRow>) -> some View {
        VStack(alignment:.leading,spacing:5) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            TextField(title,value:Binding(get:{number(row.wrappedValue.raw[key] ?? fallback)},set:{row.wrappedValue.raw[key] = $0}),format:.number).keyboardType(key == "weight" ? .decimalPad : .numberPad)
                .padding(9).background(.white.opacity(0.07),in:RoundedRectangle(cornerRadius:9)).accessibilityIdentifier("routine-\(key)-\(row.wrappedValue.raw["id"] as? String ?? "")")
        }
    }
}
struct ExercisePicker: View {
    @Environment(GymStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
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
    var title = "添加动作"
    var selectionIcon = "plus"
    let select:(Exercise)->Void
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    searchField
                    filters
                    if let error = store.catalogueError { Text(error).foregroundStyle(.orange) }
                    let results = choices
                    HStack {
                        Text("找到 \(results.count) 个动作")
                        Spacer()
                        Label("动作库", systemImage: "checkmark.seal")
                    }.font(.caption).foregroundStyle(GymTheme.muted)
                    if results.isEmpty {
                        EmptyCard(icon: "magnifyingglass", title: "没有找到动作", detail: "试试其他关键词，或清除当前筛选。")
                        Button("清除搜索与筛选") { resetFilters() }
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
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("取消") { dismiss() } } }
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
            TextField("搜索动作、肌群…", text: $search)
                .font(.system(size: 15)).autocorrectionDisabled()
                .accessibilityIdentifier("picker-search")
            if !search.isEmpty {
                Button { search = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.gray)
                }.accessibilityLabel("清除搜索")
            }
        }.padding(14).background(Color(white: 0.16), in: RoundedRectangle(cornerRadius: 14))
    }
    private var filters: some View {
        VStack(alignment: .leading, spacing: 18) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(bodyParts, id: \.self) { item in
                        Pill(title: item.isEmpty ? "全部" : Vocabulary.label(item), selected: bodyPart == item) {
                            bodyPart = item; equipment = ""
                        }
                    }
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(equipments, id: \.self) { item in
                        Pill(title: item.isEmpty ? "所有器械" : Vocabulary.label(item), selected: equipment == item) { equipment = item }
                    }
                }
            }
            HStack(spacing: 8) {
                Pill(title: "收藏", selected: favouritesOnly) { favouritesOnly.toggle() }
                Pill(title: "练过", selected: trainedOnly) { trainedOnly.toggle() }
                Pill(title: "自定义", selected: customOnly) { customOnly.toggle() }
            }
        }
    }
    private func resetFilters() {
        search = ""; bodyPart = ""; equipment = ""; favouritesOnly = false; trainedOnly = false; customOnly = false; limit = 60
    }
    private func refreshEquipment() {
        if store.state["equipFilterOn"] as? Bool == true {
            available = ((try? store.personalInfo("equipment"))?["available"] as? [String]).map { Set($0) }
        } else { available = nil }
    }
}
