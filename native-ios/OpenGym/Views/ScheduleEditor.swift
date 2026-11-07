import SwiftUI
struct ScheduleEditor: View {
    @Environment(GymStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var original: [String:Any] = [:]
    @State private var week: [String:Any] = [:]
    @State private var overrides: [String:Any] = [:]
    @State private var loaded = false
    @State private var tab = 0
    @State private var weekday = 1
    @State private var date = Date()
    @State private var discard = false
    @State private var error: String?
    private let names = [String(localized: "SUN", bundle: AppLanguage.bundle, locale: AppLanguage.locale),String(localized: "MON", bundle: AppLanguage.bundle, locale: AppLanguage.locale),String(localized: "TUE", bundle: AppLanguage.bundle, locale: AppLanguage.locale),String(localized: "WED", bundle: AppLanguage.bundle, locale: AppLanguage.locale),String(localized: "THU", bundle: AppLanguage.bundle, locale: AppLanguage.locale),String(localized: "FRI", bundle: AppLanguage.bundle, locale: AppLanguage.locale),String(localized: "SAT", bundle: AppLanguage.bundle, locale: AppLanguage.locale)]
    private var ids:[String] { week[String(weekday)] as? [String] ?? (week[String(weekday)] as? String).map { [$0] } ?? [] }
    private var proposed:[String:Any] {
        var result = original
        if original["week"] != nil || !week.isEmpty { result["week"] = week }
        if original["dayPlan"] != nil || !overrides.isEmpty { result["dayPlan"] = overrides }
        return result
    }
    private var dirty:Bool { !RecordPatch.equal(original,proposed) }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("SCHEDULE_TYPE",selection:$tab) { Text("WEEKLY_SCHEDULE").tag(0); Text("DATE_OVERRIDE").tag(1) }.pickerStyle(.segmented).accessibilityIdentifier("schedule-mode")
                }
                if tab == 0 {
                    Section("CHOOSE_WEEKDAY") {
                        Picker("DAY",selection:$weekday) { ForEach([1,2,3,4,5,6,0],id:\.self) { Text(names[$0]).tag($0) } }.pickerStyle(.menu).accessibilityIdentifier("schedule-weekday")
                    }
                    Section {
                        Button { week.removeValue(forKey:String(weekday)) } label: { ScheduleSelectionRow(title: String(localized: "REST_DAY", bundle: AppLanguage.bundle, locale: AppLanguage.locale),selected:ids.isEmpty,icon:"moon") }
                        ForEach(store.routines) { r in
                            Button {
                                var next = ids
                                if next.contains(r.id) { next.removeAll { $0 == r.id } } else { next.append(r.id) }
                                if next.isEmpty { week.removeValue(forKey:String(weekday)) } else { week[String(weekday)] = next }
                            } label: { ScheduleSelectionRow(title: r.name,selected:ids.contains(r.id),icon:"dumbbell") }.accessibilityIdentifier("weekday-routine-\(r.id)")
                        }
                    } header: { Text(String(format: String(localized: "WORKOUTS_FOR_COUNT", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(describing: names[weekday]))) }
                    Section("WEEK_OVERVIEW") {
                        ForEach([1,2,3,4,5,6,0],id:\.self) { day in
                            let selected = week[String(day)] as? [String] ?? (week[String(day)] as? String).map { [$0] } ?? []
                            HStack { Text(names[day]); Spacer(); Text(selected.compactMap { id in store.routines.first { $0.id == id }?.name }.joined(separator:" + ").isEmpty ? String(localized: "REST", bundle: AppLanguage.bundle, locale: AppLanguage.locale) : selected.compactMap { id in store.routines.first { $0.id == id }?.name }.joined(separator:" + ")).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.trailing) }
                        }
                    }
                } else {
                    Section("CHANGE_DATE") { DatePicker("DATE",selection:$date,displayedComponents:.date).environment(\.locale,AppLanguage.locale).accessibilityIdentifier("schedule-date") }
                    Section {
                        Button { overrides.removeValue(forKey:dayString(date)) } label: { ScheduleSelectionRow(title: String(localized: "BACK_TO_WEEKLY_PLAN", bundle: AppLanguage.bundle, locale: AppLanguage.locale),selected:overrides[dayString(date)] == nil,icon:"arrow.uturn.backward") }.accessibilityIdentifier("restore-weekly")
                        Button { overrides[dayString(date)] = "rest" } label: { ScheduleSelectionRow(title: String(localized: "REST_ON_THIS_DAY", bundle: AppLanguage.bundle, locale: AppLanguage.locale),selected:overrides[dayString(date)] as? String == "rest",icon:"moon") }.accessibilityIdentifier("date-rest")
                        ForEach(store.routines) { r in Button { overrides[dayString(date)] = r.id } label: { ScheduleSelectionRow(title: r.name,selected:overrides[dayString(date)] as? String == r.id,icon:"dumbbell") } }
                    }
                    if !overrides.isEmpty {
                        Section("EXISTING_DATE_OVERRIDES") {
                            ForEach(overrides.keys.sorted(),id:\.self) { day in
                                HStack { Text(day).font(.caption); Spacer(); Text(overrides[day] as? String == "rest" ? String(localized: "REST", bundle: AppLanguage.bundle, locale: AppLanguage.locale) : store.routines.first { $0.id == overrides[day] as? String }?.name ?? String(localized: "UNKNOWN_ROUTINE", bundle: AppLanguage.bundle, locale: AppLanguage.locale)).font(.caption) }
                            }
                        }
                    }
                }
            }.navigationTitle("WORKOUT_SCHEDULE").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement:.topBarLeading) { Button("CANCEL") { if dirty { discard = true } else { dismiss() } }.disabled(store.syncing) }
                    ToolbarItem(placement: .topBarTrailing) { ExplanationButton(title: String(localized: "SCHEDULE", bundle: AppLanguage.bundle, locale: AppLanguage.locale), message: String(localized: "YOU_CAN_SCHEDULE_SEVERAL_ROUTINES_ON_EACH_WEEKDAY_A_DATE_OVERRIDE_AFFECTS", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) }; ToolbarItem(placement:.topBarTrailing) { Button(store.syncing ? String(localized: "SAVING", bundle: AppLanguage.bundle, locale: AppLanguage.locale) : String(localized: "SAVE", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) { Task { if await store.saveSchedule(original:original,proposed:proposed) { dismiss() } else { error = store.editError } } }.disabled(!dirty || store.syncing).accessibilityIdentifier("save-schedule") }
                }
                .onAppear { if !loaded { for key in ["week","dayPlan"] { original[key] = store.state[key] }; week = original["week"] as? [String:Any] ?? [:]; overrides = original["dayPlan"] as? [String:Any] ?? [:]; loaded = true } }
                .alert("COULD_NOT_SAVE",isPresented:Binding(get:{error != nil},set:{if !$0 { error = nil }})) { Button("GOT_IT",role:.cancel) {} } message: { Text(error ?? "") }
                .confirmationDialog("DISCARD_SCHEDULE_CHANGES",isPresented:$discard,titleVisibility:.visible) { Button("DISCARD_CHANGES",role:.destructive) { dismiss() }; Button("KEEP_EDITING",role:.cancel) {} }
                .interactiveDismissDisabled(dirty || store.syncing)
        }.tint(GymTheme.green)
    }
}
