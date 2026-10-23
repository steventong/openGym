import SwiftUI
import Charts
struct HomeView: View {
    @Environment(GymStore.self) private var store
    @State private var weightSheet = false
    @State private var weekOffset = 0
    @State private var selectedDay = Calendar.current.startOfDay(for:Date())
    private var days: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for:Date())
        let offset = (calendar.component(.weekday,from:today) + 5) % 7
        let monday = calendar.date(byAdding:.day,value:-offset + 7 * weekOffset,to:today)!
        return (0..<7).map { calendar.date(byAdding:.day,value:$0,to:monday)! }
    }
    private var scheduled: [Routine] { store.scheduledRoutines(on:selectedDay) }
    private var routine: Routine? { scheduled.first }
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:24) {
                HStack(alignment:.center) {
                    VStack(alignment:.leading,spacing:7) {
                        Text("openGym").font(.system(size:35,weight:.bold))
                        Text(Date().formatted(.dateTime.month().day().weekday(.wide).locale(Locale(identifier:"zh_Hans_CN")))).font(.system(size:13)).foregroundStyle(GymTheme.muted)
                    }
                    Spacer()
                    Button { store.showSettings = true } label: { Image(systemName:"gearshape").font(.system(size:22)).foregroundStyle(.white).padding(12).background(GymTheme.card,in:Circle()) }.accessibilityLabel("设置")
                }
                Button { store.showSettings = true } label: {
                    HStack(spacing:7) {
                        Circle().fill(store.online ? GymTheme.green : .orange).frame(width:6,height:6)
                        Text(store.userName.map { "\($0) · \(store.status)" } ?? store.status).font(.system(size:12))
                        Spacer(); Image(systemName:"chevron.right").font(.system(size:9))
                    }.foregroundStyle(GymTheme.muted)
                }
                VStack(spacing:18) {
                    HStack {
                        Button { weekOffset -= 1 } label: { Image(systemName:"chevron.left").padding(6) }.accessibilityLabel("上一周")
                        Spacer(); Text(weekOffset == 0 ? "本周" : days[0].formatted(.dateTime.month().day())).font(.system(size:13,weight:.medium)); Spacer()
                        Button { weekOffset += 1 } label: { Image(systemName:"chevron.right").padding(6) }.accessibilityLabel("下一周")
                    }.foregroundStyle(GymTheme.muted)
                    HStack(spacing:7) {
                        ForEach(Array(days.enumerated()),id:\.offset) { i, day in
                            Button { selectedDay = day } label: {
                                VStack(spacing:11) {
                                    Text(["一","二","三","四","五","六","日"][i]).font(.system(size:11))
                                    Text(day.formatted(.dateTime.day())).font(.system(size:18,weight:.semibold))
                                    Circle().fill(store.workouts.contains { $0["d"] as? String == dayString(day) } ? GymTheme.green : .clear).frame(width:4,height:4)
                                }.foregroundStyle(day == selectedDay ? .black : GymTheme.muted).frame(maxWidth:.infinity).padding(.vertical,12)
                                    .background(day == selectedDay ? GymTheme.green : GymTheme.card,in:Capsule())
                            }.buttonStyle(.plain)
                        }
                    }
                }
                VStack(alignment:.leading,spacing:18) {
                    HStack { Text(Calendar.current.isDateInToday(selectedDay) ? "今天" : selectedDay.formatted(.dateTime.month().day())).font(.system(size:12)).foregroundStyle(GymTheme.muted); Spacer(); Image(systemName:"figure.strengthtraining.traditional").foregroundStyle(GymTheme.green) }
                    Text(store.draft?.name ?? (scheduled.isEmpty ? "休息日" : scheduled.map(\.name).joined(separator:" + "))).font(.system(size:29,weight:.bold))
                    Text(store.draft != nil ? "你的训练仍在进行，随时继续。" : routine.map { _ in "\(scheduled.flatMap(\.exercises).count) 个动作 · 按自己的节奏训练" } ?? "给身体一点恢复时间，也可以选择其他训练。").font(.system(size:13)).foregroundStyle(GymTheme.muted)
                    GreenButton(title:store.draft != nil ? "继续训练" : routine != nil ? "开始训练" : "选择训练",icon:"play.fill") {
                        if store.draft != nil { store.selectedTab = 2 } else if routine != nil { store.start(scheduled) } else { store.selectedTab = 1 }
                    }
                }.gymCard()
                if store.rotationSummary()["view"] as? [String:Any] != nil {RotationProgressCard()}
                HStack { SectionTitle(text:"体重"); Button("记录") { weightSheet = true }.font(.system(size:13,weight:.medium)) }
                VStack(alignment:.leading,spacing:15) {
                    if let last = store.bodyweights.last {
                        HStack(alignment:.firstTextBaseline,spacing:5) { Text(decimal(number(last["w"]))).font(.system(size:35,weight:.bold,design:.rounded)); Text(store.unit).font(.subheadline).foregroundStyle(GymTheme.muted); Spacer(); Text(last["d"] as? String ?? "").font(.caption).foregroundStyle(GymTheme.muted) }
                        WeightChart(points:store.bodyweights).frame(height:110)
                    } else {
                        Image(systemName:"scalemass").font(.title2).foregroundStyle(GymTheme.green)
                        Text("还没有称重记录").font(.headline)
                        Text("记一下体重，曲线就开始了。").font(.subheadline).foregroundStyle(GymTheme.muted)
                    }
                }.frame(maxWidth:.infinity,alignment:.leading).gymCard()
                HStack {
                    stat("\(store.workouts.count)","累计训练")
                    Divider().frame(height:35)
                    stat("\(store.routines.count)","我的计划")
                    Divider().frame(height:35)
                    stat("\(store.exercises.count)","动作库")
                }.gymCard()
            }.padding(22)
        }.refreshable { await store.refresh() }.sheet(isPresented:$weightSheet) { WeightEntryView() }
    }
    private func stat(_ value:String,_ label:String) -> some View {
        VStack(spacing:6) { Text(value).font(.system(size:22,weight:.semibold,design:.rounded)); Text(label).font(.system(size:11)).foregroundStyle(GymTheme.muted) }.frame(maxWidth:.infinity)
    }
}
struct WeightChart: View {
    let points: [[String:Any]]
    var body: some View {
        Chart {
            ForEach(Array(points.suffix(30).enumerated()),id:\.offset) { i, p in
                LineMark(x:.value("日期",i),y:.value("体重",number(p["w"]))).foregroundStyle(GymTheme.green).interpolationMethod(.catmullRom)
                PointMark(x:.value("日期",i),y:.value("体重",number(p["w"]))).foregroundStyle(GymTheme.green).symbolSize(20)
            }
        }.chartYScale(domain:.automatic(includesZero:false)).chartXAxis(.hidden)
    }
}
struct WeightEntryView: View {
    @Environment(GymStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var value = ""
    var body: some View {
        NavigationStack {
            Form {
                Section("今天的体重（\(store.unit)）") { TextField("输入体重",text:$value).keyboardType(.decimalPad) }
                Section { Button(store.syncing ? "正在保存…" : "保存到服务端") {
                    if let number = Double(value.replacingOccurrences(of:",",with:".")), number > 0 { Task { if await store.recordWeight(number) { dismiss() } } }
                }.disabled(store.syncing || (Double(value.replacingOccurrences(of:",",with:".")) ?? 0) <= 0) }
            }.navigationTitle("记录体重").toolbar { ToolbarItem(placement:.topBarTrailing) { Button("取消") { dismiss() } } }
        }.presentationDetents([.medium]).tint(GymTheme.green)
    }
}
