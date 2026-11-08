import SwiftUI
struct AdvancedConfigEditor: View {
    @Environment(GymStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var inputBuffer = InputCommitBuffer()
    @State private var config:[String:Any]
    @State private var error:String?
    let unit:String
    let save:([String:Any])->Void
    init(config:[String:Any],unit:String,save:@escaping([String:Any])->Void) { _config = State(initialValue:config);self.unit = unit;self.save = save }
    private var cardio:Bool { store.exercise(config["id"] as? String ?? "")?.bodyPart == "cardio" }
    private var mode:String { cardio ? "cardio" : config["mode"] as? String ?? "reps" }
    private var pyramid:[Any] { config["pyramid"] as? [Any] ?? [] }
    private var intensifier:[String:Any] { config["intensifier"] as? [String:Any] ?? [:] }
    var body:some View {
        NavigationStack {
            Form {
                Section("LOGGING_MODE") {
                    if cardio { Label("CARDIO_DURATION_AND_SPEED",systemImage:"figure.run") }
                    else { Picker("MODE",selection:Binding(get:{mode},set:{inputBuffer.commitAll();config["mode"] = $0;config.removeValue(forKey:"prog")})) { Text("REPS").tag("reps");Text("TIMED").tag("time") }.pickerStyle(.segmented).accessibilityIdentifier("advanced-mode") }
                    ConfigNumberFieldRow(title: "SETS", value: configNumberBinding("sets", fallback: 3), identifier: "config-sets")
                    if mode == "cardio" { ConfigNumberFieldRow(title: "MINUTES_PER_SET", value: configNumberBinding("min", fallback: 20), identifier: "config-min");ConfigNumberFieldRow(title: unit == "lb" ? "SPEED_MPH" : "SPEED_KM_H", value: configNumberBinding("speed", fallback: 8), identifier: "config-speed") }
                    else if mode == "time" { ConfigNumberFieldRow(title: "SECONDS_PER_SET", value: configNumberBinding("sec", fallback: 45), identifier: "config-sec");ConfigNumberFieldRow(title: "\(String(format: String(localized: "ADDED_WEIGHT_COUNT", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(describing: unit)))", value: configNumberBinding("weight", fallback: 0), identifier: "config-weight") }
                    else { ConfigNumberFieldRow(title: "TOTAL_REPS_BOTH_SIDES", value: configNumberBinding("reps", fallback: 10), identifier: "config-reps");ConfigNumberFieldRow(title: "\(String(format: String(localized: "WEIGHT_COUNT", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(describing: unit)))", value: configNumberBinding("weight", fallback: 0), identifier: "config-weight") }
                    if mode != "cardio" { Toggle("LOG_LEFT_AND_RIGHT_SEPARATELY",isOn:flag("side")).accessibilityIdentifier("advanced-side") }
                }
                if mode != "cardio" {
                    Section("WARM_UP_AND_REST") {
                        if intensifier["type"] as? String != "restpause" { Stepper(String(format: String(localized: "COUNT_WARM_UP_SETS", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(describing: Int(number(config["warmupSets"])))),value:Binding(get:{Int(number(config["warmupSets"]))},set:{config["warmupSets"] = $0}),in:0...5).accessibilityIdentifier("advanced-warmups") }
                        ConfigNumberFieldRow(title: "REST_BETWEEN_SETS_SECONDS_ZERO_FOR_DEFAULT", value: configNumberBinding("restSec", fallback: 0), identifier: "config-restSec")
                        ConfigNumberFieldRow(title: "REST_BETWEEN_WARM_UPS_SECONDS_ZERO_FOR_DEFAULT", value: configNumberBinding("warmupRestSec", fallback: 0), identifier: "config-warmupRestSec")
                    }
                }
                if mode == "reps" {
                    Section {
                        Toggle("PYRAMID_SETS",isOn:Binding(get:{!pyramid.isEmpty},set:{ enabled in
                            inputBuffer.commitAll()
                            if enabled { config["pyramid"] = [12,10,8,6];config.removeValue(forKey:"intensifier");config.removeValue(forKey:"lastToFailure") }
                            else { config.removeValue(forKey:"pyramid");config.removeValue(forKey:"pyramidWeight");config.removeValue(forKey:"pyramidRest") }
                        })).accessibilityIdentifier("advanced-pyramid")
                        if !pyramid.isEmpty {
                            ForEach(pyramid.indices,id:\.self) { i in
                                VStack(alignment:.leading,spacing:8) {
                                    HStack { Text(String(format: String(localized: "SET_COUNT", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(describing: i+1))).font(.headline);Spacer();Toggle("MAX",isOn:Binding(get:{pyramid[i] as? String == "max"},set:{setPyramid("pyramid",i,$0 ? "max" : 10)})).fixedSize() }
                                    if pyramid[i] as? String != "max" { ConfigNumberFieldRow(title: "REPS", value: pyramidNumberBinding("pyramid", index: i), fieldWidth: 80, labelFont: .caption, identifier: "pyramid-\(i)") }
                                    ConfigNumberFieldRow(title: "WEIGHT_ZERO_TO_USE_LAST_WORKOUT", value: pyramidNumberBinding("pyramidWeight", index: i), fieldWidth: 80, labelFont: .caption, identifier: "pyramidWeight-\(i)")
                                    ConfigNumberFieldRow(title: "REST_IN_SECONDS_ZERO_FOR_DEFAULT", value: pyramidNumberBinding("pyramidRest", index: i), fieldWidth: 80, labelFont: .caption, identifier: "pyramidRest-\(i)")
                                    if pyramid.count > 1 { Button("DELETE_SET",role:.destructive) { inputBuffer.commitAll(); for key in ["pyramid","pyramidWeight","pyramidRest"] { if var list = config[key] as? [Any],list.indices.contains(i) { list.remove(at:i);config[key] = list } } }.font(.caption) }
                                }.padding(.vertical,5)
                            }
                            Button("ADD_PYRAMID_SET") { inputBuffer.commitAll(); var list = pyramid;list.append(10);config["pyramid"] = list }.disabled(pyramid.count>=10)
                        }
                    } header: { HStack { Text("TARGETS_BY_SET"); Spacer(); ExplanationButton(title: "PYRAMID_AND_MAX_SETS", message: "SET_DIFFERENT_REPS_WEIGHT_AND_REST_FOR_EACH_SET_MAX_SETS_RECORD") } }
                    if pyramid.isEmpty {
                        Section {
                            Picker("SET_TYPE",selection:Binding(get:{intensifier["type"] as? String ?? "straight"},set:{ kind in
                                inputBuffer.commitAll()
                                if kind == "straight" { config.removeValue(forKey:"intensifier") }
                                else if kind == "dropset" { config["intensifier"] = ["type":kind,"count":1,"pct":20] }
                                else { config["intensifier"] = ["type":kind,"totalReps":12,"restSec":15] }
                            })) { Text("STRAIGHT_SETS").tag("straight");Text("DROP_SET").tag("dropset");Text("REST_PAUSE").tag("restpause") }.accessibilityIdentifier("advanced-intensifier")
                            if intensifier["type"] as? String == "dropset" { ConfigNumberFieldRow(title: "DROPS", value: intensityNumberBinding("count", fallback: 1), fieldWidth: 80, identifier: "config-intensity-count");ConfigNumberFieldRow(title: "WEIGHT_REDUCTION_PER_DROP", value: intensityNumberBinding("pct", fallback: 20), fieldWidth: 80, identifier: "config-intensity-pct") }
                            if intensifier["type"] as? String == "restpause" {
                                ConfigNumberFieldRow(title: "REST_PAUSE_TOTAL_REPS", value: intensityNumberBinding("totalReps", fallback: 12), fieldWidth: 80, identifier: "config-intensity-totalReps");ConfigNumberFieldRow(title: "REST_BETWEEN_MINI_SETS_SECONDS", value: intensityNumberBinding("restSec", fallback: 15), fieldWidth: 80, identifier: "config-intensity-restSec")
                            }
                        } header: { HStack { Text("DROP_SETS_REST_PAUSE"); Spacer(); ExplanationButton(title: "REST_PAUSE", message: "GENERATES_WARM_UP_AND_REST_PAUSE_SETS_MINI_SET_REPS_COUNT_TOWARDS") } }
                    }
                }
                ProgressionOptions(config:$config,mode:mode,unit:unit)
                if mode != "cardio" && pyramid.isEmpty { Section { Toggle("LAST_SET_TO_FAILURE_AMRAP",isOn:flag("lastToFailure")) } }
            }.navigationTitle("ADVANCED_SET_TYPES").navigationBarTitleDisplayMode(.inline)
                .keyboardDismissToolbar()
                .toolbar { ToolbarItem(placement:.topBarLeading) { Button("CANCEL") { dismiss() } };ToolbarItem(placement:.topBarTrailing) { Button("DONE") {
                    inputBuffer.commitAll()
                    do { var c = config;c["mode"] = mode;for key in ["inc","repsMin","setsMax","deloadFactor"] { if let text = c[key] as? String { guard let n = TrainingInput.value(text) else { throw APIError.response(0,String(localized: "COMPLETE_THE_PROGRESSION_PARAMETERS", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) };c[key] = n } }; _ = try WebRules.shared.call("validatePersonalConfig",payload:["config":c]);let next = try WebRules.shared.call("advancedConfig",payload:["config":c]) as! [String:Any];save(next);dismiss() } catch { self.error = error.localizedDescription }
                }.accessibilityIdentifier("advanced-config-done") } }
                .alert("COULD_NOT_APPLY",isPresented:Binding(get:{error != nil},set:{if !$0 { error = nil }})) { Button("GOT_IT",role:.cancel) {} } message:{Text(error ?? "")}
        }.tint(GymTheme.green).environment(\.inputCommitBuffer, inputBuffer)
    }
    private func flag(_ key:String)->Binding<Bool>{Binding(get:{config[key] as? Bool ?? false},set:{inputBuffer.commitAll();if $0 { config[key] = true } else { config.removeValue(forKey:key) }})}
    private func configNumberBinding(_ key: String, fallback: Double) -> Binding<Double> {
        Binding(get: { number(config[key] ?? fallback) }, set: { config[key] = max(0, $0) })
    }
    private func intensityNumberBinding(_ key: String, fallback: Double) -> Binding<Double> {
        Binding(get: { number(intensifier[key] ?? fallback) }, set: {
            var value = intensifier
            value[key] = max(0, $0)
            config["intensifier"] = value
        })
    }
    private func setPyramid(_ key:String,_ index:Int,_ value:Any) { inputBuffer.commitAll(); var list = config[key] as? [Any] ?? Array(repeating:0,count:pyramid.count);while list.count < pyramid.count { list.append(0) };guard list.indices.contains(index) else {return};list[index] = value;config[key] = list }
    private func pyramidNumberBinding(_ key: String, index: Int) -> Binding<Double> {
        Binding(get: {
            let list = config[key] as? [Any] ?? []
            return list.indices.contains(index) ? number(list[index]) : 0
        }, set: { setPyramid(key, index, max(0, $0)) })
    }
}
