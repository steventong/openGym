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
                Toggle(L10n.text("FILTER_EXERCISES_BY_GYM_EQUIPMENT" /* 按健身房器械筛选动作 */),isOn:$enabled)
                Picker(L10n.text("CURRENT_GYM" /* 当前健身房 */),selection:$active) {Text(L10n.text("NONE_SELECTED" /* 未选择 */)).tag("");ForEach(profiles) {p in Text(p.raw["name"] as? String ?? L10n.text("GYM" /* 健身房 */)).tag(p.raw["id"] as? String ?? "")} }
            }
            Section(L10n.text("MY_GYM" /* 我的健身房 */)) {
                ForEach($profiles) {$profile in NavigationLink {EquipmentProfileEditor(profile:$profile)} label:{Text(profile.raw["name"] as? String ?? L10n.text("GYM" /* 健身房 */))} }
                    .onDelete { offsets in let ids = offsets.compactMap {profiles[$0].raw["id"] as? String};profiles.remove(atOffsets:offsets);if ids.contains(active) {active = ""} }
                Button(L10n.text("ADD_GYM" /* 添加健身房 */)) { let id = "eq"+UUID().uuidString;profiles.append(RawRow(raw:["id":id,"name":L10n.text("NEW_GYM" /* 新健身房 */),"equipment":[],"accV":1]));if active.isEmpty {active = id} }
            }
        }.environment(\.inputCommitBuffer, inputBuffer).operationAlert($issue).navigationTitle(L10n.text("GYM_EQUIPMENT" /* 健身房器械 */)).onAppear {
            guard !loaded else{return};loaded = true;original = store.state.filter{["equipProfiles","activeEquipId","equipFilterOn"].contains($0.key)}
            profiles = (original["equipProfiles"] as? [[String:Any]] ?? []).map{RawRow(raw:$0)};active = original["activeEquipId"] as? String ?? "";enabled = original["equipFilterOn"] as? Bool ?? false
        }.toolbar {ToolbarItem(placement:.topBarTrailing) {Button(L10n.text("SAVE" /* 保存 */)) {
            inputBuffer.commitAll()
            guard profiles.allSatisfy({!($0.raw["name"] as? String ?? "").trimmingCharacters(in:.whitespacesAndNewlines).isEmpty}) else{issue = L10n.text("ENTER_A_GYM_NAME" /* 请填写健身房名称。 */);return}
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
            BufferedTextField(L10n.text("GYM_NAME" /* 健身房名称 */),text:Binding(get:{profile.raw["name"] as? String ?? ""},set:{profile.raw["name"] = String($0.prefix(80))})).textFieldStyle(.plain).stableInputLine().submitLabel(.done).onSubmit { GymKeyboard.dismiss() }
            Section(L10n.text("AVAILABLE_EQUIPMENT" /* 可用器械 */)) {ForEach(options,id:\.self) {option in
                Toggle(option == "bench" ? L10n.text("BENCH_A" /* 训练凳 */):option == "pull-up bar" ? L10n.text("PULL_UP_BAR_A" /* 单杠 */):Vocabulary.label(option),isOn:Binding(get:{(profile.raw["equipment"] as? [String] ?? []).contains(option)},set:{on in var list = profile.raw["equipment"] as? [String] ?? [];list.removeAll{$0 == option};if on{list.append(option)};profile.raw["equipment"] = list;profile.raw["accV"] = 1}))
            } }
        }.navigationTitle(L10n.text("PICK_EQUIPMENT" /* 选择器械 */)).navigationBarTitleDisplayMode(.inline)
    }
}
