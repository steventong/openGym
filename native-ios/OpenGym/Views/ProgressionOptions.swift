import SwiftUI

struct ProgressionOptions:View {
    @Environment(\.inputCommitBuffer) private var inputBuffer
    @Environment(GymStore.self) private var store
    @Binding var config:[String:Any]
    let mode:String
    let unit:String
    private var policy:String { config["prog"] as? String ?? "" }
    var body:some View {
        Section {
            Picker(L10n.text("PROGRESSION_RULE" /* 进阶规则 */),selection:Binding(get:{policy},set:{ value in
                inputBuffer?.commitAll()
                config["prog"] = value.isEmpty ? nil:value
                if value == "greyskull",config["lastToFailure"] == nil { config["lastToFailure"] = true }
                if ["double","triple"].contains(value), config["repsMin"] == nil {config["repsMin"] = max(1,number(config["reps"] ?? 10)-2)}
                if value == "triple",config["setsMax"] == nil { config["setsMax"] = min(10,number(config["sets"] ?? 3)+2) }
            })) {
                Text(L10n.text("FOLLOW_ROUTINE" /* 跟随计划 */)).tag("");Text(L10n.text("NO_AUTOMATIC_PROGRESSION" /* 不自动进阶 */)).tag("off")
                if mode == "reps" { Text(L10n.text("LINEAR_PROGRESSION" /* 线性进阶 */)).tag("linear");Text(L10n.text("GREYSKULL_LP" /* 术语：Greyskull LP */)).tag("greyskull");Text(L10n.text("DOUBLE_PROGRESSION" /* 双重进阶 */)).tag("double");Text(L10n.text("TRIPLE_PROGRESSION" /* 三重进阶 */)).tag("triple") }
                if mode == "time" { Text(L10n.text("INCREASE_DURATION" /* 增加时长 */)).tag("time") }
            }
            if mode != "cardio" {
                optionalNumber(L10n.text("INCREMENT_COUNT" /* 步进（{0}） */, mode == "time" ? L10n.text("SEC" /* 秒 */):unit),key:"inc")
                if ["double","triple"].contains(policy) { optionalNumber(L10n.text("MINIMUM_REPS_BOTH_SIDES_COMBINED" /* 次数下限（分侧时填两侧合计） */),key:"repsMin") }
                if policy == "triple" { optionalNumber(L10n.text("SETS_UP_TO" /* 组数上限 */),key:"setsMax") }
                if mode == "reps" {
                    optionalNumber(L10n.text("DELOAD_FACTOR_ZERO_FIVE_ZERO_NINEFIVE" /* 减量系数（0.5–0.95） */),key:"deloadFactor")
                    if (config["pyramid"] as? [Any] ?? []).isEmpty && (config["intensifier"] as? [String:Any])?["type"] as? String != "restpause" {
                        Toggle(L10n.text("BACK_OFF_SETS" /* 减重组（Back-off） */),isOn:Binding(get:{config["backoff"] as? Bool ?? false},set:{config["backoff"] = $0 ? true:nil}))
                    }
                }
            }
        } header: { HStack { Text(L10n.text("AUTOMATIC_PROGRESSION" /* 自动进阶 */)); Spacer(); ExplanationButton(title: L10n.text("PROGRESSION_RULE" /* 进阶规则 */), message: L10n.text("DOUBLE_PROGRESSION_INCREASES_REPS_BEFORE_WEIGHT_TRIPLE_PROGRESSION_ALSO_ADDS_SETS_BEFORE" /* 双重进阶先增加次数；三重进阶再增加组数，达到上限后增加负重。空白参数使用默认值。 */)) } }
        if mode != "cardio" {
            Section(L10n.text("WEIGHT_CONVENTION" /* 重量含义 */)) {
                if ["dumbbell","kettlebell"].contains(store.exercise(config["id"] as? String ?? "")?.equipment ?? "") {
                Picker(L10n.text("DUMBBELL_KETTLEBELL_LOAD" /* 哑铃 / 壶铃负重 */),selection:Binding(get:{config["dbLoad"] as? String ?? "as"},set:{config["dbLoad"] = $0})) { Text(L10n.text("AS_ENTERED" /* 按输入 */)).tag("as");Text(L10n.text("WEIGHT_PER_IMPLEMENT" /* 单只重量 */)).tag("each");Text(L10n.text("COMBINED_WEIGHT_OF_BOTH" /* 双只总重 */)).tag("total") }
                }
                Toggle(L10n.text("BODYWEIGHT_EXERCISE_WEIGHT_IS_ADDED_LOAD" /* 自重动作（重量为附加负重） */),isOn:Binding(get:{config["bodyweight"] as? Bool ?? (store.exercise(config["id"] as? String ?? "")?.equipment == "body weight")},set:{config["bodyweight"] = $0}))
            }
        }
    }
    private func optionalNumber(_ title:String,key:String)->some View {
        HStack { Text(title).font(.subheadline);Spacer();BufferedTextField(L10n.text("DEFAULT" /* 默认 */),text:Binding(get:{ (config[key] as? String) ?? config[key].map{personalNumber(number($0))} ?? "" },set:{ text in if text.isEmpty {config.removeValue(forKey:key)} else {config[key] = text} })).textFieldStyle(.plain).stableInputLine().submitLabel(.done).onSubmit { GymKeyboard.dismiss() }.keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width:90) }
    }
}
