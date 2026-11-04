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
    @State private var selectionLoaded = false
    var body: some View {
        let presentation = session.presentation(proposal,history:historical)
        let p = presentation.coachObject("proposal")
        let kind = p.coachText("kind"), bundle = p.coachObject("bundle")
        VStack(alignment:.leading,spacing:18) {
            Label(kind == "create" ? L10n.text("ROUTINES" /* 训练计划 */) : kind == "debrief" ? L10n.text("WORKOUT_DEBRIEF" /* 训练复盘 */) : L10n.text("SUGGESTED_CHANGES" /* 调整建议 */),systemImage:"sparkles").font(.caption.bold()).foregroundStyle(GymTheme.green)
            Text(kind == "create" ? bundle.coachText("name") : kind == "debrief" ? p.coachObject("workout").coachText("name") : L10n.text("COUNT_SUGGESTIONS" /* {0} 条建议 */, p.coachObjects("changes").count)).font(.title2.bold())
            let summary = p.coachText("summary").isEmpty ? bundle.coachText("summary") : p.coachText("summary")
            if !summary.isEmpty { Text(summary).textSelection(.enabled) }
            if historical { Text(p["dismissed"] as? Bool == true ? L10n.text("DECLINED" /* 已拒绝 */) : L10n.text("REVIEWED_HISTORY" /* 已处理 · 历史记录 */)).font(.caption).foregroundStyle(.secondary) }
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
                    Toggle(L10n.text("USE_THIS_WEEKLY_SCHEDULE" /* 使用此每周日程 */),isOn:$schedule)
                }
            } else if kind == "debrief" {
                if let score = p["score"] as? NSNumber { Text("\(score) / 10").font(.system(size:40,weight:.bold)).foregroundStyle(GymTheme.green) }
                CoachInsightsView(data:presentation.coachObject("insights"),session:session,debrief:true)
                strings(L10n.text("WHAT_WENT_WELL" /* 做得好的地方 */),p["highlights"],symbol:"checkmark.circle")
                strings(L10n.text("WHAT_TO_WATCH" /* 需要注意 */),p["watch"],symbol:"exclamationmark.triangle")
                strings(L10n.text("NEXT_WORKOUT" /* 下次训练 */),p["nextTime"],symbol:"arrow.up.right")
            } else {
                CoachInsightsView(data:presentation.coachObject("insights"),session:session)
                ForEach(Array(p.coachObjects("changes").enumerated()),id:\.offset) { _,change in
                    changeRow(change)
                }
                strings(L10n.text("NOTES_FROM_THE_COACH" /* 教练备注 */),p["notes"],symbol:"lightbulb")
            }
            if !historical {
                CoachPrimaryButton(title:kind == "create" ? L10n.text("IMPORT_THIS_PLAN" /* 导入此计划 */) : kind == "debrief" ? L10n.text("SAVE_REVIEW" /* 保存复盘 */) : L10n.text("APPLY_COUNT_CHANGES" /* 应用 {0} 项更改 */, selected.count),icon:"checkmark") { confirmApply = true }
                    .disabled(session.locked || (kind == "review" && selected.isEmpty)).accessibilityIdentifier("coach-apply")
                if kind != "debrief" { CoachTextAction(title:L10n.text("DECLINE_THIS_SUGGESTION" /* 拒绝这份建议 */)) { confirmDismiss = true }.disabled(session.locked).accessibilityIdentifier("coach-dismiss") }
            }
        }.gymCard()
        .onAppear {
            guard !selectionLoaded else { return }; selectionLoaded = true
            selected = Set(p.coachObjects("changes").filter { $0.coachText("status") != "stale" }.map { $0.coachText("id") })
        }
        .onChange(of:p.coachObjects("changes").filter { $0.coachText("status") != "stale" }.map { $0.coachText("id") }) { _,ids in selected.formIntersection(ids) }
        .confirmationDialog(kind == "debrief" ? L10n.text("SAVE_TO_COACH_HISTORY" /* 保存到教练历史？ */) : L10n.text("APPLY_COACH_SUGGESTIONS" /* 确认应用教练建议？ */),isPresented:$confirmApply,titleVisibility:.visible) {
            Button(kind == "debrief" ? L10n.text("SAVE_REVIEW" /* 保存复盘 */) : L10n.text("APPLY_CHANGES" /* 确认应用 */)) { Task { await session.resolve(proposal,accepted:Array(selected),schedule:schedule) } }
        } message: { Text(kind == "debrief" ? L10n.text("YOUR_ROUTINES_WILL_NOT_CHANGE" /* 不会修改训练计划。 */) : kind == "create" && schedule ? L10n.text("REPLACES_YOUR_WEEKLY_SCHEDULE_AND_FUTURE_DATE_OVERRIDES_EXISTING_ROUTINES_AND_WORKOUT" /* 将替换每周安排及未来单日调整，保留已有计划和训练记录。 */) : L10n.text("SYNCS_TO_ALL_DEVICES_YOU_CAN_UNDO_THIS_FROM_THE_COACH_MENU" /* 同步到所有设备，可在教练菜单撤销。 */)) }
        .confirmationDialog(L10n.text("DECLINE_THIS_SUGGESTION_A" /* 拒绝这份建议？ */),isPresented:$confirmDismiss,titleVisibility:.visible) {
            Button(L10n.text("DECLINE_SUGGESTION" /* 拒绝建议 */),role:.destructive) { Task { await session.resolve(proposal,dismissed:true) } }
        } message: { Text(L10n.text("YOUR_ROUTINES_STAY_UNCHANGED_THE_SUGGESTION_IS_KEPT_IN_HISTORY" /* 计划保持不变，建议会保留在历史中。 */)) }
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
                HStack { Text(change.coachText("title")).font(.headline); Spacer(); if stale { StatusDetailButton(title: L10n.text("OUTDATED" /* 已失效 */), message: L10n.text("YOUR_ROUTINES_CHANGED_ON_ANOTHER_DEVICE_REQUEST_A_NEW_REVIEW" /* 计划已在其他设备修改，请重新评估。 */), warning: true) } }
                if !change.coachText("routineName").isEmpty { Text(change.coachText("routineName")).font(.caption).foregroundStyle(.secondary) }
                let values = change.coachObject("values")
                if !values.isEmpty { Text(values.coachText("before")+" → "+values.coachText("after")).font(.subheadline).foregroundStyle(GymTheme.green) }
                Text(change.coachText("why")).font(.subheadline).foregroundStyle(.secondary)
                if historical { Text(change.coachText("status") == "accepted" ? L10n.text("ACCEPTED" /* 已采纳 */) : L10n.text("NOT_APPLIED" /* 未应用 */)).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer(minLength:2)
            if !historical {
                Toggle(L10n.text("CHOOSE_SUGGESTIONS" /* 选择建议 */),isOn:Binding(get:{selected.contains(id)},set:{on in if on {selected.insert(id)}else{selected.remove(id)}})).labelsHidden().toggleStyle(.switch).disabled(stale || session.locked)
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
                    metric(debrief ? L10n.text("MINUTES" /* 分钟 */) : L10n.text("WORKOUTS" /* 训练次数 */),number(summary[debrief ? "minutes" : "sessions"]))
                    metric(L10n.text("SETS" /* 组数 */),number(summary["sets"]))
                    metric(L10n.text("VOLUME_COUNT_A" /* 训练量 {0} */, session.store.unit),number(summary["volume"]))
                }
                let points = data.coachObject("bodyweight").coachObjects("points")
                if points.count > 1 {
                    Text(L10n.text("BODY_WEIGHT_CHANGE" /* 体重变化 */)).font(.caption)
                    Chart(Array(points.enumerated()),id:\.offset) { index,point in
                        LineMark(x:.value(L10n.text("ORDER" /* 顺序 */),index),y:.value(L10n.text("BODY_WEIGHT" /* 体重 */),number(point["v"] ?? point["y"]))).foregroundStyle(GymTheme.green)
                    }.frame(height:110)
                }
                let strength = data.coachObjects(debrief ? "lifts" : "strength")
                ForEach(Array(strength.prefix(6).enumerated()),id:\.offset) { _,item in
                    strengthRow(item, debrief: debrief)
                }
            }.padding(12).background(.black.opacity(0.2),in:RoundedRectangle(cornerRadius:12))
        }
    }
    private func metric(_ name: String,_ value: Double) -> some View { VStack(alignment:.leading,spacing:4) { Text(value,format:.number.precision(.fractionLength(0...1))).font(.headline);Text(name).font(.caption2).foregroundStyle(.secondary) } }
    private func strengthRow(_ item: [String: Any], debrief: Bool) -> some View {
        let name = session.store.exercise(item.coachText("id"))?.name ?? item.coachText("name")
        let value = debrief
            ? L10n.text("ESTIMATED_ONE_REP_MAX_COUNT" /* 估算 1RM {0} */, String(format: "%.1f", number(item["est"])))
            : String(format: "%.1f → %.1f", number(item["first"]), number(item["last"]))
        return HStack { Text(name); Spacer(); Text(value) }.font(.caption)
    }

}
