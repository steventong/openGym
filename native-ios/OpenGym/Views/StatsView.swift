import SwiftUI
struct StatsView: View {
    @Environment(GymStore.self) private var store
    @State private var editing: WorkoutRecord?
    @State private var historyLimit = 30
    @State private var analytics = false
    @State private var weightSheet = false
    @State private var search = ""
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
                VStack(alignment:.leading,spacing:18) {
                    HStack {
                        Text("体重趋势").font(.headline)
                        Spacer()
                        Button("添加记录") { weightSheet = true }
                            .font(.caption).foregroundStyle(GymTheme.green)
                            .frame(minHeight:44)
                            .accessibilityIdentifier("stats-add-weight")
                    }
                    if store.bodyweights.isEmpty {
                        Text("暂无体重记录").font(.subheadline).foregroundStyle(GymTheme.muted)
                    } else {
                        WeightChart(points:store.bodyweights).frame(height:140)
                    }
                }.gymCard()
                Button { analytics = true } label: { Label("动作进步、肌群与身体指标",systemImage:"chart.xyaxis.line").frame(maxWidth:.infinity,minHeight:44) }.gymCard().accessibilityIdentifier("open-personal-analytics")
                SectionTitle(text:"训练记录")
                TextField("搜索训练名称、日期、动作",text:$search).textFieldStyle(.roundedBorder)

                if store.workouts.isEmpty { EmptyCard(icon:"chart.line.uptrend.xyaxis",title:"进步，从第一组开始",detail:"完成一场训练后，这里会展示你的真实记录。") }
                LazyVStack(spacing:10) {
                    ForEach(store.workouts.filter { search.isEmpty || historyMatches($0) }.prefix(historyLimit).map(WorkoutRecord.init),id:\.id) { record in
                        Button { editing = record } label: {
                            WorkoutHistoryRow(record:record,localEdit:store.historyEdits[record.id])
                        }.buttonStyle(.plain).accessibilityIdentifier("edit-history-\(record.id)")
                    }
                }
                if store.workouts.count > historyLimit { Button("更多训练记录") { historyLimit += 30 }.frame(maxWidth:.infinity) }
            }.padding(22)
        }.refreshable { await store.refresh() }.sheet(isPresented:$analytics) { PersonalStatsHub() }.sheet(isPresented:$weightSheet) { WeightEntryView() }.sheet(item:$editing) { record in HistoryEditor(record:record,unit:store.unit) }
    }
    private func historyMatches(_ w:[String:Any])->Bool {
        let text = [w["name"] as? String ?? "",w["d"] as? String ?? "",w["note"] as? String ?? ""] + (w["entries"] as? [[String:Any]] ?? []).map {store.exercise($0["id"] as? String ?? "")?.searchText ?? $0["n"] as? String ?? ""}
        return text.joined(separator:" ").localizedCaseInsensitiveContains(search)
    }
    private func metric(_ value:String,_ label:String,_ icon:String) -> some View {
        VStack(alignment:.leading,spacing:16) {
            Image(systemName:icon).font(.system(size:20)).foregroundStyle(GymTheme.green)
            Text(value).font(.system(size:34,weight:.bold,design:.rounded))
            Text(label).font(.caption).foregroundStyle(GymTheme.muted)
        }.frame(maxWidth:.infinity,alignment:.leading).gymCard()
    }
}

private struct WorkoutHistoryRow: View {
    let record: WorkoutRecord
    let localEdit: [String:Any]?
    private var subtitle: String {
        let day = record.raw["d"] as? String ?? ""
        let date = dateFromDay(day).map { $0.formatted(.dateTime.month().day().weekday(.abbreviated).locale(Locale(identifier:"zh_Hans_CN"))) } ?? day
        let minutes = max(0,Int((number(record.raw["end"]) - number(record.raw["start"])) / 60000))
        let duration = minutes >= 60 ? "\(minutes / 60) 小时" + (minutes % 60 > 0 ? " \(minutes % 60) 分钟" : "") : "\(minutes) 分钟"
        return [date,duration,"\(record.completedSetCount) 组"].joined(separator:" · ")
    }
    var body: some View {
        HStack(spacing:12) {
            Image(systemName:record.raw["routineId"] as? String == nil ? "figure.strengthtraining.traditional" : "dumbbell.fill")
                .font(.system(size:19,weight:.medium)).foregroundStyle(.black)
                .frame(width:40,height:40).background(GymTheme.green,in:RoundedRectangle(cornerRadius:10))
                .accessibilityHidden(true)
            VStack(alignment:.leading,spacing:5) {
                HStack(spacing:8) {
                    Text(record.raw["name"] as? String ?? "训练").font(.subheadline.weight(.semibold)).foregroundStyle(.white).lineLimit(1)
                    Spacer(minLength:0)
                    let prs = (record.raw["prs"] as? [Any])?.count ?? 0
                    if prs > 0 {
                        Label("\(prs) PR",systemImage:"trophy.fill").font(.caption2.weight(.semibold))
                            .foregroundStyle(.yellow).padding(.horizontal,7).padding(.vertical,4)
                            .background(Color.yellow.opacity(0.15),in:RoundedRectangle(cornerRadius:6))
                            .fixedSize().accessibilityLabel("\(prs) 项个人纪录")
                    }
                }
                Text(subtitle).font(.caption).foregroundStyle(GymTheme.muted).fixedSize(horizontal:false,vertical:true)
                if let localEdit {
                    Label(localEdit["submitted"] as? Bool == true ? "待同步" : "本机编辑草稿",systemImage:"internaldrive")
                        .font(.caption2).foregroundStyle(.orange)
                }
            }.frame(maxWidth:.infinity,alignment:.leading)
            Image(systemName:"chevron.right").font(.caption.weight(.semibold)).foregroundStyle(GymTheme.muted).accessibilityHidden(true)
        }.padding(14).background(GymTheme.card,in:RoundedRectangle(cornerRadius:16))
            .contentShape(RoundedRectangle(cornerRadius:16))
    }
}
