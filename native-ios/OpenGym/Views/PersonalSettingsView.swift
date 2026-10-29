import SwiftUI

struct PersonalSettingsView: View {
    @Environment(GymStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var original:[String:Any] = [:]
    @State private var values:[String:Any] = [:]
    @State private var nextUnit = "kg"
    @State private var unitPrompt = false
    @State private var issue:String?
    private let keys = ["restSec","restPauseSec","effort","logRef","startFrom","keepAwake","speedUnit","oneRmFormula"]
    var body:some View {
        Form {
            Section("训练偏好") {
                Stepper("默认休息 \(Int(number(values["restSec"] ?? 90))) 秒",value:numeric("restSec",90),in:0...900,step:15)
                Stepper("Rest-pause 休息 \(Int(number(values["restPauseSec"] ?? 15))) 秒",value:numeric("restPauseSec",15),in:5...900,step:5)
                Picker("训练起始目标",selection:text("startFrom","plan")) { Text("按计划").tag("plan");Text("沿用上次").tag("last") }
                Picker("用力程度",selection:text("effort","none")) { Text("不记录").tag("none");Text("RIR").tag("rir");Text("RPE").tag("rpe") }
                Picker("参考成绩",selection:text("logRef","last")) { Text("上次训练").tag("last");Text("历史最佳").tag("best") }
                Toggle("训练时保持屏幕常亮",isOn:Binding(get:{values["keepAwake"] as? Bool ?? true},set:{values["keepAwake"] = $0}))
            }
            Section("单位与估算") {
                LabeledContent("当前重量单位",value:store.unit)
                Button("切换为 \(store.unit == "kg" ? "lb" : "kg")") { nextUnit = store.unit == "kg" ? "lb" : "kg"; unitPrompt = true }
                Picker("速度",selection:text("speedUnit",store.unit == "lb" ? "mph":"kmh")) { Text("km/h").tag("kmh");Text("mph").tag("mph") }
                Picker("1RM 公式",selection:text("oneRmFormula","epley")) {
                    Text("Epley").tag("epley");Text("Brzycki").tag("brzycki");Text("Lombardi").tag("lombardi");Text("Mayhew").tag("mayhew");Text("Wathan").tag("wathan");Text("Lander").tag("lander");Text("O’Conner").tag("oconner");Text("加权估算").tag("weighted")
                }
            }
            Section { NavigationLink("杠铃片与哑铃库存") { EquipmentInventoryView() } }
            if let issue { Section { Text(issue).foregroundStyle(.orange) } }
        }.navigationTitle("训练偏好").navigationBarTitleDisplayMode(.inline)
            .onAppear { if values.isEmpty { original = store.state.filter { keys.contains($0.key) }; values = original } }
            .toolbar { ToolbarItem(placement:.topBarTrailing) { Button("保存") { Task {
                if await store.savePersonalFields(original:original,proposed:values) { dismiss() } else { issue = store.editError }
            } }.disabled(store.syncing) } }
            .confirmationDialog("切换账号重量单位",isPresented:$unitPrompt,titleVisibility:.visible) {
                Button("换算全部重量") { changeUnit(true) }
                Button("保留数字，只更改单位") { changeUnit(false) }
                Button("取消",role:.cancel) {}
            } message: { Text("影响计划、训练历史、体重和目标体重。器械库存按 kg / lb 分别保留。") }
    }
    private func changeUnit(_ convert:Bool) { Task { if !(await store.switchProfileUnit(to:nextUnit,convert:convert)) { issue = store.editError } } }
    private func text(_ key:String,_ fallback:String)->Binding<String> { Binding(get:{values[key] as? String ?? fallback},set:{values[key] = $0}) }
    private func numeric(_ key:String,_ fallback:Double)->Binding<Double> { Binding(get:{number(values[key] ?? fallback)},set:{values[key] = $0}) }
}

struct EquipmentInventoryView: View {
    @Environment(GymStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var original:[String:Any] = [:]
    @State private var counts:[String:Int] = [:]
    @State private var bells = ""
    @State private var ownPlates = false
    @State private var unit = "kg"
    @State private var loaded = false
    @State private var issue:String?
    private var sizes:[Double] { unit == "lb" ? [45,35,25,15,10,5,2.5,1.25] : [25,20,15,10,5,2.5,1.25,0.5] }
    var body:some View {
        Form {
            Section {
                Toggle("使用我的杠铃片库存",isOn:$ownPlates)
                if ownPlates { ForEach(sizes,id:\.self) { weight in
                    Stepper("\(decimal(weight)) \(unit)：\(counts[String(weight)] ?? 0) 对",value:Binding(get:{counts[String(weight)] ?? 0},set:{counts[String(weight)] = $0}),in:0...50)
                } }
            } header:{Text("杠铃片")} footer:{Text("按对计数；关闭后使用网页版的标准健身房库存。")}
            Section {
                TextField("例如：2, 4, 6, 8, 10, 12",text:$bells).keyboardType(.numbersAndPunctuation).accessibilityIdentifier("dumbbell-inventory")
                Button("填入常用重量") { bells = (unit == "lb" ? stride(from:5,through:100,by:5).map(String.init) : stride(from:2,through:50,by:2).map(String.init)).joined(separator:", ") }
                Button("清除库存") { bells = "" }
            } header:{Text("单只哑铃重量（\(unit)）")} footer:{Text("逗号分隔。配置后，加减按钮和进阶会使用现有哑铃重量；留空沿用动作步进。")}
            if let issue { Text(issue).foregroundStyle(.orange) }
        }.navigationTitle("器械库存").navigationBarTitleDisplayMode(.inline)
            .onAppear { guard !loaded else { return }; loaded = true; unit = store.unit
                original = store.state.filter { ["plates","dumbbells"].contains($0.key) }
                let plates = (original["plates"] as? [String:Any])?[unit] as? [String:Any] ?? [:]
                ownPlates = plates.keys.contains { Double($0) != nil }
                for w in sizes { counts[String(w)] = Int(number(plates[decimalKey(w)] ?? (w == 0.5 || (unit == "lb" && [15,1.25].contains(w)) ? 0:6))) }
                let list = ((original["dumbbells"] as? [String:Any])?[unit] as? [String:Any])?["weights"] as? [Double] ?? []
                bells = list.map { String($0) }.joined(separator:", ")
            }.toolbar { ToolbarItem(placement:.topBarTrailing) { Button("保存") { save() }.disabled(store.syncing) } }
    }
    private func decimalKey(_ w:Double)->String { w.rounded() == w ? String(Int(w)) : String(w) }
    private func save() {
        let parts = bells.split(whereSeparator:{ $0 == "," || $0 == "，" || $0 == " " || $0 == "\n" })
        let weights = parts.compactMap { Double($0) }
        guard weights.count == parts.count, weights.allSatisfy({$0.isFinite && $0 > 0 && $0 < 10000}) else { issue = "请填写有效的正数重量。"; return }
        var proposed = original, plates = original["plates"] as? [String:Any] ?? [:], db = original["dumbbells"] as? [String:Any] ?? [:]
        var stock:[String:Any] = ["_ts":Date().timeIntervalSince1970*1000]
        if ownPlates { for w in sizes { stock[decimalKey(w)] = counts[String(w)] ?? 0 } }
        plates[unit] = stock; db[unit] = ["weights":Array(Set(weights)).sorted(),"_ts":Date().timeIntervalSince1970*1000]
        proposed["plates"] = plates; proposed["dumbbells"] = db
        Task { if await store.savePersonalFields(original:original,proposed:proposed,unit:unit) { dismiss() } else { issue = store.editError } }
    }
}
