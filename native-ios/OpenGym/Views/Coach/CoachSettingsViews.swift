import SwiftUI

struct CoachHistoryView: View {
    let session: CoachSession
    var body: some View {
        List {
            if session.history.isEmpty { Text(L10n.text("NO_COACH_SUGGESTIONS_YET" /* 暂无教练建议 */)).foregroundStyle(.secondary) }
            ForEach(session.history.map { CoachRecord(raw:$0) }) { record in
                NavigationLink {
                    ScrollView { CoachProposalView(session:session,proposal:record.raw,historical:true).padding() }.navigationTitle(L10n.text("SUGGESTION_DETAILS" /* 建议详情 */))
                } label: {
                    VStack(alignment:.leading,spacing:7) {
                        let kind = record.raw.coachText("kind")
                        Text(kind == "create" ? L10n.text("ROUTINES" /* 训练计划 */) : kind == "debrief" ? L10n.text("WORKOUT_DEBRIEF" /* 训练复盘 */) : kind == "revert" ? L10n.text("UNDO_HISTORY" /* 撤销记录 */) : L10n.text("ROUTINE_CHANGES" /* 计划调整 */)).font(.headline)
                        Text(record.raw.coachText("summary")).font(.subheadline).lineLimit(3)
                        Text(Date(timeIntervalSince1970:number(record.raw["at"])/1000),format:.dateTime.month().day().hour().minute()).font(.caption).foregroundStyle(.secondary)
                        if record.raw["dismissed"] as? Bool == true { Text(L10n.text("DECLINED" /* 已拒绝 */)).font(.caption).foregroundStyle(.orange) }
                    }
                }
            }
        }.navigationTitle(L10n.text("COACH_HISTORY" /* 教练历史 */))
    }
}
struct CoachCadenceView: View {
    let session: CoachSession
    @Environment(\.dismiss) private var dismiss
    @State private var mode: String
    @State private var day: Int
    @State private var time: Date
    @State private var count: Int
    static var days: [String] { [L10n.text("SUN" /* 周日 */),L10n.text("MON" /* 周一 */),L10n.text("TUE" /* 周二 */),L10n.text("WED" /* 周三 */),L10n.text("THU" /* 周四 */),L10n.text("FRI" /* 周五 */),L10n.text("SAT" /* 周六 */)] }
    init(session: CoachSession) {
        self.session = session
        let c = session.coach.coachObject("cadence"), w = c.coachObject("weekly")
        _mode = State(initialValue:c.isEmpty ? "off" : w.isEmpty ? "every" : "weekly")
        _day = State(initialValue:Int(number(w["day"])))
        let parts = w.coachText("time").split(separator:":").compactMap { Int($0) }
        _time = State(initialValue:Calendar.current.date(from:DateComponents(hour:parts.first ?? 18,minute:parts.last ?? 0)) ?? Date())
        _count = State(initialValue:max(1,Int(number(c["everyWorkouts"] ?? 4))))
    }
    var body: some View {
        Form {
            Section {
                Picker(L10n.text("REVIEW_SCHEDULE" /* 评估时机 */),selection:$mode) { Text(L10n.text("TURN_OFF" /* 关闭 */)).tag("off");Text(L10n.text("WEEKLY" /* 每周 */)).tag("weekly");Text(L10n.text("AFTER_A_NUMBER_OF_WORKOUTS" /* 每完成几次训练 */)).tag("every") }
                if mode == "weekly" {
                    Picker(L10n.text("DAY" /* 星期 */),selection:$day) { ForEach(0..<7,id:\.self) { Text(Self.days[$0]).tag($0) } }
                    DatePicker(L10n.text("TIME_SERVER_TIME_ZONE" /* 时间（服务器时区） */),selection:$time,displayedComponents:.hourAndMinute)
                } else if mode == "every" { Stepper(L10n.text("EVERY_COUNT_WORKOUTS" /* 每 {0} 次训练 */, count),value:$count,in:1...20) }
            }
            Button(L10n.text("SAVE" /* 保存 */)) {
                Task {
                    let components = Calendar.current.dateComponents([.hour,.minute],from:time)
                    let cadence: Any = mode == "off" ? "off" : mode == "weekly" ? ["weekly":["day":day,"time":String(format:"%02d:%02d",components.hour ?? 18,components.minute ?? 0)]] : ["everyWorkouts":count]
                    if await session.perform({ try await session.change("cadence",values:["cadence":cadence]) }) { dismiss() }
                }
            }.disabled(session.locked)
        }.operationAlert(Binding(get: { session.error }, set: { session.error = $0 })).navigationTitle(L10n.text("AUTOMATIC_REVIEW" /* 自动评估 */))
    }
}
struct CoachCommunityView: View {
    let session: CoachSession
    @State private var data: [String: Any] = [:]
    @State private var loading = false
    @State private var error: String?
    var body: some View {
        Form {
            Section {
                Toggle(L10n.text("JOIN_ANONYMOUS_TRAINING_COMPARISONS" /* 参与匿名训练对比 */),isOn:Binding(get:{data["sharing"] as? Bool == true},set:{value in Task { await share(value) }})).disabled(loading || data.isEmpty)
            } footer: { Text(L10n.text("ONLY_AGGREGATE_MEDIANS_ARE_COMPARED_NAMES_BODY_WEIGHT_AND_INDIVIDUAL_WORKOUTS_ARE" /* 只比较参与者的汇总中位数，不展示姓名、体重或单次训练。关闭后会立即停止参与统计。 */)) }
            Button(loading ? L10n.text("REFRESHING" /* 正在刷新 */) : error == nil ? L10n.text("REFRESH" /* 刷新 */) : L10n.text("TRY_AGAIN" /* 重试 */)) { Task { await load() } }.disabled(loading).lineLimit(1)
            if data["sharing"] as? Bool == true {
                if data["ok"] as? Bool == true {
                    LabeledContent(L10n.text("PARTICIPANTS" /* 参与人数 */),value:String(Int(number(data["people"]))))
                    let sessions = data.coachObject("sessionsPerWeek")
                    LabeledContent(L10n.text("YOUR_WEEKLY_WORKOUTS" /* 你每周训练 */),value:String(format:"%.1f",number(sessions["you"])))
                    LabeledContent(L10n.text("MEDIAN_WEEKLY_WORKOUTS" /* 每周训练中位数 */),value:String(format:"%.1f",number(sessions["median"])))
                    ForEach(Array(data.coachObjects("exercises").enumerated()),id:\.offset) { _,exercise in
                        VStack(alignment:.leading,spacing:6) {
                            Text(session.store.exercise(exercise.coachText("id"))?.name ?? exercise.coachText("name"))
                            Text(L10n.text("ESTIMATED_ONE_REP_MAX_YOU_COUNT_MEDIAN_COUNT_COUNT" /* 估算 1RM：你 {0} · 中位数 {1} {2} */, String(format: "%.1f", number(exercise["you"])), String(format: "%.1f", number(exercise["median"])), session.store.unit)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } else { Text(L10n.text("NOT_ENOUGH_PARTICIPANTS_YET_COUNT_OF_COUNT" /* 参与人数还不足：{0} / {1} 人。 */, Int(number(data["people"])), Int(number(data["minPeople"] ?? 3)))).foregroundStyle(.secondary) }
            }
        }.operationAlert($error).navigationTitle(L10n.text("ANONYMOUS_TRAINING_COMPARISONS" /* 匿名训练对比 */)).task { await load() }
    }
    private func load() async {
        loading = true;defer{loading = false}
        do { data = try await session.store.coachRequest("api/coach/cohort");error = nil } catch { self.error = error.localizedDescription }
    }
    private func share(_ value: Bool) async {
        loading = true
        do { _ = try await session.store.coachRequest("api/coach/cohort/share",method:"POST",body:["share":value]);await load() }
        catch { self.error = error.localizedDescription }
        loading = false
    }
}
