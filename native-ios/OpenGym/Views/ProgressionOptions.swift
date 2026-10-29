import SwiftUI

struct ProgressionOptions:View {
    @Environment(GymStore.self) private var store
    @Binding var config:[String:Any]
    let mode:String
    let unit:String
    private var policy:String { config["prog"] as? String ?? "" }
    var body:some View {
        Section("自动进阶") {
            Picker("进阶规则",selection:Binding(get:{policy},set:{ value in
                config["prog"] = value.isEmpty ? nil:value
                if value == "greyskull",config["lastToFailure"] == nil { config["lastToFailure"] = true }
                if ["double","triple"].contains(value), config["repsMin"] == nil {config["repsMin"] = max(1,number(config["reps"] ?? 10)-2)}
                if value == "triple",config["setsMax"] == nil { config["setsMax"] = min(10,number(config["sets"] ?? 3)+2) }
            })) {
                Text("跟随计划").tag("");Text("不自动进阶").tag("off")
                if mode == "reps" { Text("线性加重").tag("linear");Text("Greyskull LP").tag("greyskull");Text("双重进阶").tag("double");Text("三重进阶").tag("triple") }
                if mode == "time" { Text("增加时长").tag("time") }
            }
            if mode != "cardio" {
                optionalNumber("步进（\(mode == "time" ? "秒":unit)）",key:"inc")
                if ["double","triple"].contains(policy) { optionalNumber("次数下限（分侧时填两侧合计）",key:"repsMin") }
                if policy == "triple" { optionalNumber("组数上限",key:"setsMax") }
                if mode == "reps" {
                    optionalNumber("减量系数（0.5–0.95）",key:"deloadFactor")
                    if (config["pyramid"] as? [Any] ?? []).isEmpty && (config["intensifier"] as? [String:Any])?["type"] as? String != "restpause" {
                        Toggle("逐组减重（Back-off）",isOn:Binding(get:{config["backoff"] as? Bool ?? false},set:{config["backoff"] = $0 ? true:nil}))
                    }
                }
            }
            Text("跟随计划会沿用计划规则。双重进阶先增加次数；三重进阶再增加组数，达到上限后增加负重。留空的参数使用网页默认值。").font(.caption).foregroundStyle(.secondary)
        }
        if mode != "cardio" {
            Section("重量含义") {
                if ["dumbbell","kettlebell"].contains(store.exercise(config["id"] as? String ?? "")?.equipment ?? "") {
                Picker("哑铃 / 壶铃负重",selection:Binding(get:{config["dbLoad"] as? String ?? "as"},set:{config["dbLoad"] = $0})) { Text("按输入值").tag("as");Text("单只重量").tag("each");Text("双只总重").tag("total") }
                }
                Toggle("自重动作（重量为附加负重）",isOn:Binding(get:{config["bodyweight"] as? Bool ?? (store.exercise(config["id"] as? String ?? "")?.equipment == "body weight")},set:{config["bodyweight"] = $0}))
            }
        }
    }
    private func optionalNumber(_ title:String,key:String)->some View {
        HStack { Text(title).font(.subheadline);Spacer();TextField("默认",text:Binding(get:{ (config[key] as? String) ?? config[key].map{personalNumber(number($0))} ?? "" },set:{ text in if text.isEmpty {config.removeValue(forKey:key)} else {config[key] = text} })).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width:90) }
    }
}
