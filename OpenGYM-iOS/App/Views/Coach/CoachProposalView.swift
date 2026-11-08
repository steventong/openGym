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
            Label(LocalizedStringKey(kind == "create" ? "ROUTINES" : kind == "debrief" ? "WORKOUT_DEBRIEF" : "SUGGESTED_CHANGES"),systemImage:"sparkles").font(.caption.bold()).foregroundStyle(GymTheme.green)
            Text(kind == "create" ? bundle.coachText("name") : kind == "debrief" ? p.coachObject("workout").coachText("name") : String(format: String(localized: "COUNT_SUGGESTIONS", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(describing: p.coachObjects("changes").count))).font(.title2.bold())
            let summary = p.coachText("summary").isEmpty ? bundle.coachText("summary") : p.coachText("summary")
            if !summary.isEmpty { Text(summary).textSelection(.enabled) }
            if historical { Text(LocalizedStringKey(p["dismissed"] as? Bool == true ? "DECLINED" : "REVIEWED_HISTORY")).font(.caption).foregroundStyle(.secondary) }
            if kind == "create" {
                if !bundle.coachText("basedOn").isEmpty { Text(bundle.coachText("basedOn")).font(.subheadline).foregroundStyle(.secondary) }
                CoachWeeklyScheduleView(bundle: bundle)
                ForEach(Array(bundle.coachObjects("routines").enumerated()),id:\.offset) { _,routine in
                    DisclosureGroup {
                        VStack(alignment:.leading,spacing:12) {
                            if !routine.coachText("why").isEmpty { Text(routine.coachText("why")).font(.subheadline).foregroundStyle(.secondary) }
                            ForEach(Array(routine.coachObjects("ex").enumerated()),id:\.offset) { index,exercise in
                                VStack(alignment:.leading,spacing:6) {
                                    Text(String(format: String(localized: "NUMBERED_EXERCISE", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(index + 1), session.store.exercise(exercise.coachText("id"))?.name ?? exercise.coachText("id"))).font(.headline)
                                    Text(exercise.coachText("line")).font(.subheadline).foregroundStyle(GymTheme.green)
                                    if !exercise.coachText("why").isEmpty { Text(exercise.coachText("why")).font(.caption).foregroundStyle(.secondary) }
                                }.padding(.vertical,5)
                            }
                        }.padding(.top,10)
                    } label: { Text(routine.coachText("name")).font(.headline) }
                }
                if !historical {
                    Toggle("USE_THIS_WEEKLY_SCHEDULE",isOn:$schedule)
                }
            } else if kind == "debrief" {
                if let score = p["score"] as? NSNumber { Text(String(format: String(localized: "COACH_WORKOUT_SCORE", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, score.stringValue, "10")).font(.system(size:40,weight:.bold)).foregroundStyle(GymTheme.green) }
                CoachInsightsView(data:presentation.coachObject("insights"),session:session,debrief:true)
                CoachTextList(title: "WHAT_WENT_WELL", items: p["highlights"] as? [String] ?? [], symbol:"checkmark.circle")
                CoachTextList(title: "WHAT_TO_WATCH", items: p["watch"] as? [String] ?? [], symbol:"exclamationmark.triangle")
                CoachTextList(title: "NEXT_WORKOUT", items: p["nextTime"] as? [String] ?? [], symbol:"arrow.up.right")
            } else {
                CoachInsightsView(data:presentation.coachObject("insights"),session:session)
                ForEach(Array(p.coachObjects("changes").enumerated()),id:\.offset) { _,change in
                    CoachChangeRow(change: change, historical: historical, locked: session.locked, selected: changeSelection(change.coachText("id")))
                }
                CoachTextList(title: "NOTES_FROM_THE_COACH", items: p["notes"] as? [String] ?? [], symbol:"lightbulb")
            }
            if !historical {
                CoachPrimaryButton(title:kind == "create" ? "IMPORT_THIS_PLAN" : kind == "debrief" ? "SAVE_REVIEW" : "\(String(format: String(localized: "APPLY_COUNT_CHANGES", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(describing: selected.count)))",icon:"checkmark") { confirmApply = true }
                    .disabled(session.locked || (kind == "review" && selected.isEmpty)).accessibilityIdentifier("coach-apply")
                if kind != "debrief" { CoachTextAction(title:"DECLINE_THIS_SUGGESTION") { confirmDismiss = true }.disabled(session.locked).accessibilityIdentifier("coach-dismiss") }
            }
        }.gymCard()
        .onAppear {
            guard !selectionLoaded else { return }; selectionLoaded = true
            selected = Set(p.coachObjects("changes").filter { $0.coachText("status") != "stale" }.map { $0.coachText("id") })
        }
        .onChange(of:p.coachObjects("changes").filter { $0.coachText("status") != "stale" }.map { $0.coachText("id") }) { _,ids in selected.formIntersection(ids) }
        .confirmationDialog(LocalizedStringKey(kind == "debrief" ? "SAVE_TO_COACH_HISTORY" : "APPLY_COACH_SUGGESTIONS"),isPresented:$confirmApply,titleVisibility:.visible) {
            Button(LocalizedStringKey(kind == "debrief" ? "SAVE_REVIEW" : "APPLY_CHANGES")) { Task { await session.resolve(proposal,accepted:Array(selected),schedule:schedule) } }
        } message: { Text(LocalizedStringKey(kind == "debrief" ? "YOUR_ROUTINES_WILL_NOT_CHANGE" : kind == "create" && schedule ? "REPLACES_YOUR_WEEKLY_SCHEDULE_AND_FUTURE_DATE_OVERRIDES_EXISTING_ROUTINES_AND_WORKOUT" : "SYNCS_TO_ALL_DEVICES_YOU_CAN_UNDO_THIS_FROM_THE_COACH_MENU")) }
        .confirmationDialog("DECLINE_THIS_SUGGESTION_A",isPresented:$confirmDismiss,titleVisibility:.visible) {
            Button("DECLINE_SUGGESTION",role:.destructive) { Task { await session.resolve(proposal,dismissed:true) } }
        } message: { Text("YOUR_ROUTINES_STAY_UNCHANGED_THE_SUGGESTION_IS_KEPT_IN_HISTORY") }
    }
    private func changeSelection(_ id: String) -> Binding<Bool> {
        Binding(get: { selected.contains(id) }, set: { enabled in
            if enabled { selected.insert(id) }
            else { selected.remove(id) }
        })
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
                    CoachInsightMetric(name: debrief ? "MINUTES" : "WORKOUTS", value: number(summary[debrief ? "minutes" : "sessions"]))
                    CoachInsightMetric(name: "SETS", value: number(summary["sets"]))
                    CoachInsightMetric(name: "\(String(format: String(localized: "VOLUME_COUNT_A", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(describing: session.store.unit)))", value: number(summary["volume"]))
                }
                let points = data.coachObject("bodyweight").coachObjects("points")
                if points.count > 1 {
                    Text("BODY_WEIGHT_CHANGE").font(.caption)
                    Chart(Array(points.enumerated()),id:\.offset) { index,point in
                        LineMark(x:.value(String(localized: "ORDER", bundle: AppLanguage.bundle, locale: AppLanguage.locale),index),y:.value(String(localized: "BODY_WEIGHT", bundle: AppLanguage.bundle, locale: AppLanguage.locale),number(point["v"] ?? point["y"]))).foregroundStyle(GymTheme.green)
                    }.frame(height:110)
                }
                let strength = data.coachObjects(debrief ? "lifts" : "strength")
                ForEach(Array(strength.prefix(6).enumerated()),id:\.offset) { _,item in
                    CoachStrengthRow(name: session.store.exercise(item.coachText("id"))?.name ?? item.coachText("name"), value: strengthValue(item, debrief: debrief))
                }
            }.padding(12).background(.black.opacity(0.2),in:RoundedRectangle(cornerRadius:12))
        }
    }
    private func strengthValue(_ item: [String: Any], debrief: Bool) -> String {
        debrief
            ? String(format: String(localized: "ESTIMATED_ONE_REP_MAX_COUNT", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(describing: String(format: "%.1f", number(item["est"]))))
            : String(format: "%.1f → %.1f", number(item["first"]), number(item["last"]))
    }

}
