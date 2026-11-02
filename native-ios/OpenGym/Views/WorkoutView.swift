import SwiftUI
struct WorkoutView: View {
    @Environment(GymStore.self) private var store
    @State private var confirmFinish = false
    @State private var confirmDelete = false
    @State private var showWorkoutDetails = false
    @State private var showExerciseNote = false
    @State private var showExercisePicker = false
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let d = store.draft {
                        sessionHeader(d)
                        WorkoutHealthMetrics(draft: d)
                        if !d.rawEntries.isEmpty {
                            let index = min(max(0, d.activeJSON["cur"] as? Int ?? 0), d.rawEntries.count - 1)
                            exerciseCard(d, index: index)
                        } else {
                            Spacer(minLength: 0)
                            emptyWorkout
                            Spacer(minLength: 0)
                        }
                    } else {
                        Text("选择训练计划").font(.system(size: 34, weight: .bold))
                        EmptyCard(icon: "figure.strengthtraining.traditional", title: "准备好开始了吗？", detail: "选择一个训练计划开始训练。")
                        let scheduled = store.scheduledRoutines(on: Date())
                        if !scheduled.isEmpty { GreenButton(title: "开始今日安排", icon: "play.fill") { store.start(scheduled) } }
                        ForEach(store.routines) { r in GreenButton(title: r.name, icon: "play.fill") { store.start(r) } }
                        if store.routines.isEmpty { GreenButton(title: "前往训练计划") { store.selectedTab = 1 } }
                    }
                }.padding(20)
                    .frame(minHeight: store.draft?.rawEntries.isEmpty == true ? geometry.size.height : nil, alignment: .top)
                    .disabled(store.syncing)
            }.scrollDismissesKeyboard(.interactively)
        }
            .sheet(isPresented: $showWorkoutDetails) { WorkoutDetailsEditor() }
            .sheet(isPresented: $showExercisePicker) {
                ExercisePicker(title: "添加动作") { exercise in
                    store.manageLiveExercise(action: "add", index: 0, id: exercise.id)
                    showExercisePicker = false
                }
            }
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
    private var emptyWorkout: some View {
        VStack(spacing: 16) {
            Image(systemName: "dumbbell")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(GymTheme.muted)
                .accessibilityHidden(true)
            Text("请添加第一个训练动作")
                .font(.subheadline)
                .foregroundStyle(GymTheme.muted)
                .multilineTextAlignment(.center)
            Button { showExercisePicker = true } label: {
                Label("添加", systemImage: "plus")
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 24)
                    .frame(minHeight: 48)
                    .background(GymTheme.card, in: RoundedRectangle(cornerRadius: 14))
            }.buttonStyle(.plain)
                .accessibilityLabel("添加训练动作")
                .accessibilityIdentifier("empty-workout-add-exercise")
        }.frame(maxWidth: .infinity)
            .padding(.vertical, 24)
    }
    private func name(_ entry: [String: Any]) -> String { store.exercise(entry["id"] as? String ?? "")?.recordName ?? "自定义动作" }
    private func sessionHeader(_ d: TrainingDraft) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                Text(d.name)
                    .font(.headline).accessibilityIdentifier("live-workout-name-display")
                Spacer(minLength: 8)
                WorkoutDurationLabel(start: d.start)
                LiveExerciseManagement(showExerciseNote: { showExerciseNote = true }) {
                    Section("训练") {
                        Button("训练详情", systemImage: "note.text") { showWorkoutDetails = true }
                            .accessibilityIdentifier("workout-details-menu")
                        Button("保存训练并提交", systemImage: "checkmark.circle") { confirmFinish = true }.disabled(d.completedSets == 0 || store.workTimer != nil).accessibilityIdentifier("finish-workout")
                        Button(role: .destructive) { confirmDelete = true } label: {
                            Label("删除训练", systemImage: "trash")
                        }.accessibilityIdentifier("delete-workout")
                    }
                }
            }
            if let note = d.activeJSON["note"] as? String, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(note).font(.subheadline).foregroundStyle(GymTheme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("live-workout-note-display")
            }
        }
    }
    private func exerciseCard(_ d: TrainingDraft, index e: Int) -> some View {
        let entry = d.rawEntries[e]
        let rows = entry["sets"] as? [[String: Any]] ?? []
        return TrainingExerciseEditor(
            showingOptions: $showExerciseNote, entries: d.rawEntries, names: d.rawEntries.map(name),
            selected: Binding(get: { e }, set: { store.selectLiveEntry($0) }),
            rows: rows.enumerated().map { TrainingEditorRow(id: $0.element["nativeViewID"] as? String ?? "\(d.id)-\(e)-\($0.offset)", raw: $0.element, accessibilityIdentifier: "\(e)-\($0.offset)") },
            unit: d.unit, inputState: store.state.merging(["unit": d.unit]) { _, new in new }, previous: store.previousExerciseText(entry, before: d.start.timeIntervalSince1970 * 1000, exclude: d.id),
            note: Binding(get: { entry["note"] as? String ?? "" }, set: { store.setLiveNote(entry: e, text: $0) }),
            identifier: "live", entryIdentity: "\(d.id)-\(entry["nativeViewID"] as? String ?? String(e))", timerRunning: store.workTimer != nil,
            restUntil: store.restEntry == e ? store.restUntil : nil,
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
        }
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

private struct WorkoutHealthMetrics: View {
    @Environment(GymStore.self) private var store
    let draft: TrainingDraft

    var body: some View {
        // Observe live samples here so a heart-rate update does not rebuild the
        // workout editor or its open menus. Reserve space before samples arrive.
        if store.workoutHealth.enabled {
            WorkoutHealthMetricsContent(report: store.workoutHealth.report(for: draft))
        }
    }
}

struct WorkoutHealthMetricsContent: View {
    let report: HealthWorkoutReport?

    var body: some View {
        HStack(spacing: 12) {
            Text(" ").hidden().frame(maxWidth: .infinity)
                .overlay(alignment: .leading) {
                    if let energy = report?.activeCalories {
                        Label("\(energy, specifier: "%.0f") 活动千卡", systemImage: "flame.fill").foregroundStyle(.orange)
                    }
                }
            Text(" ").hidden().frame(maxWidth: .infinity)
                .overlay(alignment: .leading) {
                    if report?.state == .running, let heart = report?.heartRate {
                        Label("\(heart, specifier: "%.0f") 次/分", systemImage: "heart.fill").foregroundStyle(.red)
                    }
                }
        }.font(.caption.monospacedDigit()).lineLimit(1).minimumScaleFactor(0.5)
            .accessibilityIdentifier("workout-health-metrics")
    }
}

private struct WorkoutDurationLabel: View {
    let start: Date

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "clock").accessibilityHidden(true)
            // Keep the menu anchor's layout independent of per-second timer updates,
            // including minute/hour rollovers and Dynamic Type sizing.
            Text(verbatim: "00:00:00").hidden()
                .overlay(alignment: .trailing) {
                    TimelineView(.periodic(from: start, by: 1)) { context in
                        let elapsed = max(0, Int(context.date.timeIntervalSince(start)))
                        let duration = Duration.seconds(elapsed).formatted(.time(pattern: .hourMinuteSecond))
                        Text(duration)
                            .lineLimit(1).minimumScaleFactor(0.5)
                            .accessibilityLabel("训练时长")
                            .accessibilityValue(duration)
                    }
                }
        }.font(.caption.monospacedDigit()).foregroundStyle(GymTheme.muted)
            .fixedSize()
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("workout-duration")
    }
}

private struct WorkoutDetailsEditor: View {
    @Environment(GymStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("训练标题") {
                    TextField("训练标题", text: Binding(
                        get: { store.draft?.name ?? "" },
                        set: { text in store.changeActive { $0["name"] = text } }
                    )).accessibilityIdentifier("live-workout-name")
                }
                Section("本次训练备注") {
                    TextField("填写备注", text: Binding(
                        get: { store.draft?.activeJSON["note"] as? String ?? "" },
                        set: { text in store.changeActive { $0["note"] = text } }
                    ), axis: .vertical)
                        .lineLimit(3...6).accessibilityIdentifier("live-workout-note")
                }
            }.navigationTitle("训练详情").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }.presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
            .onChange(of: store.draft?.id) { _, _ in dismiss() }
    }
}
