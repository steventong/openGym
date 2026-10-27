import SwiftUI
import Charts

struct CoachProposalView: View {
    let session: CoachSession
    let proposal: [String: Any]
    var historical = false
    @State private var selected = Set<String>()
    @State private var schedule = true
    @State private var confirmApply = false
    @State private var confirmDismiss = false
    var body: some View {
        let presentation = session.presentation(proposal,history:historical)
        let p = presentation.coachObject("proposal")
        let kind = p.coachText("kind"), bundle = p.coachObject("bundle")
        VStack(alignment:.leading,spacing:18) {
            Label(kind == "create" ? "训练计划" : kind == "debrief" ? "训练复盘" : "调整建议",systemImage:"sparkles").font(.caption.bold()).foregroundStyle(GymTheme.green)
            Text(kind == "create" ? bundle.coachText("name") : kind == "debrief" ? p.coachObject("workout").coachText("name") : "\(p.coachObjects("changes").count) 项建议").font(.title2.bold())
            let summary = p.coachText("summary").isEmpty ? bundle.coachText("summary") : p.coachText("summary")
            if !summary.isEmpty { Text(summary).textSelection(.enabled) }
            if historical { Text(p["dismissed"] as? Bool == true ? "已拒绝" : "已处理 · 历史记录").font(.caption).foregroundStyle(.secondary) }
            if kind == "create" {
                if !bundle.coachText("basedOn").isEmpty { Text(bundle.coachText("basedOn")).font(.subheadline).foregroundStyle(.secondary) }
                weeklySchedule(bundle)
                ForEach(Array(bundle.coachObjects("routines").enumerated()),id:\.offset) { _,routine in
                    DisclosureGroup {
                        VStack(alignment:.leading,spacing:12) {
                            if !routine.coachText("why").isEmpty { Text(routine.coachText("why")).font(.subheadline).foregroundStyle(.secondary) }
                            ForEach(Array(routine.coachObjects("ex").enumerated()),id:\.offset) { index,exercise in
                                VStack(alignment:.leading,spacing:6) {
                                    Text("\(index+1). \(session.store.exercise(exercise.coachText("id"))?.name ?? exercise.coachText("id"))").font(.headline)
                                    Text(exercise.coachText("line")).font(.subheadline).foregroundStyle(GymTheme.green)
                                    if !exercise.coachText("why").isEmpty { Text(exercise.coachText("why")).font(.caption).foregroundStyle(.secondary) }
                                }.padding(.vertical,5)
                            }
                        }.padding(.top,10)
                    } label: { Text(routine.coachText("name")).font(.headline) }
                }
                if !historical {
                    Toggle("使用这份每周安排",isOn:$schedule)
                    Text("开启后替换每周安排及未来的单日调整，未安排的日期为休息日。原有训练计划和训练记录会保留。").font(.caption).foregroundStyle(.secondary)
                }
            } else if kind == "debrief" {
                if let score = p["score"] as? NSNumber { Text("\(score) / 10").font(.system(size:40,weight:.bold)).foregroundStyle(GymTheme.green) }
                CoachInsightsView(data:presentation.coachObject("insights"),session:session,debrief:true)
                strings("做得好的地方",p["highlights"],symbol:"checkmark.circle")
                strings("需要注意",p["watch"],symbol:"exclamationmark.triangle")
                strings("下次训练",p["nextTime"],symbol:"arrow.up.right")
            } else {
                if p["planMoved"] as? Bool == true { Text("计划在其他设备上有过修改。不再适用的建议已禁用。").font(.caption).foregroundStyle(.orange) }
                CoachInsightsView(data:presentation.coachObject("insights"),session:session)
                ForEach(Array(p.coachObjects("changes").enumerated()),id:\.offset) { _,change in
                    changeRow(change)
                }
                strings("教练备注",p["notes"],symbol:"lightbulb")
            }
            if !historical {
                CoachPrimaryButton(title:kind == "create" ? "导入这份计划" : kind == "debrief" ? "保存复盘" : "应用 \(selected.count) 项修改",icon:"checkmark") { confirmApply = true }
                    .disabled(session.locked || (kind == "review" && selected.isEmpty)).accessibilityIdentifier("coach-apply")
                if kind != "debrief" { CoachTextAction(title:"拒绝这份建议") { confirmDismiss = true }.disabled(session.locked).accessibilityIdentifier("coach-dismiss") }
            }
        }.gymCard()
        .onAppear { selected = Set(p.coachObjects("changes").filter { $0.coachText("status") != "stale" }.map { $0.coachText("id") }) }
        .onChange(of:p.coachObjects("changes").filter { $0.coachText("status") != "stale" }.map { $0.coachText("id") }) { _,ids in selected.formIntersection(ids) }
        .confirmationDialog(kind == "debrief" ? "保存到教练历史？" : "确认应用教练建议？",isPresented:$confirmApply,titleVisibility:.visible) {
            Button(kind == "debrief" ? "保存复盘" : "确认应用") { Task { await session.resolve(proposal,accepted:Array(selected),schedule:schedule) } }
        } message: { Text(kind == "debrief" ? "不会修改训练计划。" : "保存后会同步到所有设备，可在教练菜单中撤销。") }
        .confirmationDialog("拒绝这份建议？",isPresented:$confirmDismiss,titleVisibility:.visible) {
            Button("拒绝建议",role:.destructive) { Task { await session.resolve(proposal,dismissed:true) } }
        } message: { Text("计划保持不变，建议会保留在历史中。") }
    }
    private func weeklySchedule(_ bundle: [String: Any]) -> some View {
        let week = bundle.coachObject("week"), routines = bundle.coachObjects("routines")
        return VStack(alignment:.leading,spacing:7) {
            ForEach([1,2,3,4,5,6,0],id:\.self) { day in
                let ids = (week[String(day)] as? [String]) ?? (week[String(day)] as? String).map { [$0] } ?? []
                if !ids.isEmpty { Text("\(CoachCadenceView.days[day]) · \(ids.map { id in routines.first { $0.coachText("id") == id }?.coachText("name") ?? id }.joined(separator:" + "))").font(.caption).foregroundStyle(.secondary) }
            }
        }
    }
    private func changeRow(_ change: [String: Any]) -> some View {
        let stale = change.coachText("status") == "stale", id = change.coachText("id")
        return HStack(alignment:.top) {
            VStack(alignment:.leading,spacing:7) {
                Text(change.coachText("title")).font(.headline)
                if !change.coachText("routineName").isEmpty { Text(change.coachText("routineName")).font(.caption).foregroundStyle(.secondary) }
                let values = change.coachObject("values")
                if !values.isEmpty { Text(values.coachText("before")+" → "+values.coachText("after")).font(.subheadline).foregroundStyle(GymTheme.green) }
                Text(change.coachText("why")).font(.subheadline).foregroundStyle(.secondary)
                if stale { Text("已不适用于当前计划，请重新请求评估。").font(.caption).foregroundStyle(.orange) }
                if historical { Text(change.coachText("status") == "accepted" ? "已接受" : "未应用").font(.caption).foregroundStyle(.secondary) }
            }
            Spacer(minLength:2)
            if !historical {
                Toggle("选择建议",isOn:Binding(get:{selected.contains(id)},set:{on in if on {selected.insert(id)}else{selected.remove(id)}})).labelsHidden().toggleStyle(.switch).disabled(stale || session.locked)
            }
        }.padding(.vertical,9).opacity(stale ? 0.6 : 1)
    }
    private func strings(_ title: String,_ value: Any?,symbol: String) -> some View {
        let items = value as? [String] ?? []
        return Group { if !items.isEmpty {
            VStack(alignment:.leading,spacing:8) {
                Label(title,systemImage:symbol).font(.headline).foregroundStyle(GymTheme.green)
                ForEach(Array(items.enumerated()),id:\.offset) { _,text in Text("• "+text).font(.subheadline) }
            }
        } }
    }
}

