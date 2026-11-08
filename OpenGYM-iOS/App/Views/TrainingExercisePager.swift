import SwiftUI

/// Native scrolling owns dragging and rubber-banding. Only a deliberate pull
/// beyond an edge followed by release changes the displayed exercise.
struct TrainingExercisePager<Page: View>: View {
    @Environment(\.inputCommitBuffer) private var inputBuffer
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let selected: Int
    let names: [String]
    let select: (Int) -> Void
    @ViewBuilder let page: (Int) -> Page
    @State private var displayed: Int
    @State private var movingForward = true
    @State private var pull = TrainingExercisePull()
    @State private var draggingEntry: Int?

    init(selected: Int, names: [String], select: @escaping (Int) -> Void, @ViewBuilder page: @escaping (Int) -> Page) {
        self.selected = selected
        self.names = names
        self.select = select
        self.page = page
        _displayed = State(initialValue: selected)
    }

    var body: some View {
        // Keep the scroll view's identity inside a stable container so both pages
        // can slide together, while each new exercise starts scrolled to the top.
        ZStack {
            let index = displayed
            ScrollView(.vertical) {
                if names.indices.contains(index) {
                    page(index)
                        .padding(20)
                        .frame(maxWidth: .infinity, alignment: .top)
                }
            }
            .scrollBounceBehavior(.always, axes: .vertical)
            .scrollDismissesKeyboard(.interactively)
            .onScrollGeometryChange(for: TrainingExercisePull.self) { geometry in
                TrainingExercisePull(geometry: geometry)
            } action: { _, value in
                guard index == displayed, index == selected else { return }
                pull = value
            }
            .onScrollPhaseChange { oldPhase, newPhase, context in
                guard index == displayed, index == selected else { return }
                if newPhase == .interacting {
                    draggingEntry = index
                    pull = TrainingExercisePull(geometry: context.geometry)
                }
                guard oldPhase == .interacting else { return }
                let startedOn = draggingEntry
                draggingEntry = nil
                guard startedOn == index,
                      let next = pull.destinationOnRelease(geometry: context.geometry,
                        from: oldPhase, to: newPhase, selected: index, count: names.count) else { return }
                inputBuffer?.commitAll()
                GymKeyboard.dismiss()
                select(next)
            }
            // A new pull may begin before the slide finishes. Only the outgoing
            // page is inert; animation completion must not gate the next gesture.
            .allowsHitTesting(index == selected)
            .id(index)
            .transition(pageTransition)
        }
        .clipped()
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
        .onChange(of: selected) { old, next in
            pull = TrainingExercisePull()
            draggingEntry = nil
            movingForward = next > old
            withAnimation(reduceMotion ? .easeOut(duration: 0.18) : .smooth(duration: 0.32)) {
                displayed = next
            }
        }
        .onDisappear { pull = TrainingExercisePull(); draggingEntry = nil }
    }

    private var pageTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .move(edge: movingForward ? .bottom : .top),
            removal: .move(edge: movingForward ? .top : .bottom))
    }
}
