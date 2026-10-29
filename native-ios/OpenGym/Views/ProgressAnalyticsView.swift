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
        if metric == "sets" { raw = ((data["perSet"] as? [String:Any])?["lines"] as? [[String:Any]] ?? []).flatMap { line in (line["points"] as? [[String:Any]] ?? []).map { $0.merging(["series":"第 \(Int(number(line["n"]))) 组"]) {_,new in new} } } } else { raw = data[metric] as? [[String:Any]] ?? [] }
        return raw.compactMap { p in
            guard number(p["t"])>0, let y = p["y"] as? Double else {return nil}
            let date = Date(timeIntervalSince1970:number(p["t"])/1000)
            guard days == 0 || date >= Calendar.current.date(byAdding:.day,value:-days,to:Date())! else {return nil}
            return TrendPoint(date:date,value:y,series:p["series"] as? String ?? "")
        }
    }
    private var unit:String { metric == "e1rm" ? store.unit:metric == "effort" ? data["effortUnit"] as? String ?? "RIR":metric == "max" ? "次":metric == "sets" ? data["perSetUnit"] as? String ?? store.unit:data["unit"] as? String ?? store.unit }
    var body:some View {
        List {
            Section {
                Picker("动作",selection:$selected) { ForEach(ids,id:\.self) { Text(label($0)).tag($0) } }
                Picker("指标",selection:$metric) { Text("最佳组").tag("points");Text("估算 1RM").tag("e1rm");Text("逐组").tag("sets");Text("用力程度").tag("effort");Text("Max 次数").tag("max") }
                Picker("范围",selection:$days) { Text("1 月").tag(30);Text("3 月").tag(90);Text("1 年").tag(365);Text("全部").tag(0) }.pickerStyle(.segmented)
                TrendChart(points:points,unit:unit).frame(height:210)
                if metric == "e1rm" { Text("按所选公式计算，次数过高或无有效负重时不提供估算。").font(.caption).foregroundStyle(.secondary) }
            }
            if let issue { Text(issue).foregroundStyle(.orange) }
            Section("历史记录") {
                ForEach(Array(store.workouts.filter { ($0["entries"] as? [[String:Any]] ?? []).contains {$0["id"] as? String == selected} }.enumerated()),id:\.offset) { _,w in
                    VStack(alignment:.leading,spacing:6) {
                        Text("\(w["d"] as? String ?? "") · \(w["name"] as? String ?? "训练")")
                        ForEach(Array((w["entries"] as? [[String:Any]] ?? []).filter {$0["id"] as? String == selected}.enumerated()),id:\.offset) { _,entry in
                            Text(entrySummary(entry)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }.navigationTitle("动作进步").navigationBarTitleDisplayMode(.inline)
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
                Picker("指标",selection:$metric) { Text("完成组数").tag("load");Text("每周计划").tag("plan");Text("疲劳估算").tag("fatigue");Text("力量保留").tag("strength") }
                if metric == "load" { Picker("范围",selection:$days) { Text("7 天").tag(7);Text("30 天").tag(30);Text("90 天").tag(90);Text("全部").tag(0) }.pickerStyle(.segmented) }
                if ["fatigue","strength"].contains(metric) { Text("根据训练记录计算的趋势估计，用于了解训练分布。").font(.caption).foregroundStyle(.secondary) }
                ForEach(Array(muscles.enumerated()),id:\.offset) { _,muscle in
                    let id = muscle["id"] as? String ?? "", value = number((data[metric] as? [String:Any])?[id])
                    VStack(alignment:.leading,spacing:6) {
                        HStack { Text(muscleName(id));Spacer();Text(["fatigue","strength"].contains(metric) ? "\(Int(value*100))%":decimal(value)+" 组").foregroundStyle(.secondary) }
                        ProgressView(value:value,total:["fatigue","strength"].contains(metric) ? max(1,value):max(1,((data[metric] as? [String:Any]) ?? [:]).values.map{number($0)}.max() ?? 1)).tint(GymTheme.green)
                    }
                }
            }
            if let issue { Text(issue).foregroundStyle(.orange) }
        }.navigationTitle("肌群训练分布").navigationBarTitleDisplayMode(.inline).onAppear {reload()}.onChange(of:days) {_,_ in reload()}.onChange(of:store.lastSync) {_,_ in reload()}
    }
    private func reload() {do {data = try store.personalInfo("muscles",["days":days,"now":Date().timeIntervalSince1970*1000]);issue = nil} catch {issue = error.localizedDescription} }
}
struct PersonalStatsHub:View {
    @Environment(\.dismiss) private var dismiss
    var body:some View {
        NavigationStack {
            List {
                NavigationLink("动作进步与历史") { ExerciseProgressView() }
                NavigationLink("结构平衡") { StructuralBalanceView() }
                NavigationLink("肌群训练分布") { MuscleAnalyticsView() }
                NavigationLink("体重历史与目标") { BodyRecordsView(measurements:false) }
                NavigationLink("身体围度") { BodyRecordsView(measurements:true) }
            }.navigationTitle("进步分析").toolbar { ToolbarItem(placement:.topBarTrailing) { Button("完成") {dismiss()} } }
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
                Picker("参考体系",selection:$template) {ForEach(Array((data["templates"] as? [[String:Any]] ?? []).enumerated()),id:\.offset) {_,t in Text(t["name"] as? String ?? "").tag(t["id"] as? String ?? "")} }
                Text("按网页相同的参考比例比较已记录动作。缺少基准动作或体重时会显示缺项，不会用零替代。").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(Array(roles.enumerated()),id:\.offset) {_,role in
                let result = (data["result"] as? [[String:Any]] ?? []).first {$0["roleId"] as? String == role["id"] as? String} ?? [:]
                let id = result["configuredExerciseId"] as? String ?? ""
                Section(role["label"] as? String ?? "动作") {
                    Text(store.exercise(id)?.name ?? id)
                    if let pct = result["actualPct"] as? Double {LabeledContent("当前比例",value:decimal(pct)+"%")}
                    Text(status(result)).foregroundStyle(.secondary)
                    Button("选择对应动作") {selected = RawRow(raw:role)}
                    if result["isOverridden"] as? Bool == true {Button("恢复默认动作") {assign(role,nil)}}
                }
            }
            if let issue {Text(issue).foregroundStyle(.orange)}
        }.navigationTitle("结构平衡").navigationBarTitleDisplayMode(.inline)
            .onAppear {reload()}.onChange(of:template){_,_ in reload()}.onChange(of:store.lastSync){_,_ in reload()}
            .sheet(item:$selected) {row in ExercisePicker(title:"选择对应动作") {ex in assign(row.raw,ex.id);selected = nil} }
    }
    private func status(_ row:[String:Any])->String {
        if row["needsBodyweight"] as? Bool == true{return "需要体重记录"};if row["needsAnchor"] as? Bool == true{return "需要基准动作记录"}
        return ["no-data":"暂无可比较记录","noData":"暂无可比较记录","balanced":"达到参考比例","weak":"低于参考比例","borderline":"接近参考比例","strong":"高于参考比例"][row["status"] as? String ?? ""] ?? row["status"] as? String ?? "暂无数据"
    }
    private func reload() {do {data = try store.personalInfo("balance",["template":template]);issue = nil} catch {issue = error.localizedDescription} }
    private func assign(_ role:[String:Any],_ id:String?) {
        let original = store.state.filter {$0.key == "balanceOverrides"};var overrides = original["balanceOverrides"] as? [String:Any] ?? [:]
        overrides[template+":"+(role["id"] as? String ?? "")] = ["id":id as Any? ?? NSNull(),"_ts":Date().timeIntervalSince1970*1000]
        Task {if await store.savePersonalFields(original:original,proposed:["balanceOverrides":overrides]) {reload()} else {issue = store.editError}}
    }
}
