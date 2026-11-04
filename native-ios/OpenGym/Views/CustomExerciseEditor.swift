import SwiftUI

struct CustomExerciseEditor:View {
    @Environment(GymStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let original:[String:Any]?
    @State private var inputBuffer = InputCommitBuffer()
    @State private var raw:[String:Any]
    @State private var issue:String?
    @State private var invalidField: String?
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
                Section(L10n.text("EXERCISE_INFORMATION" /* 动作信息 */)) {
                    BufferedTextField(L10n.text("EXERCISE_NAME" /* 动作名称 */),text:text("n")).textFieldStyle(.plain).stableInputLine().submitLabel(.done).onSubmit { GymKeyboard.dismiss() }.invalidInput(invalidField == "n").accessibilityIdentifier("custom-exercise-name")
                    Picker(L10n.text("BODY_PART" /* 身体部位 */),selection:text("bp")) { ForEach(parts,id:\.self) { Text(Vocabulary.label($0)).tag($0) } }
                    Picker(L10n.text("EQUIPMENT" /* 器械 */),selection:text("eq")) { ForEach(Array(Set(store.exercises.map(\.equipment)+[raw["eq"] as? String ?? "body weight"])).sorted(),id:\.self) { Text(Vocabulary.label($0)).tag($0) } }
                    BufferedTextField(L10n.text("DESCRIPTION_AND_INSTRUCTIONS" /* 说明与动作要领 */),text:text("desc"),axis:.vertical).textFieldStyle(.plain).submitLabel(.done).onSubmit { GymKeyboard.dismiss() }.lineLimit(3...10)
                    BufferedTextField(L10n.text("VIDEO_OR_TUTORIAL_URL_OPTIONAL" /* 视频或教学链接（可选） */),text:text("url")).textFieldStyle(.plain).stableInputLine().submitLabel(.done).onSubmit { GymKeyboard.dismiss() }.keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled().invalidInput(invalidField == "url")
                }
                if raw["bp"] as? String != "cardio" {
                    Section(L10n.text("PRIMARY_MUSCLE_GROUPS" /* 主要肌群 */)) { ForEach(muscles,id:\.self) { muscle in Toggle(muscleName(muscle),isOn:muscleBinding("primaries",muscle)) } }
                    Section(L10n.text("SECONDARY_MUSCLES" /* 次要肌群 */)) { ForEach(muscles.filter { !(raw["primaries"] as? [String] ?? []).contains($0) },id:\.self) { muscle in Toggle(muscleName(muscle),isOn:muscleBinding("secondaries",muscle)) } }
                }
                if original != nil { Section { Button(L10n.text("DELETE_EXERCISE" /* 删除动作 */),role:.destructive) { confirmDelete = true }.disabled(store.syncing) } }
            }.operationAlert($issue).navigationTitle(original == nil ? L10n.text("CUSTOM_EXERCISE" /* 自定义动作 */):L10n.text("EDIT_EXERCISE" /* 编辑动作 */)).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement:.topBarLeading) { Button(L10n.text("CANCEL" /* 取消 */)) { dismiss() } };ToolbarItem(placement:.topBarTrailing) { Button(L10n.text("SAVE" /* 保存 */)) { save() }.disabled(store.syncing).accessibilityIdentifier("save-custom-exercise") } }
                .confirmationDialog(L10n.text("DELETE_THIS_EXERCISE" /* 删除这个动作？ */),isPresented:$confirmDelete,titleVisibility:.visible) {
                    Button(L10n.text("DELETE" /* 删除 */),role:.destructive) { guard let original else {return}; Task { if await store.deleteCustomExercise(original) { store.selectedExercise = nil;dismiss() } else { issue = store.editError } } }
                } message:{Text(L10n.text("THE_EXERCISE_WILL_BE_REMOVED_FROM_YOUR_ROUTINES_COMPLETED_WORKOUTS_KEEP_ITS" /* 会从计划中移除，已完成的训练保留动作名称、肌群与组记录。 */))}
        }.environment(\.inputCommitBuffer, inputBuffer)
    }
    private func text(_ key:String)->Binding<String> { Binding(get:{raw[key] as? String ?? ""},set:{raw[key] = $0; if invalidField == key { invalidField = nil }}) }
    private func muscleBinding(_ key:String,_ value:String)->Binding<Bool> { Binding(get:{(raw[key] as? [String] ?? []).contains(value)},set:{on in var list = raw[key] as? [String] ?? [];list.removeAll{$0 == value};if on{list.append(value)};raw[key] = list}) }
    private func save() {
        inputBuffer.commitAll()
        invalidField = nil
        var proposed = raw
        let name = (raw["n"] as? String ?? "").trimmingCharacters(in:.whitespacesAndNewlines)
        guard !name.isEmpty, name.count<=80 else { invalidField = "n"; issue = L10n.text("USE_A_NAME_BETWEEN_ONE_AND_EIGHTZERO_CHARACTERS" /* 名称需为 1–80 个字符。 */);return }
        let renamed = name.lowercased() != (original?["n"] as? String ?? "").lowercased()
        if renamed && store.exercises.contains(where:{$0.id != raw["id"] as? String && ($0.name.localizedCaseInsensitiveCompare(name) == .orderedSame || $0.english.localizedCaseInsensitiveCompare(name) == .orderedSame)}) { invalidField = "n"; issue = L10n.text("AN_EXERCISE_WITH_THIS_NAME_ALREADY_EXISTS" /* 已存在同名动作。 */);return }
        let url = (raw["url"] as? String ?? "").trimmingCharacters(in:.whitespacesAndNewlines)
        if !url.isEmpty { guard let parsed = URL(string:url), ["https","http"].contains(parsed.scheme?.lowercased() ?? ""),parsed.host != nil,parsed.user == nil,parsed.password == nil else { invalidField = "url"; issue = L10n.text("ENTER_A_VALID_HTTP_OR_HTTPS_URL" /* 请输入有效的 http 或 https 链接。 */);return } }
        proposed["n"] = name;proposed["url"] = url.isEmpty ? nil:url;proposed["desc"] = String((raw["desc"] as? String ?? "").prefix(1000))
        let primary = raw["bp"] as? String == "cardio" ? ["cardiovascular system"] : raw["primaries"] as? [String] ?? []
        let secondary = (raw["secondaries"] as? [String] ?? []).filter{!primary.contains($0)}
        proposed["primaries"] = primary;proposed["secondaries"] = secondary;proposed["sm"] = secondary;proposed["muscleGroups"] = primary+secondary
        proposed["tg"] = primary.contains(original?["tg"] as? String ?? "") ? original?["tg"] : primary.first ?? ""
        Task { if await store.savePersonalRecord(collection:"customEx",key:"id",original:original,proposed:proposed) { if let id = proposed["id"] as? String, store.selectedExercise != nil { store.selectedExercise = store.exercise(id) };dismiss() } else { issue = store.editError } }
    }
}
func muscleName(_ id:String)->String { ["trapezius":L10n.text("TRAPS_A" /* 斜方肌 */),"deltoids":L10n.text("SHOULDERS_A" /* 肩部 */),"chest":L10n.text("CHEST_A" /* 胸部 */),"upper-back":L10n.text("UPPER_BACK_A" /* 上背部 */),"serratus":L10n.text("SERRATUS" /* 前锯肌 */),"biceps":L10n.text("BICEPS_A" /* 肱二头肌 */),"triceps":L10n.text("TRICEPS_A" /* 肱三头肌 */),"forearm":L10n.text("FOREARMS_A" /* 前臂 */),"abs":L10n.text("ABS_A" /* 腹肌 */),"obliques":L10n.text("OBLIQUES_A" /* 腹斜肌 */),"lower-back":L10n.text("LOWER_BACK_A" /* 下背部 */),"gluteal":L10n.text("GLUTES_A" /* 臀部 */),"quadriceps":L10n.text("QUADS_A" /* 股四头肌 */),"hamstring":L10n.text("HAMSTRINGS_A" /* 腘绳肌 */),"adductors":L10n.text("ADDUCTORS_A" /* 内收肌 */),"hip-flexors":L10n.text("HIP_FLEXORS_A" /* 髋屈肌 */),"calves":L10n.text("CALVES_A" /* 小腿 */),"tibialis":L10n.text("SHINS_A" /* 胫前肌 */),"cardiovascular system":L10n.text("CARDIOVASCULAR_SYSTEM" /* 心血管系统 */)][id] ?? Vocabulary.label(id) }
