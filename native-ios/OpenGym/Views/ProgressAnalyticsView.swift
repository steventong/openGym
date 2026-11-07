import SwiftUI

struct ExerciseProgressView:View {
    @Environment(GymStore.self) private var store
    var initialID:String? = nil
    @State private var selected = ""
    @State private var metric = "points"
    @State private var days = 90
    @State private var data:[String:Any] = [:]
    @State private var issue:String?
    private var ids:[String] { Set(store.workouts.flatMap {$0["entries"] as? [[String:Any]] ?? []}.compactMap {$0["id"] as? String}).union(initialID.map {[$0]} ?? []).sorted { label($0) < label($1) } }
    private var points:[TrendPoint] {
        let raw:[[String:Any]]
        if metric == "sets" { raw = ((data["perSet"] as? [String:Any])?["lines"] as? [[String:Any]] ?? []).flatMap { line in (line["points"] as? [[String:Any]] ?? []).map { $0.merging(["series":String(format: String(localized: "SET_COUNT", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(describing: Int(number(line["n"]))))]) {_,new in new} } } } else { raw = data[metric] as? [[String:Any]] ?? [] }
        return TrendPoint.identified(raw.compactMap { p in
            guard number(p["t"])>0, let y = p["y"] as? Double else {return nil}
            let date = Date(timeIntervalSince1970:number(p["t"])/1000)
            guard days == 0 || date >= Calendar.current.date(byAdding:.day,value:-days,to:Date())! else {return nil}
            return TrendPoint(date:date,value:y,series:p["series"] as? String ?? "")
        })
    }
    private var unit:String { metric == "e1rm" ? store.unit:metric == "effort" ? data["effortUnit"] as? String ?? "RIR":metric == "max" ? String(localized: "REPS_A", bundle: AppLanguage.bundle, locale: AppLanguage.locale):metric == "sets" ? data["perSetUnit"] as? String ?? store.unit:data["unit"] as? String ?? store.unit }
    var body:some View {
        List {
            Section {
                Picker("EXERCISE",selection:$selected) { ForEach(ids,id:\.self) { Text(label($0)).tag($0) } }
                Picker("METRIC",selection:$metric) { Text("TOP_SET").tag("points");Text("ESTIMATED_ONE_REP_MAX").tag("e1rm");Text("SET_BY_SET").tag("sets");Text("EFFORT").tag("effort");Text("MAX_REPS").tag("max") }
                Picker("RANGE",selection:$days) { Text("ONE_MONTH").tag(30);Text("THREE_MONTHS").tag(90);Text("ONE_YEAR").tag(365);Text("ALL").tag(0) }.pickerStyle(.segmented)
                TrendChart(points:points,unit:unit).frame(height:210)
            }
            Section("HISTORY") {
                ForEach(Array(store.workouts.filter { ($0["entries"] as? [[String:Any]] ?? []).contains {$0["id"] as? String == selected} }.enumerated()),id:\.offset) { _,w in
                    VStack(alignment:.leading,spacing:6) {
                        Text("\(w["d"] as? String ?? "") · \(w["name"] as? String ?? String(localized: "WORKOUT", bundle: AppLanguage.bundle, locale: AppLanguage.locale))")
                        ForEach(Array((w["entries"] as? [[String:Any]] ?? []).filter {$0["id"] as? String == selected}.enumerated()),id:\.offset) { _,entry in
                            Text(entrySummary(entry)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }.operationAlert($issue).navigationTitle("EXERCISE_PROGRESS").navigationBarTitleDisplayMode(.inline)
            .onAppear { if selected.isEmpty { selected = initialID ?? ids.first ?? "" };reload() }
            .onChange(of:selected) {_,_ in reload()}.onChange(of:store.lastSync) {_,_ in reload()}
    }
    private func label(_ id:String)->String { store.exercise(id)?.name ?? store.workouts.flatMap {$0["entries"] as? [[String:Any]] ?? []}.first {$0["id"] as? String == id}?["n"] as? String ?? id }
    private func reload() { guard !selected.isEmpty else{return};do {data = try store.personalInfo("progress",["id":selected]);issue = nil} catch {issue = error.localizedDescription} }
    private func entrySummary(_ entry:[String:Any])->String {
        let w:[String:Any] = ["name":"","d":"","entries":[entry]]
        return (try? store.personalInfo("workoutText",["workout":w,"names":[selected:label(selected)]]))?["text"] as? String ?? ""
    }
}
struct MuscleAnalyticsView:View {
    @Environment(GymStore.self) private var store
    @State private var data:[String:Any] = [:]
    @State private var days = 30
    @State private var metric = "load"
    @State private var issue:String?
    private var muscles:[[String:Any]] { data["muscles"] as? [[String:Any]] ?? [] }
    var body:some View {
        List {
            Section {
                Picker("METRIC",selection:$metric) { Text("COMPLETED_SETS").tag("load");Text("WEEKLY_SCHEDULE").tag("plan");Text("ESTIMATED_FATIGUE").tag("fatigue");Text("STRENGTH_RETENTION").tag("strength") }
                if metric == "load" { Picker("RANGE",selection:$days) { Text("SEVEN_DAYS").tag(7);Text("THREEZERO_DAYS").tag(30);Text("NINEZERO_DAYS").tag(90);Text("ALL").tag(0) }.pickerStyle(.segmented) }
                ForEach(Array(muscles.enumerated()),id:\.offset) { _,muscle in
                    let id = muscle["id"] as? String ?? "", value = number((data[metric] as? [String:Any])?[id])
                    VStack(alignment:.leading,spacing:6) {
                        HStack { Text(String(localized: String.LocalizationValue(id), table: "Muscles", bundle: AppLanguage.bundle, locale: AppLanguage.locale));Spacer();Text(["fatigue","strength"].contains(metric) ? "\(Int(value*100))%":String(format: String(localized: "COUNT_SETS", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(describing: decimal(value)))).foregroundStyle(.secondary) }
                        ProgressView(value:value,total:["fatigue","strength"].contains(metric) ? max(1,value):max(1,((data[metric] as? [String:Any]) ?? [:]).values.map{number($0)}.max() ?? 1)).tint(GymTheme.green)
                    }
                }
            }
        }.operationAlert($issue).navigationTitle("TRAINING_BY_MUSCLE").navigationBarTitleDisplayMode(.inline).onAppear {reload()}.onChange(of:days) {_,_ in reload()}.onChange(of:store.lastSync) {_,_ in reload()}
    }
    private func reload() {do {data = try store.personalInfo("muscles",["days":days,"now":Date().timeIntervalSince1970*1000]);issue = nil} catch {issue = error.localizedDescription} }
}
struct PersonalStatsHub:View {
    @Environment(\.dismiss) private var dismiss
    var body:some View {
        NavigationStack {
            List {
                NavigationLink("EXERCISE_PROGRESS_AND_HISTORY") { ExerciseProgressView() }
                NavigationLink("STRUCTURAL_BALANCE") { StructuralBalanceView() }
                NavigationLink("TRAINING_BY_MUSCLE") { MuscleAnalyticsView() }
                NavigationLink("WEIGHT_HISTORY_AND_GOAL") { BodyRecordsView(measurements:false) }
                NavigationLink("BODY_MEASUREMENTS") { BodyRecordsView(measurements:true) }
            }.navigationTitle("PROGRESS_ANALYSIS").toolbar { ToolbarItem(placement:.topBarTrailing) { Button("DONE") {dismiss()} } }
        }
    }
}

struct StructuralBalanceView:View {
    @Environment(GymStore.self) private var store
    @State private var template = "poliquin"
    @State private var data:[String:Any] = [:]
    @State private var selected:RawRow?
    @State private var issue:String?
    private var roles:[[String:Any]] { (data["template"] as? [String:Any])?["roles"] as? [[String:Any]] ?? [] }
    var body:some View {
        List {
            Section {
                Picker("REFERENCE_SYSTEM",selection:$template) {ForEach(Array((data["templates"] as? [[String:Any]] ?? []).enumerated()),id:\.offset) {_,t in Text(t["name"] as? String ?? "").tag(t["id"] as? String ?? "")} }
                HStack { Text("REFERENCE_RATIO"); Spacer(); ExplanationButton(title: String(localized: "STRUCTURAL_BALANCE", bundle: AppLanguage.bundle, locale: AppLanguage.locale), message: String(localized: "COMPARES_YOUR_LOGGED_LIFTS_WITH_REFERENCE_RATIOS_RATIOS_ARE_UNAVAILABLE_WITHOUT_A", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) }
            }
            ForEach(Array(roles.enumerated()),id:\.offset) {_,role in
                let result = (data["result"] as? [[String:Any]] ?? []).first {$0["roleId"] as? String == role["id"] as? String} ?? [:]
                let id = result["configuredExerciseId"] as? String ?? ""
                Section(role["label"] as? String ?? String(localized: "EXERCISE", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) {
                    Text(store.exercise(id)?.name ?? id)
                    if let pct = result["actualPct"] as? Double {LabeledContent("CURRENT_RATIO",value:decimal(pct)+"%")}
                    Text(status(result)).foregroundStyle(.secondary)
                    Button("CHOOSE_MATCHING_EXERCISE") {selected = RawRow(raw:role)}
                    if result["isOverridden"] as? Bool == true {Button("RESTORE_DEFAULT_EXERCISES") {assign(role,nil)}}
                }
            }
        }.operationAlert($issue).navigationTitle("STRUCTURAL_BALANCE").navigationBarTitleDisplayMode(.inline)
            .onAppear {reload()}.onChange(of:template){_,_ in reload()}.onChange(of:store.lastSync){_,_ in reload()}
            .sheet(item:$selected) {row in ExercisePicker(title:String(localized: "CHOOSE_MATCHING_EXERCISE", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) {ex in assign(row.raw,ex.id);selected = nil} }
    }
    private func status(_ row:[String:Any])->String {
        if row["needsBodyweight"] as? Bool == true{return String(localized: "BODY_WEIGHT_RECORD_NEEDED", bundle: AppLanguage.bundle, locale: AppLanguage.locale)};if row["needsAnchor"] as? Bool == true{return String(localized: "BASELINE_LIFT_NEEDED", bundle: AppLanguage.bundle, locale: AppLanguage.locale)}
        return ["no-data":String(localized: "NO_COMPARABLE_RECORDS_YET", bundle: AppLanguage.bundle, locale: AppLanguage.locale),"noData":String(localized: "NO_COMPARABLE_RECORDS_YET", bundle: AppLanguage.bundle, locale: AppLanguage.locale),"balanced":String(localized: "AT_REFERENCE_RATIO", bundle: AppLanguage.bundle, locale: AppLanguage.locale),"weak":String(localized: "BELOW_REFERENCE_RATIO", bundle: AppLanguage.bundle, locale: AppLanguage.locale),"borderline":String(localized: "NEAR_REFERENCE_RATIO", bundle: AppLanguage.bundle, locale: AppLanguage.locale),"strong":String(localized: "ABOVE_REFERENCE_RATIO", bundle: AppLanguage.bundle, locale: AppLanguage.locale)][row["status"] as? String ?? ""] ?? row["status"] as? String ?? String(localized: "NO_DATA_YET", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
    }
    private func reload() {do {data = try store.personalInfo("balance",["template":template]);issue = nil} catch {issue = error.localizedDescription} }
    private func assign(_ role:[String:Any],_ id:String?) {
        let original = store.state.filter {$0.key == "balanceOverrides"};var overrides = original["balanceOverrides"] as? [String:Any] ?? [:]
        overrides[template+":"+(role["id"] as? String ?? "")] = ["id":id as Any? ?? NSNull(),"_ts":Date().timeIntervalSince1970*1000]
        Task {if await store.savePersonalFields(original:original,proposed:["balanceOverrides":overrides]) {reload()} else {issue = store.editError}}
    }
}
