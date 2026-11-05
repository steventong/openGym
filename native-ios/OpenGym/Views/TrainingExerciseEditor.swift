import SwiftUI

/// Shared exercise page for an active session and a saved workout.
/// Owners provide persistence and the live-only timer controls.
struct TrainingExerciseEditor<ExerciseActions: View, Accessory: View>: View {
    @Environment(GymStore.self) private var store
    @Environment(\.inputCommitBuffer) private var inputBuffer
    @Binding var showingOptions: Bool
    let entries: [[String: Any]]
    let names: [String]
    @Binding var selected: Int
    let rows: [TrainingEditorRow]
    let unit: String
    var inputState: [String: Any] = [:]
    let previous: String
    var previousNote: String? = nil
    @Binding var note: String
    let identifier: String
    var showsEntryPosition = true
    var allowsEntryNavigation = true
    var entryIdentity: String? = nil
    var timerRunning = false
    var restUntil: Date? = nil
    var startTimer: ((Int) -> Void)? = nil
    var startRest: ((Int, Double) -> Void)? = nil
    let showDetails: () -> Void
    let addSet: () -> Void
    let copySet: (Int) -> Void
    let removeSet: (Int) -> Void
    let editSet: (Int, [String: Any]) -> Void
    var undoRemove: (() -> Void)? = nil
    @ViewBuilder let exerciseActions: () -> ExerciseActions
    @ViewBuilder let accessory: () -> Accessory
    @State private var unitError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if entries.indices.contains(selected) {
                exerciseCard(entries[selected])
                    .accessibilityActions {
                        if allowsEntryNavigation, selected > 0 {
                            Button(L10n.text("PREVIOUS_EXERCISE" /* 上一个动作 */)) { selectEntry(offset: -1) }
                        }
                        if allowsEntryNavigation, selected + 1 < entries.count {
                            Button(L10n.text("NEXT_EXERCISE" /* 下一个动作 */)) { selectEntry(offset: 1) }
                        }
                    }
                if showsEntryPosition {
                    ExercisePositionLabel(index: selected, count: entries.count)
                        .font(.caption.monospacedDigit()).foregroundStyle(GymTheme.muted)
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("\(identifier)-entry-position")
                }
            }
        }.sheet(isPresented: $showingOptions) {
            optionsSheet
        }.onChange(of: selected) { _, _ in showingOptions = false; unitError = nil }
    }

    private func selectEntry(offset: Int) {
        let next = selected + offset
        guard entries.indices.contains(next) else { return }
        inputBuffer?.commitAll()
        GymKeyboard.dismiss()
        selected = next
    }

    private func exerciseCard(_ entry: [String: Any]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            accessory()
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 10) {
                    ExerciseThumbnail(id: entry["id"] as? String ?? "", size: 40)
                    let parts = store.exercise(entry["id"] as? String ?? "")?.titleParts
                    VStack(alignment: .leading, spacing: 4) {
                        Text(parts?.primary ?? names[selected])
                            .font(.headline).lineLimit(1).minimumScaleFactor(0.75)
                        if let subtitle = parts?.secondary, !subtitle.isEmpty {
                            Text(subtitle).font(.caption).foregroundStyle(GymTheme.muted)
                                .lineLimit(2)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("\(identifier)-exercise-title")
                    HStack(spacing: 0) {
                        Button(action: showDetails) {
                            Image(systemName: "info.circle").font(.title2).frame(width: 48, height: 48).contentShape(Rectangle())
                        }.accessibilityLabel(L10n.text("EXERCISE_DETAILS" /* 动作详情 */))
                        exerciseActions()
                    }
                }
                if entry["sg"] != nil { Label(L10n.text("SUPERSET" /* 超级组 */), systemImage: "link").font(.caption).foregroundStyle(GymTheme.green) }
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(previous).font(.caption).foregroundStyle(GymTheme.muted).lineLimit(1).fixedSize(horizontal: true, vertical: false)
                }.accessibilityIdentifier("previous-exercise")
                if let previousNote {
                    Text(L10n.text("PREVIOUS_WORKOUT_NOTE" /* 上次备注：{0} */, previousNote))
                        .font(.caption).foregroundStyle(GymTheme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("previous-exercise-note")
                }
            }
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                VStack(alignment: .leading, spacing: 8) {
                    AdvancedSetEditor(row: row.raw, target: (entry["target"] as? [String: Any] ?? [:]).merging(["id": entry["id"] ?? ""]) { _, new in new }, unit: unit, inputState: inputState, identifier: row.accessibilityIdentifier ?? row.id, setLabel: L10n.text("SET_COUNT" /* 第 {0} 组 */, setNumber(index)), copySet: { copySet(index) }, removeSet: { removeSet(index) }, timerRunning: timerRunning,
                                      startTimer: startTimer.map { start in { start(index) } },
                                      startRest: startRest.map { start in { start(index, $0) } }) { editSet(index, $0) }
                }
                if index < rows.count - 1 { Divider() }
            // Reset row-local state only when changing exercises, not when inserting
            // or deleting a sibling row. Each row has its own stable identity.
            }.id([entryIdentity ?? String(selected), entry["id"] as? String ?? ""])
            if rows.isEmpty { Text(L10n.text("NO_SETS_YET" /* 暂无训练组 */)).font(.subheadline).foregroundStyle(GymTheme.muted) }
            HStack(spacing: 12) {
                if let undoRemove {
                    Button(action: undoRemove) { Image(systemName: "arrow.uturn.backward").frame(width: 44, height: 44) }
                        .buttonStyle(.borderless).accessibilityLabel(L10n.text("UNDO_SET_DELETION" /* 撤销删除训练组 */))
                }
                if startRest != nil {
                    // Keep the same space before, during, and after rest; the overlay cannot resize the card.
                    Color.clear.frame(maxWidth: .infinity)
                        .overlay(alignment: .center) {
                            if let restUntil {
                                ExerciseRestStatus(end: restUntil)
                                    .accessibilityIdentifier("card-rest-timer")
                            }
                        }.allowsHitTesting(false)
                }
                Button(action: addSet) { Label(L10n.text("ADD_SET" /* 添加一组 */), systemImage: "plus").frame(maxWidth: .infinity, minHeight: 44) }
                    .buttonStyle(.borderless).disabled(timerRunning).accessibilityIdentifier("add-set")
            }.font(.subheadline).lineLimit(1).minimumScaleFactor(0.6).frame(height: 44)
        }.gymCard()
    }

    private var optionsSheet: some View {
        NavigationStack {
            Form {
                Section(L10n.text("NOTES_FOR_THIS_EXERCISE" /* 本次动作备注 */)) {
                    BufferedTextField(L10n.text("ADD_NOTE" /* 添加备注 */), text: $note, axis: .vertical).textFieldStyle(.plain).submitLabel(.done).onSubmit { GymKeyboard.dismiss() }
                        .lineLimit(3...6).accessibilityIdentifier("\(identifier)-exercise-note")
                }
                if entries.indices.contains(selected), !rows.isEmpty,
                   (entries[selected]["target"] as? [String: Any])?["mode"] as? String != "cardio",
                   rows.contains(where: { $0.raw["mode"] as? String != "cardio" }) {
                    Section {
                        Picker(L10n.text("WEIGHT_UNIT_FOR_THIS_WORKOUT" /* 本次重量单位 */), selection: Binding(get: {
                            TrainingInput.weightUnit(rows.first?.raw ?? [:], fallback: unit)
                        }, set: { next in
                            inputBuffer?.commitAll()
                            do {
                                // Validate every row first so a switch cannot discard unfinished input.
                                for row in rows { try TrainingInput.validateWeightSwitch(row.raw) }
                                for index in rows.indices { editSet(index, ["action": "weightUnit", "unit": next]) }
                            } catch { unitError = error.localizedDescription }
                        })) {
                            Text(L10n.text("KG_KILOGRAMS" /* kg 公斤 */)).tag("kg")
                            Text(L10n.text("LB_POUNDS" /* lb 磅 */)).tag("lb")
                        }.pickerStyle(.segmented).disabled(timerRunning)
                            .accessibilityIdentifier("\(identifier)-weight-unit")
                    } header: { HStack { Text(L10n.text("WEIGHT_UNIT_FOR_THIS_WORKOUT" /* 本次重量单位 */)); Spacer(); ExplanationButton(title: L10n.text("WEIGHT_UNIT" /* 重量单位 */), message: L10n.text("EXISTING_WEIGHTS_ARE_CONVERTED_AUTOMATICALLY_FOR_THIS_EXERCISE_ONLY" /* 已有重量自动换算，仅影响本次动作。 */)) } }
                }
            }.navigationTitle(L10n.text("NOTES_AND_UNITS" /* 备注与单位 */)).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L10n.text("DONE" /* 完成 */)) { inputBuffer?.commitAll(); showingOptions = false } } }
                .alert(L10n.text("YOUR_WEIGHT_INPUT_HAS_BEEN_KEPT" /* 重量输入已保留 */), isPresented: Binding(get: { unitError != nil }, set: { if !$0 { unitError = nil } })) {
                    Button(L10n.text("GOT_IT" /* 知道了 */), role: .cancel) {}
                } message: { Text(unitError ?? "") }
        }.presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
    }

    private func isRightHalf(_ index: Int) -> Bool {
        index > 0 && rows[index].raw["side"] as? String == "R" && rows[index - 1].raw["side"] as? String == "L"
    }

    private func paired(_ index: Int) -> Bool {
        isRightHalf(index) || (index + 1 < rows.count && isRightHalf(index + 1))
    }

    private func setNumber(_ index: Int) -> Int {
        (0...index).filter { !isRightHalf($0) }.count
    }


}

