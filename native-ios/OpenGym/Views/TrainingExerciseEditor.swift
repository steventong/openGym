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
                TrainingExerciseCard(entry: entries[selected], name: names[selected], rows: rows,
                    unit: unit, inputState: inputState, previous: previous, previousNote: previousNote,
                    identifier: identifier, entryIdentity: entryIdentity ?? String(selected), timerRunning: timerRunning,
                    restUntil: restUntil, startTimer: startTimer, startRest: startRest, showDetails: showDetails,
                    addSet: addSet, copySet: copySet, removeSet: removeSet, editSet: editSet, undoRemove: undoRemove,
                    exerciseActions: exerciseActions, accessory: accessory)
                    .accessibilityActions {
                        if allowsEntryNavigation, selected > 0 {
                            Button("PREVIOUS_EXERCISE") { selectEntry(offset: -1) }
                        }
                        if allowsEntryNavigation, selected + 1 < entries.count {
                            Button("NEXT_EXERCISE") { selectEntry(offset: 1) }
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


    private var optionsSheet: some View {
        NavigationStack {
            Form {
                Section("NOTES_FOR_THIS_EXERCISE") {
                    BufferedTextField(String(localized: "ADD_NOTE", bundle: AppLanguage.bundle, locale: AppLanguage.locale), text: $note, axis: .vertical).textFieldStyle(.plain).submitLabel(.done).onSubmit { GymKeyboard.dismiss() }
                        .lineLimit(3...6).accessibilityIdentifier("\(identifier)-exercise-note")
                }
                if entries.indices.contains(selected), !rows.isEmpty,
                   (entries[selected]["target"] as? [String: Any])?["mode"] as? String != "cardio",
                   rows.contains(where: { $0.raw["mode"] as? String != "cardio" }) {
                    Section {
                        Picker("WEIGHT_UNIT_FOR_THIS_WORKOUT", selection: Binding(get: {
                            TrainingInput.weightUnit(rows.first?.raw ?? [:], fallback: unit)
                        }, set: { next in
                            inputBuffer?.commitAll()
                            do {
                                // Validate every row first so a switch cannot discard unfinished input.
                                for row in rows { try TrainingInput.validateWeightSwitch(row.raw) }
                                for index in rows.indices { editSet(index, ["action": "weightUnit", "unit": next]) }
                            } catch { unitError = error.localizedDescription }
                        })) {
                            Text("KG_KILOGRAMS").tag("kg")
                            Text("LB_POUNDS").tag("lb")
                        }.pickerStyle(.segmented).disabled(timerRunning)
                            .accessibilityIdentifier("\(identifier)-weight-unit")
                    } header: { HStack { Text("WEIGHT_UNIT_FOR_THIS_WORKOUT"); Spacer(); ExplanationButton(title: String(localized: "WEIGHT_UNIT", bundle: AppLanguage.bundle, locale: AppLanguage.locale), message: String(localized: "EXISTING_WEIGHTS_ARE_CONVERTED_AUTOMATICALLY_FOR_THIS_EXERCISE_ONLY", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) } }
                }
            }.navigationTitle("NOTES_AND_UNITS").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("DONE") { inputBuffer?.commitAll(); showingOptions = false } } }
                .alert("YOUR_WEIGHT_INPUT_HAS_BEEN_KEPT", isPresented: Binding(get: { unitError != nil }, set: { if !$0 { unitError = nil } })) {
                    Button("GOT_IT", role: .cancel) {}
                } message: { Text(unitError ?? "") }
        }.presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
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
                Text(ready ? String(localized: "RELEASE_TO_SWITCH_EXERCISE", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
                    : previous ? String(localized: "KEEP_PULLING_DOWN_TO_VIEW", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
                    : String(localized: "KEEP_PULLING_UP_TO_VIEW", bundle: AppLanguage.bundle, locale: AppLanguage.locale)).font(.caption2)
                Text(previous ? String(format: String(localized: "PREVIOUS_EXERCISE_NAMED", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(describing: name))
                    : String(format: String(localized: "NEXT_EXERCISE_NAMED", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(describing: name)))
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
            Text(String(format: String(localized: "EXERCISE_COUNT_OF_COUNT", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(describing: index + 1), String(describing: count)))
        }.fixedSize().accessibilityElement(children: .combine)
    }
}
