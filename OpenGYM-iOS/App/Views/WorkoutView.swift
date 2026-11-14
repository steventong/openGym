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
    @State private var showingCompletion = false
    var body: some View {
        NavigationStack {
            workoutContent
                .navigationTitle(store.draft?.name ?? String(localized: "CHOOSE_A_ROUTINE", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
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
                            WorkoutMenuView(draft: d, timerRunning: store.workTimer != nil,
                                addExercise: { store.liveInputBuffer.commitAll(); showExercisePicker = true },
                                reorderExercises: { store.liveInputBuffer.commitAll(); exerciseOrderDraft = store.draft },
                                showDetails: { store.liveInputBuffer.commitAll(); showWorkoutDetails = true },
                                finishWorkout: { confirmFinish = true }, deleteWorkout: { confirmDelete = true })
                        }
                        if d.allSetsCompleted {
                            ToolbarItem(placement: .topBarLeading) {
                                Button("SAVE_WORKOUT") { confirmFinish = true }
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
        .onChange(of: store.draft?.activeJSON["cur"] as? Int) { _, _ in showExerciseNote = false }
    }
    private var workoutContent: some View {
        GeometryReader { geometry in
            Group {
                if let d = store.draft, !d.rawEntries.isEmpty {
                    // 全部组完成后，在最后一个动作之后追加“全部动作已完成”页；它不是真实动作，不写入 cur。
                    let names = d.rawEntries.map(name)
                    let completed = d.allSetsCompleted
                    let current = min(max(0, d.activeJSON["cur"] as? Int ?? 0), names.count - 1)
                    TrainingExercisePager(selected: completed && showingCompletion ? names.count : current,
                        names: completed ? names + [String(localized: "ALL_EXERCISES_COMPLETE", bundle: AppLanguage.bundle, locale: AppLanguage.locale)] : names,
                        select: { index in
                            showingCompletion = index == names.count
                            if index < names.count { store.selectLiveEntry(index) }
                        }) { index in
                        if index == names.count {
                            WorkoutExercisePrompt(icon: "checkmark.circle", message: "ALL_EXERCISES_COMPLETE",
                                buttonTitle: "ADD_NEW_EXERCISE", buttonAccessibilityLabel: "ADD_NEW_EXERCISE",
                                buttonIdentifier: "completed-workout-add-exercise") {
                                store.liveInputBuffer.commitAll(); showExercisePicker = true
                            }
                            // 页面外层有 20pt 内边距，居中区域扣除上下两侧。
                            .containerRelativeFrame(.vertical) { length, _ in max(0, length - 40) }
                        } else {
                            VStack(alignment: .leading, spacing: 20) {
                                WorkoutNoteView(note: d.activeJSON["note"] as? String)
                                LiveWorkoutExerciseCard(draft: d, index: index, showingNote: $showExerciseNote)
                            }
                        }
                    }.id(d.id)
                        // 最后一组完成时自动翻到完成页；撤销或新增组后回到动作页。
                        .onChange(of: completed) { _, done in showingCompletion = done }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            if let d = store.draft {
                                WorkoutNoteView(note: d.activeJSON["note"] as? String)
                                Spacer(minLength: 0)
                                WorkoutExercisePrompt(icon: "dumbbell", message: "NO_EXERCISES_YET", buttonTitle: "ADD",
                                    buttonAccessibilityLabel: "ADD_WORKOUT_EXERCISE",
                                    buttonIdentifier: "empty-workout-add-exercise") { showExercisePicker = true }
                                Spacer(minLength: 0)
                            } else {
                                planHeading(title: "START_WORKOUT", icon: "figure.strengthtraining.traditional")
                                GreenButton(title: "FREESTYLE", icon: "figure.strengthtraining.traditional") { store.startFreestyle() }
                                    .accessibilityIdentifier("start-freestyle-workout")
                                let scheduled = store.scheduledRoutines(on: Date())
                                if !scheduled.isEmpty {
                                    planHeading(title: "TODAY_S_PLAN", icon: "calendar")
                                    GreenButton(title: "\(scheduled.map(\.name).joined(separator: " + "))", icon: "play.fill") { store.start(scheduled) }
                                }
                                planHeading(title: "ALL_TRAINING_PLANS", icon: "list.bullet")
                                ForEach(store.routines) { r in GreenButton(title: "\(r.name)", icon: "play.fill") { store.start(r) } }
                                if store.routines.isEmpty { GreenButton(title: "GO_TO_ROUTINES") { store.selectedTab = 1 } }
                            }
                        }.padding(20)
                            .frame(minHeight: store.draft != nil ? geometry.size.height : nil, alignment: .top)
                    }.scrollDismissesKeyboard(.interactively)
                }
            }.keyboardDismissToolbar()
        }
            .sheet(isPresented: $showWorkoutDetails) { WorkoutDetailsEditor() }
            .sheet(isPresented: $showExercisePicker) {
                ExercisePicker(title: "ADD_EXERCISE") { exercise in
                    store.manageLiveExercise(action: "add", index: 0, id: exercise.id)
                    showExercisePicker = false
                }
            }
            .sheet(item: $exerciseOrderDraft) { draft in
                ExerciseOrderSheet(entries: draft.rawEntries) { order, baseline in
                    try store.reorderLiveExercises(order, expectedEntries: baseline, sessionID: draft.id)
                }
            }
            .confirmationDialog("SAVE_AND_SUBMIT_WORKOUT", isPresented: $confirmFinish, titleVisibility: .visible) {
                Button("SAVE_AND_SUBMIT_WORKOUT_A") { Task { await store.finish() } }
                Button("CONTINUE_WORKOUT", role: .cancel) {}
            }
            .confirmationDialog("DELETE_THIS_WORKOUT", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("DELETE_WORKOUT_A", role: .destructive) { store.deleteCurrentWorkout() }
                Button("CONTINUE_WORKOUT", role: .cancel) {}
            } message: {
                Text("THE_LOCAL_DRAFT_WILL_BE_DELETED_AND_ITS_TIMER_STOPPED_THIS_CANNOT")
            }
            .task { while !Task.isCancelled { store.settleTimer(); try? await Task.sleep(for: .seconds(1)) } }
    }
    private func planHeading(title: LocalizedStringKey, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(GymTheme.muted)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .accessibilityAddTraits(.isHeader)
    }

    private func name(_ entry: [String: Any]) -> String { store.exercise(entry["id"] as? String ?? "")?.titleParts.primary ?? String(localized: "CUSTOM_EXERCISE", bundle: AppLanguage.bundle, locale: AppLanguage.locale) }
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
            Text(verbatim: " ").hidden().frame(maxWidth: .infinity)
                .overlay(alignment: .leading) {
                    if let energy = report?.activeCalories {
                        Label(String(format: String(localized: "COUNT_ACTIVE_KCAL", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(describing: String(format: "%.0f", energy))), systemImage: "flame.fill").foregroundStyle(.orange)
                    }
                }
            Text(verbatim: " ").hidden().frame(maxWidth: .infinity)
                .overlay(alignment: .leading) {
                    if report?.state == .running, let heart = report?.heartRate {
                        Label(String(format: String(localized: "COUNT_BPM", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(describing: String(format: "%.0f", heart))), systemImage: "heart.fill").foregroundStyle(.red)
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
                            .accessibilityLabel("SESSION_LENGTH")
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
                Section("WORKOUT_TITLE") {
                    BufferedTextField("WORKOUT_TITLE", text: Binding(
                        get: { store.draft?.name ?? "" },
                        set: { text in store.changeActive { $0["name"] = text } }
                    )).textFieldStyle(.plain).stableInputLine().submitLabel(.done).onSubmit { GymKeyboard.dismiss() }.accessibilityIdentifier("live-workout-name")
                }
                Section("WORKOUT_NOTES") {
                    BufferedTextField("ADD_NOTE", text: Binding(
                        get: { store.draft?.activeJSON["note"] as? String ?? "" },
                        set: { text in store.changeActive { $0["note"] = text } }
                    ), axis: .vertical).textFieldStyle(.plain).submitLabel(.done).onSubmit { GymKeyboard.dismiss() }
                        .lineLimit(3...6).accessibilityIdentifier("live-workout-note")
                }
            }.navigationTitle("WORKOUT_DETAILS").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("DONE") { store.liveInputBuffer.commitAll(); dismiss() } } }
        }.presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
            .onChange(of: store.draft?.id) { _, _ in dismiss() }
    }
}