/// Native scrolling owns dragging and rubber-banding. Only a deliberate pull
/// beyond an edge followed by release changes the displayed exercise.
struct TrainingExercisePager<Page: View>: View {
    @Environment(\.inputCommitBuffer) private var inputBuffer
    let selected: Int
    let names: [String]
    let select: (Int) -> Void
    @ViewBuilder let page: (Int) -> Page
    @State private var pull = TrainingExercisePull()
    @State private var draggingEntry: Int?

    var body: some View {
        ScrollView(.vertical) {
            if names.indices.contains(selected) {
                page(selected)
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .scrollBounceBehavior(.always, axes: .vertical)
        .scrollDismissesKeyboard(.interactively)
        .onScrollGeometryChange(for: TrainingExercisePull.self) { geometry in
            TrainingExercisePull(geometry: geometry)
        } action: { _, value in pull = value }
        .onScrollPhaseChange { oldPhase, newPhase, context in
            if newPhase == .interacting {
                draggingEntry = selected
                // A new upward pull at the bottom should show its hint even
                // before another geometry update crosses an overscroll distance.
                pull = TrainingExercisePull(geometry: context.geometry)
            }
            guard oldPhase == .interacting else { return }
            let startedOn = draggingEntry
            draggingEntry = nil
            guard startedOn == selected,
                  let next = pull.destinationOnRelease(geometry: context.geometry,
                    from: oldPhase, to: newPhase, selected: selected, count: names.count) else { return }
            inputBuffer?.commitAll()
            GymKeyboard.dismiss()
            select(next)
        }
        .id(selected)
        .overlay(alignment: .top) {
            if draggingEntry == selected, pull.top > 0, names.indices.contains(selected - 1) {
                TrainingExercisePagingHint(name: names[selected - 1], previous: true, ready: pull.top == 2)
            }
        }
        .overlay(alignment: .bottom) {
            if draggingEntry == selected, pull.bottom > 0, names.indices.contains(selected + 1) {
                TrainingExercisePagingHint(name: names[selected + 1], previous: false, ready: pull.bottom == 2)
            }
        }
        .onChange(of: selected) { _, _ in pull = TrainingExercisePull(); draggingEntry = nil }
        .onDisappear { pull = TrainingExercisePull(); draggingEntry = nil }
    }
}

struct TrainingExercisePull: Equatable {
    // Hint visibility and release confirmation are separate: the bottom hint
    // appears at the edge, while a deliberate native overscroll arms switching.
    static let threshold: CGFloat = 36
    var top = 0
    var bottom = 0

    init() {}
    init(geometry: ScrollGeometry) {
        let topEdge = -geometry.contentInsets.top
        // SwiftUI's containerSize already excludes the top/bottom insets, but
        // contentOffset is still in UIScrollView coordinates. Adding the bottom
        // inset again made users pull through both bars' heights before the threshold.
        let bottomEdge = topEdge + max(0, geometry.contentSize.height - geometry.containerSize.height)
        func stage(_ distance: CGFloat) -> Int {
            distance >= Self.threshold ? 2 : (distance >= 6 ? 1 : 0)
        }
        top = stage(topEdge - geometry.contentOffset.y)
        let bottomDistance = geometry.contentOffset.y - bottomEdge
        if bottomDistance >= Self.threshold {
            bottom = 2
        } else if bottomDistance >= -1, geometry.contentOffset.y >= topEdge {
            bottom = 1
        }
    }

    func destinationOnRelease(geometry: ScrollGeometry, from oldPhase: ScrollPhase, to newPhase: ScrollPhase,
                              selected: Int, count: Int) -> Int? {
        guard oldPhase == .interacting, newPhase == .decelerating || newPhase == .idle,
              (0..<count).contains(selected) else { return nil }
        let released = Self(geometry: geometry)
        // Require both the displayed ready hint and the release position. Pulling
        // back cancels; inertia, spring-back and an unseen fast flick cannot switch.
        if top == 2, released.top == 2, selected > 0 { return selected - 1 }
        if bottom == 2, released.bottom == 2, selected + 1 < count { return selected + 1 }
        return nil
    }
}

struct TrainingExercisePagingHint: View {
    let name: String
    let previous: Bool
    let ready: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: ready ? "arrow.turn.down.right" : (previous ? "arrow.down" : "arrow.up"))
                .accessibilityHidden(true)
            VStack(spacing: 3) {
                Text(ready ? L10n.text("RELEASE_TO_SWITCH_EXERCISE" /* 松开切换 */)
                    : previous ? L10n.text("KEEP_PULLING_DOWN_TO_VIEW" /* 继续下拉查看 */)
                    : L10n.text("KEEP_PULLING_UP_TO_VIEW" /* 继续上拉查看 */)).font(.caption2)
                Text(previous ? L10n.text("PREVIOUS_EXERCISE_NAMED" /* 上一个动作：{0} */, name)
                    : L10n.text("NEXT_EXERCISE_NAMED" /* 下一个动作：{0} */, name))
                    .font(.caption).lineLimit(2).multilineTextAlignment(.center)
            }
        }
        .foregroundStyle(ready ? GymTheme.green : GymTheme.muted)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20).padding(.vertical, 8)
        .background(GymTheme.background)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(previous ? "previous-exercise-pull-hint" : "next-exercise-pull-hint")
        .allowsHitTesting(false)
    }
}

