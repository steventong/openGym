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
            Picker("PROGRESSION_RULE",selection:Binding(get:{policy},set:{ value in
                inputBuffer?.commitAll()
                config["prog"] = value.isEmpty ? nil:value
                if value == "greyskull",config["lastToFailure"] == nil { config["lastToFailure"] = true }
                if ["double","triple"].contains(value), config["repsMin"] == nil {config["repsMin"] = max(1,number(config["reps"] ?? 10)-2)}
                if value == "triple",config["setsMax"] == nil { config["setsMax"] = min(10,number(config["sets"] ?? 3)+2) }
            })) {
                Text("FOLLOW_ROUTINE").tag("");Text("NO_AUTOMATIC_PROGRESSION").tag("off")
                if mode == "reps" { Text("LINEAR_PROGRESSION").tag("linear");Text("GREYSKULL_LP").tag("greyskull");Text("DOUBLE_PROGRESSION").tag("double");Text("TRIPLE_PROGRESSION").tag("triple") }
                if mode == "time" { Text("INCREASE_DURATION").tag("time") }
            }
            if mode != "cardio" {
                OptionalProgressionFieldRow(title: String(format: String(localized: "INCREMENT_COUNT", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(describing: mode == "time" ? String(localized: "SEC", bundle: AppLanguage.bundle, locale: AppLanguage.locale):unit)), text: optionalNumberBinding("inc"))
                if ["double","triple"].contains(policy) { OptionalProgressionFieldRow(title: String(localized: "MINIMUM_REPS_BOTH_SIDES_COMBINED", bundle: AppLanguage.bundle, locale: AppLanguage.locale), text: optionalNumberBinding("repsMin")) }
                if policy == "triple" { OptionalProgressionFieldRow(title: String(localized: "SETS_UP_TO", bundle: AppLanguage.bundle, locale: AppLanguage.locale), text: optionalNumberBinding("setsMax")) }
                if mode == "reps" {
                    OptionalProgressionFieldRow(title: String(localized: "DELOAD_FACTOR_ZERO_FIVE_ZERO_NINEFIVE", bundle: AppLanguage.bundle, locale: AppLanguage.locale), text: optionalNumberBinding("deloadFactor"))
                    if (config["pyramid"] as? [Any] ?? []).isEmpty && (config["intensifier"] as? [String:Any])?["type"] as? String != "restpause" {
                        Toggle("BACK_OFF_SETS",isOn:Binding(get:{config["backoff"] as? Bool ?? false},set:{config["backoff"] = $0 ? true:nil}))
                    }
                }
            }
        } header: { HStack { Text("AUTOMATIC_PROGRESSION"); Spacer(); ExplanationButton(title: String(localized: "PROGRESSION_RULE", bundle: AppLanguage.bundle, locale: AppLanguage.locale), message: String(localized: "DOUBLE_PROGRESSION_INCREASES_REPS_BEFORE_WEIGHT_TRIPLE_PROGRESSION_ALSO_ADDS_SETS_BEFORE", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) } }
        if mode != "cardio" {
            Section("WEIGHT_CONVENTION") {
                if ["dumbbell","kettlebell"].contains(store.exercise(config["id"] as? String ?? "")?.equipment ?? "") {
                Picker("DUMBBELL_KETTLEBELL_LOAD",selection:Binding(get:{config["dbLoad"] as? String ?? "as"},set:{config["dbLoad"] = $0})) { Text("AS_ENTERED").tag("as");Text("WEIGHT_PER_IMPLEMENT").tag("each");Text("COMBINED_WEIGHT_OF_BOTH").tag("total") }
                }
                Toggle("BODYWEIGHT_EXERCISE_WEIGHT_IS_ADDED_LOAD",isOn:Binding(get:{config["bodyweight"] as? Bool ?? (store.exercise(config["id"] as? String ?? "")?.equipment == "body weight")},set:{config["bodyweight"] = $0}))
            }
        }
    }
    private func optionalNumberBinding(_ key: String) -> Binding<String> {
        Binding(get: { (config[key] as? String) ?? config[key].map { personalNumber(number($0)) } ?? "" }, set: { text in
            if text.isEmpty { config.removeValue(forKey: key) }
            else { config[key] = text }
        })
    }
}
