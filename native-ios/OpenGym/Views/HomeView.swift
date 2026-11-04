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
                        Text(L10n.text("START_WORKOUT" /* 开始训练 */)).font(.system(size:35,weight:.bold))
                        Text(Date().formatted(.dateTime.month().day().weekday(.wide).locale(L10n.locale))).font(.system(size:13)).foregroundStyle(GymTheme.muted)
                    }
                    Spacer()
                    Button { store.showSettings = true } label: { Image(systemName:"gearshape").font(.system(size:22)).foregroundStyle(.white).padding(12).background(GymTheme.card,in:Circle()) }.accessibilityLabel(L10n.text("SETTINGS" /* 设置 */))
                }
                VStack(spacing:18) {
                    HStack {
                        Button { weekOffset -= 1 } label: { Image(systemName:"chevron.left").padding(6) }.accessibilityLabel(L10n.text("PREVIOUS_WEEK" /* 上一周 */))
                        Spacer(); Text(weekOffset == 0 ? L10n.text("THIS_WEEK" /* 本周 */) : calendarDays[0].formatted(.dateTime.month().day())).font(.system(size:13,weight:.medium)); Spacer()
                        Button { weekOffset += 1 } label: { Image(systemName:"chevron.right").padding(6) }.accessibilityLabel(L10n.text("NEXT_WEEK" /* 下一周 */))
                    }.foregroundStyle(GymTheme.muted)
                    HStack(spacing:7) {
                        ForEach(Array(calendarDays.enumerated()),id:\.offset) { i, day in
                            Button { selectedDay = day } label: {
                                VStack(spacing:11) {
                                    Text([L10n.text("MO" /* 一 */),L10n.text("TU" /* 二 */),L10n.text("WE" /* 三 */),L10n.text("TH" /* 四 */),L10n.text("FR" /* 五 */),L10n.text("SA" /* 六 */),L10n.text("SU" /* 日 */)][i]).font(.system(size:11))
                                    Text(day.formatted(.dateTime.day())).font(.system(size:18,weight:.semibold))
                                    Circle().fill(markers[i] == .completed ? GymTheme.green : markers[i] == .planned ? GymTheme.muted : .clear)
                                        .frame(width:4,height:4).accessibilityHidden(true)
                                }.foregroundStyle(day == selectedDay ? .black : GymTheme.muted).frame(maxWidth:.infinity).padding(.vertical,12)
                                    .background(day == selectedDay ? GymTheme.green : GymTheme.card,in:Capsule())
                            }.buttonStyle(.plain)
                                .accessibilityValue(markers[i] == .completed ? L10n.text("WORKOUT_LOGGED" /* 有训练记录 */) : markers[i] == .planned ? L10n.text("WORKOUT_SCHEDULED" /* 已安排训练 */) : L10n.text("NO_WORKOUT_SCHEDULED" /* 无训练安排 */))
                        }
                    }
                }
                VStack(alignment:.leading,spacing:18) {
                    HStack { Text(Calendar.current.isDateInToday(selectedDay) ? L10n.text("TODAY" /* 今天 */) : selectedDay.formatted(.dateTime.month().day())).font(.system(size:12)).foregroundStyle(GymTheme.muted); Spacer(); Image(systemName:"figure.strengthtraining.traditional").foregroundStyle(GymTheme.green) }
                        .lineLimit(1).frame(height:20)
                    HStack(alignment:.bottom,spacing:12) {
                        Text(store.draft?.name ?? (scheduled.isEmpty ? L10n.text("REST_DAY" /* 休息日 */) : scheduled.map(\.name).joined(separator:" + ")))
                            .font(.system(size:29,weight:.bold)).lineLimit(1)
                            .frame(maxWidth:.infinity, alignment:.leading)
                        if store.draft == nil && !scheduled.isEmpty {
                            Text(L10n.text("COUNT_EXERCISES" /* {0} 个动作 */, scheduled.flatMap(\.exercises).count))
                                .font(.system(size:13)).foregroundStyle(GymTheme.muted)
                                .lineLimit(1).fixedSize()
                        }
                    }.frame(height:36, alignment:.leading)
                    GlassEffectContainer {
                        VStack(spacing: 18) {
                            trainingButton(
                                store.draft != nil ? L10n.text("CONTINUE_WORKOUT" /* 继续训练 */) : scheduled.isEmpty ? L10n.text("FREESTYLE" /* 自由训练 */) : L10n.text("START_WORKOUT" /* 开始训练 */),
                                icon: store.draft == nil && scheduled.isEmpty ? "figure.strengthtraining.traditional" : "play.fill",
                                primary: true,
                                identifier: store.draft == nil && scheduled.isEmpty ? "start-freestyle-workout" : "home-start-workout",
                                startedAt: store.draft?.start
                            ) {
                                if store.draft != nil {
                                    store.selectedTab = 2
                                } else if scheduled.isEmpty {
                                    store.startFreestyle()
                                } else {
                                    store.start(scheduled)
                                }
                            }
                            trainingButton(
                                scheduled.isEmpty ? L10n.text("CHOOSE_A_ROUTINE" /* 选择训练计划 */) : L10n.text("FREESTYLE" /* 自由训练 */),
                                icon: scheduled.isEmpty ? "list.bullet" : "figure.strengthtraining.traditional",
                                primary: false,
                                identifier: scheduled.isEmpty ? "home-select-plan" : "start-freestyle-workout",
                                enabled: store.draft == nil
                            ) {
                                if scheduled.isEmpty {
                                    store.selectedTab = 2
                                } else {
                                    store.startFreestyle()
                                }
                            }
                        }
                    }
                }.gymCard()
                if store.rotationSummary()["view"] as? [String:Any] != nil {RotationProgressCard()}
            }.padding(22)
        }.refreshable { await store.refresh() }
    }
    private func trainingButton(_ title:String,icon:String,primary:Bool,identifier:String,startedAt:Date? = nil,enabled:Bool = true,action:@escaping () -> Void) -> some View {
        let button = Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon).frame(width: 22, height: 22).accessibilityHidden(true)
                Text(title)
                    .padding(.horizontal, startedAt == nil ? 0 : 32)
                    .frame(maxWidth: .infinity)
                Color.clear.frame(width: 22, height: 22).accessibilityHidden(true)
            }
            .font(.system(size: primary ? 17 : 15, weight: .semibold))
            .lineLimit(1).minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .trailing) {
                if let startedAt {
                    HomeWorkoutDurationLabel(start: startedAt)
                        .allowsHitTesting(false)
                }
            }
            .foregroundStyle(enabled ? (primary ? Color.black : GymTheme.green) : GymTheme.muted)
        }
        .disabled(!enabled)
        .controlSize(.large)
        .buttonBorderShape(.capsule)
        .accessibilityIdentifier(identifier)

        return Group {
            if primary {
                button.buttonStyle(.glassProminent)
            } else {
                button.buttonStyle(.glass)
            }
        }
    }

}
private struct HomeWorkoutDurationLabel: View {
    let start: Date

