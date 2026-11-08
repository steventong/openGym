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
                Picker("LANGUAGE", selection: text("lang", AppLanguage.language)) {
                    Text("LANGUAGE_CHINESE").tag("zh")
                    Text("LANGUAGE_ENGLISH").tag("en")
                }
            }
            Section("WORKOUT_PREFERENCES") {
                Stepper(String(format: String(localized: "DEFAULT_REST_COUNT_SECONDS", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(describing: Int(number(values["restSec"] ?? 90)))),value:numeric("restSec",90),in:0...900,step:15)
                Stepper(String(format: String(localized: "REST_PAUSE_REST_COUNT_SECONDS", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(describing: Int(number(values["restPauseSec"] ?? 15)))),value:numeric("restPauseSec",15),in:5...900,step:5)
                Picker("STARTING_TARGETS",selection:text("startFrom","plan")) { Text("USE_ROUTINE_TARGETS").tag("plan");Text("USE_LAST_WORKOUT").tag("last") }
                Picker("EFFORT",selection:text("effort","none")) { Text("DON_T_LOG").tag("none");Text("RIR").tag("rir");Text("RPE").tag("rpe") }
                Picker("REFERENCE_PERFORMANCE",selection:text("logRef","last")) { Text("LAST_WORKOUT").tag("last");Text("PERSONAL_BEST").tag("best") }
                Toggle("KEEP_SCREEN_AWAKE_DURING_WORKOUTS",isOn:Binding(get:{values["keepAwake"] as? Bool ?? true},set:{values["keepAwake"] = $0}))
            }
            Section("UNITS_AND_ESTIMATES") {
                LabeledContent("CURRENT_WEIGHT_UNIT",value:store.unit)
                Button(String(format: String(localized: "SWITCH_TO_COUNT", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(describing: store.unit == "kg" ? "lb" : "kg"))) { nextUnit = store.unit == "kg" ? "lb" : "kg"; unitPrompt = true }
                Picker("SPEED",selection:text("speedUnit",store.unit == "lb" ? "mph":"kmh")) { Text("UNIT_SPEED_KMH").tag("kmh");Text("UNIT_SPEED_MPH").tag("mph") }
                Picker("ONE_REP_MAX_FORMULA",selection:text("oneRmFormula","epley")) {
                    Text("FORMULA_EPLEY").tag("epley");Text("FORMULA_BRZYCKI").tag("brzycki");Text("FORMULA_LOMBARDI").tag("lombardi");Text("FORMULA_MAYHEW").tag("mayhew");Text("FORMULA_WATHAN").tag("wathan");Text("FORMULA_LANDER").tag("lander");Text("FORMULA_OCONNER").tag("oconner");Text("WEIGHTED_ESTIMATE").tag("weighted")
                }
            }
            Section { NavigationLink("PLATES_AND_DUMBBELLS") { EquipmentInventoryView() } }
        }.operationAlert($issue).navigationTitle("WORKOUT_PREFERENCES").navigationBarTitleDisplayMode(.inline)
            .onAppear { if values.isEmpty { original = store.state.filter { keys.contains($0.key) }; values = original } }
            .toolbar { ToolbarItem(placement:.topBarTrailing) { Button("SAVE") { Task {
                if await store.savePersonalFields(original:original,proposed:values) { dismiss() } else { issue = store.editError }
            } }.disabled(store.syncing) } }
            .confirmationDialog("CHANGE_ACCOUNT_WEIGHT_UNIT",isPresented:$unitPrompt,titleVisibility:.visible) {
                Button("CONVERT_ALL_WEIGHTS") { changeUnit(true) }
                Button("KEEP_NUMBERS_CHANGE_UNIT_ONLY") { changeUnit(false) }
                Button("CANCEL",role:.cancel) {}
            } message: { Text("APPLIES_TO_ROUTINES_WORKOUT_HISTORY_BODY_WEIGHT_AND_TARGET_WEIGHT_EQUIPMENT_INVENTORIES") }
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
                Toggle("USE_MY_PLATE_INVENTORY",isOn:$ownPlates)
                if ownPlates { ForEach(sizes,id:\.self) { weight in
                    Stepper(String(format: String(localized: "COUNT_COUNT_COUNT_PAIRS", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(describing: decimal(weight)), String(describing: unit), String(describing: counts[String(weight)] ?? 0)),value:Binding(get:{counts[String(weight)] ?? 0},set:{counts[String(weight)] = $0}),in:0...50)
                } }
            } header: { HStack { Text("PLATES_PAIRS"); Spacer(); ExplanationButton(title: "EQUIPMENT_INVENTORY", message: "TURN_OFF_YOUR_CUSTOM_INVENTORY_TO_USE_STANDARD_PLATES_DUMBBELL_WEIGHTS_ARE") } }
            Section {
                TextField("FOR_EXAMPLE_TWO_FOUR_SIX_EIGHT_ONEZERO_ONETWO",text:$bells).textFieldStyle(.plain).stableInputLine().submitLabel(.done).onSubmit { GymKeyboard.dismiss() }.keyboardType(.numbersAndPunctuation)
                    .invalidInput(invalidWeights).onChange(of: bells) { _, _ in invalidWeights = false }.accessibilityIdentifier("dumbbell-inventory")
                Button("FILL_WITH_COMMON_WEIGHTS") { bells = (unit == "lb" ? stride(from:5,through:100,by:5).map(String.init) : stride(from:2,through:50,by:2).map(String.init)).joined(separator:", ") }
                Button("CLEAR_INVENTORY") { bells = "" }
            } header:{Text(String(format: String(localized: "WEIGHT_PER_DUMBBELL_COUNT", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(describing: unit)))}
        }.operationAlert($issue).navigationTitle("EQUIPMENT_INVENTORY").navigationBarTitleDisplayMode(.inline)
            .onAppear { guard !loaded else { return }; loaded = true; unit = store.unit
                original = store.state.filter { ["plates","dumbbells"].contains($0.key) }
                let plates = (original["plates"] as? [String:Any])?[unit] as? [String:Any] ?? [:]
                ownPlates = plates.keys.contains { Double($0) != nil }
                for w in sizes { counts[String(w)] = Int(number(plates[decimalKey(w)] ?? (w == 0.5 || (unit == "lb" && [15,1.25].contains(w)) ? 0:6))) }
                let list = ((original["dumbbells"] as? [String:Any])?[unit] as? [String:Any])?["weights"] as? [Double] ?? []
                bells = list.map { String($0) }.joined(separator:", ")
            }.toolbar { ToolbarItem(placement:.topBarTrailing) { Button("SAVE") { save() }.disabled(store.syncing) } }
    }
    private func decimalKey(_ w:Double)->String { w.rounded() == w ? String(Int(w)) : String(w) }
    private func save() {
        let parts = bells.split(whereSeparator:{ $0 == "," || $0 == "，" || $0 == " " || $0 == "\n" })
        let weights = parts.compactMap { Double($0) }
        guard weights.count == parts.count, weights.allSatisfy({$0.isFinite && $0 > 0 && $0 < 10000}) else { invalidWeights = true; issue = String(localized: "ENTER_VALID_WEIGHTS_GREATER_THAN_ZERO", bundle: AppLanguage.bundle, locale: AppLanguage.locale); return }
        var proposed = original, plates = original["plates"] as? [String:Any] ?? [:], db = original["dumbbells"] as? [String:Any] ?? [:]
        var stock:[String:Any] = ["_ts":Date().timeIntervalSince1970*1000]
        if ownPlates { for w in sizes { stock[decimalKey(w)] = counts[String(w)] ?? 0 } }
        plates[unit] = stock; db[unit] = ["weights":Array(Set(weights)).sorted(),"_ts":Date().timeIntervalSince1970*1000]
        proposed["plates"] = plates; proposed["dumbbells"] = db
        Task { if await store.savePersonalFields(original:original,proposed:proposed,unit:unit) { dismiss() } else { issue = store.editError } }
    }
}
