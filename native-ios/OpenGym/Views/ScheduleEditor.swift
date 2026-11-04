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
    private let names = [L10n.text("SUN" /* 周日 */),L10n.text("MON" /* 周一 */),L10n.text("TUE" /* 周二 */),L10n.text("WED" /* 周三 */),L10n.text("THU" /* 周四 */),L10n.text("FRI" /* 周五 */),L10n.text("SAT" /* 周六 */)]
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
                    Picker(L10n.text("SCHEDULE_TYPE" /* 排期类型 */),selection:$tab) { Text(L10n.text("WEEKLY_SCHEDULE" /* 每周计划 */)).tag(0); Text(L10n.text("DATE_OVERRIDE" /* 单日调整 */)).tag(1) }.pickerStyle(.segmented).accessibilityIdentifier("schedule-mode")
                }
                if tab == 0 {
                    Section(L10n.text("CHOOSE_WEEKDAY" /* 选择星期 */)) {
                        Picker(L10n.text("DAY" /* 星期 */),selection:$weekday) { ForEach([1,2,3,4,5,6,0],id:\.self) { Text(names[$0]).tag($0) } }.pickerStyle(.menu).accessibilityIdentifier("schedule-weekday")
                    }
                    Section {
                        Button { week.removeValue(forKey:String(weekday)) } label: { selectionRow(L10n.text("REST_DAY" /* 休息日 */),selected:ids.isEmpty,icon:"moon") }
                        ForEach(store.routines) { r in
                            Button {
                                var next = ids
                                if next.contains(r.id) { next.removeAll { $0 == r.id } } else { next.append(r.id) }
                                if next.isEmpty { week.removeValue(forKey:String(weekday)) } else { week[String(weekday)] = next }
                            } label: { selectionRow(r.name,selected:ids.contains(r.id),icon:"dumbbell") }.accessibilityIdentifier("weekday-routine-\(r.id)")
                        }
                    } header: { Text(L10n.text("WORKOUTS_FOR_COUNT" /* {0}的训练 */, names[weekday])) }
                    Section(L10n.text("WEEK_OVERVIEW" /* 一周概览 */)) {
                        ForEach([1,2,3,4,5,6,0],id:\.self) { day in
                            let selected = week[String(day)] as? [String] ?? (week[String(day)] as? String).map { [$0] } ?? []
                            HStack { Text(names[day]); Spacer(); Text(selected.compactMap { id in store.routines.first { $0.id == id }?.name }.joined(separator:" + ").isEmpty ? L10n.text("REST" /* 休息 */) : selected.compactMap { id in store.routines.first { $0.id == id }?.name }.joined(separator:" + ")).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.trailing) }
                        }
                    }
                } else {
                    Section(L10n.text("CHANGE_DATE" /* 调整日期 */)) { DatePicker(L10n.text("DATE" /* 日期 */),selection:$date,displayedComponents:.date).environment(\.locale,L10n.locale).accessibilityIdentifier("schedule-date") }
                    Section {
                        Button { overrides.removeValue(forKey:dayString(date)) } label: { selectionRow(L10n.text("BACK_TO_WEEKLY_PLAN" /* 恢复每周计划 */),selected:overrides[dayString(date)] == nil,icon:"arrow.uturn.backward") }.accessibilityIdentifier("restore-weekly")
                        Button { overrides[dayString(date)] = "rest" } label: { selectionRow(L10n.text("REST_ON_THIS_DAY" /* 这一天休息 */),selected:overrides[dayString(date)] as? String == "rest",icon:"moon") }.accessibilityIdentifier("date-rest")
                        ForEach(store.routines) { r in Button { overrides[dayString(date)] = r.id } label: { selectionRow(r.name,selected:overrides[dayString(date)] as? String == r.id,icon:"dumbbell") } }
                    }
                    if !overrides.isEmpty {
                        Section(L10n.text("EXISTING_DATE_OVERRIDES" /* 已有单日调整 */)) {
                            ForEach(overrides.keys.sorted(),id:\.self) { day in
                                HStack { Text(day).font(.caption); Spacer(); Text(overrides[day] as? String == "rest" ? L10n.text("REST" /* 休息 */) : store.routines.first { $0.id == overrides[day] as? String }?.name ?? L10n.text("UNKNOWN_ROUTINE" /* 未知计划 */)).font(.caption) }
                            }
                        }
                    }
                }
            }.navigationTitle(L10n.text("WORKOUT_SCHEDULE" /* 训练排期 */)).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement:.topBarLeading) { Button(L10n.text("CANCEL" /* 取消 */)) { if dirty { discard = true } else { dismiss() } }.disabled(store.syncing) }
                    ToolbarItem(placement: .topBarTrailing) { ExplanationButton(title: L10n.text("SCHEDULE" /* 训练安排 */), message: L10n.text("YOU_CAN_SCHEDULE_SEVERAL_ROUTINES_ON_EACH_WEEKDAY_A_DATE_OVERRIDE_AFFECTS" /* 每周计划支持多选。单日调整仅影响所选日期，每周安排与已有循环保留。 */)) }; ToolbarItem(placement:.topBarTrailing) { Button(store.syncing ? L10n.text("SAVING" /* 正在保存 */) : L10n.text("SAVE" /* 保存 */)) { Task { if await store.saveSchedule(original:original,proposed:proposed) { dismiss() } else { error = store.editError } } }.disabled(!dirty || store.syncing).accessibilityIdentifier("save-schedule") }
                }
                .onAppear { if !loaded { for key in ["week","dayPlan"] { original[key] = store.state[key] }; week = original["week"] as? [String:Any] ?? [:]; overrides = original["dayPlan"] as? [String:Any] ?? [:]; loaded = true } }
                .alert(L10n.text("COULD_NOT_SAVE" /* 无法保存 */),isPresented:Binding(get:{error != nil},set:{if !$0 { error = nil }})) { Button(L10n.text("GOT_IT" /* 知道了 */),role:.cancel) {} } message: { Text(error ?? "") }
                .confirmationDialog(L10n.text("DISCARD_SCHEDULE_CHANGES" /* 放弃排期修改？ */),isPresented:$discard,titleVisibility:.visible) { Button(L10n.text("DISCARD_CHANGES" /* 放弃修改 */),role:.destructive) { dismiss() }; Button(L10n.text("KEEP_EDITING" /* 继续编辑 */),role:.cancel) {} }
                .interactiveDismissDisabled(dirty || store.syncing)
        }.tint(GymTheme.green)
    }
    private func selectionRow(_ text:String,selected:Bool,icon:String) -> some View {
        HStack { Label(text,systemImage:icon).foregroundStyle(.primary); Spacer(); Image(systemName:selected ? "checkmark.circle.fill" : "circle").foregroundStyle(selected ? GymTheme.green : .gray) }
    }
}
