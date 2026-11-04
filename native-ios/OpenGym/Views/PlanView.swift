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
                    VStack(alignment:.leading,spacing:7) { Text(L10n.text("ROUTINES" /* 训练计划 */)).font(.system(size:34,weight:.bold)) }
                    Spacer()
                    if store.userName != nil {
                        Button { coach = true } label: {
                            Text(L10n.text("AI_LABEL" /* 术语：AI */)).font(.system(size:16,weight:.bold)).foregroundStyle(GymTheme.green)
                                .frame(width:44,height:44).background(GymTheme.green.opacity(0.12),in:Circle())
                        }.accessibilityLabel(L10n.text("AI_COACH" /* AI 教练 */)).accessibilityIdentifier("open-coach")
                    }
                    Button { create = true } label: { Image(systemName:"plus").font(.system(size:20)).foregroundStyle(GymTheme.green).padding(12).background(GymTheme.green.opacity(0.12),in:Circle()) }.accessibilityLabel(L10n.text("NEW_ROUTINE" /* 新建训练计划 */))
                }
                if store.userName == nil {
                    EmptyCard(icon:"link",title:L10n.text("CONNECT_ACCOUNT" /* 连接账号 */))
                    GreenButton(title:L10n.text("CONNECT_ACCOUNT" /* 连接账号 */),icon:"link") { store.showSettings = true }
                } else if store.routines.isEmpty {
                    EmptyCard(icon:"calendar",title:L10n.text("NO_ROUTINES_YET" /* 还没有训练计划。 */))
                    GreenButton(title:L10n.text("CREATE_ROUTINE" /* 创建计划 */),icon:"plus") { create = true }
                }
                if store.userName != nil {
                    Button { schedule = true } label: { HStack { Label(L10n.text("WORKOUT_SCHEDULE" /* 训练排期 */),systemImage:"calendar.badge.clock"); Spacer(); Text(L10n.text("WEEKLY_BY_DATE" /* 每周 / 单日 */)).font(.caption); Image(systemName:"chevron.right") }.foregroundStyle(GymTheme.green).gymCard() }.accessibilityIdentifier("open-schedule")
                }
                if store.userName != nil {
                    Button {rotation = true} label:{HStack {Label(L10n.text("ROTATION_SCHEDULE" /* 循环排期 */),systemImage:"repeat");Spacer();Text(L10n.text("ORDER_PROGRESS" /* 顺序 / 进度 */)).font(.caption);Image(systemName:"chevron.right")}.foregroundStyle(GymTheme.green).gymCard()}.accessibilityIdentifier("open-rotation")
                    if store.rotationSummary()["view"] as? [String:Any] != nil {RotationProgressCard()}
                }
                ForEach(store.routines) { routine in
                    VStack(alignment:.leading,spacing:16) {
                        Button { selected = routine } label: {
                            HStack {
                                Image(systemName:"dumbbell").font(.system(size:24)).foregroundStyle(GymTheme.green).frame(width:50,height:50).background(GymTheme.green.opacity(0.12),in:RoundedRectangle(cornerRadius:14))
                                VStack(alignment:.leading,spacing:6) { Text(routine.name).font(.system(size:20,weight:.bold)); Text(L10n.text("COUNT_EXERCISES_COUNT_SETS" /* {0} 个动作 · {1} 组 */, routine.exercises.count, routine.exercises.reduce(0) { $0 + Int(number($1["sets"])) })).font(.caption).foregroundStyle(GymTheme.muted) }
                                Spacer(); Image(systemName:"chevron.right").font(.caption).foregroundStyle(GymTheme.muted)
                            }
                        }.buttonStyle(.plain).accessibilityIdentifier("edit-routine-\(routine.id)")
                        if !routine.exercises.isEmpty {
                            RoutineExercisePreview(exercises:routine.exercises)
                        }
                        GreenButton(title:L10n.text("START_WORKOUT" /* 开始训练 */),icon:"play.fill") { store.start(routine) }
                            .disabled(store.draft != nil)
                            .accessibilityIdentifier("start-routine-\(routine.id)")
                    }.gymCard()
                }
                Button { tools = true } label: { Label(L10n.text("TEMPLATES_AND_ROUTINE_IMPORT_EXPORT" /* 模板与计划导入 / 导出 */),systemImage:"square.and.arrow.up").frame(maxWidth:.infinity,minHeight:44) }.accessibilityIdentifier("open-plan-tools")
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
        .accessibilityLabel(L10n.text("COUNT_EXERCISES" /* {0} 个动作 */, exercises.count))
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
                Section(L10n.text("ROUTINE_NAME" /* 计划名称 */)) { BufferedTextField(L10n.text("FOR_EXAMPLE_UPPER_BODY_A" /* 例如：上肢训练 A */),text:$name).textFieldStyle(.plain).stableInputLine().submitLabel(.done).onSubmit { GymKeyboard.dismiss() }.accessibilityIdentifier("routine-name") }
                Section(L10n.text("CHOOSE_EXERCISES_COUNT_SELECTED" /* 选择动作 · 已选 {0} 个 */, ids.count)) {
                    CommittedSearchField(L10n.text("SEARCH_EXERCISES" /* 搜索动作 */),text:$query).textFieldStyle(.plain).stableInputLine().submitLabel(.search).onSubmit { GymKeyboard.dismiss() }.accessibilityIdentifier("routine-exercise-search")
                    ForEach(results) { exercise in
                        Button {
                            if ids.contains(exercise.id) { ids.removeAll { $0 == exercise.id } } else { ids.append(exercise.id) }
                        } label: {
                            HStack {
                                ExerciseThumbnail(id:exercise.id,size:44)
                                Text(exercise.name).font(.system(size:14)).foregroundStyle(.white).lineLimit(1)
                                Spacer()
                                Text("3 × 10").font(.caption).foregroundStyle(.secondary).fixedSize()
                                    .accessibilityLabel(L10n.text("DEFAULTS_TO_THREE_SETS_OF_ONEZERO_REPS" /* 默认 3 组，每组 10 次 */))
                                Image(systemName:ids.contains(exercise.id) ? "checkmark.circle.fill" : "circle").foregroundStyle(ids.contains(exercise.id) ? GymTheme.green : .gray)
                            }
                        }
                    }
                }
            }.navigationTitle(L10n.text("NEW_ROUTINE" /* 新建训练计划 */)).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement:.topBarLeading) { Button(L10n.text("CANCEL" /* 取消 */)) { dismiss() } }
                    ToolbarItem(placement:.topBarTrailing) { Button(store.syncing ? L10n.text("SAVING" /* 正在保存 */) : L10n.text("SAVE" /* 保存 */)) { inputBuffer.commitAll(); let title = name.trimmingCharacters(in:.whitespacesAndNewlines); guard !title.isEmpty, !ids.isEmpty else { return }; Task { if await store.addRoutine(name:title,exerciseIDs:ids) { dismiss() } } }.disabled((name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && !inputBuffer.hasPending) || ids.isEmpty || store.syncing) }
                }
        }.tint(GymTheme.green).environment(\.inputCommitBuffer, inputBuffer)
    }
}
