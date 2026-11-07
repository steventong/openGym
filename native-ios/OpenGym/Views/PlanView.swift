import SwiftUI
struct PlanView: View {
    @Environment(GymStore.self) private var store
    @State private var create = false
    @State private var tools = false
    @State private var coach = false
    @State private var schedule = false
    @State private var rotation = false
    @State private var selected: Routine?
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:22) {
                HStack {
                    VStack(alignment:.leading,spacing:7) { Text("ROUTINES").font(.system(size:34,weight:.bold)) }
                    Spacer()
                    if store.userName != nil {
                        Button { coach = true } label: {
                            Text("AI_LABEL").font(.system(size:16,weight:.bold)).foregroundStyle(GymTheme.green)
                                .frame(width:44,height:44).background(GymTheme.green.opacity(0.12),in:Circle())
                        }.accessibilityLabel("AI_COACH").accessibilityIdentifier("open-coach")
                    }
                    Button { create = true } label: { Image(systemName:"plus").font(.system(size:20)).foregroundStyle(GymTheme.green).padding(12).background(GymTheme.green.opacity(0.12),in:Circle()) }.accessibilityLabel("NEW_ROUTINE")
                }
                if store.userName == nil {
                    EmptyCard(icon:"link",title:String(localized: "CONNECT_ACCOUNT", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                    GreenButton(title:String(localized: "CONNECT_ACCOUNT", bundle: AppLanguage.bundle, locale: AppLanguage.locale),icon:"link") { store.showSettings = true }
                } else if store.routines.isEmpty {
                    EmptyCard(icon:"calendar",title:String(localized: "NO_ROUTINES_YET", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                    GreenButton(title:String(localized: "CREATE_ROUTINE", bundle: AppLanguage.bundle, locale: AppLanguage.locale),icon:"plus") { create = true }
                }
                if store.userName != nil {
                    Button { schedule = true } label: { HStack { Label("WORKOUT_SCHEDULE",systemImage:"calendar.badge.clock"); Spacer(); Text("WEEKLY_BY_DATE").font(.caption); Image(systemName:"chevron.right") }.foregroundStyle(GymTheme.green).gymCard() }.accessibilityIdentifier("open-schedule")
                }
                if store.userName != nil {
                    Button {rotation = true} label:{HStack {Label("ROTATION_SCHEDULE",systemImage:"repeat");Spacer();Text("ORDER_PROGRESS").font(.caption);Image(systemName:"chevron.right")}.foregroundStyle(GymTheme.green).gymCard()}.accessibilityIdentifier("open-rotation")
                    if store.rotationSummary()["view"] as? [String:Any] != nil {RotationProgressCard()}
                }
                ForEach(store.routines) { routine in
                    VStack(alignment:.leading,spacing:16) {
                        Button { selected = routine } label: {
                            HStack {
                                Image(systemName:"dumbbell").font(.system(size:24)).foregroundStyle(GymTheme.green).frame(width:50,height:50).background(GymTheme.green.opacity(0.12),in:RoundedRectangle(cornerRadius:14))
                                VStack(alignment:.leading,spacing:6) { Text(routine.name).font(.system(size:20,weight:.bold)); Text(String(format: String(localized: "COUNT_EXERCISES_COUNT_SETS", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(describing: routine.exercises.count), String(describing: routine.exercises.reduce(0) { $0 + Int(number($1["sets"])) }))).font(.caption).foregroundStyle(GymTheme.muted) }
                                Spacer(); Image(systemName:"chevron.right").font(.caption).foregroundStyle(GymTheme.muted)
                            }
                        }.buttonStyle(.plain).accessibilityIdentifier("edit-routine-\(routine.id)")
                        if !routine.exercises.isEmpty {
                            RoutineExercisePreview(exercises:routine.exercises)
                        }
                        GreenButton(title:String(localized: "START_WORKOUT", bundle: AppLanguage.bundle, locale: AppLanguage.locale),icon:"play.fill") { store.start(routine) }
                            .disabled(store.draft != nil)
                            .accessibilityIdentifier("start-routine-\(routine.id)")
                    }.gymCard()
                }
                Button { tools = true } label: { Label("TEMPLATES_AND_ROUTINE_IMPORT_EXPORT",systemImage:"square.and.arrow.up").frame(maxWidth:.infinity,minHeight:44) }.accessibilityIdentifier("open-plan-tools")
            }.padding(22)
        }.refreshable { await store.refresh() }.sheet(isPresented:$create) { RoutineComposer() }
            .sheet(isPresented:$tools) { PlanToolsView() }
            .sheet(isPresented:$coach) { CoachView() }
            .sheet(isPresented:$schedule) { ScheduleEditor() }
            .sheet(isPresented:$rotation) {RotationEditor()}
            .sheet(item:$selected) { routine in RoutineEditor(routine:routine,unit:store.unit) }
    }
}
private struct RoutineExercisePreview: View {
    let exercises: [[String: Any]]
    private let thumbnailSize: CGFloat = 52
    private let spacing: CGFloat = 8

    var body: some View {
        GeometryReader { geometry in
            let capacity = max(1, Int((geometry.size.width + spacing) / (thumbnailSize + spacing)))
            let visibleCount = min(exercises.count, capacity)
            HStack(spacing:spacing) {
                ForEach(0..<visibleCount, id:\.self) { index in
                    ExerciseThumbnail(id:exercises[index]["id"] as? String ?? "", size:thumbnailSize)
                        .overlay {
                            if exercises.count > capacity && index == visibleCount - 1 {
                                // The covered thumbnail also belongs to the remaining group.
                                let remainingCount = exercises.count - visibleCount + 1
                                RoundedRectangle(cornerRadius:12)
                                    .fill(.black.opacity(0.6))
                                    .overlay {
                                        Text(verbatim:"\(remainingCount)+")
                                            .font(.system(size:18, weight:.bold))
                                            .foregroundStyle(.white)
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.5)
                                            .padding(4)
                                    }
                            }
                        }
                }
            }
        }
        .frame(height:thumbnailSize)
        .accessibilityElement(children:.ignore)
        .accessibilityLabel(String(format: String(localized: "COUNT_EXERCISES", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(describing: exercises.count)))
    }
}

struct RoutineComposer: View {
    @Environment(GymStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var inputBuffer = InputCommitBuffer()
    @State private var name = ""
    @State private var query = ""
    @State private var ids: [String] = []
    private var results: [Exercise] { Array(store.exercises.filter { query.isEmpty ? ["0025","0043","0150","0027","0047","0031"].contains($0.id) : $0.searchText.localizedCaseInsensitiveContains(query) }.prefix(50)) }
    var body: some View {
        NavigationStack {
            List {
                Section("ROUTINE_NAME") { BufferedTextField(String(localized: "FOR_EXAMPLE_UPPER_BODY_A", bundle: AppLanguage.bundle, locale: AppLanguage.locale),text:$name).textFieldStyle(.plain).stableInputLine().submitLabel(.done).onSubmit { GymKeyboard.dismiss() }.accessibilityIdentifier("routine-name") }
                Section(String(format: String(localized: "CHOOSE_EXERCISES_COUNT_SELECTED", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(describing: ids.count))) {
                    CommittedSearchField(String(localized: "SEARCH_EXERCISES", bundle: AppLanguage.bundle, locale: AppLanguage.locale),text:$query).textFieldStyle(.plain).stableInputLine().submitLabel(.search).onSubmit { GymKeyboard.dismiss() }.accessibilityIdentifier("routine-exercise-search")
                    ForEach(results) { exercise in
                        Button {
                            if ids.contains(exercise.id) { ids.removeAll { $0 == exercise.id } } else { ids.append(exercise.id) }
                        } label: {
                            HStack {
                                ExerciseThumbnail(id:exercise.id,size:44)
                                Text(exercise.name).font(.system(size:14)).foregroundStyle(.white).lineLimit(1)
                                Spacer()
                                Text("3 × 10").font(.caption).foregroundStyle(.secondary).fixedSize()
                                    .accessibilityLabel("DEFAULTS_TO_THREE_SETS_OF_ONEZERO_REPS")
                                Image(systemName:ids.contains(exercise.id) ? "checkmark.circle.fill" : "circle").foregroundStyle(ids.contains(exercise.id) ? GymTheme.green : .gray)
                            }
                        }
                    }
                }
            }.navigationTitle("NEW_ROUTINE").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement:.topBarLeading) { Button("CANCEL") { dismiss() } }
                    ToolbarItem(placement:.topBarTrailing) { Button(store.syncing ? String(localized: "SAVING", bundle: AppLanguage.bundle, locale: AppLanguage.locale) : String(localized: "SAVE", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) { inputBuffer.commitAll(); let title = name.trimmingCharacters(in:.whitespacesAndNewlines); guard !title.isEmpty, !ids.isEmpty else { return }; Task { if await store.addRoutine(name:title,exerciseIDs:ids) { dismiss() } } }.disabled((name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && !inputBuffer.hasPending) || ids.isEmpty || store.syncing) }
                }
        }.tint(GymTheme.green).environment(\.inputCommitBuffer, inputBuffer)
    }
}
