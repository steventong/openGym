import SwiftUI
struct EquipmentProfilesView:View {
    @Environment(GymStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var original:[String:Any] = [:]
    @State private var profiles:[RawRow] = []
    @State private var active = ""
    @State private var enabled = false
    @State private var loaded = false
    @State private var issue:String?
    var body:some View {
        Form {
            Section {
                Toggle("按健身房器械筛选动作",isOn:$enabled)
                Picker("当前健身房",selection:$active) {Text("未选择").tag("");ForEach(profiles) {p in Text(p.raw["name"] as? String ?? "健身房").tag(p.raw["id"] as? String ?? "")} }
            }
            Section("我的健身房") {
                ForEach($profiles) {$profile in NavigationLink {EquipmentProfileEditor(profile:$profile)} label:{Text(profile.raw["name"] as? String ?? "健身房")} }
                    .onDelete { offsets in let ids = offsets.compactMap {profiles[$0].raw["id"] as? String};profiles.remove(atOffsets:offsets);if ids.contains(active) {active = ""} }
                Button("添加健身房") { let id = "eq"+UUID().uuidString;profiles.append(RawRow(raw:["id":id,"name":"新健身房","equipment":[],"accV":1]));if active.isEmpty {active = id} }
            }
            if let issue {Text(issue).foregroundStyle(.orange)}
        }.navigationTitle("健身房器械").onAppear {
            guard !loaded else{return};loaded = true;original = store.state.filter{["equipProfiles","activeEquipId","equipFilterOn"].contains($0.key)}
            profiles = (original["equipProfiles"] as? [[String:Any]] ?? []).map{RawRow(raw:$0)};active = original["activeEquipId"] as? String ?? "";enabled = original["equipFilterOn"] as? Bool ?? false
        }.toolbar {ToolbarItem(placement:.topBarTrailing) {Button("保存") {
            guard profiles.allSatisfy({!($0.raw["name"] as? String ?? "").trimmingCharacters(in:.whitespacesAndNewlines).isEmpty}) else{issue = "请填写健身房名称。";return}
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
            TextField("健身房名称",text:Binding(get:{profile.raw["name"] as? String ?? ""},set:{profile.raw["name"] = String($0.prefix(80))}))
            Section("可用器械") {ForEach(options,id:\.self) {option in
                Toggle(option == "bench" ? "训练凳":option == "pull-up bar" ? "单杠":Vocabulary.label(option),isOn:Binding(get:{(profile.raw["equipment"] as? [String] ?? []).contains(option)},set:{on in var list = profile.raw["equipment"] as? [String] ?? [];list.removeAll{$0 == option};if on{list.append(option)};profile.raw["equipment"] = list;profile.raw["accV"] = 1}))
            } }
        }.navigationTitle("选择器械").navigationBarTitleDisplayMode(.inline)
    }
}
