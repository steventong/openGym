import SwiftUI
struct WorkoutView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(GymStore.self) private var store
    @State private var confirmFinish = false
    @State private var confirmDelete = false
    @State private var showWorkoutDetails = false
    @State private var showExerciseNote = false
    @State private var showExercisePicker = false
    @State private var exerciseOrderDraft: TrainingDraft?
    var body: some View {
        NavigationStack {
            workoutContent
                .navigationTitle(store.draft?.name ?? L10n.text("CHOOSE_A_ROUTINE" /* 选择训练计划 */))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if let d = store.draft {
                        ToolbarItem(placement: .principal) {
                            VStack(spacing: 2) {
                                Text(d.name)
                                    .font(.headline).lineLimit(1)
                                    .accessibilityIdentifier("live-workout-name-display")
                                HStack(spacing: 10) {
                                    WorkoutDurationLabel(start: d.start)
                                    if !d.rawEntries.isEmpty {
                                        let index = min(max(0, d.activeJSON["cur"] as? Int ?? 0), d.rawEntries.count - 1)
                                        ExercisePositionLabel(index: index, count: d.rawEntries.count)
                                            .accessibilityIdentifier("live-entry-position")
                                    }
                                }.font(.caption.monospacedDigit()).foregroundStyle(GymTheme.muted)
                            }
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            workoutMenu(d)
                        }
                        if d.allSetsCompleted {
                            ToolbarItem(placement: .topBarLeading) {
                                Button(L10n.text("SAVE_WORKOUT" /* 保存训练 */)) { confirmFinish = true }
                                    .disabled(store.workTimer != nil)
                                    .accessibilityIdentifier("save-completed-workout")
                            }
                        }
                    }
                    if store.localSaveError != nil {
                        ToolbarItem(placement: .topBarLeading) {
                            LocalSaveIssueIndicator()
                        }
                    }
                }
        }
        .environment(\.inputCommitBuffer, store.liveInputBuffer)
        .onChange(of: scenePhase) { _, phase in if phase != .active { store.liveInputBuffer.commitAll() } }
        .onDisappear { store.liveInputBuffer.commitAll() }
    }
    private var workoutContent: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let d = store.draft {
                        if let note = d.activeJSON["note"] as? String, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(note).font(.subheadline).foregroundStyle(GymTheme.muted)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .accessibilityIdentifier("live-workout-note-display")
                        }
                        // Keep health metrics off the phone page until their layout is settled.
                        if !d.rawEntries.isEmpty {
                            let index = min(max(0, d.activeJSON["cur"] as? Int ?? 0), d.rawEntries.count - 1)
                            exerciseCard(d, index: index)
                        } else {
                            Spacer(minLength: 0)
                            emptyWorkout
                            Spacer(minLength: 0)
                        }
                    } else {
                        EmptyCard(icon: "figure.strengthtraining.traditional", title: L10n.text("START_WORKOUT" /* 开始训练 */))
                        GreenButton(title: L10n.text("FREESTYLE" /* 自由训练 */), icon: "figure.strengthtraining.traditional") { store.startFreestyle() }
                            .accessibilityIdentifier("start-freestyle-workout")
                        let scheduled = store.scheduledRoutines(on: Date())
                        if !scheduled.isEmpty { GreenButton(title: L10n.text("START_TODAY_S_WORKOUTS" /* 开始今日安排 */), icon: "play.fill") { store.start(scheduled) } }
                        ForEach(store.routines) { r in GreenButton(title: r.name, icon: "play.fill") { store.start(r) } }
                        if store.routines.isEmpty { GreenButton(title: L10n.text("GO_TO_ROUTINES" /* 前往训练计划 */)) { store.selectedTab = 1 } }
                    }
                }.padding(20)
                    .frame(minHeight: store.draft?.rawEntries.isEmpty == true ? geometry.size.height : nil, alignment: .top)
            }.scrollDismissesKeyboard(.interactively)
                .modifier(TrainingExercisePaging(selected: store.draft?.activeJSON["cur"] as? Int ?? 0,
                    names: store.draft?.rawEntries.map(name) ?? [], select: store.selectLiveEntry))
                .keyboardDismissToolbar()
        }
            .sheet(isPresented: $showWorkoutDetails) { WorkoutDetailsEditor() }
            .sheet(isPresented: $showExercisePicker) {
                ExercisePicker(title: L10n.text("ADD_EXERCISE" /* 添加动作 */)) { exercise in
                    store.manageLiveExercise(action: "add", index: 0, id: exercise.id)
                    showExercisePicker = false
                }
            }
            .sheet(item: $exerciseOrderDraft) { draft in
                ExerciseOrderSheet(entries: draft.rawEntries) { order, baseline in
                    try store.reorderLiveExercises(order, expectedEntries: baseline, sessionID: draft.id)
                }
            }
            .confirmationDialog(L10n.text("SAVE_AND_SUBMIT_WORKOUT" /* 保存训练并提交？ */), isPresented: $confirmFinish, titleVisibility: .visible) {
                Button(L10n.text("SAVE_AND_SUBMIT" /* 保存并提交 */)) { Task { await store.finish() } }
                Button(L10n.text("CONTINUE_WORKOUT" /* 继续训练 */), role: .cancel) {}
            }
            .confirmationDialog(L10n.text("DELETE_THIS_WORKOUT" /* 删除训练记录？ */), isPresented: $confirmDelete, titleVisibility: .visible) {
                Button(L10n.text("DELETE_WORKOUT_A" /* 删除训练 */), role: .destructive) { store.deleteCurrentWorkout() }
                Button(L10n.text("CONTINUE_WORKOUT" /* 继续训练 */), role: .cancel) {}
            } message: {
                Text(L10n.text("THE_LOCAL_DRAFT_WILL_BE_DELETED_AND_ITS_TIMER_STOPPED_THIS_CANNOT" /* 将清除本次训练的本机草稿并停止计时，无法撤销。已提交的历史记录和训练计划不受影响。 */))
            }
            .task { while !Task.isCancelled { store.settleTimer(); try? await Task.sleep(for: .seconds(1)) } }
    }
    private var emptyWorkout: some View {
        VStack(spacing: 16) {
            Image(systemName: "dumbbell")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(GymTheme.muted)
                .accessibilityHidden(true)
            Text(L10n.text("NO_EXERCISES_YET" /* 还没有动作。 */))
                .font(.subheadline)
                .foregroundStyle(GymTheme.muted)
                .multilineTextAlignment(.center)
            Button { showExercisePicker = true } label: {
                Label(L10n.text("ADD" /* 添加 */), systemImage: "plus")
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 24)
                    .frame(minHeight: 48)
                    .background(GymTheme.card, in: RoundedRectangle(cornerRadius: 14))
            }.buttonStyle(.plain)
                .accessibilityLabel(L10n.text("ADD_WORKOUT_EXERCISE" /* 添加训练动作 */))
                .accessibilityIdentifier("empty-workout-add-exercise")
        }.frame(maxWidth: .infinity)
            .padding(.vertical, 24)
    }
    private func name(_ entry: [String: Any]) -> String { store.exercise(entry["id"] as? String ?? "")?.recordName ?? L10n.text("CUSTOM_EXERCISE" /* 自定义动作 */) }
    private func workoutMenu(_ d: TrainingDraft) -> some View {
        Menu {
            Section {
                Button(L10n.text("ADD_EXERCISE" /* 添加动作 */), systemImage: "plus") { store.liveInputBuffer.commitAll(); showExercisePicker = true }
                    .accessibilityIdentifier("add-workout-exercise")
                Button(L10n.text("REORDER_EXERCISES" /* 调整动作顺序 */), systemImage: "arrow.up.arrow.down") { store.liveInputBuffer.commitAll(); exerciseOrderDraft = store.draft }
                    .disabled(d.rawEntries.count < 2).accessibilityIdentifier("reorder-exercises")
            }
            Section(L10n.text("WORKOUT" /* 训练 */)) {
                Button(L10n.text("WORKOUT_DETAILS" /* 训练详情 */), systemImage: "note.text") { store.liveInputBuffer.commitAll(); showWorkoutDetails = true }
                    .accessibilityIdentifier("workout-details-menu")
                Button(L10n.text("SAVE_AND_SUBMIT_WORKOUT_A" /* 保存训练并提交 */), systemImage: "checkmark.circle") { confirmFinish = true }
                    .disabled(d.completedSets == 0 || store.workTimer != nil).accessibilityIdentifier("finish-workout")
                Button(role: .destructive) { confirmDelete = true } label: {
                    Label(L10n.text("DELETE_WORKOUT_A" /* 删除训练 */), systemImage: "trash")
                }.accessibilityIdentifier("delete-workout")
            }
        } label: {
            Label(L10n.text("WORKOUT_MENU" /* 训练菜单 */), systemImage: "ellipsis")
        }.accessibilityIdentifier("workout-menu")
    }
    private func exerciseCard(_ d: TrainingDraft, index e: Int) -> some View {
        let entry = d.rawEntries[e]
        let rows = entry["sets"] as? [[String: Any]] ?? []
        let previous = store.previousExerciseReference(entry, before: d.start.timeIntervalSince1970 * 1000, exclude: d.id)
        return TrainingExerciseEditor(
            showingOptions: $showExerciseNote, entries: d.rawEntries, names: d.rawEntries.map(name),
            selected: Binding(get: { e }, set: { store.selectLiveEntry($0) }),
            rows: rows.enumerated().map { TrainingEditorRow(id: $0.element["nativeViewID"] as? String ?? "\(d.id)-\(e)-\($0.offset)", raw: $0.element, accessibilityIdentifier: "\(e)-\($0.offset)") },
            unit: d.unit, inputState: store.state.merging(["unit": d.unit]) { _, new in new }, previous: previous.text, previousNote: previous.note,
            note: Binding(get: { entry["note"] as? String ?? "" }, set: { store.setLiveNote(entry: e, text: $0) }),
            identifier: "live", showsEntryPosition: false, entryIdentity: "\(d.id)-\(entry["nativeViewID"] as? String ?? String(e))", timerRunning: store.workTimer != nil,
            restUntil: store.restEntry == e ? store.restUntil : nil,
            startTimer: { store.startWorkTimer(entry: e, set: $0) },
            startRest: { store.startRest(entry: e, seconds: $1, set: $0) },
            showDetails: { store.selectedExercise = store.exercise(entry["id"] as? String ?? "") },
            addSet: { store.addLiveSet(entry: e) },
            copySet: { store.copyLiveSet(entry: e, set: $0) },
            removeSet: { store.removeLiveSet(entry: e, set: $0) },
            editSet: { store.liveRowAction(entry: e, set: $0, action: $1) },
            undoRemove: store.canUndoSetRemoval ? { store.undoSetRemoval() } : nil,
            exerciseActions: { LiveExerciseManagement(showExerciseNote: { store.liveInputBuffer.commitAll(); showExerciseNote = true }) }
        ) {
            if let timer = store.workTimer, timer["entry"] as? Int == e { timerCard(timer) }
        }
    }
    private func timerCard(_ timer: [String: Any]) -> some View {
        let paused = timer["paused"] as? Bool == true
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(paused ? L10n.text("TIMER_PAUSED" /* 计时已暂停 */) : L10n.text("EXERCISE_TIMER" /* 动作计时 */), systemImage: "stopwatch")
                Spacer()
                TrainingCountdownText(end: Date(timeIntervalSince1970: number(timer["end"])),
                    pausedRemaining: paused ? number(timer["remaining"]) : nil)
                    .font(.title2.monospacedDigit()).frame(width: 84, alignment: .trailing)
            }
            HStack {
                Button(paused ? L10n.text("RESUME" /* 继续 */) : L10n.text("PAUSE" /* 暂停 */)) { store.pauseWorkTimer() }
                Spacer()
                Button(L10n.text("FINISH_EARLY_A" /* 提前完成 */)) { store.finishWorkTimer() }
                Button(L10n.text("CANCEL" /* 取消 */), role: .cancel) { store.finishWorkTimer(cancel: true) }
            }.font(.subheadline)
        }.foregroundStyle(GymTheme.green).accessibilityIdentifier("work-timer")
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
                        Label(L10n.text("COUNT_ACTIVE_KCAL" /* {0} 活动千卡 */, String(format: "%.0f", energy)), systemImage: "flame.fill").foregroundStyle(.orange)
                    }
                }
            Text(" ").hidden().frame(maxWidth: .infinity)
                .overlay(alignment: .leading) {
                    if report?.state == .running, let heart = report?.heartRate {
                        Label(L10n.text("COUNT_BPM" /* {0} 次/分 */, String(format: "%.0f", heart)), systemImage: "heart.fill").foregroundStyle(.red)
                    }
                }
        }.font(.caption.monospacedDigit()).lineLimit(1).minimumScaleFactor(0.5)
            .accessibilityIdentifier("workout-health-metrics")
    }
}

