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
                    Picker("MEASUREMENT",selection:$selected) { ForEach(fields) { f in Text(f.name).tag(f.id) } }
                }
                Picker("TIME_RANGE",selection:$range) { Text("ONE_MONTH").tag(30);Text("THREE_MONTHS").tag(90);Text("ONE_YEAR").tag(365);Text("ALL").tag(0) }.pickerStyle(.segmented)
                TrendChart(points:points,unit:measurements ? (selected == "bodyFat" ? "%":store.unit == "lb" ? "in":"cm") : store.unit).frame(height:180)
                Button(measurements ? String(localized: "LOG_MEASUREMENTS", bundle: AppLanguage.bundle, locale: AppLanguage.locale) : String(localized: "LOG_BODY_WEIGHT", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) { editor = PersonalRecord() }.accessibilityIdentifier("add-body-record")
            }
            if !measurements {
                Section(String(format: String(localized: "TARGET_WEIGHT_COUNT", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(describing: goalUnit))) {
                    BufferedTextField(String(localized: "LEAVE_BLANK_TO_REMOVE_GOAL", bundle: AppLanguage.bundle, locale: AppLanguage.locale),text:$goal).textFieldStyle(.plain).stableInputLine().submitLabel(.done).onSubmit { GymKeyboard.dismiss() }.keyboardType(.decimalPad).invalidInput(invalidGoal)
                        .onChange(of: goal) { _, _ in invalidGoal = false }
                    Button("SAVE_GOAL") {
                        inputBuffer.commitAll()
                        guard goal.isEmpty || (TrainingInput.value(goal).map { $0 > 0 && $0 < 1000 } ?? false) else { invalidGoal = true; issue = String(localized: "ENTER_A_VALID_TARGET_WEIGHT", bundle: AppLanguage.bundle, locale: AppLanguage.locale); return }
                        let unit = goalUnit
                        Task { if await store.savePersonalFields(original:goalOriginal,proposed:goal.isEmpty ? [:] : ["targetW":TrainingInput.value(goal)!],unit:unit) { goalOriginal = store.state.filter { $0.key == "targetW" } } else { issue = store.editError } }
                    }.disabled(store.syncing)
                }
            } else { Section { NavigationLink("CHOOSE_MEASUREMENTS") { MeasurementFieldsView() } } }
            Section("HISTORY") {
                if records.isEmpty { Text("NO_RECORDS_YET").foregroundStyle(.secondary) }
                ForEach(Array(records.reversed().enumerated()),id:\.offset) { _,row in
                    HStack {
                        VStack(alignment:.leading,spacing:5) {
                            Text(row["d"] as? String ?? "")
                            Text(summary(row)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { editor = PersonalRecord(raw:row) } label:{Image(systemName:"pencil").frame(width:44,height:44)}.buttonStyle(.borderless).accessibilityLabel(String(format: String(localized: "EDIT_COUNT", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(describing: row["d"] as? String ?? "")))
                        Button(role:.destructive) { deleting = PersonalRecord(raw:row) } label:{Image(systemName:"trash").frame(width:44,height:44)}.buttonStyle(.borderless).accessibilityLabel("DELETE_RECORD")
                    }
                }
            }
        }.environment(\.inputCommitBuffer, inputBuffer).operationAlert($issue).navigationTitle(measurements ? String(localized: "BODY_MEASUREMENTS", bundle: AppLanguage.bundle, locale: AppLanguage.locale) : String(localized: "BODY_WEIGHT_RECORDS", bundle: AppLanguage.bundle, locale: AppLanguage.locale)).navigationBarTitleDisplayMode(.inline)
            .keyboardDismissToolbar()
            .onAppear { guard !goalLoaded else { return }; goalLoaded = true; goalUnit = store.unit; goalOriginal = store.state.filter{$0.key == "targetW"}; goal = store.state["targetW"].map { personalNumber(number($0)) } ?? "" }
            .sheet(item:$editor) { record in BodyRecordEditor(original:record.raw,measurements:measurements,fields:fields,unit:store.unit) }
            .confirmationDialog("DELETE_THIS_RECORD",isPresented:Binding(get:{deleting != nil},set:{if !$0 { deleting = nil }}),titleVisibility:.visible) {
                Button("DELETE",role:.destructive) { guard let row = deleting?.raw else { return }; Task { if !(await store.savePersonalRecord(collection:collection,key:"d",original:row,proposed:nil)) { issue = store.editError } } }
                Button("CANCEL",role:.cancel) {}
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
        if points.isEmpty { ContentUnavailableView(String(localized: "NO_DATA_YET", bundle: AppLanguage.bundle, locale: AppLanguage.locale),systemImage:"chart.xyaxis.line",description: nil) }
        else {
            Chart(points) { p in
                LineMark(x:.value(String(localized: "DATE", bundle: AppLanguage.bundle, locale: AppLanguage.locale),p.date),y:.value(unit,p.value)).foregroundStyle(by:.value(String(localized: "SETS_A", bundle: AppLanguage.bundle, locale: AppLanguage.locale),p.series))
                PointMark(x:.value(String(localized: "DATE", bundle: AppLanguage.bundle, locale: AppLanguage.locale),p.date),y:.value(unit,p.value)).foregroundStyle(by:.value(String(localized: "SETS_A", bundle: AppLanguage.bundle, locale: AppLanguage.locale),p.series))
            }.chartYScale(domain:.automatic(includesZero:false)).chartLegend(points.allSatisfy{$0.series.isEmpty} ? .hidden : .visible)
                .accessibilityLabel(String(format: String(localized: "COUNT_TREND_POINTS_MEASURED_IN_COUNT", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(describing: points.count), String(describing: unit)))
        }
    }
}
func dateFromDay(_ day:String)->Date? { let f = DateFormatter();f.locale = Locale(identifier:"en_US_POSIX");f.dateFormat = "yyyy-MM-dd";return f.date(from:day) }
struct MeasureField:Identifiable {
    let id:String;let name:String
    static var builtin:[MeasureField] { zip(["neck","shoulders","chest","waist","hips","abdomen","upperArmLeft","upperArmRight","forearmLeft","forearmRight","wristLeft","wristRight","thighLeft","thighRight","calfLeft","calfRight","ankleLeft","ankleRight","bodyFat"],[String(localized: "MEASUREMENT_NECK", bundle: AppLanguage.bundle, locale: AppLanguage.locale),String(localized: "MEASUREMENT_SHOULDERS", bundle: AppLanguage.bundle, locale: AppLanguage.locale),String(localized: "MEASUREMENT_CHEST", bundle: AppLanguage.bundle, locale: AppLanguage.locale),String(localized: "WAIST_A", bundle: AppLanguage.bundle, locale: AppLanguage.locale),String(localized: "HIPS", bundle: AppLanguage.bundle, locale: AppLanguage.locale),String(localized: "ABDOMEN", bundle: AppLanguage.bundle, locale: AppLanguage.locale),String(localized: "LEFT_UPPER_ARM", bundle: AppLanguage.bundle, locale: AppLanguage.locale),String(localized: "RIGHT_UPPER_ARM", bundle: AppLanguage.bundle, locale: AppLanguage.locale),String(localized: "LEFT_FOREARM", bundle: AppLanguage.bundle, locale: AppLanguage.locale),String(localized: "RIGHT_FOREARM", bundle: AppLanguage.bundle, locale: AppLanguage.locale),String(localized: "LEFT_WRIST", bundle: AppLanguage.bundle, locale: AppLanguage.locale),String(localized: "RIGHT_WRIST", bundle: AppLanguage.bundle, locale: AppLanguage.locale),String(localized: "LEFT_THIGH", bundle: AppLanguage.bundle, locale: AppLanguage.locale),String(localized: "RIGHT_THIGH", bundle: AppLanguage.bundle, locale: AppLanguage.locale),String(localized: "LEFT_CALF", bundle: AppLanguage.bundle, locale: AppLanguage.locale),String(localized: "RIGHT_CALF", bundle: AppLanguage.bundle, locale: AppLanguage.locale),String(localized: "LEFT_ANKLE", bundle: AppLanguage.bundle, locale: AppLanguage.locale),String(localized: "RIGHT_ANKLE", bundle: AppLanguage.bundle, locale: AppLanguage.locale),String(localized: "BODY_FAT", bundle: AppLanguage.bundle, locale: AppLanguage.locale)]).map { MeasureField(id:$0,name:$1) } }
    static func all(_ state:[String:Any])->[MeasureField] {
        var result = builtin
        var seen = Set<String>()
        let customs = (state["customMeasurements"] as? [[String:Any]] ?? []) + (state["measurements"] as? [[String:Any]] ?? []).flatMap { $0["other"] as? [[String:Any]] ?? [] }
        for c in customs { if let id = c["id"] as? String, seen.insert(id).inserted { result.append(MeasureField(id:"other:"+id,name:c["name"] as? String ?? String(localized: "CUSTOM", bundle: AppLanguage.bundle, locale: AppLanguage.locale))) } }
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
        guard measurements else { return [MeasureField(id:"w",name:String(localized: "BODY_WEIGHT", bundle: AppLanguage.bundle, locale: AppLanguage.locale))] }
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
                DatePicker("DATE",selection:$date,in:...Date(),displayedComponents:.date)
                ForEach(visible) { f in HStack {
                    Text(f.name);Spacer()
                    TextField("NOT_ENTERED",text:Binding(get:{values[f.id] ?? ""},set:{values[f.id] = $0; if invalidField == f.id { invalidField = nil }})).textFieldStyle(.plain).stableInputLine().submitLabel(.done).onSubmit { GymKeyboard.dismiss() }
                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width:110).invalidInput(invalidField == f.id).accessibilityIdentifier("body-field-\(f.id)")
                    Text(f.id == "bodyFat" ? "%":measurements ? (unit == "lb" ? "in":"cm"):unit).font(.caption).foregroundStyle(.secondary)
                } }
            }.operationAlert($issue).navigationTitle(measurements ? String(localized: "LOG_MEASUREMENTS", bundle: AppLanguage.bundle, locale: AppLanguage.locale) : String(localized: "LOG_BODY_WEIGHT", bundle: AppLanguage.bundle, locale: AppLanguage.locale)).navigationBarTitleDisplayMode(.inline)
                .keyboardDismissToolbar()
                .toolbar { ToolbarItem(placement:.topBarLeading) { Button("CANCEL") { dismiss() } };ToolbarItem(placement:.topBarTrailing) { Button("SAVE") { save() }.disabled(store.syncing).accessibilityIdentifier("save-body-record") } }
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
                guard let n = TrainingInput.value(text), n>0, n <= (f.id == "bodyFat" ? 100:2000) else { invalidField = f.id; issue = String(format: String(localized: "CHECK_THE_VALUE_FOR_COUNT", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(describing: f.name));return }
                value = measurements && f.id != "bodyFat" && unit == "lb" ? (n*2.54*10).rounded()/10 : n;hasValue = true
            }
            if f.id.hasPrefix("other:") {
                let id = String(f.id.dropFirst(6)); let i = others.firstIndex {$0["id"] as? String == id}
                var item = i.map {others[$0]} ?? ["id":id,"name":f.name];item["value"] = value.map { $0 as Any } ?? NSNull()
                if let i { others[i] = item } else { others.append(item) }
            } else { row[f.id] = value.map { $0 as Any } ?? NSNull() }
        }
        guard hasValue else { invalidField = visible.first?.id; issue = String(localized: "ENTER_AT_LEAST_ONE_MEASUREMENT", bundle: AppLanguage.bundle, locale: AppLanguage.locale);return }
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
            Section("MEASUREMENT") { ForEach(MeasureField.builtin) { f in Toggle(f.name,isOn:Binding(get:{enabled.contains(f.id)},set:{if $0 { enabled.insert(f.id) } else { enabled.remove(f.id) }})) } }
            Section("CUSTOM_MEASUREMENTS") {
                ForEach(custom.indices,id:\.self) { i in Toggle(custom[i]["name"] as? String ?? "",isOn:Binding(get:{custom[i]["enabled"] as? Bool != false},set:{custom[i]["enabled"] = $0})) }
                TextField("MEASUREMENT_NAME",text:$name).textFieldStyle(.plain).stableInputLine().submitLabel(.done).onSubmit { GymKeyboard.dismiss() }
                Button("ADD_MEASUREMENT") { let clean = name.trimmingCharacters(in:.whitespacesAndNewlines);guard !clean.isEmpty else{return};guard !custom.contains(where:{($0["name"] as? String ?? "").localizedCaseInsensitiveCompare(clean) == .orderedSame}) else {issue = String(localized: "THIS_MEASUREMENT_ALREADY_EXISTS", bundle: AppLanguage.bundle, locale: AppLanguage.locale);return};custom.append(["id":UUID().uuidString,"name":String(clean.prefix(60)),"enabled":true]);name = "" }
            }
        }.operationAlert($issue).navigationTitle("CHOOSE_MEASUREMENTS").onAppear { guard !loaded else {return};loaded = true;original = store.state.filter {["measurementEnabled","customMeasurements"].contains($0.key)};enabled = Set(original["measurementEnabled"] as? [String] ?? MeasureField.builtin.map(\.id));custom = original["customMeasurements"] as? [[String:Any]] ?? [] }
            .toolbar { ToolbarItem(placement:.topBarTrailing) { Button("SAVE") { Task { if await store.savePersonalFields(original:original,proposed:["measurementEnabled":enabled.sorted(),"customMeasurements":custom]) { dismiss() } else { issue = store.editError } } }.disabled(store.syncing) } }
    }
}

func personalNumber(_ value:Double)->String { String(format:"%.8g",value) }
