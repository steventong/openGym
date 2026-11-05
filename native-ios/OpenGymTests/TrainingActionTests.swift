import XCTest
import SwiftUI
import UIKit
@testable import OpenGym

@MainActor final class TrainingActionTests: XCTestCase {
    private var root: URL!
    private var store: GymStore!
    private var now: Date!

    override func setUp() async throws {
        now = Date()
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        store = GymStore(userID: "shared-action-test", storage: LocalTrainingStorage(root: root))
        store.state = ["unit": "kg", "restSec": 90]
        store.draft = try TrainingDraft.fromWeb(["id": "session", "name": "训练", "start": 1000, "cur": 0,
            "entries": [["id": "bench", "sets": [["w": 40, "r": 10, "done": false], ["w": 40, "r": 10, "done": false], ["w": 40, "r": 10, "done": false]]]]], unit: "kg")
    }
    override func tearDown() async throws { store = nil; try? FileManager.default.removeItem(at: root) }

    private func watchCommand(_ action: String) throws -> WatchTrainingCommand {
        let state = store.watchSnapshot()
        return WatchTrainingCommand(account: state.account, sessionID: try XCTUnwrap(state.sessionID), revision: state.revision,
            action: action, entry: action == "skipRest" ? try XCTUnwrap(state.restEntry) : try XCTUnwrap(state.nextSet?.entry),
            index: action == "complete" ? state.nextSet?.index : nil, side: state.nextSet?.side)
    }

    func testCompletionProtectsEndRestAcrossWatchAndActivityForExactlyFiveSeconds() throws {
        let complete = try watchCommand("complete")
        XCTAssertEqual(store.performWatchCommand(complete, now: now)["accepted"] as? Bool, true)
        let deadline = try XCTUnwrap(store.trainingActionReadyAt)
        XCTAssertEqual(deadline.timeIntervalSince(now), 5, accuracy: 0.00001)
        XCTAssertEqual(store.watchSnapshot().actionReadyAt, store.workoutActivityState()?.actionReadyAt)
        let skip = try XCTUnwrap(store.workoutActivityState()?.restCommand)
        XCTAssertNotNil(store.performActivityCommand(skip, now: now.addingTimeInterval(4.999)))
        XCTAssertNotNil(store.restUntil)
        // A replayed completion is still acknowledged without extending protection.
        XCTAssertEqual(store.performWatchCommand(complete, now: now.addingTimeInterval(1))["accepted"] as? Bool, true)
        XCTAssertEqual(store.trainingActionReadyAt, deadline)
        XCTAssertNil(store.performActivityCommand(skip, now: deadline))
        XCTAssertNil(store.restUntil)
        XCTAssertEqual(try XCTUnwrap(store.trainingActionReadyAt).timeIntervalSince(deadline), 5, accuracy: 0.00001)
    }

    func testEndRestProtectsCompletionAcrossActivityAndWatchIncludingColdLaunch() throws {
        store.startRest(entry: 0, seconds: 90)
        XCTAssertNil(store.performActivityCommand(try XCTUnwrap(store.workoutActivityState()?.restCommand), now: now))
        let complete = try watchCommand("complete")
        XCTAssertEqual(store.performWatchCommand(complete, now: now.addingTimeInterval(4.999))["accepted"] as? Bool, false)
        XCTAssertEqual(store.draft?.completedSets, 0)
        let restored = GymStore(userID: "shared-action-test", storage: LocalTrainingStorage(root: root))
        restored.state = store.state; restored.restoreDraft()
        XCTAssertEqual(restored.trainingActionReadyAt, store.trainingActionReadyAt)
        XCTAssertEqual(restored.performWatchCommand(complete, now: now.addingTimeInterval(3))["accepted"] as? Bool, false)
        XCTAssertEqual(restored.performWatchCommand(complete, now: try XCTUnwrap(restored.trainingActionReadyAt))["accepted"] as? Bool, true)
        XCTAssertEqual(restored.draft?.completedSets, 1)
    }

