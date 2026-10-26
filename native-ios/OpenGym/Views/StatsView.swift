import SwiftUI
struct StatsView: View {
    @Environment(GymStore.self) private var store
    @State private var editing: WorkoutRecord?
    @State private var historyLimit = 30
    private var completedSets: [[String:Any]] {
        store.workouts.flatMap { $0["entries"] as? [[String:Any]] ?? [] }.flatMap { $0["sets"] as? [[String:Any]] ?? [] }.flatMap { row -> [[String:Any]] in if let sides = row["sides"] as? [String:[String:Any]] {return [sides["L"],sides["R"]].compactMap{$0}};return [row] }.filter { $0["done"] as? Bool == true }
    }
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:24) {
                VStack(alignment:.leading,spacing:7) { Text("训练统计").font(.system(size:34,weight:.bold)); Text("每一次训练，都在积累").font(.subheadline).foregroundStyle(GymTheme.muted) }
                HStack(spacing:12) {
                    metric("\(store.workouts.count)","累计训练","figure.strengthtraining.traditional")
                    metric("\(completedSets.count)","完成组数","checkmark.circle")
                }
                VStack(alignment:.leading,spacing:16) {
                    HStack { Text("训练足迹").font(.headline); Spacer(); Text("最近 12 周").font(.caption).foregroundStyle(GymTheme.muted) }
                    let trained = Set(store.workouts.compactMap { $0["d"] as? String })
                    let cells = (0..<84).map { Calendar.current.date(byAdding:.day,value:$0-83,to:Date())! }
                    HStack(spacing:5) {
                        ForEach(0..<12,id:\.self) { week in
                            VStack(spacing:5) { ForEach(0..<7,id:\.self) { day in RoundedRectangle(cornerRadius:3).fill(trained.contains(dayString(cells[week*7+day])) ? GymTheme.green : Color(white:0.20)).aspectRatio(1,contentMode:.fit) } }
                        }
                    }.accessibilityLabel("最近十二周的训练活动图")
                }.gymCard()
                if !store.bodyweights.isEmpty {
                    VStack(alignment:.leading,spacing:18) { SectionTitle(text:"体重趋势"); WeightChart(points:store.bodyweights).frame(height:140) }.gymCard()
                }
                SectionTitle(text:"训练记录")
                if store.workouts.isEmpty { EmptyCard(icon:"chart.line.uptrend.xyaxis",title:"进步，从第一组开始",detail:"完成一场训练后，这里会展示你的真实记录。") }
                ForEach(Array(store.workouts.prefix(historyLimit).enumerated()),id:\.offset) { _, workout in
                    VStack(alignment:.leading,spacing:13) {
                        HStack { Text(workout["name"] as? String ?? "训练").font(.headline); Spacer(); Button { editing = WorkoutRecord(raw:workout) } label: { Label("编辑",systemImage:"pencil").font(.caption) }.accessibilityIdentifier("edit-history-\(WorkoutRecord.key(workout))") }
                        if let local = store.historyEdits[WorkoutRecord.key(workout)] {
                            HStack {
                                Label(local["submitted"] as? Bool == true ? "已存本机 · 待同步" : "本机编辑草稿",systemImage:"internaldrive").font(.caption).foregroundStyle(.orange)
                                Spacer()
                                if local["submitted"] as? Bool == true { Button("重新提交") { Task { if !(await store.submitHistoryEdit(WorkoutRecord.key(workout))) { store.error = store.editError ?? store.localSaveError } } }.font(.caption).disabled(store.syncing) }
                            }
                        }
                        HStack { Text(workout["d"] as? String ?? ""); Spacer(); Text("\(max(0,Int((number(workout["end"]) - number(workout["start"])) / 60000))) 分钟") }.font(.caption).foregroundStyle(GymTheme.muted)
                        ForEach(Array((workout["entries"] as? [[String:Any]] ?? []).enumerated()),id:\.offset) { index, entry in
                            let sets = (entry["sets"] as? [[String:Any]] ?? []).filter(rawCompleted)
                            HStack { Text(store.exercise(entry["id"] as? String ?? "")?.recordLabel(at: index) ?? "\(index + 1).自定义动作").fixedSize(horizontal: false, vertical: true); Spacer(); Text("\(sets.count) 组").foregroundStyle(GymTheme.green) }.font(.system(size:13))
                        }
                    }.gymCard()
                }
                if store.workouts.count > historyLimit { Button("更多训练记录") { historyLimit += 30 }.frame(maxWidth:.infinity) }
            }.padding(22)
        }.refreshable { await store.refresh() }.sheet(item:$editing) { record in HistoryEditor(record:record,unit:store.unit) }
    }
    private func metric(_ value:String,_ label:String,_ icon:String) -> some View {
        VStack(alignment:.leading,spacing:16) {
            Image(systemName:icon).font(.system(size:20)).foregroundStyle(GymTheme.green)
            Text(value).font(.system(size:34,weight:.bold,design:.rounded))
            Text(label).font(.caption).foregroundStyle(GymTheme.muted)
        }.frame(maxWidth:.infinity,alignment:.leading).gymCard()
    }
}
