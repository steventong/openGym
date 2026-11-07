import SwiftUI
struct RoutineEditor: View {
    @Environment(GymStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var inputBuffer = InputCommitBuffer()
    @State private var original: [String:Any]
    let expectedUnit: String
    @State private var name: String
    @State private var rows: [RawRow]
    @State private var pick = false
    @State private var sorting = false
    @State private var configuration: RawRow?
    @State private var discard = false
    @State private var confirmDelete = false
    @State private var deleting = false
    @State private var saving = false
    @State private var errorTitle = String(localized: "COULD_NOT_SAVE", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
    @State private var error: String?
    init(routine:Routine,unit:String) {
        _original = State(initialValue: routine.raw); expectedUnit = unit
        _name = State(initialValue:routine.name); _rows = State(initialValue:routine.exercises.map { RawRow(raw:$0) })
    }
    private var proposed:[String:Any] { var r = original; r["name"] = name.trimmingCharacters(in:.whitespacesAndNewlines); r["ex"] = rows.map(\.raw); return r }
    private var dirty: Bool { inputBuffer.hasPending || !RecordPatch.equal(original,proposed) }
    var body: some View {
        NavigationStack {
            List {
                Section("ROUTINE_NAME") { BufferedTextField(String(localized: "ROUTINE_NAME", bundle: AppLanguage.bundle, locale: AppLanguage.locale),text:$name).textFieldStyle(.plain).stableInputLine().submitLabel(.done).onSubmit { GymKeyboard.dismiss() }.accessibilityIdentifier("edit-routine-name") }
                Section {
                    ForEach($rows) { $row in
                        VStack(alignment:.leading,spacing:14) {
                            HStack {
                                ExerciseThumbnail(id:row.raw["id"] as? String ?? "",size:46)
                                Text(store.exercise(row.raw["id"] as? String ?? "")?.name ?? row.raw["id"] as? String ?? String(localized: "EXERCISE", bundle: AppLanguage.bundle, locale: AppLanguage.locale)).font(.headline)
                                Spacer()
                                RoutineExerciseReplacement(slot: $row.raw, routineID: original["id"] as? String ?? "")
                            }
                            if EditValidation.ordinaryConfig(row.raw) {
                                HStack {
                                    RoutineNumberField(title: String(localized: "SETS", bundle: AppLanguage.bundle, locale: AppLanguage.locale), value: numericBinding("sets", fallback: 3, row: $row), allowsDecimal: false, identifier: "routine-sets-\(row.raw["id"] as? String ?? "")")
                                    RoutineNumberField(title: String(localized: "REPS", bundle: AppLanguage.bundle, locale: AppLanguage.locale), value: numericBinding("reps", fallback: 10, row: $row), allowsDecimal: false, identifier: "routine-reps-\(row.raw["id"] as? String ?? "")")
                                    RoutineNumberField(title: expectedUnit, value: numericBinding("weight", fallback: 0, row: $row), allowsDecimal: true, identifier: "routine-weight-\(row.raw["id"] as? String ?? "")")
                                }
                                Stepper(String(format: String(localized: "REST_BETWEEN_SETS_COUNT_SECONDS", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(describing: Int(number(row.raw["restSec"] ?? 90)))),value:Binding(get:{Int(number(row.raw["restSec"] ?? 90))},set:{row.raw["restSec"] = $0}),in:0...900,step:15).font(.subheadline)
                            } else { Text("ADVANCED_SET_TYPES").font(.caption).foregroundStyle(.secondary) }
                            Button { inputBuffer.commitAll(); configuration = rows.first { $0.id == row.id } } label: { Label("ADVANCED_SETS_AND_TIMERS",systemImage:"slider.horizontal.3") }.buttonStyle(.borderless).accessibilityIdentifier("advanced-slot-\(row.raw["id"] as? String ?? "")")
                            if row.raw["sg"] != nil { Label("SUPERSET",systemImage:"link").font(.caption).foregroundStyle(GymTheme.green) }
                            HStack {
                                if rows.last?.id != row.id { Button("MAKE_SUPERSET_WITH_NEXT") { group(row.id,"pair") }.font(.caption).buttonStyle(.borderless) }
                                if row.raw["sg"] != nil { Button("UNPAIR") { group(row.id,"unpair") }.font(.caption).buttonStyle(.borderless) }
                            }
                            BufferedTextField(String(localized: "EXERCISE_NOTES", bundle: AppLanguage.bundle, locale: AppLanguage.locale),text:Binding(get:{row.raw["note"] as? String ?? ""},set:{row.raw["note"] = $0})).textFieldStyle(.plain).stableInputLine().submitLabel(.done).onSubmit { GymKeyboard.dismiss() }.font(.subheadline)
                            HStack {
                                Button { inputBuffer.commitAll(); sorting = true } label: { Label("REORDER_EXERCISES", systemImage: "arrow.up.arrow.down").frame(minHeight: 48) }.disabled(rows.count < 2)
                                Spacer()
                                Button(role:.destructive) { inputBuffer.commitAll(); let id = row.id; rows.removeAll { $0.id == id } } label: { Image(systemName:"minus.circle") }.accessibilityLabel("REMOVE_EXERCISE")
                            }.font(.caption).buttonStyle(.borderless)
                        }.padding(.vertical,7)
                    }.onDelete { inputBuffer.commitAll(); rows.remove(atOffsets:$0) }
                    Button { inputBuffer.commitAll(); pick = true } label: { Label("ADD_EXERCISE",systemImage:"plus.circle.fill") }.accessibilityIdentifier("edit-add-exercise")
                } header: { Text(String(format: String(localized: "EXERCISE_COUNT", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(describing: rows.count))) }
                Section {
                    Button(role:.destructive) { guard !saving, !deleting else { return }; confirmDelete = true } label: {
                        Label(deleting ? String(localized: "DELETING", bundle: AppLanguage.bundle, locale: AppLanguage.locale) : String(localized: "DELETE_ROUTINE_A", bundle: AppLanguage.bundle, locale: AppLanguage.locale),systemImage:"trash")
                    }.accessibilityIdentifier("delete-routine")
                }
            }.navigationTitle("EDIT_ROUTINE").navigationBarTitleDisplayMode(.inline)
                .keyboardDismissToolbar()
                .toolbar {
                    ToolbarItem(placement:.topBarLeading) { Button("CANCEL") { guard !saving, !deleting else { return }; inputBuffer.commitAll(); if dirty { discard = true } else { dismiss() } } }
                    ToolbarItem(placement:.topBarTrailing) { Button(saving ? String(localized: "SAVING", bundle: AppLanguage.bundle, locale: AppLanguage.locale) : String(localized: "SAVE", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) { Task { await saveRoutine() } }.accessibilityIdentifier("save-routine-edit") }
                }
                .sheet(isPresented: $sorting) {
                    ExerciseOrderSheet(entries: rows.map(\.raw)) { order, baseline in
                        guard RecordPatch.equal(baseline, rows.map(\.raw)) else { throw APIError.response(0, String(localized: "THE_EXERCISE_LIST_HAS_CHANGED_OPEN_THE_REORDER_SCREEN_AGAIN", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) }
                        let result = try ExerciseOrder.apply(order, to: ["entries": rows.map(\.raw)])
                        guard let updated = result["entries"] as? [[String: Any]] else { throw APIError.invalidResponse }
                        let existing = rows
                        rows = order.enumerated().map { offset, index in
                            var row = existing[index]; row.raw = updated[offset]; return row
                        }
                    }
                }
                .sheet(item:$configuration) { selected in AdvancedConfigEditor(config:selected.raw,unit:expectedUnit) { updated in if let i = rows.firstIndex(where:{$0.id == selected.id}) { rows[i].raw = updated } } }
                .sheet(isPresented:$pick) { ExercisePicker { exercise in rows.append(RawRow(raw:["id":exercise.id,"sets":3,"reps":10,"weight":0,"restSec":90])); pick = false } }
                .alert(errorTitle,isPresented:Binding(get:{error != nil},set:{if !$0 { error = nil }})) { Button("GOT_IT",role:.cancel) {} } message: { Text(error ?? "") }
                .confirmationDialog("DELETE_ROUTINE",isPresented:$confirmDelete,titleVisibility:.visible) {
                    Button("DELETE_ROUTINE_A",role:.destructive) { Task { await deleteRoutine() } }
                    Button("CANCEL",role:.cancel) {}
                } message: {
                    Text(String(format: String(localized: "COUNT_AND_ITS_SCHEDULE_WILL_BE_DELETED_THIS_CANNOT_BE_UNDONE_YOUR", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(describing: original["name"] as? String ?? String(localized: "ROUTINES", bundle: AppLanguage.bundle, locale: AppLanguage.locale))) + (dirty ? String(localized: "YOUR_UNSAVED_CHANGES_WILL_BE_DISCARDED", bundle: AppLanguage.bundle, locale: AppLanguage.locale) : ""))
                }
                .confirmationDialog("DISCARD_UNSAVED_CHANGES",isPresented:$discard,titleVisibility:.visible) { Button("DISCARD_CHANGES",role:.destructive) { dismiss() }; Button("KEEP_EDITING",role:.cancel) {} }
                .interactiveDismissDisabled(dirty || saving || deleting)
        }.tint(GymTheme.green).environment(\.inputCommitBuffer, inputBuffer)
    }
    private func saveRoutine() async {
        inputBuffer.commitAll()
        guard !saving, !deleting, !store.syncing else { return }
        guard dirty else { dismiss(); return }
        saving = true; defer { saving = false }
        let snapshot = proposed
        if await store.saveRoutine(original: original, proposed: snapshot, expectedUnit: expectedUnit) {
            inputBuffer.commitAll()
            original = snapshot
            // Keep any edits entered while the request was in flight in this editor.
            if RecordPatch.equal(proposed, snapshot) { dismiss() }
        } else { errorTitle = String(localized: "COULD_NOT_SAVE", bundle: AppLanguage.bundle, locale: AppLanguage.locale); error = store.editError }
    }
    private func deleteRoutine() async {
        guard !saving, !deleting, let id = original["id"] as? String else { return }
        deleting = true; defer { deleting = false }
        if await store.deleteRoutine(id:id) { dismiss() }
        else { errorTitle = String(localized: "COULD_NOT_DELETE", bundle: AppLanguage.bundle, locale: AppLanguage.locale); error = store.editError }
    }
    private func group(_ id:UUID,_ operation:String,_ direction:Int = 0) {
        inputBuffer.commitAll()
        guard let i = rows.firstIndex(where:{$0.id == id}) else { return }
        do { let result = try WebRules.shared.call("planGroup",payload:["rows":rows.map(\.raw),"operation":operation,"index":i,"direction":direction]) as! [[String:Any]];rows = result.map { RawRow(raw:$0) } } catch { errorTitle = String(localized: "COULD_NOT_SAVE", bundle: AppLanguage.bundle, locale: AppLanguage.locale); self.error = error.localizedDescription }
    }
    private func numericBinding(_ key: String, fallback: Double, row: Binding<RawRow>) -> Binding<Double> {
        Binding(get: { number(row.wrappedValue.raw[key] ?? fallback) }, set: { row.wrappedValue.raw[key] = $0 })
    }
}
struct ExercisePicker: View {
    @Environment(GymStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var searchReset = 0
    @State private var available:Set<String>?
    @State private var favouritesOnly = false
    @State private var trainedOnly = false
    @State private var customOnly = false
    @State private var bodyPart = ""
    @State private var equipment = ""
    @State private var limit = 60
    private let bodyParts = ["", "back", "cardio", "chest", "full body", "lower arms", "lower legs", "neck", "shoulders", "upper arms", "upper legs", "waist"]
    private var choices:[Exercise] {
        let favourites = store.favouriteIDs
        let trained = trainedOnly ? store.trainedExerciseIDs : []
        let customs = Set(store.customExercises.compactMap { $0["id"] as? String })
        let matching = store.exercises.filter {
            (search.isEmpty || $0.searchText.localizedCaseInsensitiveContains(search)) &&
            (!favouritesOnly || favourites.contains($0.id)) &&
            (!trainedOnly || trained.contains($0.id)) &&
            (!customOnly || customs.contains($0.id)) &&
            (bodyPart.isEmpty || $0.bodyPart == bodyPart) &&
            (equipment.isEmpty || $0.equipment == equipment) &&
            (available == nil || available!.contains($0.id))
        }
        return matching.filter {favourites.contains($0.id)} + matching.filter {!favourites.contains($0.id)}
    }
    private var equipments: [String] {
        [""] + Set(store.exercises.filter { bodyPart.isEmpty || $0.bodyPart == bodyPart }.map(\.equipment)).sorted()
    }
    var title = String(localized: "ADD_EXERCISE", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
    var selectionIcon = "plus"
    let select:(Exercise)->Void
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    searchField
                    filters
                    let results = choices
                    HStack {
                        Text(String(format: String(localized: "COUNT_EXERCISES_FOUND", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(describing: results.count)))
                        Spacer()
                        if let error = store.catalogueError { StatusDetailButton(title: String(localized: "COULD_NOT_LOAD", bundle: AppLanguage.bundle, locale: AppLanguage.locale), message: error, warning: true) }
                        else { Label("EXERCISES", systemImage: "checkmark.seal") }
                    }.font(.caption).foregroundStyle(GymTheme.muted)
                    if results.isEmpty {
                        EmptyCard(icon: "magnifyingglass", title: String(localized: "NO_EXERCISES_FOUND", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                        Button("CLEAR_SEARCH_AND_FILTERS") { resetFilters() }
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    LazyVStack(spacing: 10) {
                        ForEach(Array(results.prefix(limit))) { exercise in
                            Button { select(exercise) } label: {
                                ExerciseRow(exercise: exercise, accessoryIcon: selectionIcon)
                            }.buttonStyle(.plain)
                                .accessibilityIdentifier("pick-\(exercise.id)")
                        }
                        if results.count > limit { ExercisePageTrigger(limit: $limit, total: results.count).id(limit) }
                    }
                }.padding(20)
            }.background(GymTheme.background)
                .scrollDismissesKeyboard(.interactively)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("CANCEL") { dismiss() } } }
                .onAppear { refreshEquipment() }
                .onChange(of: store.lastSync) { _, _ in refreshEquipment() }
                .onChange(of: search) { _, _ in limit = 60 }
                .onChange(of: bodyPart) { _, _ in limit = 60 }
                .onChange(of: equipment) { _, _ in limit = 60 }
                .onChange(of: favouritesOnly) { _, _ in limit = 60 }
                .onChange(of: trainedOnly) { _, _ in limit = 60 }
                .onChange(of: customOnly) { _, _ in limit = 60 }
        }.tint(GymTheme.green)
    }
    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(GymTheme.muted)
            CommittedSearchField(String(localized: "SEARCH_EXERCISES_MUSCLES", bundle: AppLanguage.bundle, locale: AppLanguage.locale), text: $search, resetToken: searchReset).submitLabel(.search).onSubmit { GymKeyboard.dismiss() }
                .textFieldStyle(.plain).font(.system(size: 15)).autocorrectionDisabled()
                .accessibilityIdentifier("picker-search")
            if !search.isEmpty {
                Button { searchReset += 1; search = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.gray)
                }.accessibilityLabel("CLEAR_SEARCH")
            }
        }.padding(.horizontal, 14).frame(height: 48)
            .background(Color(white: 0.16), in: RoundedRectangle(cornerRadius: 14))
    }
    private var filters: some View {
        VStack(alignment: .leading, spacing: 18) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(bodyParts, id: \.self) { item in
                        Pill(title: item.isEmpty ? String(localized: "ALL", bundle: AppLanguage.bundle, locale: AppLanguage.locale) : String(localized: String.LocalizationValue(item), table: "Vocabulary", bundle: AppLanguage.bundle, locale: AppLanguage.locale), selected: bodyPart == item) {
                            bodyPart = item; equipment = ""
                        }
                    }
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(equipments, id: \.self) { item in
                        Pill(title: item.isEmpty ? String(localized: "ANY_EQUIPMENT", bundle: AppLanguage.bundle, locale: AppLanguage.locale) : String(localized: String.LocalizationValue(item), table: "Vocabulary", bundle: AppLanguage.bundle, locale: AppLanguage.locale), selected: equipment == item) { equipment = item }
                    }
                }
            }
            HStack(spacing: 8) {
                Pill(title: String(localized: "FAVOURITES", bundle: AppLanguage.bundle, locale: AppLanguage.locale), selected: favouritesOnly) { favouritesOnly.toggle() }
                Pill(title: String(localized: "PREVIOUSLY_TRAINED", bundle: AppLanguage.bundle, locale: AppLanguage.locale), selected: trainedOnly) { trainedOnly.toggle() }
                Pill(title: String(localized: "CUSTOM", bundle: AppLanguage.bundle, locale: AppLanguage.locale), selected: customOnly) { customOnly.toggle() }
            }
        }
    }
    private func resetFilters() {
        searchReset += 1; search = ""; bodyPart = ""; equipment = ""; favouritesOnly = false; trainedOnly = false; customOnly = false; limit = 60
    }
    private func refreshEquipment() {
        if store.state["equipFilterOn"] as? Bool == true {
            available = ((try? store.personalInfo("equipment"))?["available"] as? [String]).map { Set($0) }
        } else { available = nil }
    }
}
