import SwiftUI
private struct HistoryEntryDraft: Identifiable {
    var id = UUID()
    var raw:[String:Any]
    var sets:[RawRow]
    init(_ raw:[String:Any]) { self.raw = raw; sets = (raw["sets"] as? [[String:Any]] ?? []).map { RawRow(raw:$0) } }
    var value:[String:Any] { var next = raw; if raw["sets"] != nil || !sets.isEmpty { next["sets"] = sets.map(\.raw) }; return next }
}
struct HistoryEditor: View {
    @Environment(GymStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let original:[String:Any]
    let expectedUnit:String
    @State private var name:String
    @State private var note:String
    @State private var date:Date
    @State private var minutes:Double
    @State private var entries:[HistoryEntryDraft]
    @State private var pick = false
    @State private var discard = false
    @State private var error:String?
    init(record:WorkoutRecord,unit:String) {
        original = record.raw; expectedUnit = unit
        _name = State(initialValue:record.raw["name"] as? String ?? "训练")
        _note = State(initialValue:record.raw["note"] as? String ?? "")
        _date = State(initialValue:Date(timeIntervalSince1970:number(record.raw["start"])/1000))
        _minutes = State(initialValue:max(0,number(record.raw["end"]) - number(record.raw["start"]))/60000)
        _entries = State(initialValue:(record.raw["entries"] as? [[String:Any]] ?? []).map(HistoryEntryDraft.init))
    }
    private var proposed:[String:Any] {
        var next = original; next["name"] = name.trimmingCharacters(in:.whitespacesAndNewlines)
        if note != (original["note"] as? String ?? "") { next["note"] = note.trimmingCharacters(in:.whitespacesAndNewlines) }
        next["entries"] = entries.map(\.value)
        let start = date.timeIntervalSince1970 * 1000, duration = minutes * 60000
        let changedDate = abs(start-number(original["start"])) > 1
        if changedDate { next["start"] = start; next["d"] = dayString(date) }
        if changedDate || abs(duration - (number(original["end"]) - number(original["start"]))) > 1 { next["end"] = start + duration }
        return next
    }
    private var dirty:Bool { !RecordPatch.equal(original,proposed) }
    var body: some View {
        NavigationStack {
            List {
                Section("训练信息") {
                    TextField("训练名称",text:$name).accessibilityIdentifier("history-name")
                    DatePicker("日期和开始时间",selection:$date,in:...Date(),displayedComponents:[.date,.hourAndMinute]).environment(\.locale,Locale(identifier:"zh_CN")).accessibilityIdentifier("history-date")
                    HStack { Text("时长（分钟）"); Spacer(); TextField("分钟",value:$minutes,format:.number.precision(.fractionLength(0...2))).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width:100).accessibilityIdentifier("history-duration") }
                    TextField("训练备注",text:$note,axis:.vertical).lineLimit(2...5).accessibilityIdentifier("history-note")
                }
                ForEach($entries) { $entry in
                    Section {
                        ForEach($entry.sets) { $set in
                            VStack(alignment:.leading,spacing:10) {
                                if EditValidation.ordinarySet(set.raw,entry:entry.raw) {
                                    HStack {
                                        historyNumber("重量 · \(expectedUnit)",key:"w",row:$set)
                                        historyNumber("次数",key:"r",row:$set)
                                        Toggle("完成",isOn:Binding(get:{set.raw["done"] as? Bool ?? false},set:{set.raw["done"] = $0})).labelsHidden().tint(GymTheme.green)
                                    }
                                    Toggle("热身组",isOn:Binding(get:{let phase = set.raw["phase"] as? String; return phase.map { ["warmup","warm-up","warm_up"].contains($0) } ?? (set.raw["warmup"] as? Bool ?? false)},set:{set.raw["phase"] = $0 ? "warmup" : "work"; set.raw["warmup"] = $0})).font(.caption)
                                } else { Text("高级组型参数原样保留，可在网页中调整。").font(.caption).foregroundStyle(.secondary) }
                                Button(role:.destructive) { let id = set.id; entry.sets.removeAll { $0.id == id } } label: { Label("移除此组",systemImage:"minus.circle").font(.caption) }.buttonStyle(.borderless)
                            }.padding(.vertical,4)
                        }
                        Button {
                            let last = entry.sets.last?.raw ?? [:]
                            entry.sets.append(RawRow(raw:["w":number(last["w"]),"r":max(1,number(last["r"] ?? 10)),"done":true,"phase":"work","mode":"reps"]))
                        } label: { Label("添加普通组",systemImage:"plus") }.buttonStyle(.borderless)
                        TextField("动作备注",text:Binding(get:{entry.raw["note"] as? String ?? ""},set:{entry.raw["note"] = $0})).font(.subheadline)
                        Button("移除此动作",role:.destructive) { let id = entry.id; entries.removeAll { $0.id == id } }.font(.caption).buttonStyle(.borderless)
                    } header: { Text(store.exercise(entry.raw["id"] as? String ?? "")?.name ?? entry.raw["id"] as? String ?? "动作") }
                }
                Section { Button { pick = true } label: { Label("添加动作",systemImage:"plus.circle") } }
                Section { Text("保存后重算训练量和个人纪录，保留照片、计划关联和其他未修改信息。取消不会修改已保存的记录。").font(.caption).foregroundStyle(.secondary) }
            }.navigationTitle("编辑训练记录").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement:.topBarLeading) { Button("取消") { if dirty { discard = true } else { dismiss() } }.disabled(store.syncing) }
                    ToolbarItem(placement:.topBarTrailing) { Button(store.syncing ? "保存中…" : "保存") { Task { if await store.saveWorkout(original:original,proposed:proposed,expectedUnit:expectedUnit) { dismiss() } else { error = store.editError } } }.disabled(!dirty || store.syncing).accessibilityIdentifier("save-history") }
                }
                .sheet(isPresented:$pick) { ExercisePicker { ex in entries.append(HistoryEntryDraft(["id":ex.id,"sets":[["w":0,"r":10,"done":true,"phase":"work"]]])); pick = false } }
                .alert("无法保存",isPresented:Binding(get:{error != nil},set:{if !$0 { error = nil }})) { Button("知道了",role:.cancel) {} } message: { Text(error ?? "") }
                .confirmationDialog("放弃记录修改？",isPresented:$discard,titleVisibility:.visible) { Button("放弃修改",role:.destructive) { dismiss() }; Button("继续编辑",role:.cancel) {} }
                .interactiveDismissDisabled(dirty || store.syncing)
        }.tint(GymTheme.green)
    }
    private func historyNumber(_ title:String,key:String,row:Binding<RawRow>) -> some View {
        VStack(alignment:.leading,spacing:5) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            TextField(title,value:Binding(get:{number(row.wrappedValue.raw[key])},set:{row.wrappedValue.raw[key] = $0}),format:.number).keyboardType(key == "r" ? .numberPad : .decimalPad)
                .padding(9).background(.white.opacity(0.07),in:RoundedRectangle(cornerRadius:9)).accessibilityIdentifier("history-\(key)-\(row.wrappedValue.id)")
        }
    }
}
