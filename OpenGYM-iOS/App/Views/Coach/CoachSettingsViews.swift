import SwiftUI

struct CoachHistoryView: View {
    let session: CoachSession
    var body: some View {
        List {
            if session.history.isEmpty { Text("NO_COACH_SUGGESTIONS_YET").foregroundStyle(.secondary) }
            ForEach(session.history.map { CoachRecord(raw:$0) }) { record in
                NavigationLink {
                    ScrollView { CoachProposalView(session:session,proposal:record.raw,historical:true).padding() }.navigationTitle("SUGGESTION_DETAILS")
                } label: {
                    VStack(alignment:.leading,spacing:7) {
                        let kind = record.raw.coachText("kind")
                        Text(LocalizedStringKey(kind == "create" ? "ROUTINES" : kind == "debrief" ? "WORKOUT_DEBRIEF" : kind == "revert" ? "UNDO_HISTORY" : "ROUTINE_CHANGES")).font(.headline)
                        Text(record.raw.coachText("summary")).font(.subheadline).lineLimit(3)
                        Text(Date(timeIntervalSince1970:number(record.raw["at"])/1000),format:.dateTime.month().day().hour().minute()).font(.caption).foregroundStyle(.secondary)
                        if record.raw["dismissed"] as? Bool == true { Text("DECLINED").font(.caption).foregroundStyle(.orange) }
                    }
                }
            }
        }.navigationTitle("COACH_HISTORY")
    }
}
struct CoachCadenceView: View {
    let session: CoachSession
    @Environment(\.dismiss) private var dismiss
    @State private var mode: String
    @State private var day: Int
    @State private var time: Date
    @State private var count: Int
    static let days: [String.LocalizationValue] = ["SUN","MON","TUE","WED","THU","FRI","SAT"]
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
        let days = Self.days.map { String(localized: $0, bundle: AppLanguage.bundle, locale: AppLanguage.locale) }

        Form {
            Section {
                Picker("REVIEW_SCHEDULE",selection:$mode) { Text("TURN_OFF").tag("off");Text("WEEKLY").tag("weekly");Text("AFTER_A_NUMBER_OF_WORKOUTS").tag("every") }
                if mode == "weekly" {
                    Picker("DAY",selection:$day) { ForEach(0..<7,id:\.self) { Text(days[$0]).tag($0) } }
                    DatePicker("TIME_SERVER_TIME_ZONE",selection:$time,displayedComponents:.hourAndMinute)
                } else if mode == "every" { Stepper(String(format: String(localized: "EVERY_COUNT_WORKOUTS", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(describing: count)),value:$count,in:1...20) }
            }
            Button("SAVE") {
                Task {
                    let components = Calendar.current.dateComponents([.hour,.minute],from:time)
                    let cadence: Any = mode == "off" ? "off" : mode == "weekly" ? ["weekly":["day":day,"time":String(format:"%02d:%02d",components.hour ?? 18,components.minute ?? 0)]] : ["everyWorkouts":count]
                    if await session.perform({ try await session.change("cadence",values:["cadence":cadence]) }) { dismiss() }
                }
            }.disabled(session.locked)
        }.operationAlert(Binding(get: { session.error }, set: { session.error = $0 })).navigationTitle("AUTOMATIC_REVIEW")
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
                Toggle("JOIN_ANONYMOUS_TRAINING_COMPARISONS",isOn:Binding(get:{data["sharing"] as? Bool == true},set:{value in Task { await share(value) }})).disabled(loading || data.isEmpty)
            } footer: { Text("ONLY_AGGREGATE_MEDIANS_ARE_COMPARED_NAMES_BODY_WEIGHT_AND_INDIVIDUAL_WORKOUTS_ARE") }
            Button(LocalizedStringKey(loading ? "REFRESHING" : error == nil ? "REFRESH" : "TRY_AGAIN")) { Task { await load() } }.disabled(loading).lineLimit(1)
            if data["sharing"] as? Bool == true {
                if data["ok"] as? Bool == true {
                    LabeledContent("PARTICIPANTS",value:String(Int(number(data["people"]))))
                    let sessions = data.coachObject("sessionsPerWeek")
                    LabeledContent("YOUR_WEEKLY_WORKOUTS",value:String(format:"%.1f",number(sessions["you"])))
                    LabeledContent("MEDIAN_WEEKLY_WORKOUTS",value:String(format:"%.1f",number(sessions["median"])))
                    ForEach(Array(data.coachObjects("exercises").enumerated()),id:\.offset) { _,exercise in
                        VStack(alignment:.leading,spacing:6) {
                            Text(session.store.exercise(exercise.coachText("id"))?.name ?? exercise.coachText("name"))
                            Text(String(format: String(localized: "ESTIMATED_ONE_REP_MAX_YOU_COUNT_MEDIAN_COUNT_COUNT", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(describing: String(format: "%.1f", number(exercise["you"]))), String(describing: String(format: "%.1f", number(exercise["median"]))), String(describing: session.store.unit))).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } else { Text(String(format: String(localized: "NOT_ENOUGH_PARTICIPANTS_YET_COUNT_OF_COUNT", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(describing: Int(number(data["people"]))), String(describing: Int(number(data["minPeople"] ?? 3))))).foregroundStyle(.secondary) }
            }
        }.operationAlert($error).navigationTitle("ANONYMOUS_TRAINING_COMPARISONS").task { await load() }
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