    func testNaturalExpiryKeepsEndRestActionWithoutStartingProtection() throws {
        store.startRest(entry: 0, seconds: 90)
        store.restUntil = now.addingTimeInterval(-1)
        let snapshot = store.watchSnapshot()
        XCTAssertFalse(snapshot.isResting(at: now))
        XCTAssertEqual(snapshot.primaryAction(reachable: true, reconnecting: false, hasPending: false, sending: false, at: now), .endRest)
        XCTAssertNil(snapshot.actionReadyAt)
        XCTAssertNotNil(store.workoutActivityState()?.restCommand)
        XCTAssertEqual(store.performWatchCommand(try watchCommand("complete"), now: now)["accepted"] as? Bool, false)
        XCTAssertEqual(store.performWatchCommand(try watchCommand("skipRest"), now: now)["accepted"] as? Bool, true)
        XCTAssertEqual(store.draft?.completedSets, 0)
    }

    func testPhoneCheckboxBypassesTextButtonProtection() throws {
        XCTAssertEqual(store.performWatchCommand(try watchCommand("complete"), now: now)["accepted"] as? Bool, true)
        XCTAssertTrue(store.watchSnapshot().actionTiming.isProtected(at: now))
        XCTAssertTrue(store.liveRowAction(entry: 0, set: 1, action: ["action": "toggle"]))
        XCTAssertEqual(store.draft?.completedSets, 2)
    }

    func testCountdownFormattingAndProtectionShareBoundaryWithoutNegativeValues() {
        let end = now.addingTimeInterval(5)
        let timing = TrainingActionTiming(restEnd: nil, readyAt: end)
        let style = TrainingCountdownSecondsStyle(end: end)
        for elapsed in [0.0, 0.1, 1.0, 4.999, 5.0, 6.0] {
            let date = now.addingTimeInterval(elapsed)
            XCTAssertEqual(style.format(date), "\(timing.protectionSeconds(at: date))S")
            XCTAssertEqual(timing.isProtected(at: date), elapsed < 5)
        }
        XCTAssertEqual(style.discreteInput(after: now), now.addingTimeInterval(1))
        XCTAssertNil(style.discreteInput(after: end))
    }

    func testSystemTimerIntervalHandlesFutureAndExpiredRestWithoutInvalidRange() {
        for remaining in [90.0, 5, 0.1, 0, -1, -3600] {
            let interval = TrainingCountdownText.timerInterval(endingAt: now.addingTimeInterval(remaining), now: now)
            XCTAssertEqual(interval.lowerBound, now)
            XCTAssertEqual(interval.upperBound.timeIntervalSince(now), max(0, remaining), accuracy: 0.00001)
        }
    }

    func testWatchCountdownPadsSecondsWithoutTruncatingOrGoingNegative() {
        let style = TrainingCountdownSecondsStyle(end: now, minimumIntegerDigits: 3, suffix: "")
        for (remaining, expected) in [(105.0, "105"), (55.0, "055"), (9.0, "009"), (0.1, "001"),
                                       (0.0, "000"), (-1.0, "000"), (1000.0, "1000")] {
            XCTAssertEqual(style.format(now.addingTimeInterval(-remaining)), expected)
            XCTAssertEqual(style.formattedSeconds(remaining), expected)
        }
        XCTAssertEqual(style.discreteInput(after: now.addingTimeInterval(-1)), now)
        XCTAssertNil(style.discreteInput(after: now))
    }

    func testSharedControlProtectionExpiresButExplicitAndParentDisablingRemain() async throws {
        var observations: [(Bool, Bool)] = []
        func content(deadline: Date?, busy: Bool = false, parentDisabled: Bool = false,
                     systemDeadlinePassed: Bool = false) -> some View {
            TrainingActionControl(title: "完成本组", symbol: "checkmark",
                timing: .init(readyAt: deadline), disabled: busy, quietReady: true,
                systemDeadlinePassed: systemDeadlinePassed) { label in
                    Button {} label: {
                        label.background(ActionAvailabilityProbe(disabled: label.disabled) { observations.append(($0, $1)) })
                    }
                }.disabled(parentDisabled).frame(width: 184)
        }
        let deadline = Date().addingTimeInterval(1)
        let controller = UIHostingController(rootView: content(deadline: deadline))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 184, height: 100)
        window.rootViewController = controller; window.makeKeyAndVisible()
        defer { window.isHidden = true }
        controller.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(observations.last?.0, true)
        XCTAssertEqual(observations.last?.1, false)
        try await Task.sleep(for: .seconds(1.1))
        XCTAssertEqual(observations.last?.0, false)
        XCTAssertEqual(observations.last?.1, true)

