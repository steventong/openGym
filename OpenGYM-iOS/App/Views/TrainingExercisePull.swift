import SwiftUI

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
        // Require both a visible armed hint and the release position. Pulling
        // back cancels; inertia, spring-back and an unseen fast flick cannot switch.
        if top == 2, released.top == 2, selected > 0 { return selected - 1 }
        if bottom == 2, released.bottom == 2, selected + 1 < count { return selected + 1 }
        return nil
    }
}
