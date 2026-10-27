import SwiftUI
struct PlanView: View {
    @Environment(GymStore.self) private var store
    @State private var create = false
    @State private var coach = false
    @State private var schedule = false
    @State private var rotation = false
    @State private var selected: Routine?
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:22) {
                HStack {
                    VStack(alignment:.leading,spacing:7) { Text("训练计划").font(.system(size:34,weight:.bold)); Text("安排训练，保持自己的节奏").font(.subheadline).foregroundStyle(GymTheme.muted) }
                    Spacer()
                    if store.userName != nil {
                        Button { coach = true } label: {
                            Text("AI").font(.system(size:16,weight:.bold)).foregroundStyle(GymTheme.green)
                                .frame(width:44,height:44).background(GymTheme.green.opacity(0.12),in:Circle())
                        }.accessibilityLabel("AI 教练").accessibilityIdentifier("open-coach")
                    }
                    Button { create = true } label: { Image(systemName:"plus").font(.system(size:20)).foregroundStyle(GymTheme.green).padding(12).background(GymTheme.green.opacity(0.12),in:Circle()) }.accessibilityLabel("新建计划")
                }
                if store.userName == nil {
                    EmptyCard(icon:"link",title:"连接你的训练档案",detail:"配对网页账号后，原有计划和训练记录会出现在这里。")
                    GreenButton(title:"连接账号",icon:"link") { store.showSettings = true }
                } else if store.routines.isEmpty {
                    EmptyCard(icon:"calendar",title:"第一份训练计划",detail:"从喜欢的动作开始，逐步建立自己的训练习惯。")
                    GreenButton(title:"创建计划",icon:"plus") { create = true }
                }
                if store.userName != nil {
                    Button { schedule = true } label: { HStack { Label("训练排期",systemImage:"calendar.badge.clock"); Spacer(); Text("每周 / 单日").font(.caption); Image(systemName:"chevron.right") }.foregroundStyle(GymTheme.green).gymCard() }.accessibilityIdentifier("open-schedule")
                }
                if store.userName != nil {
                    Button {rotation = true} label:{HStack {Label("循环排期",systemImage:"repeat");Spacer();Text("顺序 / 进度").font(.caption);Image(systemName:"chevron.right")}.foregroundStyle(GymTheme.green).gymCard()}.accessibilityIdentifier("open-rotation")
                    if store.rotationSummary()["view"] as? [String:Any] != nil {RotationProgressCard()}
                }
                ForEach(store.routines) { routine in
                    VStack(alignment:.leading,spacing:16) {
                        Button { selected = routine } label: {
                            HStack {
                                Image(systemName:"dumbbell").font(.system(size:24)).foregroundStyle(GymTheme.green).frame(width:50,height:50).background(GymTheme.green.opacity(0.12),in:RoundedRectangle(cornerRadius:14))
                                VStack(alignment:.leading,spacing:6) { Text(routine.name).font(.system(size:20,weight:.bold)); Text("\(routine.exercises.count) 个动作 · \(routine.exercises.reduce(0) { $0 + Int(number($1["sets"])) }) 组").font(.caption).foregroundStyle(GymTheme.muted) }
                                Spacer(); Image(systemName:"chevron.right").font(.caption).foregroundStyle(GymTheme.muted)
                            }
                        }.buttonStyle(.plain).accessibilityIdentifier("edit-routine-\(routine.id)")
                        HStack(spacing:8) {
                            ForEach(Array(routine.exercises.prefix(4).enumerated()),id:\.offset) { _, cfg in ExerciseThumbnail(id:cfg["id"] as? String ?? "",size:52) }
                            Spacer()
                        }
                        GreenButton(title:"开始训练",icon:"play.fill") { store.start(routine) }
                    }.gymCard()
                }
            }.padding(22)
        }.refreshable { await store.refresh() }.sheet(isPresented:$create) { RoutineComposer() }
            .sheet(isPresented:$coach) { CoachView() }
            .sheet(isPresented:$schedule) { ScheduleEditor() }
            .sheet(isPresented:$rotation) {RotationEditor()}
            .sheet(item:$selected) { routine in RoutineEditor(routine:routine,unit:store.unit) }
    }
}
struct RoutineComposer: View {
    @Environment(GymStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var query = ""
    @State private var ids: [String] = []
    private var results: [Exercise] { Array(store.exercises.filter { query.isEmpty ? ["0025","0043","0150","0027","0047","0031"].contains($0.id) : $0.searchText.localizedCaseInsensitiveContains(query) }.prefix(50)) }
    var body: some View {
        NavigationStack {
            List {
                Section("计划名称") { TextField("例如：上肢训练 A",text:$name).accessibilityIdentifier("routine-name") }
                Section("选择动作 · 已选 \(ids.count) 个") {
                    TextField("搜索动作",text:$query).accessibilityIdentifier("routine-exercise-search")
                    ForEach(results) { exercise in
                        Button {
                            if ids.contains(exercise.id) { ids.removeAll { $0 == exercise.id } } else { ids.append(exercise.id) }
                        } label: {
                            HStack { ExerciseThumbnail(id:exercise.id,size:44); Text(exercise.name).font(.system(size:14)).foregroundStyle(.white); Spacer(); Image(systemName:ids.contains(exercise.id) ? "checkmark.circle.fill" : "circle").foregroundStyle(ids.contains(exercise.id) ? GymTheme.green : .gray) }
                        }
                    }
                }
                Section { Text("默认每个动作 3 组 × 10 次。训练中可修改重量与次数，完成后同步到网页。").font(.footnote).foregroundStyle(.secondary) }
            }.navigationTitle("新建计划").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement:.topBarLeading) { Button("取消") { dismiss() } }
                    ToolbarItem(placement:.topBarTrailing) { Button(store.syncing ? "保存中…" : "保存") { Task { if await store.addRoutine(name:name.trimmingCharacters(in:.whitespacesAndNewlines),exerciseIDs:ids) { dismiss() } } }.disabled(name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || ids.isEmpty || store.syncing) }
                }
        }.tint(GymTheme.green)
    }
}