        // WidgetKit can resolve the stale-state variant while archiving the
        // view before the deadline. System expiry must override that old date.
        let archivedDeadline = Date().addingTimeInterval(60)
        controller.rootView = content(deadline: archivedDeadline)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(observations.last?.0, true)
        XCTAssertEqual(observations.last?.1, false)
        controller.rootView = content(deadline: archivedDeadline, systemDeadlinePassed: true)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(observations.last?.0, false)
        XCTAssertEqual(observations.last?.1, true)

        controller.rootView = content(deadline: archivedDeadline, busy: true, systemDeadlinePassed: true)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(observations.last?.0, true)
        XCTAssertEqual(observations.last?.1, false)
        controller.rootView = content(deadline: archivedDeadline, parentDisabled: true, systemDeadlinePassed: true)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(observations.last?.0, false)
        XCTAssertEqual(observations.last?.1, false)
    }

    func testLiveActivityContentFitsHeightBudgetAcrossStatesAndLanguages() throws {
        for language in ["zh", "en"] {
            for width: CGFloat in [296, 347, 384] {
                for island in [false, true] {
                    var baseline: CGFloat?
                    for phase in ["rest", "expired", "ready", "protected", "busy"] {
                        var state = try XCTUnwrap(store.workoutActivityState())
                        state.language = language
                        state.trainingName = language == "zh" ? "力量训练" : "Strength training"
                        state.exercise = language == "zh" ? "坐姿单臂哑铃肩上推举" : "Seated single-arm dumbbell shoulder press"
                        state.position = language == "zh" ? "第 2/6 个动作" : "Exercise 2/6"
                        state.setLabel = L10n.format("SET_COUNT_OF_COUNT", language: language, arguments: [2, 4])
                        state.setWeight = "40 kg"; state.setDetail = language == "zh" ? "10 次" : "10 reps"
                        state.commandTitle = language == "zh" ? "完成本组" : "Complete set"
                        state.restEnd = phase == "ready" ? nil : now.addingTimeInterval(phase == "expired" ? -55 : 55)
                        state.setCompletionLabel = phase == "ready" ? nil : L10n.format("COMPLETED", language: language)
                        state.restCommand = phase == "ready" ? nil : "preview-rest"
                        state.actionReadyAt = phase == "protected" ? now.addingTimeInterval(5) : nil
                        state.busyTitle = phase == "busy" ? (language == "zh" ? "正在保存" : "Saving") : nil
                        let view = WorkoutActivityContent(state: state, island: island)
                            .environment(\.colorScheme, .dark).environment(\.dynamicTypeSize, .large)
                            .frame(width: width).background(Color(white: 0.07))
                        let controller = UIHostingController(rootView: view)
                        let size = controller.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
                        // Expanded content also needs room for the system's top regions.
                        XCTAssertLessThanOrEqual(size.height + (island ? 36 : 0), 160)
                        XCTAssertLessThanOrEqual(size.width, width)
                        if let baseline { XCTAssertEqual(size.height, baseline, accuracy: 0.5) }
                        else { baseline = size.height }
                        if width == 347 {
                            let renderer = ImageRenderer(content: view)
                            renderer.scale = 2
                            let image = try XCTUnwrap(renderer.uiImage)
                            let attachment = XCTAttachment(image: image)
                            attachment.name = "shared-action-\(language)-\(island ? "island" : "lock")-\(phase)"
                            attachment.lifetime = .keepAlways
                            add(attachment)
                        }
                    }
                }
            }
        }
    }

    func testOlderPayloadsDecodeWithoutProtectionDeadline() throws {
        let encoded = try JSONEncoder().encode(store.watchSnapshot())
        XCTAssertNil(try JSONDecoder().decode(WatchTrainingSnapshot.self, from: encoded).actionReadyAt)
        let state = try XCTUnwrap(store.workoutActivityState())
        XCTAssertNil(try JSONDecoder().decode(WorkoutActivityAttributes.ContentState.self, from: JSONEncoder().encode(state)).actionReadyAt)
    }
}

private struct ActionAvailabilityProbe: UIViewRepresentable {
    let disabled: Bool
    let observe: (Bool, Bool) -> Void
    @Environment(\.isEnabled) private var isEnabled
    func makeUIView(context: Context) -> UIView { UIView() }
    func updateUIView(_ view: UIView, context: Context) { observe(disabled, isEnabled) }
}
