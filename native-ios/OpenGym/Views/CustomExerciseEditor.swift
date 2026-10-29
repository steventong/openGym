import SwiftUI

struct CustomExerciseEditor:View {
    @Environment(GymStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let original:[String:Any]?
    @State private var raw:[String:Any]
    @State private var issue:String?
    @State private var confirmDelete = false
    @MainActor init(original:[String:Any]? = nil) {
        self.original = original
        var initial = original ?? ["id":"c"+UUID().uuidString,"n":"","bp":"chest","eq":"body weight","custom":true]
        if let original, (original["primaries"] as? [String] ?? []).isEmpty,
           let metadata = try? WebRules.shared.call("personalInfo",payload:["action":"customMetadata","state":[:],"exercise":original]) as? [String:Any],let groups = metadata["groups"] as? [String] {
            initial["primaries"] = Array(groups.prefix(1));initial["secondaries"] = Array(groups.dropFirst())
        }
        _raw = State(initialValue:initial)
    }
    private let parts = ["back","cardio","chest","full body","lower arms","lower legs","neck","shoulders","upper arms","upper legs","waist"]
    private let muscles = ["abs","obliques","chest","trapezius","upper-back","lower-back","lats","deltoids","biceps","triceps","forearm","gluteal","quadriceps","hamstring","adductors","calves","serratus","hip-flexors","tibialis"]
    var body:some View {
        NavigationStack {
            Form {
                Section("动作信息") {
                    TextField("动作名称",text:text("n")).accessibilityIdentifier("custom-exercise-name")
                    Picker("身体部位",selection:text("bp")) { ForEach(parts,id:\.self) { Text(Vocabulary.label($0)).tag($0) } }
                    Picker("器械",selection:text("eq")) { ForEach(Array(Set(store.exercises.map(\.equipment)+[raw["eq"] as? String ?? "body weight"])).sorted(),id:\.self) { Text(Vocabulary.label($0)).tag($0) } }
                    TextField("说明与动作要领",text:text("desc"),axis:.vertical).lineLimit(3...10)
                    TextField("视频或教学链接（可选）",text:text("url")).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                if raw["bp"] as? String != "cardio" {
                    Section("主要肌群") { ForEach(muscles,id:\.self) { muscle in Toggle(muscleName(muscle),isOn:muscleBinding("primaries",muscle)) } }
                    Section("次要肌群") { ForEach(muscles.filter { !(raw["primaries"] as? [String] ?? []).contains($0) },id:\.self) { muscle in Toggle(muscleName(muscle),isOn:muscleBinding("secondaries",muscle)) } }
                }
                if let issue { Text(issue).foregroundStyle(.orange) }
                if original != nil { Section { Button("删除动作",role:.destructive) { confirmDelete = true }.disabled(store.syncing) } }
            }.navigationTitle(original == nil ? "自定义动作":"编辑动作").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement:.topBarLeading) { Button("取消") { dismiss() } };ToolbarItem(placement:.topBarTrailing) { Button("保存") { save() }.disabled(store.syncing).accessibilityIdentifier("save-custom-exercise") } }
                .confirmationDialog("删除这个动作？",isPresented:$confirmDelete,titleVisibility:.visible) {
                    Button("删除",role:.destructive) { guard let original else {return}; Task { if await store.deleteCustomExercise(original) { store.selectedExercise = nil;dismiss() } else { issue = store.editError } } }
                } message:{Text("会从计划中移除，已完成的训练保留动作名称、肌群与组记录。")}
        }
    }
    private func text(_ key:String)->Binding<String> { Binding(get:{raw[key] as? String ?? ""},set:{raw[key] = $0}) }
    private func muscleBinding(_ key:String,_ value:String)->Binding<Bool> { Binding(get:{(raw[key] as? [String] ?? []).contains(value)},set:{on in var list = raw[key] as? [String] ?? [];list.removeAll{$0 == value};if on{list.append(value)};raw[key] = list}) }
    private func save() {
        var proposed = raw
        let name = (raw["n"] as? String ?? "").trimmingCharacters(in:.whitespacesAndNewlines)
        guard !name.isEmpty, name.count<=80 else { issue = "名称需为 1–80 个字符。";return }
        let renamed = name.lowercased() != (original?["n"] as? String ?? "").lowercased()
        if renamed && store.exercises.contains(where:{$0.id != raw["id"] as? String && ($0.name.localizedCaseInsensitiveCompare(name) == .orderedSame || $0.english.localizedCaseInsensitiveCompare(name) == .orderedSame)}) { issue = "已存在同名动作。";return }
        let url = (raw["url"] as? String ?? "").trimmingCharacters(in:.whitespacesAndNewlines)
        if !url.isEmpty { guard let parsed = URL(string:url), ["https","http"].contains(parsed.scheme?.lowercased() ?? ""),parsed.host != nil,parsed.user == nil,parsed.password == nil else { issue = "请输入有效的 http 或 https 链接。";return } }
        proposed["n"] = name;proposed["url"] = url.isEmpty ? nil:url;proposed["desc"] = String((raw["desc"] as? String ?? "").prefix(1000))
        let primary = raw["bp"] as? String == "cardio" ? ["cardiovascular system"] : raw["primaries"] as? [String] ?? []
        let secondary = (raw["secondaries"] as? [String] ?? []).filter{!primary.contains($0)}
        proposed["primaries"] = primary;proposed["secondaries"] = secondary;proposed["sm"] = secondary;proposed["muscleGroups"] = primary+secondary
        proposed["tg"] = primary.contains(original?["tg"] as? String ?? "") ? original?["tg"] : primary.first ?? ""
        Task { if await store.savePersonalRecord(collection:"customEx",key:"id",original:original,proposed:proposed) { if let id = proposed["id"] as? String, store.selectedExercise != nil { store.selectedExercise = store.exercise(id) };dismiss() } else { issue = store.editError } }
    }
}
func muscleName(_ id:String)->String { ["abs":"腹肌","obliques":"腹斜肌","chest":"胸肌","trapezius":"斜方肌","upper-back":"上背","lower-back":"下背","lats":"背阔肌","deltoids":"三角肌","biceps":"肱二头肌","triceps":"肱三头肌","forearm":"前臂","gluteal":"臀肌","quadriceps":"股四头肌","hamstring":"腘绳肌","adductors":"内收肌","calves":"小腿","serratus":"前锯肌","hip-flexors":"髋屈肌","tibialis":"胫骨前肌"][id] ?? Vocabulary.label(id) }
