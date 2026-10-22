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
    private let names = ["周日","周一","周二","周三","周四","周五","周六"]
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
                    Picker("排期类型",selection:$tab) { Text("每周计划").tag(0); Text("单日调整").tag(1) }.pickerStyle(.segmented).accessibilityIdentifier("schedule-mode")
                    if store.state["queue"] as? [String:Any] != nil { Text("已有循环或教练排期，首页会按网页规则合并显示；这里编辑每周安排和单日覆盖。").font(.caption).foregroundStyle(.secondary) }
                }
                if tab == 0 {
                    Section("选择星期") {
                        Picker("星期",selection:$weekday) { ForEach([1,2,3,4,5,6,0],id:\.self) { Text(names[$0]).tag($0) } }.pickerStyle(.menu).accessibilityIdentifier("schedule-weekday")
                    }
                    Section {
                        Button { week.removeValue(forKey:String(weekday)) } label: { selectionRow("休息日",selected:ids.isEmpty,icon:"moon") }
                        ForEach(store.routines) { r in
                            Button {
                                var next = ids
                                if next.contains(r.id) { next.removeAll { $0 == r.id } } else { next.append(r.id) }
                                if next.isEmpty { week.removeValue(forKey:String(weekday)) } else { week[String(weekday)] = next }
                            } label: { selectionRow(r.name,selected:ids.contains(r.id),icon:"dumbbell") }.accessibilityIdentifier("weekday-routine-\(r.id)")
                        }
                    } header: { Text("\(names[weekday])的训练") } footer: { Text("可以选择多个计划，首页可一起开始训练。每周重复，不影响已有的单日调整。") }
                    Section("一周概览") {
                        ForEach([1,2,3,4,5,6,0],id:\.self) { day in
                            let selected = week[String(day)] as? [String] ?? (week[String(day)] as? String).map { [$0] } ?? []
                            HStack { Text(names[day]); Spacer(); Text(selected.compactMap { id in store.routines.first { $0.id == id }?.name }.joined(separator:" + ").isEmpty ? "休息" : selected.compactMap { id in store.routines.first { $0.id == id }?.name }.joined(separator:" + ")).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.trailing) }
                        }
                    }
                } else {
                    Section("调整日期") { DatePicker("日期",selection:$date,displayedComponents:.date).environment(\.locale,Locale(identifier:"zh_CN")).accessibilityIdentifier("schedule-date") }
                    Section {
                        Button { overrides.removeValue(forKey:dayString(date)) } label: { selectionRow("恢复每周计划",selected:overrides[dayString(date)] == nil,icon:"arrow.uturn.backward") }.accessibilityIdentifier("restore-weekly")
                        Button { overrides[dayString(date)] = "rest" } label: { selectionRow("这一天休息",selected:overrides[dayString(date)] as? String == "rest",icon:"moon") }.accessibilityIdentifier("date-rest")
                        ForEach(store.routines) { r in Button { overrides[dayString(date)] = r.id } label: { selectionRow(r.name,selected:overrides[dayString(date)] as? String == r.id,icon:"dumbbell") } }
                    } footer: { Text("只改变所选日期，每周安排保持不变。单日最多指定一个计划，与网页版一致。") }
                    if !overrides.isEmpty {
                        Section("已有单日调整") {
                            ForEach(overrides.keys.sorted(),id:\.self) { day in
                                HStack { Text(day).font(.caption); Spacer(); Text(overrides[day] as? String == "rest" ? "休息" : store.routines.first { $0.id == overrides[day] as? String }?.name ?? "未知计划").font(.caption) }
                            }
                        }
                    }
                }
            }.navigationTitle("训练排期").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement:.topBarLeading) { Button("取消") { if dirty { discard = true } else { dismiss() } }.disabled(store.syncing) }
                    ToolbarItem(placement:.topBarTrailing) { Button(store.syncing ? "保存中…" : "保存") { Task { if await store.saveSchedule(original:original,proposed:proposed) { dismiss() } else { error = store.editError } } }.disabled(!dirty || store.syncing).accessibilityIdentifier("save-schedule") }
                }
                .onAppear { if !loaded { for key in ["week","dayPlan"] { original[key] = store.state[key] }; week = original["week"] as? [String:Any] ?? [:]; overrides = original["dayPlan"] as? [String:Any] ?? [:]; loaded = true } }
                .alert("无法保存",isPresented:Binding(get:{error != nil},set:{if !$0 { error = nil }})) { Button("知道了",role:.cancel) {} } message: { Text(error ?? "") }
                .confirmationDialog("放弃排期修改？",isPresented:$discard,titleVisibility:.visible) { Button("放弃修改",role:.destructive) { dismiss() }; Button("继续编辑",role:.cancel) {} }
                .interactiveDismissDisabled(dirty || store.syncing)
        }.tint(GymTheme.green)
    }
    private func selectionRow(_ text:String,selected:Bool,icon:String) -> some View {
        HStack { Label(text,systemImage:icon).foregroundStyle(.primary); Spacer(); Image(systemName:selected ? "checkmark.circle.fill" : "circle").foregroundStyle(selected ? GymTheme.green : .gray) }
    }
}
