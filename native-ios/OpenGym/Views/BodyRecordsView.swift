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
    @State private var inputBuffer = InputCommitBuffer()
    @State private var goal = ""
    @State private var goalOriginal:[String:Any] = [:]
    @State private var goalLoaded = false
    @State private var goalUnit = "kg"
    @State private var invalidGoal = false
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
                    Picker(L10n.text("MEASUREMENT" /* 测量项 */),selection:$selected) { ForEach(fields) { f in Text(f.name).tag(f.id) } }
                }
                Picker(L10n.text("TIME_RANGE" /* 时间范围 */),selection:$range) { Text(L10n.text("ONE_MONTH" /* 1 月 */)).tag(30);Text(L10n.text("THREE_MONTHS" /* 3 月 */)).tag(90);Text(L10n.text("ONE_YEAR" /* 1 年 */)).tag(365);Text(L10n.text("ALL" /* 全部 */)).tag(0) }.pickerStyle(.segmented)
                TrendChart(points:points,unit:measurements ? (selected == "bodyFat" ? "%":store.unit == "lb" ? "in":"cm") : store.unit).frame(height:180)
                Button(measurements ? L10n.text("LOG_MEASUREMENTS" /* 记录测量 */) : L10n.text("LOG_BODY_WEIGHT" /* 记录体重 */)) { editor = PersonalRecord() }.accessibilityIdentifier("add-body-record")
            }
            if !measurements {
                Section(L10n.text("TARGET_WEIGHT_COUNT" /* 目标体重（{0}） */, goalUnit)) {
                    BufferedTextField(L10n.text("LEAVE_BLANK_TO_REMOVE_GOAL" /* 留空取消目标 */),text:$goal).textFieldStyle(.plain).stableInputLine().submitLabel(.done).onSubmit { GymKeyboard.dismiss() }.keyboardType(.decimalPad).invalidInput(invalidGoal)
                        .onChange(of: goal) { _, _ in invalidGoal = false }
                    Button(L10n.text("SAVE_GOAL" /* 保存目标 */)) {
                        inputBuffer.commitAll()
                        guard goal.isEmpty || (TrainingInput.value(goal).map { $0 > 0 && $0 < 1000 } ?? false) else { invalidGoal = true; issue = L10n.text("ENTER_A_VALID_TARGET_WEIGHT" /* 请输入有效目标体重。 */); return }
                        let unit = goalUnit
                        Task { if await store.savePersonalFields(original:goalOriginal,proposed:goal.isEmpty ? [:] : ["targetW":TrainingInput.value(goal)!],unit:unit) { goalOriginal = store.state.filter { $0.key == "targetW" } } else { issue = store.editError } }
                    }.disabled(store.syncing)
                }
            } else { Section { NavigationLink(L10n.text("CHOOSE_MEASUREMENTS" /* 选择测量项 */)) { MeasurementFieldsView() } } }
            Section(L10n.text("HISTORY" /* 历史 */)) {
                if records.isEmpty { Text(L10n.text("NO_RECORDS_YET" /* 暂无记录 */)).foregroundStyle(.secondary) }
                ForEach(Array(records.reversed().enumerated()),id:\.offset) { _,row in
                    HStack {
                        VStack(alignment:.leading,spacing:5) {
                            Text(row["d"] as? String ?? "")
                            Text(summary(row)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { editor = PersonalRecord(raw:row) } label:{Image(systemName:"pencil").frame(width:44,height:44)}.buttonStyle(.borderless).accessibilityLabel(L10n.text("EDIT_COUNT" /* 编辑 {0} */, row["d"] as? String ?? ""))
                        Button(role:.destructive) { deleting = PersonalRecord(raw:row) } label:{Image(systemName:"trash").frame(width:44,height:44)}.buttonStyle(.borderless).accessibilityLabel(L10n.text("DELETE_RECORD" /* 删除记录 */))
                    }
                }
            }
        }.environment(\.inputCommitBuffer, inputBuffer).operationAlert($issue).navigationTitle(measurements ? L10n.text("BODY_MEASUREMENTS" /* 身体围度 */) : L10n.text("BODY_WEIGHT_RECORDS" /* 体重记录 */)).navigationBarTitleDisplayMode(.inline)
            .keyboardDismissToolbar()
            .onAppear { guard !goalLoaded else { return }; goalLoaded = true; goalUnit = store.unit; goalOriginal = store.state.filter{$0.key == "targetW"}; goal = store.state["targetW"].map { personalNumber(number($0)) } ?? "" }
            .sheet(item:$editor) { record in BodyRecordEditor(original:record.raw,measurements:measurements,fields:fields,unit:store.unit) }
            .confirmationDialog(L10n.text("DELETE_THIS_RECORD" /* 删除这条记录？ */),isPresented:Binding(get:{deleting != nil},set:{if !$0 { deleting = nil }}),titleVisibility:.visible) {
                Button(L10n.text("DELETE" /* 删除 */),role:.destructive) { guard let row = deleting?.raw else { return }; Task { if !(await store.savePersonalRecord(collection:collection,key:"d",original:row,proposed:nil)) { issue = store.editError } } }
                Button(L10n.text("CANCEL" /* 取消 */),role:.cancel) {}
            }
    }
    private func summary(_ row:[String:Any])->String {
        if !measurements { return "\(decimal(number(row["w"]))) \(store.unit)" }
        return fields.filter { MeasureField.value(row,$0.id)>0 }.prefix(4).map { "\($0.name) \(decimal(MeasureField.value(row,$0.id) / (store.unit == "lb" && $0.id != "bodyFat" ? 2.54:1)))" }.joined(separator:" · ")
    }
}
struct TrendPoint:Identifiable {
    struct ID:Hashable { let date:Date; let series:String; let occurrence:Int }
    let date:Date
    let value:Double
    var series = ""
    var occurrence = 0
    var id:ID { ID(date:date,series:series,occurrence:occurrence) }
    // Imported sessions may share a timestamp. Keep each point distinct without random IDs.
    static func identified(_ points:[TrendPoint]) -> [TrendPoint] {
        var counts:[ID:Int] = [:]
        return points.map { point in
            var next = point
            let key = ID(date:point.date,series:point.series,occurrence:0)
            next.occurrence = counts[key,default:0]
            counts[key,default:0] += 1
            return next
        }
    }
}
struct TrendChart:View {
    let points:[TrendPoint]
    let unit:String
    var body:some View {
        if points.isEmpty { ContentUnavailableView(L10n.text("NO_DATA_YET" /* 暂无数据 */),systemImage:"chart.xyaxis.line",description: nil) }
        else {
            Chart(points) { p in
                LineMark(x:.value(L10n.text("DATE" /* 日期 */),p.date),y:.value(unit,p.value)).foregroundStyle(by:.value(L10n.text("SETS_A" /* 组 */),p.series))
                PointMark(x:.value(L10n.text("DATE" /* 日期 */),p.date),y:.value(unit,p.value)).foregroundStyle(by:.value(L10n.text("SETS_A" /* 组 */),p.series))
            }.chartYScale(domain:.automatic(includesZero:false)).chartLegend(points.allSatisfy{$0.series.isEmpty} ? .hidden : .visible)
                .accessibilityLabel(L10n.text("COUNT_TREND_POINTS_MEASURED_IN_COUNT" /* {0} 条趋势数据，单位 {1} */, points.count, unit))
        }
    }
}
func dateFromDay(_ day:String)->Date? { let f = DateFormatter();f.locale = Locale(identifier:"en_US_POSIX");f.dateFormat = "yyyy-MM-dd";return f.date(from:day) }
struct MeasureField:Identifiable {
    let id:String;let name:String
    static var builtin:[MeasureField] { zip(["neck","shoulders","chest","waist","hips","abdomen","upperArmLeft","upperArmRight","forearmLeft","forearmRight","wristLeft","wristRight","thighLeft","thighRight","calfLeft","calfRight","ankleLeft","ankleRight","bodyFat"],[L10n.text("MEASUREMENT_NECK" /* 颈围 */),L10n.text("MEASUREMENT_SHOULDERS" /* 肩围 */),L10n.text("MEASUREMENT_CHEST" /* 胸围 */),L10n.text("WAIST_A" /* 腰围 */),L10n.text("HIPS" /* 臀围 */),L10n.text("ABDOMEN" /* 腹围 */),L10n.text("LEFT_UPPER_ARM" /* 左上臂 */),L10n.text("RIGHT_UPPER_ARM" /* 右上臂 */),L10n.text("LEFT_FOREARM" /* 左前臂 */),L10n.text("RIGHT_FOREARM" /* 右前臂 */),L10n.text("LEFT_WRIST" /* 左手腕 */),L10n.text("RIGHT_WRIST" /* 右手腕 */),L10n.text("LEFT_THIGH" /* 左大腿 */),L10n.text("RIGHT_THIGH" /* 右大腿 */),L10n.text("LEFT_CALF" /* 左小腿 */),L10n.text("RIGHT_CALF" /* 右小腿 */),L10n.text("LEFT_ANKLE" /* 左脚踝 */),L10n.text("RIGHT_ANKLE" /* 右脚踝 */),L10n.text("BODY_FAT" /* 体脂率 */)]).map { MeasureField(id:$0,name:$1) } }
    static func all(_ state:[String:Any])->[MeasureField] {
        var result = builtin
        var seen = Set<String>()
        let customs = (state["customMeasurements"] as? [[String:Any]] ?? []) + (state["measurements"] as? [[String:Any]] ?? []).flatMap { $0["other"] as? [[String:Any]] ?? [] }
        for c in customs { if let id = c["id"] as? String, seen.insert(id).inserted { result.append(MeasureField(id:"other:"+id,name:c["name"] as? String ?? L10n.text("CUSTOM" /* 自定义 */))) } }
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
    @State private var invalidField: String?
    @State private var ready = false
    private var visible:[MeasureField] {
        guard measurements else { return [MeasureField(id:"w",name:L10n.text("BODY_WEIGHT" /* 体重 */))] }
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
                DatePicker(L10n.text("DATE" /* 日期 */),selection:$date,in:...Date(),displayedComponents:.date)
                ForEach(visible) { f in HStack {
                    Text(f.name);Spacer()
                    TextField(L10n.text("NOT_ENTERED" /* 未填写 */),text:Binding(get:{values[f.id] ?? ""},set:{values[f.id] = $0; if invalidField == f.id { invalidField = nil }})).textFieldStyle(.plain).stableInputLine().submitLabel(.done).onSubmit { GymKeyboard.dismiss() }
                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width:110).invalidInput(invalidField == f.id).accessibilityIdentifier("body-field-\(f.id)")
                    Text(f.id == "bodyFat" ? "%":measurements ? (unit == "lb" ? "in":"cm"):unit).font(.caption).foregroundStyle(.secondary)
                } }
            }.operationAlert($issue).navigationTitle(measurements ? L10n.text("LOG_MEASUREMENTS" /* 记录测量 */) : L10n.text("LOG_BODY_WEIGHT" /* 记录体重 */)).navigationBarTitleDisplayMode(.inline)
                .keyboardDismissToolbar()
                .toolbar { ToolbarItem(placement:.topBarLeading) { Button(L10n.text("CANCEL" /* 取消 */)) { dismiss() } };ToolbarItem(placement:.topBarTrailing) { Button(L10n.text("SAVE" /* 保存 */)) { save() }.disabled(store.syncing).accessibilityIdentifier("save-body-record") } }
                .onAppear { guard !ready else { return };ready = true;date = (original?["d"] as? String).flatMap(dateFromDay) ?? Date()
                    for f in visible { let v = measurements ? MeasureField.value(original ?? [:],f.id):number(original?["w"]);values[f.id] = v>0 ? personalNumber(v/(measurements && f.id != "bodyFat" && unit == "lb" ? 2.54:1)):"" }
                }
        }
    }
    private func save() {
        invalidField = nil
        var row = original ?? [:], hasValue = false
        row["d"] = dayString(date);row["t"] = Date().timeIntervalSince1970*1000
        var others = row["other"] as? [[String:Any]] ?? []
        for f in visible {
            let text = (values[f.id] ?? "").trimmingCharacters(in:.whitespacesAndNewlines)
            var value:Double?
            if !text.isEmpty {
                guard let n = TrainingInput.value(text), n>0, n <= (f.id == "bodyFat" ? 100:2000) else { invalidField = f.id; issue = L10n.text("CHECK_THE_VALUE_FOR_COUNT" /* 请检查{0}的数值。 */, f.name);return }
                value = measurements && f.id != "bodyFat" && unit == "lb" ? (n*2.54*10).rounded()/10 : n;hasValue = true
            }
            if f.id.hasPrefix("other:") {
                let id = String(f.id.dropFirst(6)); let i = others.firstIndex {$0["id"] as? String == id}
                var item = i.map {others[$0]} ?? ["id":id,"name":f.name];item["value"] = value.map { $0 as Any } ?? NSNull()
                if let i { others[i] = item } else { others.append(item) }
            } else { row[f.id] = value.map { $0 as Any } ?? NSNull() }
        }
        guard hasValue else { invalidField = visible.first?.id; issue = L10n.text("ENTER_AT_LEAST_ONE_MEASUREMENT" /* 请至少输入一项测量 */);return }
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
            Section(L10n.text("MEASUREMENT" /* 测量项 */)) { ForEach(MeasureField.builtin) { f in Toggle(f.name,isOn:Binding(get:{enabled.contains(f.id)},set:{if $0 { enabled.insert(f.id) } else { enabled.remove(f.id) }})) } }
            Section(L10n.text("CUSTOM_MEASUREMENTS" /* 自定义项目 */)) {
                ForEach(custom.indices,id:\.self) { i in Toggle(custom[i]["name"] as? String ?? "",isOn:Binding(get:{custom[i]["enabled"] as? Bool != false},set:{custom[i]["enabled"] = $0})) }
                TextField(L10n.text("MEASUREMENT_NAME" /* 项目名称 */),text:$name).textFieldStyle(.plain).stableInputLine().submitLabel(.done).onSubmit { GymKeyboard.dismiss() }
                Button(L10n.text("ADD_MEASUREMENT" /* 添加项目 */)) { let clean = name.trimmingCharacters(in:.whitespacesAndNewlines);guard !clean.isEmpty else{return};guard !custom.contains(where:{($0["name"] as? String ?? "").localizedCaseInsensitiveCompare(clean) == .orderedSame}) else {issue = L10n.text("THIS_MEASUREMENT_ALREADY_EXISTS" /* 该项目已存在。 */);return};custom.append(["id":UUID().uuidString,"name":String(clean.prefix(60)),"enabled":true]);name = "" }
            }
        }.operationAlert($issue).navigationTitle(L10n.text("CHOOSE_MEASUREMENTS" /* 选择测量项 */)).onAppear { guard !loaded else {return};loaded = true;original = store.state.filter {["measurementEnabled","customMeasurements"].contains($0.key)};enabled = Set(original["measurementEnabled"] as? [String] ?? MeasureField.builtin.map(\.id));custom = original["customMeasurements"] as? [[String:Any]] ?? [] }
            .toolbar { ToolbarItem(placement:.topBarTrailing) { Button(L10n.text("SAVE" /* 保存 */)) { Task { if await store.savePersonalFields(original:original,proposed:["measurementEnabled":enabled.sorted(),"customMeasurements":custom]) { dismiss() } else { issue = store.editError } } }.disabled(store.syncing) } }
    }
}

func personalNumber(_ value:Double)->String { String(format:"%.8g",value) }
