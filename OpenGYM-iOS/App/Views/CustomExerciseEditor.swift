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
                Section("EXERCISE_INFORMATION") {
                    BufferedTextField("EXERCISE_NAME",text:text("n")).textFieldStyle(.plain).stableInputLine().submitLabel(.done).onSubmit { GymKeyboard.dismiss() }.invalidInput(invalidField == "n").accessibilityIdentifier("custom-exercise-name")
                    Picker("BODY_PART",selection:text("bp")) { ForEach(parts,id:\.self) { Text(String(localized: String.LocalizationValue($0), table: "Vocabulary", bundle: AppLanguage.bundle, locale: AppLanguage.locale)).tag($0) } }
                    Picker("EQUIPMENT",selection:text("eq")) { ForEach(Array(Set(store.exercises.map(\.equipment)+[raw["eq"] as? String ?? "body weight"])).sorted(),id:\.self) { Text(String(localized: String.LocalizationValue($0), table: "Vocabulary", bundle: AppLanguage.bundle, locale: AppLanguage.locale)).tag($0) } }
                    BufferedTextField("DESCRIPTION_AND_INSTRUCTIONS",text:text("desc"),axis:.vertical).textFieldStyle(.plain).submitLabel(.done).onSubmit { GymKeyboard.dismiss() }.lineLimit(3...10)
                    BufferedTextField("VIDEO_OR_TUTORIAL_URL_OPTIONAL",text:text("url")).textFieldStyle(.plain).stableInputLine().submitLabel(.done).onSubmit { GymKeyboard.dismiss() }.keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled().invalidInput(invalidField == "url")
                }
                if raw["bp"] as? String != "cardio" {
                    Section("PRIMARY_MUSCLE_GROUPS") { ForEach(muscles,id:\.self) { muscle in Toggle(String(localized: String.LocalizationValue(muscle), table: "Muscles", bundle: AppLanguage.bundle, locale: AppLanguage.locale),isOn:muscleBinding("primaries",muscle)) } }
                    Section("SECONDARY_MUSCLES") { ForEach(muscles.filter { !(raw["primaries"] as? [String] ?? []).contains($0) },id:\.self) { muscle in Toggle(String(localized: String.LocalizationValue(muscle), table: "Muscles", bundle: AppLanguage.bundle, locale: AppLanguage.locale),isOn:muscleBinding("secondaries",muscle)) } }
                }
                if original != nil { Section { Button("DELETE_EXERCISE",role:.destructive) { confirmDelete = true }.disabled(store.syncing) } }
            }.operationAlert($issue).navigationTitle(LocalizedStringKey(original == nil ? "CUSTOM_EXERCISE":"EDIT_EXERCISE")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement:.topBarLeading) { Button("CANCEL") { dismiss() } };ToolbarItem(placement:.topBarTrailing) { Button("SAVE") { save() }.disabled(store.syncing).accessibilityIdentifier("save-custom-exercise") } }
                .confirmationDialog("DELETE_THIS_EXERCISE",isPresented:$confirmDelete,titleVisibility:.visible) {
                    Button("DELETE",role:.destructive) { guard let original else {return}; Task { if await store.deleteCustomExercise(original) { store.selectedExercise = nil;dismiss() } else { issue = store.editError } } }
                } message:{Text("THE_EXERCISE_WILL_BE_REMOVED_FROM_YOUR_ROUTINES_COMPLETED_WORKOUTS_KEEP_ITS")}
        }.environment(\.inputCommitBuffer, inputBuffer)
    }
    private func text(_ key:String)->Binding<String> { Binding(get:{raw[key] as? String ?? ""},set:{raw[key] = $0; if invalidField == key { invalidField = nil }}) }
    private func muscleBinding(_ key:String,_ value:String)->Binding<Bool> { Binding(get:{(raw[key] as? [String] ?? []).contains(value)},set:{on in var list = raw[key] as? [String] ?? [];list.removeAll{$0 == value};if on{list.append(value)};raw[key] = list}) }
    private func save() {
        inputBuffer.commitAll()
        invalidField = nil
        var proposed = raw
        let name = (raw["n"] as? String ?? "").trimmingCharacters(in:.whitespacesAndNewlines)
        guard !name.isEmpty, name.count<=80 else { invalidField = "n"; issue = String(localized: "USE_A_NAME_BETWEEN_ONE_AND_EIGHTZERO_CHARACTERS", bundle: AppLanguage.bundle, locale: AppLanguage.locale);return }
        let renamed = name.lowercased() != (original?["n"] as? String ?? "").lowercased()
        if renamed && store.exercises.contains(where:{$0.id != raw["id"] as? String && ($0.name.localizedCaseInsensitiveCompare(name) == .orderedSame || $0.english.localizedCaseInsensitiveCompare(name) == .orderedSame)}) { invalidField = "n"; issue = String(localized: "AN_EXERCISE_WITH_THIS_NAME_ALREADY_EXISTS", bundle: AppLanguage.bundle, locale: AppLanguage.locale);return }
        let url = (raw["url"] as? String ?? "").trimmingCharacters(in:.whitespacesAndNewlines)
        if !url.isEmpty { guard let parsed = URL(string:url), ["https","http"].contains(parsed.scheme?.lowercased() ?? ""),parsed.host != nil,parsed.user == nil,parsed.password == nil else { invalidField = "url"; issue = String(localized: "ENTER_A_VALID_HTTP_OR_HTTPS_URL", bundle: AppLanguage.bundle, locale: AppLanguage.locale);return } }
        proposed["n"] = name;proposed["url"] = url.isEmpty ? nil:url;proposed["desc"] = String((raw["desc"] as? String ?? "").prefix(1000))
        let primary = raw["bp"] as? String == "cardio" ? ["cardiovascular system"] : raw["primaries"] as? [String] ?? []
        let secondary = (raw["secondaries"] as? [String] ?? []).filter{!primary.contains($0)}
        proposed["primaries"] = primary;proposed["secondaries"] = secondary;proposed["sm"] = secondary;proposed["muscleGroups"] = primary+secondary
        proposed["tg"] = primary.contains(original?["tg"] as? String ?? "") ? original?["tg"] : primary.first ?? ""
        Task { if await store.savePersonalRecord(collection:"customEx",key:"id",original:original,proposed:proposed) { if let id = proposed["id"] as? String, store.selectedExercise != nil { store.selectedExercise = store.exercise(id) };dismiss() } else { issue = store.editError } }
    }
}
