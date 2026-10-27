import SwiftUI

struct CoachHistoryView: View {
    let session: CoachSession
    var body: some View {
        List {
            if session.history.isEmpty { Text("还没有教练建议。处理后的计划、调整和复盘会保存在这里。").foregroundStyle(.secondary) }
            ForEach(session.history.map { CoachRecord(raw:$0) }) { record in
                NavigationLink {
                    ScrollView { CoachProposalView(session:session,proposal:record.raw,historical:true).padding() }.navigationTitle("建议详情")
                } label: {
                    VStack(alignment:.leading,spacing:7) {
                        let kind = record.raw.coachText("kind")
                        Text(kind == "create" ? "训练计划" : kind == "debrief" ? "训练复盘" : kind == "revert" ? "撤销记录" : "计划调整").font(.headline)
                        Text(record.raw.coachText("summary")).font(.subheadline).lineLimit(3)
                        Text(Date(timeIntervalSince1970:number(record.raw["at"])/1000),format:.dateTime.month().day().hour().minute()).font(.caption).foregroundStyle(.secondary)
                        if record.raw["dismissed"] as? Bool == true { Text("已拒绝").font(.caption).foregroundStyle(.orange) }
                    }
                }
            }
        }.navigationTitle("教练历史")
    }
}
struct CoachCadenceView: View {
    let session: CoachSession
    @Environment(\.dismiss) private var dismiss
    @State private var mode: String
    @State private var day: Int
    @State private var time: Date
    @State private var count: Int
    static let days = ["周日","周一","周二","周三","周四","周五","周六"]
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
                Picker("评估时机",selection:$mode) { Text("关闭").tag("off");Text("每周").tag("weekly");Text("每完成几次训练").tag("every") }
                if mode == "weekly" {
                    Picker("星期",selection:$day) { ForEach(0..<7,id:\.self) { Text(Self.days[$0]).tag($0) } }
                    DatePicker("时间",selection:$time,displayedComponents:.hourAndMinute)
                } else if mode == "every" { Stepper("每 \(count) 次训练",value:$count,in:1...20) }
            } footer: { Text(mode == "off" ? "只有你主动请求时才进行评估。" : "由服务器按已同步的训练数据触发，有建议时会出现在教练中。每周时间使用服务器时区。") }
            if let error = session.error { Text(error).foregroundStyle(.orange) }
            Button("保存") {
                Task {
                    let components = Calendar.current.dateComponents([.hour,.minute],from:time)
                    let cadence: Any = mode == "off" ? "off" : mode == "weekly" ? ["weekly":["day":day,"time":String(format:"%02d:%02d",components.hour ?? 18,components.minute ?? 0)]] : ["everyWorkouts":count]
                    if await session.perform({ try await session.change("cadence",values:["cadence":cadence]) }) { dismiss() }
                }
            }.disabled(session.locked)
        }.navigationTitle("自动评估")
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
                Toggle("参与匿名训练对比",isOn:Binding(get:{data["sharing"] as? Bool == true},set:{value in Task { await share(value) }})).disabled(loading || data.isEmpty)
            } footer: { Text("只比较参与者的汇总中位数，不展示姓名、体重或单次训练。关闭后会立即停止参与统计。") }
            if loading { ProgressView() }
            if let error { Text(error).foregroundStyle(.orange);Button("重试") { Task { await load() } } }
            if data["sharing"] as? Bool == true {
                if data["ok"] as? Bool == true {
                    LabeledContent("参与人数",value:String(Int(number(data["people"]))))
                    let sessions = data.coachObject("sessionsPerWeek")
                    LabeledContent("你每周训练",value:String(format:"%.1f",number(sessions["you"])))
                    LabeledContent("每周训练中位数",value:String(format:"%.1f",number(sessions["median"])))
                    ForEach(Array(data.coachObjects("exercises").enumerated()),id:\.offset) { _,exercise in
                        VStack(alignment:.leading,spacing:6) {
                            Text(session.store.exercise(exercise.coachText("id"))?.name ?? exercise.coachText("name"))
                            Text("估算 1RM：你 \(number(exercise["you"]),specifier:"%.1f") · 中位数 \(number(exercise["median"]),specifier:"%.1f") \(session.store.unit)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } else { Text("参与人数还不足：\(Int(number(data["people"]))) / \(Int(number(data["minPeople"] ?? 3))) 人。").foregroundStyle(.secondary) }
            }
        }.navigationTitle("匿名训练对比").task { await load() }
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
