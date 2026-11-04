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
        if metric == "sets" { raw = ((data["perSet"] as? [String:Any])?["lines"] as? [[String:Any]] ?? []).flatMap { line in (line["points"] as? [[String:Any]] ?? []).map { $0.merging(["series":L10n.text("SET_COUNT" /* 第 {0} 组 */, Int(number(line["n"])))]) {_,new in new} } } } else { raw = data[metric] as? [[String:Any]] ?? [] }
        return TrendPoint.identified(raw.compactMap { p in
            guard number(p["t"])>0, let y = p["y"] as? Double else {return nil}
            let date = Date(timeIntervalSince1970:number(p["t"])/1000)
            guard days == 0 || date >= Calendar.current.date(byAdding:.day,value:-days,to:Date())! else {return nil}
            return TrendPoint(date:date,value:y,series:p["series"] as? String ?? "")
        })
    }
    private var unit:String { metric == "e1rm" ? store.unit:metric == "effort" ? data["effortUnit"] as? String ?? "RIR":metric == "max" ? L10n.text("REPS_A" /* 次 */):metric == "sets" ? data["perSetUnit"] as? String ?? store.unit:data["unit"] as? String ?? store.unit }
    var body:some View {
        List {
            Section {
                Picker(L10n.text("EXERCISE" /* 动作 */),selection:$selected) { ForEach(ids,id:\.self) { Text(label($0)).tag($0) } }
                Picker(L10n.text("METRIC" /* 指标 */),selection:$metric) { Text(L10n.text("TOP_SET" /* 最佳组 */)).tag("points");Text(L10n.text("ESTIMATED_ONE_REP_MAX" /* 估算 1RM */)).tag("e1rm");Text(L10n.text("SET_BY_SET" /* 逐组 */)).tag("sets");Text(L10n.text("EFFORT" /* 用力程度 */)).tag("effort");Text(L10n.text("MAX_REPS" /* 力竭次数 */)).tag("max") }
                Picker(L10n.text("RANGE" /* 范围 */),selection:$days) { Text(L10n.text("ONE_MONTH" /* 1 月 */)).tag(30);Text(L10n.text("THREE_MONTHS" /* 3 月 */)).tag(90);Text(L10n.text("ONE_YEAR" /* 1 年 */)).tag(365);Text(L10n.text("ALL" /* 全部 */)).tag(0) }.pickerStyle(.segmented)
                TrendChart(points:points,unit:unit).frame(height:210)
            }
            Section(L10n.text("HISTORY" /* 历史 */)) {
                ForEach(Array(store.workouts.filter { ($0["entries"] as? [[String:Any]] ?? []).contains {$0["id"] as? String == selected} }.enumerated()),id:\.offset) { _,w in
                    VStack(alignment:.leading,spacing:6) {
                        Text("\(w["d"] as? String ?? "") · \(w["name"] as? String ?? L10n.text("WORKOUT" /* 训练 */))")
                        ForEach(Array((w["entries"] as? [[String:Any]] ?? []).filter {$0["id"] as? String == selected}.enumerated()),id:\.offset) { _,entry in
                            Text(entrySummary(entry)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }.operationAlert($issue).navigationTitle(L10n.text("EXERCISE_PROGRESS" /* 动作进步 */)).navigationBarTitleDisplayMode(.inline)
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
                Picker(L10n.text("METRIC" /* 指标 */),selection:$metric) { Text(L10n.text("COMPLETED_SETS" /* 完成组数 */)).tag("load");Text(L10n.text("WEEKLY_SCHEDULE" /* 每周计划 */)).tag("plan");Text(L10n.text("ESTIMATED_FATIGUE" /* 疲劳估算 */)).tag("fatigue");Text(L10n.text("STRENGTH_RETENTION" /* 力量保留 */)).tag("strength") }
                if metric == "load" { Picker(L10n.text("RANGE" /* 范围 */),selection:$days) { Text(L10n.text("SEVEN_DAYS" /* 7 天 */)).tag(7);Text(L10n.text("THREEZERO_DAYS" /* 30 天 */)).tag(30);Text(L10n.text("NINEZERO_DAYS" /* 90 天 */)).tag(90);Text(L10n.text("ALL" /* 全部 */)).tag(0) }.pickerStyle(.segmented) }
                ForEach(Array(muscles.enumerated()),id:\.offset) { _,muscle in
                    let id = muscle["id"] as? String ?? "", value = number((data[metric] as? [String:Any])?[id])
                    VStack(alignment:.leading,spacing:6) {
                        HStack { Text(muscleName(id));Spacer();Text(["fatigue","strength"].contains(metric) ? "\(Int(value*100))%":L10n.text("COUNT_SETS" /* {0} 组 */, decimal(value))).foregroundStyle(.secondary) }
                        ProgressView(value:value,total:["fatigue","strength"].contains(metric) ? max(1,value):max(1,((data[metric] as? [String:Any]) ?? [:]).values.map{number($0)}.max() ?? 1)).tint(GymTheme.green)
                    }
                }
            }
        }.operationAlert($issue).navigationTitle(L10n.text("TRAINING_BY_MUSCLE" /* 肌群训练分布 */)).navigationBarTitleDisplayMode(.inline).onAppear {reload()}.onChange(of:days) {_,_ in reload()}.onChange(of:store.lastSync) {_,_ in reload()}
    }
    private func reload() {do {data = try store.personalInfo("muscles",["days":days,"now":Date().timeIntervalSince1970*1000]);issue = nil} catch {issue = error.localizedDescription} }
}
struct PersonalStatsHub:View {
    @Environment(\.dismiss) private var dismiss
    var body:some View {
        NavigationStack {
            List {
                NavigationLink(L10n.text("EXERCISE_PROGRESS_AND_HISTORY" /* 动作进步与历史 */)) { ExerciseProgressView() }
                NavigationLink(L10n.text("STRUCTURAL_BALANCE" /* 结构平衡 */)) { StructuralBalanceView() }
                NavigationLink(L10n.text("TRAINING_BY_MUSCLE" /* 肌群训练分布 */)) { MuscleAnalyticsView() }
                NavigationLink(L10n.text("WEIGHT_HISTORY_AND_GOAL" /* 体重历史与目标 */)) { BodyRecordsView(measurements:false) }
                NavigationLink(L10n.text("BODY_MEASUREMENTS" /* 身体围度 */)) { BodyRecordsView(measurements:true) }
            }.navigationTitle(L10n.text("PROGRESS_ANALYSIS" /* 进步分析 */)).toolbar { ToolbarItem(placement:.topBarTrailing) { Button(L10n.text("DONE" /* 完成 */)) {dismiss()} } }
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
                Picker(L10n.text("REFERENCE_SYSTEM" /* 参考体系 */),selection:$template) {ForEach(Array((data["templates"] as? [[String:Any]] ?? []).enumerated()),id:\.offset) {_,t in Text(t["name"] as? String ?? "").tag(t["id"] as? String ?? "")} }
                HStack { Text(L10n.text("REFERENCE_RATIO" /* 参考比例 */)); Spacer(); ExplanationButton(title: L10n.text("STRUCTURAL_BALANCE" /* 结构平衡 */), message: L10n.text("COMPARES_YOUR_LOGGED_LIFTS_WITH_REFERENCE_RATIOS_RATIOS_ARE_UNAVAILABLE_WITHOUT_A" /* 基于已记录动作比较参考比例；缺少基准动作或体重时不提供比例。 */)) }
            }
            ForEach(Array(roles.enumerated()),id:\.offset) {_,role in
                let result = (data["result"] as? [[String:Any]] ?? []).first {$0["roleId"] as? String == role["id"] as? String} ?? [:]
                let id = result["configuredExerciseId"] as? String ?? ""
                Section(role["label"] as? String ?? L10n.text("EXERCISE" /* 动作 */)) {
                    Text(store.exercise(id)?.name ?? id)
                    if let pct = result["actualPct"] as? Double {LabeledContent(L10n.text("CURRENT_RATIO" /* 当前比例 */),value:decimal(pct)+"%")}
                    Text(status(result)).foregroundStyle(.secondary)
                    Button(L10n.text("CHOOSE_MATCHING_EXERCISE" /* 选择对应动作 */)) {selected = RawRow(raw:role)}
                    if result["isOverridden"] as? Bool == true {Button(L10n.text("RESTORE_DEFAULT_EXERCISES" /* 恢复默认动作 */)) {assign(role,nil)}}
                }
            }
        }.operationAlert($issue).navigationTitle(L10n.text("STRUCTURAL_BALANCE" /* 结构平衡 */)).navigationBarTitleDisplayMode(.inline)
            .onAppear {reload()}.onChange(of:template){_,_ in reload()}.onChange(of:store.lastSync){_,_ in reload()}
            .sheet(item:$selected) {row in ExercisePicker(title:L10n.text("CHOOSE_MATCHING_EXERCISE" /* 选择对应动作 */)) {ex in assign(row.raw,ex.id);selected = nil} }
    }
    private func status(_ row:[String:Any])->String {
        if row["needsBodyweight"] as? Bool == true{return L10n.text("BODY_WEIGHT_RECORD_NEEDED" /* 需要体重记录 */)};if row["needsAnchor"] as? Bool == true{return L10n.text("BASELINE_LIFT_NEEDED" /* 需要基准动作记录 */)}
        return ["no-data":L10n.text("NO_COMPARABLE_RECORDS_YET" /* 暂无可比较记录 */),"noData":L10n.text("NO_COMPARABLE_RECORDS_YET" /* 暂无可比较记录 */),"balanced":L10n.text("AT_REFERENCE_RATIO" /* 达到参考比例 */),"weak":L10n.text("BELOW_REFERENCE_RATIO" /* 低于参考比例 */),"borderline":L10n.text("NEAR_REFERENCE_RATIO" /* 接近参考比例 */),"strong":L10n.text("ABOVE_REFERENCE_RATIO" /* 高于参考比例 */)][row["status"] as? String ?? ""] ?? row["status"] as? String ?? L10n.text("NO_DATA_YET" /* 暂无数据 */)
    }
    private func reload() {do {data = try store.personalInfo("balance",["template":template]);issue = nil} catch {issue = error.localizedDescription} }
    private func assign(_ role:[String:Any],_ id:String?) {
        let original = store.state.filter {$0.key == "balanceOverrides"};var overrides = original["balanceOverrides"] as? [String:Any] ?? [:]
        overrides[template+":"+(role["id"] as? String ?? "")] = ["id":id as Any? ?? NSNull(),"_ts":Date().timeIntervalSince1970*1000]
        Task {if await store.savePersonalFields(original:original,proposed:["balanceOverrides":overrides]) {reload()} else {issue = store.editError}}
    }
}
