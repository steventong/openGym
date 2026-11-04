import SwiftUI

struct PersonalSettingsView: View {
    @Environment(GymStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var original:[String:Any] = [:]
    @State private var values:[String:Any] = [:]
    @State private var nextUnit = "kg"
    @State private var unitPrompt = false
    @State private var issue:String?
    private let keys = ["lang","restSec","restPauseSec","effort","logRef","startFrom","keepAwake","speedUnit","oneRmFormula"]
    var body:some View {
        Form {
            Section {
                Picker(L10n.text("LANGUAGE" /* 语言 */), selection: text("lang", L10n.language)) {
                    Text(L10n.text("LANGUAGE_CHINESE" /* 简体中文 */)).tag("zh")
                    Text(L10n.text("LANGUAGE_ENGLISH" /* 术语：English */)).tag("en")
                }
            }
            Section(L10n.text("WORKOUT_PREFERENCES" /* 训练偏好 */)) {
                Stepper(L10n.text("DEFAULT_REST_COUNT_SECONDS" /* 默认休息 {0} 秒 */, Int(number(values["restSec"] ?? 90))),value:numeric("restSec",90),in:0...900,step:15)
                Stepper(L10n.text("REST_PAUSE_REST_COUNT_SECONDS" /* 休息暂停组内休息 {0} 秒 */, Int(number(values["restPauseSec"] ?? 15))),value:numeric("restPauseSec",15),in:5...900,step:5)
                Picker(L10n.text("STARTING_TARGETS" /* 训练起始目标 */),selection:text("startFrom","plan")) { Text(L10n.text("USE_ROUTINE_TARGETS" /* 按计划 */)).tag("plan");Text(L10n.text("USE_LAST_WORKOUT" /* 沿用上次 */)).tag("last") }
                Picker(L10n.text("EFFORT" /* 用力程度 */),selection:text("effort","none")) { Text(L10n.text("DON_T_LOG" /* 不记录 */)).tag("none");Text(L10n.text("RIR" /* 术语：RIR */)).tag("rir");Text(L10n.text("RPE" /* 术语：RPE */)).tag("rpe") }
                Picker(L10n.text("REFERENCE_PERFORMANCE" /* 参考成绩 */),selection:text("logRef","last")) { Text(L10n.text("LAST_WORKOUT" /* 上次训练 */)).tag("last");Text(L10n.text("PERSONAL_BEST" /* 历史最佳 */)).tag("best") }
                Toggle(L10n.text("KEEP_SCREEN_AWAKE_DURING_WORKOUTS" /* 训练时保持屏幕常亮 */),isOn:Binding(get:{values["keepAwake"] as? Bool ?? true},set:{values["keepAwake"] = $0}))
            }
            Section(L10n.text("UNITS_AND_ESTIMATES" /* 单位与估算 */)) {
                LabeledContent(L10n.text("CURRENT_WEIGHT_UNIT" /* 当前重量单位 */),value:store.unit)
                Button(L10n.text("SWITCH_TO_COUNT" /* 切换为 {0} */, store.unit == "kg" ? "lb" : "kg")) { nextUnit = store.unit == "kg" ? "lb" : "kg"; unitPrompt = true }
                Picker(L10n.text("SPEED" /* 速度 */),selection:text("speedUnit",store.unit == "lb" ? "mph":"kmh")) { Text(L10n.text("UNIT_SPEED_KMH" /* 公里/小时 */)).tag("kmh");Text(L10n.text("UNIT_SPEED_MPH" /* 英里/小时 */)).tag("mph") }
                Picker(L10n.text("ONE_REP_MAX_FORMULA" /* 1RM 公式 */),selection:text("oneRmFormula","epley")) {
                    Text(L10n.text("FORMULA_EPLEY" /* 术语：Epley */)).tag("epley");Text(L10n.text("FORMULA_BRZYCKI" /* 术语：Brzycki */)).tag("brzycki");Text(L10n.text("FORMULA_LOMBARDI" /* 术语：Lombardi */)).tag("lombardi");Text(L10n.text("FORMULA_MAYHEW" /* 术语：Mayhew */)).tag("mayhew");Text(L10n.text("FORMULA_WATHAN" /* 术语：Wathan */)).tag("wathan");Text(L10n.text("FORMULA_LANDER" /* 术语：Lander */)).tag("lander");Text(L10n.text("FORMULA_OCONNER" /* 术语：O’Conner */)).tag("oconner");Text(L10n.text("WEIGHTED_ESTIMATE" /* 加权估算 */)).tag("weighted")
                }
            }
            Section { NavigationLink(L10n.text("PLATES_AND_DUMBBELLS" /* 杠铃片与哑铃库存 */)) { EquipmentInventoryView() } }
        }.operationAlert($issue).navigationTitle(L10n.text("WORKOUT_PREFERENCES" /* 训练偏好 */)).navigationBarTitleDisplayMode(.inline)
            .onAppear { if values.isEmpty { original = store.state.filter { keys.contains($0.key) }; values = original } }
            .toolbar { ToolbarItem(placement:.topBarTrailing) { Button(L10n.text("SAVE" /* 保存 */)) { Task {
                if await store.savePersonalFields(original:original,proposed:values) { dismiss() } else { issue = store.editError }
            } }.disabled(store.syncing) } }
            .confirmationDialog(L10n.text("CHANGE_ACCOUNT_WEIGHT_UNIT" /* 切换账号重量单位 */),isPresented:$unitPrompt,titleVisibility:.visible) {
                Button(L10n.text("CONVERT_ALL_WEIGHTS" /* 换算全部重量 */)) { changeUnit(true) }
                Button(L10n.text("KEEP_NUMBERS_CHANGE_UNIT_ONLY" /* 保留数字，只更改单位 */)) { changeUnit(false) }
                Button(L10n.text("CANCEL" /* 取消 */),role:.cancel) {}
            } message: { Text(L10n.text("APPLIES_TO_ROUTINES_WORKOUT_HISTORY_BODY_WEIGHT_AND_TARGET_WEIGHT_EQUIPMENT_INVENTORIES" /* 影响计划、训练历史、体重和目标体重。器械库存按 kg / lb 分别保留。 */)) }
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
    @State private var invalidWeights = false
    @State private var ownPlates = false
    @State private var unit = "kg"
    @State private var loaded = false
    @State private var issue:String?
    private var sizes:[Double] { unit == "lb" ? [45,35,25,15,10,5,2.5,1.25] : [25,20,15,10,5,2.5,1.25,0.5] }
    var body:some View {
        Form {
            Section {
                Toggle(L10n.text("USE_MY_PLATE_INVENTORY" /* 使用我的杠铃片库存 */),isOn:$ownPlates)
                if ownPlates { ForEach(sizes,id:\.self) { weight in
                    Stepper(L10n.text("COUNT_COUNT_COUNT_PAIRS" /* {0} {1}：{2} 对 */, decimal(weight), unit, counts[String(weight)] ?? 0),value:Binding(get:{counts[String(weight)] ?? 0},set:{counts[String(weight)] = $0}),in:0...50)
                } }
            } header: { HStack { Text(L10n.text("PLATES_PAIRS" /* 杠铃片（对） */)); Spacer(); ExplanationButton(title: L10n.text("EQUIPMENT_INVENTORY" /* 器械库存 */), message: L10n.text("TURN_OFF_YOUR_CUSTOM_INVENTORY_TO_USE_STANDARD_PLATES_DUMBBELL_WEIGHTS_ARE" /* 关闭自定义库存后使用标准配片。哑铃库存用于重量加减和进阶；留空沿用动作步进。 */)) } }
            Section {
                TextField(L10n.text("FOR_EXAMPLE_TWO_FOUR_SIX_EIGHT_ONEZERO_ONETWO" /* 例如：2, 4, 6, 8, 10, 12 */),text:$bells).textFieldStyle(.plain).stableInputLine().submitLabel(.done).onSubmit { GymKeyboard.dismiss() }.keyboardType(.numbersAndPunctuation)
                    .invalidInput(invalidWeights).onChange(of: bells) { _, _ in invalidWeights = false }.accessibilityIdentifier("dumbbell-inventory")
                Button(L10n.text("FILL_WITH_COMMON_WEIGHTS" /* 填入常用重量 */)) { bells = (unit == "lb" ? stride(from:5,through:100,by:5).map(String.init) : stride(from:2,through:50,by:2).map(String.init)).joined(separator:", ") }
                Button(L10n.text("CLEAR_INVENTORY" /* 清除库存 */)) { bells = "" }
            } header:{Text(L10n.text("WEIGHT_PER_DUMBBELL_COUNT" /* 单只哑铃重量（{0}） */, unit))}
        }.operationAlert($issue).navigationTitle(L10n.text("EQUIPMENT_INVENTORY" /* 器械库存 */)).navigationBarTitleDisplayMode(.inline)
            .onAppear { guard !loaded else { return }; loaded = true; unit = store.unit
                original = store.state.filter { ["plates","dumbbells"].contains($0.key) }
                let plates = (original["plates"] as? [String:Any])?[unit] as? [String:Any] ?? [:]
                ownPlates = plates.keys.contains { Double($0) != nil }
                for w in sizes { counts[String(w)] = Int(number(plates[decimalKey(w)] ?? (w == 0.5 || (unit == "lb" && [15,1.25].contains(w)) ? 0:6))) }
                let list = ((original["dumbbells"] as? [String:Any])?[unit] as? [String:Any])?["weights"] as? [Double] ?? []
                bells = list.map { String($0) }.joined(separator:", ")
            }.toolbar { ToolbarItem(placement:.topBarTrailing) { Button(L10n.text("SAVE" /* 保存 */)) { save() }.disabled(store.syncing) } }
    }
    private func decimalKey(_ w:Double)->String { w.rounded() == w ? String(Int(w)) : String(w) }
    private func save() {
        let parts = bells.split(whereSeparator:{ $0 == "," || $0 == "，" || $0 == " " || $0 == "\n" })
        let weights = parts.compactMap { Double($0) }
        guard weights.count == parts.count, weights.allSatisfy({$0.isFinite && $0 > 0 && $0 < 10000}) else { invalidWeights = true; issue = L10n.text("ENTER_VALID_WEIGHTS_GREATER_THAN_ZERO" /* 请填写有效的正数重量。 */); return }
        var proposed = original, plates = original["plates"] as? [String:Any] ?? [:], db = original["dumbbells"] as? [String:Any] ?? [:]
        var stock:[String:Any] = ["_ts":Date().timeIntervalSince1970*1000]
        if ownPlates { for w in sizes { stock[decimalKey(w)] = counts[String(w)] ?? 0 } }
        plates[unit] = stock; db[unit] = ["weights":Array(Set(weights)).sorted(),"_ts":Date().timeIntervalSince1970*1000]
        proposed["plates"] = plates; proposed["dumbbells"] = db
        Task { if await store.savePersonalFields(original:original,proposed:proposed,unit:unit) { dismiss() } else { issue = store.editError } }
    }
}
