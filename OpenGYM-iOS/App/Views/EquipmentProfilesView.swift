import SwiftUI
struct EquipmentProfilesView:View {
    @Environment(GymStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var inputBuffer = InputCommitBuffer()
    @State private var original:[String:Any] = [:]
    @State private var profiles:[RawRow] = []
    @State private var active = ""
    @State private var enabled = false
    @State private var loaded = false
    @State private var issue:String?
    var body:some View {
        Form {
            Section {
                Toggle("FILTER_EXERCISES_BY_GYM_EQUIPMENT",isOn:$enabled)
                Picker("CURRENT_GYM",selection:$active) {Text("NONE_SELECTED").tag("");ForEach(profiles) {p in Text(p.raw["name"] as? String ?? String(localized: "GYM", bundle: AppLanguage.bundle, locale: AppLanguage.locale)).tag(p.raw["id"] as? String ?? "")} }
            }
            Section("MY_GYM") {
                ForEach($profiles) {$profile in NavigationLink {EquipmentProfileEditor(profile:$profile)} label:{Text(profile.raw["name"] as? String ?? String(localized: "GYM", bundle: AppLanguage.bundle, locale: AppLanguage.locale))} }
                    .onDelete { offsets in let ids = offsets.compactMap {profiles[$0].raw["id"] as? String};profiles.remove(atOffsets:offsets);if ids.contains(active) {active = ""} }
                Button("ADD_GYM") { let id = "eq"+UUID().uuidString;profiles.append(RawRow(raw:["id":id,"name":String(localized: "NEW_GYM", bundle: AppLanguage.bundle, locale: AppLanguage.locale),"equipment":[],"accV":1]));if active.isEmpty {active = id} }
            }
        }.environment(\.inputCommitBuffer, inputBuffer).operationAlert($issue).navigationTitle("GYM_EQUIPMENT").onAppear {
            guard !loaded else{return};loaded = true;original = store.state.filter{["equipProfiles","activeEquipId","equipFilterOn"].contains($0.key)}
            profiles = (original["equipProfiles"] as? [[String:Any]] ?? []).map{RawRow(raw:$0)};active = original["activeEquipId"] as? String ?? "";enabled = original["equipFilterOn"] as? Bool ?? false
        }.toolbar {ToolbarItem(placement:.topBarTrailing) {Button("SAVE") {
            inputBuffer.commitAll()
            guard profiles.allSatisfy({!($0.raw["name"] as? String ?? "").trimmingCharacters(in:.whitespacesAndNewlines).isEmpty}) else{issue = String(localized: "ENTER_A_GYM_NAME", bundle: AppLanguage.bundle, locale: AppLanguage.locale);return}
            let proposed:[String:Any] = ["equipProfiles":profiles.map(\.raw),"activeEquipId":active,"equipFilterOn":enabled]
            Task {if await store.savePersonalFields(original:original,proposed:proposed) {dismiss()} else{issue = store.editError}}
        }.disabled(store.syncing)} }
    }
}
struct EquipmentProfileEditor:View {
    @Environment(GymStore.self) private var store
    @Binding var profile:RawRow
    private var options:[String] { (try? store.personalInfo("equipment"))?["equipment"] as? [String] ?? [] }
    var body:some View {
        Form {
            BufferedTextField("GYM_NAME",text:Binding(get:{profile.raw["name"] as? String ?? ""},set:{profile.raw["name"] = String($0.prefix(80))})).textFieldStyle(.plain).stableInputLine().submitLabel(.done).onSubmit { GymKeyboard.dismiss() }
            Section("AVAILABLE_EQUIPMENT") {ForEach(options,id:\.self) {option in
                Toggle(option == "bench" ? String(localized: "BENCH_A", bundle: AppLanguage.bundle, locale: AppLanguage.locale):option == "pull-up bar" ? String(localized: "PULL_UP_BAR_A", bundle: AppLanguage.bundle, locale: AppLanguage.locale):String(localized: String.LocalizationValue(option), table: "Vocabulary", bundle: AppLanguage.bundle, locale: AppLanguage.locale),isOn:Binding(get:{(profile.raw["equipment"] as? [String] ?? []).contains(option)},set:{on in var list = profile.raw["equipment"] as? [String] ?? [];list.removeAll{$0 == option};if on{list.append(option)};profile.raw["equipment"] = list;profile.raw["accV"] = 1}))
            } }
        }.navigationTitle("PICK_EQUIPMENT").navigationBarTitleDisplayMode(.inline)
    }
}
