import SwiftUI
struct WorkoutView: View {
    @Environment(GymStore.self) private var store
    @State private var confirmFinish = false
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
                        HStack {
                            Button { store.selectLiveEntry(index - 1) } label: { Label("上一个", systemImage: "chevron.left").frame(minHeight: 48) }.disabled(index == 0)
                            Spacer()
                            Button { store.selectLiveEntry(index + 1) } label: { Label("下一个", systemImage: "chevron.right").frame(minHeight: 48) }.disabled(index == d.rawEntries.count - 1)
                        }
                    }
                    Text("输入自动保存到本机。右上角菜单可保存训练并提交；提交失败后保留草稿，可重复提交。").font(.caption).foregroundStyle(GymTheme.muted)
                } else {
                    Text("开始训练").font(.system(size: 34, weight: .bold))
                    EmptyCard(icon: "figure.strengthtraining.traditional", title: "准备好开始了吗？", detail: "选择计划，按目标逐组训练。")
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
            .task { while !Task.isCancelled { store.settleTimer(); try? await Task.sleep(for: .seconds(1)) } }
    }
    private func name(_ entry: [String: Any]) -> String { store.exercise(entry["id"] as? String ?? "")?.recordName ?? "自定义动作" }
    private func status(_ entry: [String: Any]) -> String {
        let rows = entry["sets"] as? [[String: Any]] ?? []
        if !rows.isEmpty && rows.allSatisfy({ $0["done"] as? Bool == true }) { return "已练" }
        return rows.contains(where: rawCompleted) ? "进行中" : "待练"
    }
    private func sessionHeader(_ d: TrainingDraft) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                if !d.rawEntries.isEmpty {
                    let i = min(max(0, d.activeJSON["cur"] as? Int ?? 0), d.rawEntries.count - 1)
                    Menu {
                        ForEach(d.rawEntries.indices, id: \.self) { index in
                            Button("\(index + 1).\(name(d.rawEntries[index]))") { store.selectLiveEntry(index) }
                        }
                    } label: {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) { Text("\(i + 1).\(name(d.rawEntries[i]))").font(.headline); Text("\(status(d.rawEntries[i])) · \(i + 1) / \(d.rawEntries.count)").font(.caption).foregroundStyle(GymTheme.green) }
                            Image(systemName: "chevron.down").font(.caption)
                        }.frame(minHeight: 48).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier("live-exercise-selector")
                }
                Spacer(minLength: 8)
                Menu {
                    Button("保存训练并提交") { confirmFinish = true }.disabled(d.completedSets == 0 || store.workTimer != nil).accessibilityIdentifier("finish-workout")
                    Button("保存到本机") { store.persistDraft() }
                } label: { Image(systemName: "ellipsis.circle").font(.title2).frame(width: 48, height: 48) }.accessibilityLabel("训练菜单")
            }
            HStack { Text(d.name).lineLimit(1); Spacer(); Text(d.start, style: .timer).monospacedDigit() }.font(.caption).foregroundStyle(GymTheme.muted)
        }
    }
    private func exerciseCard(_ d: TrainingDraft, index e: Int) -> some View {
        let entry = d.rawEntries[e]
        let rows = entry["sets"] as? [[String: Any]] ?? []
        return VStack(alignment: .leading, spacing: 16) {
            if let timer = store.workTimer, timer["entry"] as? Int == e { timerCard(timer) }
            if let until = store.restUntil, store.restEntry == e { restCard(until) }
            HStack { ExerciseThumbnail(id: entry["id"] as? String ?? "", size: 48); Text("\(e + 1).\(name(entry))").font(.headline); Spacer(); Button { store.selectedExercise = store.exercise(entry["id"] as? String ?? "") } label: { Image(systemName: "info.circle").frame(width: 44, height: 44) }.accessibilityLabel("动作详情") }
            if let note = (entry["target"] as? [String: Any])?["note"] as? String, !note.isEmpty { Text(note).font(.caption).foregroundStyle(GymTheme.muted) }
            if entry["sg"] != nil { Label("超级组", systemImage: "link").font(.caption).foregroundStyle(GymTheme.green) }
            ScrollView(.horizontal, showsIndicators: false) {
                Text(store.previousExerciseText(entry, before: d.start.timeIntervalSince1970 * 1000, exclude: d.id)).font(.caption).foregroundStyle(GymTheme.muted).lineLimit(1).fixedSize(horizontal: true, vertical: false)
            }.accessibilityIdentifier("previous-exercise")
            TextField("本次动作备注", text: Binding(get: { entry["note"] as? String ?? "" }, set: { store.setLiveNote(entry: e, text: $0) }), axis: .vertical).font(.subheadline).accessibilityIdentifier("live-exercise-note")
            ForEach(rows.indices, id: \.self) { s in
                VStack(alignment: .leading, spacing: 8) {
                    Text("第 \(s + 1) 组").font(.caption).foregroundStyle(GymTheme.muted)
                    AdvancedSetEditor(row: rows[s], target: entry["target"] as? [String: Any] ?? [:], unit: d.unit, identifier: "\(e)-\(s)", timerRunning: store.workTimer != nil, startTimer: { store.startWorkTimer(entry: e, set: s) }, startRest: { store.startRest(entry: e, seconds: $0) }) { store.liveRowAction(entry: e, set: s, action: $0) }
                }
                if s < rows.count - 1 { Divider() }
            }
            Button { store.addLiveSet(entry: e) } label: { Label("添加一组", systemImage: "plus").font(.subheadline).frame(maxWidth: .infinity, minHeight: 44) }.disabled(store.workTimer != nil)
        }.gymCard().id(e)
    }
    private func restCard(_ until: Date) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let seconds = max(0, Int(ceil(until.timeIntervalSince(context.date))))
            HStack { Label(seconds > 0 ? "组间休息" : "休息结束", systemImage: "timer"); Spacer(); Text(String(format: "%02d:%02d", seconds / 60, seconds % 60)).monospacedDigit(); Button("跳过") { store.restUntil = nil }.frame(minHeight: 44) }.font(.subheadline).foregroundStyle(GymTheme.green)
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