struct TrainingEditorRow: Identifiable {
    let id: String
    let raw: [String: Any]
    var accessibilityIdentifier: String? = nil
}

struct ExercisePositionLabel: View {
    let index: Int
    let count: Int

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "dumbbell").accessibilityHidden(true)
            Text(L10n.text("EXERCISE_COUNT_OF_COUNT" /* 第 {0}/{1} 个动作 */, index + 1, count))
        }.fixedSize().accessibilityElement(children: .combine)
    }
}

private struct ExerciseRestStatus: View {
    let end: Date

    var body: some View {
        // Keep deadline updates local, so they cannot disturb open editor menus.
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(spacing: 4) {
                HStack(spacing: 2) {
                    Image(systemName: "timer").accessibilityHidden(true)
                    Text(L10n.text("REST_BETWEEN_SETS" /* 组间休息 */))
                }
                Group {
                    if context.date >= end {
                        Text(L10n.text("ENDED" /* 已结束 */))
                    } else {
                        Text(TrainingCountdownSecondsStyle(end: end).format(context.date))
                    }
                }.fontWeight(.semibold).monospacedDigit()
            }.font(.caption).foregroundStyle(GymTheme.green)
                .lineLimit(1).minimumScaleFactor(0.6)
                .accessibilityElement(children: .combine)
        }
    }
}
