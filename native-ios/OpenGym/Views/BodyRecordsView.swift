import SwiftUI
import Charts

struct PersonalRecord: Identifiable {
    let id = UUID()
    var raw:[String:Any]?
}
struct BodyRecordsView: View {
    @Environment(GymStore.self) private var store
    let measurements:Bool
    @State private var editor:PersonalRecord?
    @State private var deleting:PersonalRecord?
    @State private var selected = "waist"
    @State private var range = 90
    @State private var goal = ""
    @State private var goalOriginal:[String:Any] = [:]
    @State private var issue:String?
    private var collection:String { measurements ? "measurements" : "bodyweight" }
    private var records:[[String:Any]] { (store.state[collection] as? [[String:Any]] ?? []).sorted { ($0["d"] as? String ?? "") < ($1["d"] as? String ?? "") } }
    private var fields:[MeasureField] { MeasureField.all(store.state) }
    private var points:[TrendPoint] { records.compactMap { r in
        guard let d = r["d"] as? String, let date = dateFromDay(d), range == 0 || date >= Calendar.current.date(byAdding:.day,value:-range,to:Date())! else { return nil }
        let value = measurements ? MeasureField.value(r,selected) : number(r["w"])
        guard value > 0 else { return nil }; return TrendPoint(date:date,value:measurements && selected != "bodyFat" && store.unit == "lb" ? value/2.54:value)
    } }
    var body:some View {
        List {
            Section {
                if measurements {
                    Picker("测量项目",selection:$selected) { ForEach(fields) { f in Text(f.name).tag(f.id) } }
                }
                Picker("时间范围",selection:$range) { Text("1 月").tag(30);Text("3 月").tag(90);Text("1 年").tag(365);Text("全部").tag(0) }.pickerStyle(.segmented)
                TrendChart(points:points,unit:measurements ? (selected == "bodyFat" ? "%":store.unit == "lb" ? "in":"cm") : store.unit).frame(height:180)
                Button(measurements ? "记录围度" : "记录体重") { editor = PersonalRecord() }.accessibilityIdentifier("add-body-record")
            }
            if !measurements {
                Section("目标体重（\(store.unit)）") {
                    TextField("留空取消目标",text:$goal).keyboardType(.decimalPad)
                    Button("保存目标") {
                        guard goal.isEmpty || (TrainingInput.value(goal).map { $0 > 0 && $0 < 1000 } ?? false) else { issue = "请输入有效目标体重。"; return }
                        let unit = store.unit
                        Task { if await store.savePersonalFields(original:goalOriginal,proposed:goal.isEmpty ? [:] : ["targetW":TrainingInput.value(goal)!],unit:unit) { goalOriginal = store.state.filter { $0.key == "targetW" } } else { issue = store.editError } }
                    }.disabled(store.syncing)
                }
            } else { Section { NavigationLink("选择测量项目") { MeasurementFieldsView() } } }
            if let issue { Text(issue).foregroundStyle(.orange) }
            Section("记录历史") {
                if records.isEmpty { Text("暂无记录").foregroundStyle(.secondary) }
                ForEach(Array(records.reversed().enumerated()),id:\.offset) { _,row in
                    HStack {
                        VStack(alignment:.leading,spacing:5) {
                            Text(row["d"] as? String ?? "")
                            Text(summary(row)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { editor = PersonalRecord(raw:row) } label:{Image(systemName:"pencil").frame(width:44,height:44)}.buttonStyle(.borderless).accessibilityLabel("编辑 \(row["d"] as? String ?? "")")
                        Button(role:.destructive) { deleting = PersonalRecord(raw:row) } label:{Image(systemName:"trash").frame(width:44,height:44)}.buttonStyle(.borderless).accessibilityLabel("删除记录")
                    }
                }
            }
        }.navigationTitle(measurements ? "身体围度" : "体重记录").navigationBarTitleDisplayMode(.inline)
            .onAppear { goalOriginal = store.state.filter{$0.key == "targetW"}; goal = store.state["targetW"].map { personalNumber(number($0)) } ?? "" }
            .sheet(item:$editor) { record in BodyRecordEditor(original:record.raw,measurements:measurements,fields:fields,unit:store.unit) }
            .confirmationDialog("删除这条记录？",isPresented:Binding(get:{deleting != nil},set:{if !$0 { deleting = nil }}),titleVisibility:.visible) {
                Button("删除",role:.destructive) { guard let row = deleting?.raw else { return }; Task { if !(await store.savePersonalRecord(collection:collection,key:"d",original:row,proposed:nil)) { issue = store.editError } } }
                Button("取消",role:.cancel) {}
            }
    }
    private func summary(_ row:[String:Any])->String {
        if !measurements { return "\(decimal(number(row["w"]))) \(store.unit)" }
        return fields.filter { MeasureField.value(row,$0.id)>0 }.prefix(4).map { "\($0.name) \(decimal(MeasureField.value(row,$0.id) / (store.unit == "lb" && $0.id != "bodyFat" ? 2.54:1)))" }.joined(separator:" · ")
    }
}
struct TrendPoint:Identifiable { let id = UUID(); let date:Date; let value:Double; var series = "" }
struct TrendChart:View {
    let points:[TrendPoint]
    let unit:String
    var body:some View {
        if points.isEmpty { ContentUnavailableView("暂无数据",systemImage:"chart.xyaxis.line",description:Text("记录完成后，趋势会显示在这里。")) }
        else {
            Chart(points) { p in
                LineMark(x:.value("日期",p.date),y:.value(unit,p.value)).foregroundStyle(by:.value("组",p.series))
                PointMark(x:.value("日期",p.date),y:.value(unit,p.value)).foregroundStyle(by:.value("组",p.series))
            }.chartYScale(domain:.automatic(includesZero:false)).chartLegend(points.allSatisfy{$0.series.isEmpty} ? .hidden : .visible)
                .accessibilityLabel("\(points.count) 条趋势数据，单位 \(unit)")
        }
    }
}
func dateFromDay(_ day:String)->Date? { let f = DateFormatter();f.locale = Locale(identifier:"en_US_POSIX");f.dateFormat = "yyyy-MM-dd";return f.date(from:day) }
struct MeasureField:Identifiable {
    let id:String;let name:String
    static let builtin:[MeasureField] = zip(["neck","shoulders","chest","waist","hips","abdomen","upperArmLeft","upperArmRight","forearmLeft","forearmRight","wristLeft","wristRight","thighLeft","thighRight","calfLeft","calfRight","ankleLeft","ankleRight","bodyFat"],["颈围","肩围","胸围","腰围","臀围","腹围","左上臂","右上臂","左前臂","右前臂","左腕","右腕","左大腿","右大腿","左小腿","右小腿","左踝","右踝","体脂率"]).map { MeasureField(id:$0,name:$1) }
    static func all(_ state:[String:Any])->[MeasureField] {
        var result = builtin
        var seen = Set<String>()
        let customs = (state["customMeasurements"] as? [[String:Any]] ?? []) + (state["measurements"] as? [[String:Any]] ?? []).flatMap { $0["other"] as? [[String:Any]] ?? [] }
        for c in customs { if let id = c["id"] as? String, seen.insert(id).inserted { result.append(MeasureField(id:"other:"+id,name:c["name"] as? String ?? "自定义")) } }
        return result
    }
    static func value(_ row:[String:Any],_ key:String)->Double { key.hasPrefix("other:") ? number((row["other"] as? [[String:Any]] ?? []).first {$0["id"] as? String == String(key.dropFirst(6))}?["value"]) : number(row[key]) }
}
struct BodyRecordEditor:View {
    @Environment(GymStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let original:[String:Any]?
    let measurements:Bool
    let fields:[MeasureField]
    let unit:String
    @State private var date = Date()
    @State private var values:[String:String] = [:]
    @State private var issue:String?
    @State private var ready = false
    private var visible:[MeasureField] {
        guard measurements else { return [MeasureField(id:"w",name:"体重")] }
        let enabled = store.state["measurementEnabled"] as? [String]
        let custom = store.state["customMeasurements"] as? [[String:Any]] ?? []
        return fields.filter { f in
            if MeasureField.value(original ?? [:],f.id)>0 { return true }
            if f.id.hasPrefix("other:") { return custom.contains { $0["id"] as? String == String(f.id.dropFirst(6)) && $0["enabled"] as? Bool != false } }
            return enabled?.contains(f.id) ?? true
        }
    }
    var body:some View {
        NavigationStack {
            Form {
                DatePicker("日期",selection:$date,in:...Date(),displayedComponents:.date)
                ForEach(visible) { f in HStack {
                    Text(f.name);Spacer()
                    TextField("未填写",text:Binding(get:{values[f.id] ?? ""},set:{values[f.id] = $0})).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width:110).accessibilityIdentifier("body-field-\(f.id)")
                    Text(f.id == "bodyFat" ? "%":measurements ? (unit == "lb" ? "in":"cm"):unit).font(.caption).foregroundStyle(.secondary)
                } }
                if let issue { Text(issue).foregroundStyle(.orange) }
            }.navigationTitle(measurements ? "记录围度" : "记录体重").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement:.topBarLeading) { Button("取消") { dismiss() } };ToolbarItem(placement:.topBarTrailing) { Button("保存") { save() }.disabled(store.syncing).accessibilityIdentifier("save-body-record") } }
                .onAppear { guard !ready else { return };ready = true;date = (original?["d"] as? String).flatMap(dateFromDay) ?? Date()
                    for f in visible { let v = measurements ? MeasureField.value(original ?? [:],f.id):number(original?["w"]);values[f.id] = v>0 ? personalNumber(v/(measurements && f.id != "bodyFat" && unit == "lb" ? 2.54:1)):"" }
                }
        }
    }
    private func save() {
        var row = original ?? [:], hasValue = false
        row["d"] = dayString(date);row["t"] = Date().timeIntervalSince1970*1000
        var others = row["other"] as? [[String:Any]] ?? []
        for f in visible {
            let text = (values[f.id] ?? "").trimmingCharacters(in:.whitespacesAndNewlines)
            var value:Double?
            if !text.isEmpty {
                guard let n = TrainingInput.value(text), n>0, n <= (f.id == "bodyFat" ? 100:2000) else { issue = "请检查\(f.name)的数值。";return }
                value = measurements && f.id != "bodyFat" && unit == "lb" ? (n*2.54*10).rounded()/10 : n;hasValue = true
            }
            if f.id.hasPrefix("other:") {
                let id = String(f.id.dropFirst(6)); let i = others.firstIndex {$0["id"] as? String == id}
                var item = i.map {others[$0]} ?? ["id":id,"name":f.name];item["value"] = value.map { $0 as Any } ?? NSNull()
                if let i { others[i] = item } else { others.append(item) }
            } else { row[f.id] = value.map { $0 as Any } ?? NSNull() }
        }
        guard hasValue else { issue = "请至少填写一项。";return }
        if measurements { row["other"] = others } else { row.removeValue(forKey:"healthKit") }
        Task { if await store.savePersonalRecord(collection:measurements ? "measurements":"bodyweight",key:"d",original:original,proposed:row,unit:unit) { dismiss() } else { issue = store.editError } }
    }
}
struct MeasurementFieldsView:View {
    @Environment(GymStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var original:[String:Any] = [:]
    @State private var enabled = Set<String>()
    @State private var custom:[[String:Any]] = []
    @State private var name = ""
    @State private var loaded = false
    @State private var issue:String?
    var body:some View {
        Form {
            Section("测量项目") { ForEach(MeasureField.builtin) { f in Toggle(f.name,isOn:Binding(get:{enabled.contains(f.id)},set:{if $0 { enabled.insert(f.id) } else { enabled.remove(f.id) }})) } }
            Section("自定义项目") {
                ForEach(custom.indices,id:\.self) { i in Toggle(custom[i]["name"] as? String ?? "",isOn:Binding(get:{custom[i]["enabled"] as? Bool != false},set:{custom[i]["enabled"] = $0})) }
                TextField("项目名称",text:$name)
                Button("添加项目") { let clean = name.trimmingCharacters(in:.whitespacesAndNewlines);guard !clean.isEmpty else{return};guard !custom.contains(where:{($0["name"] as? String ?? "").localizedCaseInsensitiveCompare(clean) == .orderedSame}) else {issue = "该项目已存在。";return};custom.append(["id":UUID().uuidString,"name":String(clean.prefix(60)),"enabled":true]);name = "" }
            }
            if let issue { Text(issue).foregroundStyle(.orange) }
        }.navigationTitle("选择测量项目").onAppear { guard !loaded else {return};loaded = true;original = store.state.filter {["measurementEnabled","customMeasurements"].contains($0.key)};enabled = Set(original["measurementEnabled"] as? [String] ?? MeasureField.builtin.map(\.id));custom = original["customMeasurements"] as? [[String:Any]] ?? [] }
            .toolbar { ToolbarItem(placement:.topBarTrailing) { Button("保存") { Task { if await store.savePersonalFields(original:original,proposed:["measurementEnabled":enabled.sorted(),"customMeasurements":custom]) { dismiss() } else { issue = store.editError } } }.disabled(store.syncing) } }
    }
}

func personalNumber(_ value:Double)->String { String(format:"%.8g",value) }
