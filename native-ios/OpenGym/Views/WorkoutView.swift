import SwiftUI
struct WorkoutView: View {
    @Environment(GymStore.self) private var store
    @FocusState private var editing: Bool
    @State private var confirmFinish = false
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:22) {
                if let draft = store.draft {
                    HStack(alignment:.top) {
                        VStack(alignment:.leading,spacing:7) { Text(draft.name).font(.system(size:30,weight:.bold)); Label("训练进行中",systemImage:"circle.fill").font(.system(size:12)).foregroundStyle(GymTheme.green) }
                        Spacer()
                        Text(draft.start,style:.timer).monospacedDigit().font(.system(size:23,weight:.medium,design:.rounded)).foregroundStyle(GymTheme.green)
                    }
                    HStack { Text("\(draft.completedSets) / \(draft.entries.flatMap(\.sets).count) 组已完成").font(.subheadline); Spacer(); Text(draft.unit).font(.caption).foregroundStyle(GymTheme.muted) }
                    ProgressView(value:Double(draft.completedSets),total:Double(max(1,draft.entries.flatMap(\.sets).count))).tint(GymTheme.green)
                    if let until = store.restUntil {
                        TimelineView(.periodic(from:.now,by:1)) { context in
                            let remaining = max(0,Int(until.timeIntervalSince(context.date)))
                            HStack { Image(systemName:"timer"); Text(remaining > 0 ? "组间休息" : "休息结束"); Spacer(); Text(String(format:"%02d:%02d",remaining / 60,remaining % 60)).monospacedDigit(); Button("跳过") { store.restUntil = nil } }.font(.subheadline).foregroundStyle(GymTheme.green).gymCard()
                        }
                    }
                    ForEach(Array(draft.entries.enumerated()),id:\.offset) { e, entry in
                        VStack(alignment:.leading,spacing:16) {
                            Button { if let exercise = store.exercise(entry.id) { store.selectedExercise = exercise } } label: {
                                HStack(spacing:12) { ExerciseThumbnail(id:entry.id,size:54); VStack(alignment:.leading,spacing:5) { Text(entry.name).font(.system(size:17,weight:.semibold)); Text("点击查看动作示范").font(.caption).foregroundStyle(GymTheme.muted) }; Spacer(); Image(systemName:"play.circle").foregroundStyle(GymTheme.green) }
                            }.buttonStyle(.plain)
                            HStack { Text("组").frame(width:28); Text("重量 · \(draft.unit)").frame(maxWidth:.infinity); Text("次数").frame(maxWidth:.infinity); Text("完成").frame(width:40) }.font(.caption).foregroundStyle(GymTheme.muted)
                            ForEach(Array(entry.sets.enumerated()),id:\.element.id) { s, set in
                                HStack(spacing:10) {
                                    Text("\(s + 1)").font(.system(size:14,weight:.semibold,design:.rounded)).frame(width:28).foregroundStyle(set.done ? GymTheme.green : GymTheme.muted)
                                    TextField("0",value:Binding(get:{ store.draft?.entries[e].sets[s].weight ?? 0 },set:{ value in store.updateSet(entry:e,set:s) { $0.weight = min(2000,max(0,value)) } }),format:.number.precision(.fractionLength(0...2)))
                                        .keyboardType(.decimalPad).multilineTextAlignment(.center).padding(11).background(Color(white:0.16),in:RoundedRectangle(cornerRadius:10)).focused($editing).accessibilityLabel("第 \(s + 1) 组重量").accessibilityIdentifier("weight-\(e)-\(s)")
                                    TextField("10",value:Binding(get:{ store.draft?.entries[e].sets[s].reps ?? 0 },set:{ value in store.updateSet(entry:e,set:s) { $0.reps = min(1000,max(0,value)) } }),format:.number)
                                        .keyboardType(.numberPad).multilineTextAlignment(.center).padding(11).background(Color(white:0.16),in:RoundedRectangle(cornerRadius:10)).focused($editing).accessibilityLabel("第 \(s + 1) 组次数").accessibilityIdentifier("reps-\(e)-\(s)")
                                    Button {
                                        editing = false
                                        store.updateSet(entry:e,set:s) { row in
                                            guard row.reps > 0 else { return }
                                            row.done.toggle(); row.completedAt = row.done ? Date().timeIntervalSince1970 * 1000 : nil
                                            if row.done { store.restUntil = Date().addingTimeInterval(max(0,entry.restSec ?? number(store.state["restSec"] ?? 90))) }
                                        }
                                    } label: { Image(systemName:"checkmark").font(.system(size:16,weight:.bold)).frame(width:40,height:40).foregroundStyle(set.done ? .black : GymTheme.muted).background(set.done ? GymTheme.green : Color(white:0.16),in:RoundedRectangle(cornerRadius:10)) }
                                        .accessibilityLabel("\(entry.name)第\(s+1)组\(set.done ? "已完成" : "完成")").accessibilityIdentifier("complete-\(e)-\(s)")
                                }
                            }
                            Button {
                                guard var current = store.draft else { return }
                                var set = current.entries[e].sets.last ?? TrainingSet(); set.id = UUID().uuidString; set.done = false; set.completedAt = nil
                                current.entries[e].sets.append(set); store.draft = current
                            } label: { Label("添加一组",systemImage:"plus").font(.system(size:13)).frame(maxWidth:.infinity).padding(.top,4) }
                        }.gymCard()
                    }
                    GreenButton(title:store.syncing ? "正在同步…" : "完成训练",icon:"checkmark") { editing = false; confirmFinish = true }.disabled(store.syncing || draft.completedSets == 0).accessibilityIdentifier("finish-workout")
                    Text("训练草稿自动保存在此设备，完成后保存到服务端。").font(.caption).foregroundStyle(GymTheme.muted).frame(maxWidth:.infinity)
                } else {
                    Text("开始训练").font(.system(size:34,weight:.bold))
                    EmptyCard(icon:"figure.strengthtraining.traditional",title:"准备好开始了吗？",detail:"选择一个计划，逐组记录重量和次数。")
                    if store.routines.isEmpty { GreenButton(title:"前往训练计划",icon:"calendar") { store.selectedTab = 1 } }
                    ForEach(store.routines) { routine in GreenButton(title:routine.name,icon:"play.fill") { store.start(routine) } }
                }
            }.padding(22)
        }.scrollDismissesKeyboard(.interactively).toolbar { ToolbarItemGroup(placement:.keyboard) { Spacer(); Button("完成输入") { editing = false } } }
            .confirmationDialog("完成并保存训练？",isPresented:$confirmFinish,titleVisibility:.visible) {
                Button("保存到服务端") { Task { await store.finish() } }
                Button("继续训练",role:.cancel) {}
            } message: { Text("只计入已完成的组，未完成的动作不会记入训练成果。") }
    }
}
