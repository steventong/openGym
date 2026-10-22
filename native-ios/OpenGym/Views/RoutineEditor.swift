import SwiftUI
struct RoutineEditor: View {
    @Environment(GymStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let original: [String:Any]
    let expectedUnit: String
    @State private var name: String
    @State private var rows: [RawRow]
    @State private var pick = false
    @State private var discard = false
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
                            }
                            if EditValidation.ordinaryConfig(row.raw) {
                                HStack {
                                    numeric("组数",key:"sets",fallback:3,row:$row)
                                    numeric("次数",key:"reps",fallback:10,row:$row)
                                    numeric(expectedUnit,key:"weight",fallback:0,row:$row)
                                }
                                Stepper("组间休息 \(Int(number(row.raw["restSec"] ?? 90))) 秒",value:Binding(get:{Int(number(row.raw["restSec"] ?? 90))},set:{row.raw["restSec"] = $0}),in:0...900,step:15).font(.subheadline)
                            } else { Text("此动作使用高级组型，参数原样保留；可调整备注和顺序。").font(.caption).foregroundStyle(.secondary) }
                            TextField("动作备注",text:Binding(get:{row.raw["note"] as? String ?? ""},set:{row.raw["note"] = $0})).font(.subheadline)
                            HStack {
                                Button { shift(row.id,-1) } label: { Label("上移",systemImage:"arrow.up") }.disabled(rows.first?.id == row.id)
                                Button { shift(row.id,1) } label: { Label("下移",systemImage:"arrow.down") }.disabled(rows.last?.id == row.id)
                                Spacer()
                                Button(role:.destructive) { let id = row.id; rows.removeAll { $0.id == id } } label: { Image(systemName:"minus.circle") }.accessibilityLabel("移除动作")
                            }.font(.caption).buttonStyle(.borderless)
                        }.padding(.vertical,7)
                    }.onMove { rows.move(fromOffsets:$0,toOffset:$1) }.onDelete { rows.remove(atOffsets:$0) }
                    Button { pick = true } label: { Label("添加动作",systemImage:"plus.circle.fill") }.accessibilityIdentifier("edit-add-exercise")
                } header: { Text("动作 · \(rows.count)") } footer: { Text("保存后更新计划。正在进行的训练草稿不受影响。") }
            }.navigationTitle("编辑计划").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement:.topBarLeading) { Button("取消") { if dirty { discard = true } else { dismiss() } }.disabled(store.syncing) }
                    ToolbarItem(placement:.topBarTrailing) { Button(store.syncing ? "保存中…" : "保存") { Task { if await store.saveRoutine(original:original,proposed:proposed,expectedUnit:expectedUnit) { dismiss() } else { error = store.editError } } }.disabled(store.syncing || !dirty).accessibilityIdentifier("save-routine-edit") }
                }
                .sheet(isPresented:$pick) { ExercisePicker { exercise in rows.append(RawRow(raw:["id":exercise.id,"sets":3,"reps":10,"weight":0,"restSec":90])); pick = false } }
                .alert("无法保存",isPresented:Binding(get:{error != nil},set:{if !$0 { error = nil }})) { Button("知道了",role:.cancel) {} } message: { Text(error ?? "") }
                .confirmationDialog("放弃未保存的修改？",isPresented:$discard,titleVisibility:.visible) { Button("放弃修改",role:.destructive) { dismiss() }; Button("继续编辑",role:.cancel) {} }
                .interactiveDismissDisabled(dirty || store.syncing)
        }.tint(GymTheme.green)
    }
    private func shift(_ id:UUID,_ direction:Int) { guard let i = rows.firstIndex(where:{$0.id == id}), rows.indices.contains(i + direction) else { return }; rows.swapAt(i,i + direction) }
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
    let select:(Exercise)->Void
    var body: some View {
        NavigationStack {
            List {
                TextField("搜索动作",text:$search).accessibilityIdentifier("picker-search")
                ForEach(Array(store.exercises.filter { search.isEmpty || $0.searchText.localizedCaseInsensitiveContains(search) }.prefix(60))) { ex in
                    Button { select(ex) } label: { HStack { ExerciseThumbnail(id:ex.id,size:45); Text(ex.name).font(.subheadline).foregroundStyle(.primary); Spacer(); Image(systemName:"plus") } }.accessibilityIdentifier("pick-\(ex.id)")
                }
            }.navigationTitle("添加动作").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement:.topBarTrailing) { Button("取消") { dismiss() } } }
        }
    }
}
