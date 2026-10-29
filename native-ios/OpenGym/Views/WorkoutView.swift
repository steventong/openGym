import SwiftUI
struct WorkoutView: View {
    @Environment(GymStore.self) private var store
    @State private var confirmFinish = false
    @State private var confirmDelete = false
    @State private var showNote = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let d = store.draft {
                    sessionHeader(d)
                    let info = (try? WebRules.shared.call("sessionInfo", payload: ["active": d.activeJSON])) as? [String: Any] ?? [:]
                    ProgressView(value: number(info["done"]), total: max(1, number(info["total"]))).tint(GymTheme.green)
                    if !d.rawEntries.isEmpty {
                        let index = min(max(0, d.activeJSON["cur"] as? Int ?? 0), d.rawEntries.count - 1)
                        exerciseCard(d, index: index)
                    }
                    Text("输入自动保存到本机。右上角菜单可保存训练并提交；提交失败后保留草稿，可重复提交。").font(.caption).foregroundStyle(GymTheme.muted)
                } else {
                    Text("开始训练").font(.system(size: 34, weight: .bold))
                    EmptyCard(icon: "figure.strengthtraining.traditional", title: "准备好开始了吗？", detail: "选择训练计划，或开始自由训练，边练边添加动作。")
                    GreenButton(title: "自由训练", icon: "figure.strengthtraining.traditional") { store.startFreestyle() }
                        .accessibilityIdentifier("start-freestyle-workout")
                    let scheduled = store.scheduledRoutines(on: Date())
                    if !scheduled.isEmpty { GreenButton(title: "开始今日安排", icon: "play.fill") { store.start(scheduled) } }
                    ForEach(store.routines) { r in GreenButton(title: r.name, icon: "play.fill") { store.start(r) } }
                    if store.routines.isEmpty { GreenButton(title: "前往训练计划") { store.selectedTab = 1 } }
                }
            }.padding(20).disabled(store.syncing)
        }.scrollDismissesKeyboard(.interactively)
            .confirmationDialog("保存训练并提交？", isPresented: $confirmFinish, titleVisibility: .visible) {
                Button("保存并提交") { Task { await store.finish() } }
                Button("继续训练", role: .cancel) {}
            }
            .confirmationDialog("删除本次训练？", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("删除训练", role: .destructive) { store.deleteCurrentWorkout() }.disabled(store.syncing)
                Button("继续训练", role: .cancel) {}
            } message: {
                Text("将清除本次训练的本机草稿并停止计时，无法撤销。已提交的历史记录和训练计划不受影响。")
            }
            .task { while !Task.isCancelled { store.settleTimer(); try? await Task.sleep(for: .seconds(1)) } }
    }
    private func name(_ entry: [String: Any]) -> String { store.exercise(entry["id"] as? String ?? "")?.recordName ?? "自定义动作" }
    private func sessionHeader(_ d: TrainingDraft) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                TextField("训练名称", text: Binding(get: { d.name }, set: { text in store.changeActive { $0["name"] = text } }))
                    .font(.headline).accessibilityIdentifier("live-workout-name")
                Spacer(minLength: 8)
                LiveExerciseManagement()
                Menu {
                    Button(showNote ? "收起训练备注" : "训练备注", systemImage: "note.text") { showNote.toggle() }
                    Button("保存训练并提交") { confirmFinish = true }.disabled(d.completedSets == 0 || store.workTimer != nil).accessibilityIdentifier("finish-workout")
                    Button(role: .destructive) { confirmDelete = true } label: {
                        Label("删除训练", systemImage: "trash")
                    }.accessibilityIdentifier("delete-workout")
                } label: { Image(systemName: "ellipsis.circle").font(.title2).frame(width: 48, height: 48) }.accessibilityLabel("训练菜单")
            }
            HStack { Text("训练时长"); Spacer(); Text(d.start, style: .timer).monospacedDigit() }.font(.caption).foregroundStyle(GymTheme.muted)
            if showNote {
                TextField("本次训练备注", text: Binding(get: { d.activeJSON["note"] as? String ?? "" }, set: { text in store.changeActive { $0["note"] = text } }), axis: .vertical)
                .font(.subheadline).accessibilityIdentifier("live-workout-note")
            }
        }
    }
    private func exerciseCard(_ d: TrainingDraft, index e: Int) -> some View {
        let entry = d.rawEntries[e]
        let rows = entry["sets"] as? [[String: Any]] ?? []
        return TrainingExerciseEditor(
            entries: d.rawEntries, names: d.rawEntries.map(name),
            selected: Binding(get: { e }, set: { store.selectLiveEntry($0) }),
            rows: rows.enumerated().map { TrainingEditorRow(id: "\(e)-\($0.offset)", raw: $0.element) },
            unit: d.unit, inputState: store.state.merging(["unit": d.unit]) { _, new in new }, previous: store.previousExerciseText(entry, before: d.start.timeIntervalSince1970 * 1000, exclude: d.id),
            note: Binding(get: { entry["note"] as? String ?? "" }, set: { store.setLiveNote(entry: e, text: $0) }),
            identifier: "live", timerRunning: store.workTimer != nil,
            startTimer: { store.startWorkTimer(entry: e, set: $0) },
            startRest: { store.startRest(entry: e, seconds: $1, set: $0) },
            showDetails: { store.selectedExercise = store.exercise(entry["id"] as? String ?? "") },
            addSet: { store.addLiveSet(entry: e) },
            copySet: { store.copyLiveSet(entry: e, set: $0) },
            removeSet: { store.removeLiveSet(entry: e, set: $0) },
            editSet: { store.liveRowAction(entry: e, set: $0, action: $1) },
            undoRemove: store.canUndoSetRemoval ? { store.undoSetRemoval() } : nil
        ) {
            if let timer = store.workTimer, timer["entry"] as? Int == e { timerCard(timer) }
            if let until = store.restUntil, store.restEntry == e { restCard(until) }

        }
    }
    private func restCard(_ until: Date) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let seconds = max(0, Int(ceil(until.timeIntervalSince(context.date))))
            VStack(spacing: 6) {
                HStack { Label(seconds > 0 ? "组间休息" : "休息结束", systemImage: "timer"); Spacer(); Text(String(format: "%02d:%02d", seconds / 60, seconds % 60)).monospacedDigit() }
                HStack {
                    Button("−15 秒") { store.adjustRest(by: -15) }.accessibilityIdentifier("rest-minus")
                    Spacer()
                    Button("+15 秒") { store.adjustRest(by: 15) }.accessibilityIdentifier("rest-plus")
                    Spacer()
                    Button("跳过") { store.restUntil = nil }
                }.frame(minHeight: 44)
            }.font(.subheadline).foregroundStyle(GymTheme.green)
        }.accessibilityIdentifier("card-rest-timer")
    }
    private func timerCard(_ timer: [String: Any]) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { c in
            let paused = timer["paused"] as? Bool == true
            let sec = max(0, Int(ceil(paused ? number(timer["remaining"]) : number(timer["end"]) - c.date.timeIntervalSince1970)))
            VStack(spacing: 12) {
                HStack { Label(paused ? "计时已暂停" : "动作计时", systemImage: "stopwatch"); Spacer(); Text(String(format: "%02d:%02d", sec / 60, sec % 60)).font(.title2.monospacedDigit()) }
                HStack { Button(paused ? "继续" : "暂停") { store.pauseWorkTimer() }; Spacer(); Button("提前完成") { store.finishWorkTimer() }; Button("取消", role: .cancel) { store.finishWorkTimer(cancel: true) } }.font(.subheadline)
            }.foregroundStyle(GymTheme.green).accessibilityIdentifier("work-timer")
        }
    }
}
