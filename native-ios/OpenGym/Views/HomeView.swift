import SwiftUI
import Charts
struct HomeView: View {
    @Environment(GymStore.self) private var store
    @State private var weekOffset = 0
    @State private var selectedDay = Calendar.current.startOfDay(for:Date())
    private var days: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for:Date())
        let offset = (calendar.component(.weekday,from:today) + 5) % 7
        let monday = calendar.date(byAdding:.day,value:-offset + 7 * weekOffset,to:today)!
        return (0..<7).map { calendar.date(byAdding:.day,value:$0,to:monday)! }
    }
    var body: some View {
        let calendarDays = days
        let markers = store.trainingDayMarkers(on: calendarDays)
        let scheduled = store.scheduledRoutines(on: selectedDay)
        ScrollView {
            VStack(alignment:.leading,spacing:24) {
                HStack(alignment:.center) {
                    VStack(alignment:.leading,spacing:7) {
                        Text("开始训练").font(.system(size:35,weight:.bold))
                        Text(Date().formatted(.dateTime.month().day().weekday(.wide).locale(Locale(identifier:"zh_Hans_CN")))).font(.system(size:13)).foregroundStyle(GymTheme.muted)
                    }
                    Spacer()
                    Button { store.showSettings = true } label: { Image(systemName:"gearshape").font(.system(size:22)).foregroundStyle(.white).padding(12).background(GymTheme.card,in:Circle()) }.accessibilityLabel("设置")
                }
                VStack(spacing:18) {
                    HStack {
                        Button { weekOffset -= 1 } label: { Image(systemName:"chevron.left").padding(6) }.accessibilityLabel("上一周")
                        Spacer(); Text(weekOffset == 0 ? "本周" : calendarDays[0].formatted(.dateTime.month().day())).font(.system(size:13,weight:.medium)); Spacer()
                        Button { weekOffset += 1 } label: { Image(systemName:"chevron.right").padding(6) }.accessibilityLabel("下一周")
                    }.foregroundStyle(GymTheme.muted)
                    HStack(spacing:7) {
                        ForEach(Array(calendarDays.enumerated()),id:\.offset) { i, day in
                            Button { selectedDay = day } label: {
                                VStack(spacing:11) {
                                    Text(["一","二","三","四","五","六","日"][i]).font(.system(size:11))
                                    Text(day.formatted(.dateTime.day())).font(.system(size:18,weight:.semibold))
                                    Circle().fill(markers[i] == .completed ? GymTheme.green : markers[i] == .planned ? GymTheme.muted : .clear)
                                        .frame(width:4,height:4).accessibilityHidden(true)
                                }.foregroundStyle(day == selectedDay ? .black : GymTheme.muted).frame(maxWidth:.infinity).padding(.vertical,12)
                                    .background(day == selectedDay ? GymTheme.green : GymTheme.card,in:Capsule())
                            }.buttonStyle(.plain)
                                .accessibilityValue(markers[i] == .completed ? "有训练记录" : markers[i] == .planned ? "已安排训练" : "无训练安排")
                        }
                    }
                }
                VStack(alignment:.leading,spacing:18) {
                    HStack { Text(Calendar.current.isDateInToday(selectedDay) ? "今天" : selectedDay.formatted(.dateTime.month().day())).font(.system(size:12)).foregroundStyle(GymTheme.muted); Spacer(); Image(systemName:"figure.strengthtraining.traditional").foregroundStyle(GymTheme.green) }
                    Text(store.draft?.name ?? (scheduled.isEmpty ? "休息日" : scheduled.map(\.name).joined(separator:" + ")))
                        .font(.system(size:29,weight:.bold)).lineLimit(1).minimumScaleFactor(0.7)
                        .frame(height:36, alignment:.leading)
                    Text("\(scheduled.flatMap(\.exercises).count) 个动作")
                        .font(.system(size:13)).foregroundStyle(GymTheme.muted).lineLimit(1, reservesSpace:true)
                        .opacity(store.draft == nil && !scheduled.isEmpty ? 1 : 0)
                        .accessibilityHidden(store.draft != nil || scheduled.isEmpty)
                    if store.draft != nil {
                        GreenButton(title:"继续训练",icon:"play.fill") {
                            store.selectedTab = 2
                        }.frame(height:56).accessibilityIdentifier("home-start-workout")
                    } else if scheduled.isEmpty {
                        GreenButton(title:"自由训练",icon:"figure.strengthtraining.traditional") {
                            store.startFreestyle()
                        }.frame(height:56).accessibilityIdentifier("start-freestyle-workout")
                        Button {
                            store.selectedTab = 2
                        } label: {
                            Text("选择训练计划")
                                .font(.subheadline)
                                .foregroundStyle(GymTheme.green)
                                .frame(maxWidth:.infinity,minHeight:44)
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityIdentifier("home-select-plan")
                    } else {
                        GreenButton(title:"开始训练",icon:"play.fill") {
                            store.start(scheduled)
                        }.frame(height:56).accessibilityIdentifier("home-start-workout")
                        secondaryTrainingButton("自由训练",icon:"figure.strengthtraining.traditional",identifier:"start-freestyle-workout") {
                            store.startFreestyle()
                        }
                    }
                }.gymCard()
                if store.rotationSummary()["view"] as? [String:Any] != nil {RotationProgressCard()}
            }.padding(22)
        }.refreshable { await store.refresh() }
    }
    private func secondaryTrainingButton(_ title:String,icon:String,identifier:String,action:@escaping () -> Void) -> some View {
        Button(action:action) {
            Label(title,systemImage:icon)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth:.infinity,minHeight:44)
                .foregroundStyle(GymTheme.green)
                .background(GymTheme.green.opacity(0.1),in:RoundedRectangle(cornerRadius:15))
        }.buttonStyle(.plain).accessibilityIdentifier(identifier)
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
                Section { Button(store.syncing ? "正在保存" : "保存到服务端") {
                    if let number = Double(value.replacingOccurrences(of:",",with:".")), number > 0 { Task { if await store.recordWeight(number) { dismiss() } } }
                }.disabled(store.syncing || (Double(value.replacingOccurrences(of:",",with:".")) ?? 0) <= 0) }
            }.navigationTitle("记录体重").toolbar { ToolbarItem(placement:.topBarTrailing) { Button("取消") { dismiss() } } }
        }.presentationDetents([.medium]).tint(GymTheme.green)
    }
}