private struct WorkoutDurationLabel: View {
    let start: Date

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "clock").accessibilityHidden(true)
            // Keep the menu anchor's layout independent of per-second timer updates,
            // including minute/hour rollovers and Dynamic Type sizing.
            Text(verbatim: "00:00:00").hidden()
                .overlay(alignment: .leading) {
                    TimelineView(.periodic(from: start, by: 1)) { context in
                        let elapsed = max(0, Int(context.date.timeIntervalSince(start)))
                        let duration = Duration.seconds(elapsed).formatted(.time(pattern: .hourMinuteSecond(padHourToLength: 2)))
                        Text(duration)
                            .lineLimit(1).minimumScaleFactor(0.5)
                            .accessibilityLabel(L10n.text("SESSION_LENGTH" /* 训练时长 */))
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
                Section(L10n.text("WORKOUT_TITLE" /* 训练标题 */)) {
                    BufferedTextField(L10n.text("WORKOUT_TITLE" /* 训练标题 */), text: Binding(
                        get: { store.draft?.name ?? "" },
                        set: { text in store.changeActive { $0["name"] = text } }
                    )).textFieldStyle(.plain).stableInputLine().submitLabel(.done).onSubmit { GymKeyboard.dismiss() }.accessibilityIdentifier("live-workout-name")
                }
                Section(L10n.text("WORKOUT_NOTES" /* 本次训练备注 */)) {
                    BufferedTextField(L10n.text("ADD_NOTE" /* 添加备注 */), text: Binding(
                        get: { store.draft?.activeJSON["note"] as? String ?? "" },
                        set: { text in store.changeActive { $0["note"] = text } }
                    ), axis: .vertical).textFieldStyle(.plain).submitLabel(.done).onSubmit { GymKeyboard.dismiss() }
                        .lineLimit(3...6).accessibilityIdentifier("live-workout-note")
                }
            }.navigationTitle(L10n.text("WORKOUT_DETAILS" /* 训练详情 */)).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L10n.text("DONE" /* 完成 */)) { store.liveInputBuffer.commitAll(); dismiss() } } }
        }.presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
            .onChange(of: store.draft?.id) { _, _ in dismiss() }
    }
}