struct CoachInsightsView: View {
    let data: [String: Any]
    let session: CoachSession
    var debrief = false
    var body: some View {
        let summary = debrief ? data.coachObject("now") : data
        if !data.isEmpty && (debrief || number(summary["sessions"]) > 0) {
            VStack(alignment:.leading,spacing:12) {
                HStack(spacing:18) {
                    metric(debrief ? "分钟" : "训练次数",number(summary[debrief ? "minutes" : "sessions"]))
                    metric("训练组数",number(summary["sets"]))
                    metric("训练量 \(session.store.unit)",number(summary["volume"]))
                }
                let points = data.coachObject("bodyweight").coachObjects("points")
                if points.count > 1 {
                    Text("体重变化").font(.caption)
                    Chart(Array(points.enumerated()),id:\.offset) { index,point in
                        LineMark(x:.value("顺序",index),y:.value("体重",number(point["v"] ?? point["y"]))).foregroundStyle(GymTheme.green)
                    }.frame(height:110)
                }
                let strength = data.coachObjects(debrief ? "lifts" : "strength")
                ForEach(Array(strength.prefix(6).enumerated()),id:\.offset) { _,item in
                    HStack {
                        Text(session.store.exercise(item.coachText("id"))?.name ?? item.coachText("name"))
                        Spacer()
                        Text(debrief ? "估算 1RM \(number(item["est"]),specifier:"%.1f")" : "\(number(item["first"]),specifier:"%.1f") → \(number(item["last"]),specifier:"%.1f")")
                    }.font(.caption)
                }
            }.padding(12).background(.black.opacity(0.2),in:RoundedRectangle(cornerRadius:12))
        }
    }
    private func metric(_ name: String,_ value: Double) -> some View { VStack(alignment:.leading,spacing:4) { Text(value,format:.number.precision(.fractionLength(0...1))).font(.headline);Text(name).font(.caption2).foregroundStyle(.secondary) } }
}