    var body: some View {
        // Reserve a stable trailing slot so ticking digits never move the title.
        Text(verbatim: "00:00:00").hidden()
            .overlay(alignment: .trailing) {
                TimelineView(.periodic(from: start, by: 1)) { context in
                    let elapsed = max(0, Int(context.date.timeIntervalSince(start)))
                    let duration = Duration.seconds(elapsed).formatted(.time(pattern: .hourMinuteSecond))
                    Text(duration)
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .accessibilityLabel(L10n.text("SESSION_LENGTH" /* 训练时长 */))
                        .accessibilityValue(duration)
                }
            }
            .font(.system(size: 12, weight: .medium).monospacedDigit())
            .fixedSize()
            .accessibilityIdentifier("home-workout-duration")
    }
}
struct WeightChart: View {
    let points: [[String:Any]]
    var body: some View {
        Chart {
            ForEach(Array(points.suffix(30).enumerated()),id:\.offset) { i, p in
                LineMark(x:.value(L10n.text("DATE" /* 日期 */),i),y:.value(L10n.text("BODY_WEIGHT" /* 体重 */),number(p["w"]))).foregroundStyle(GymTheme.green).interpolationMethod(.catmullRom)
                PointMark(x:.value(L10n.text("DATE" /* 日期 */),i),y:.value(L10n.text("BODY_WEIGHT" /* 体重 */),number(p["w"]))).foregroundStyle(GymTheme.green).symbolSize(20)
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
                Section(L10n.text("TODAY_S_WEIGHT_COUNT" /* 今天的体重（{0}） */, store.unit)) { TextField(L10n.text("ENTER_BODY_WEIGHT" /* 输入体重 */),text:$value).textFieldStyle(.plain).stableInputLine().submitLabel(.done).onSubmit { GymKeyboard.dismiss() }.keyboardType(.decimalPad) }
                Section { Button(store.syncing ? L10n.text("SAVING" /* 正在保存 */) : L10n.text("SAVE_TO_SERVER" /* 保存到服务端 */)) {
                    if let number = Double(value.replacingOccurrences(of:",",with:".")), number > 0 { Task { if await store.recordWeight(number) { dismiss() } } }
                }.disabled(store.syncing || (Double(value.replacingOccurrences(of:",",with:".")) ?? 0) <= 0) }
            }.navigationTitle(L10n.text("LOG_BODY_WEIGHT" /* 记录体重 */)).toolbar { ToolbarItem(placement:.topBarTrailing) { Button(L10n.text("CANCEL" /* 取消 */)) { dismiss() } } }
                .keyboardDismissToolbar()
        }.presentationDetents([.medium]).tint(GymTheme.green)
    }
}
