import XCTest
import SwiftUI
import UIKit
@testable import OpenGYM

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

    func testSetClockSurvivesEditsAndRestartsAfterRest() throws {
        let initialStart = try XCTUnwrap(store.watchSnapshot().setStartedAt)
        XCTAssertEqual(store.workoutActivityState()?.setStartedAt, initialStart)
        store.changeActive { $0["name"] = "Renamed" }
        XCTAssertEqual(store.watchSnapshot().setStartedAt, initialStart)
        store.startRest(entry: 0, seconds: 90, set: 0)
        XCTAssertNil(store.watchSnapshot().setStartedAt)
        XCTAssertNil(store.workoutActivityState()?.setStartedAt)
        store.endRestFromTextButton(at: now)
        XCTAssertEqual(try XCTUnwrap(store.watchSnapshot().setStartedAt).timeIntervalSince1970, now.timeIntervalSince1970, accuracy: 0.000001)
        XCTAssertEqual(store.workoutActivityState()?.setStartedAt, store.watchSnapshot().setStartedAt)
        let activity = try XCTUnwrap(store.workoutActivityState())
        XCTAssertEqual(try JSONDecoder().decode(WorkoutActivityAttributes.ContentState.self, from: JSONEncoder().encode(activity)).setStartedAt, activity.setStartedAt)
        let restored = try JSONDecoder().decode(WatchTrainingSnapshot.self, from: JSONEncoder().encode(store.watchSnapshot()))
        XCTAssertEqual(try XCTUnwrap(restored.setStartedAt).timeIntervalSince1970, now.timeIntervalSince1970, accuracy: 0.000001)
        store.changeActive { $0["name"] = "Renamed again" }
        XCTAssertEqual(try XCTUnwrap(store.watchSnapshot().setStartedAt).timeIntervalSince1970, now.timeIntervalSince1970, accuracy: 0.000001)
    }

    func testSetClockTracksNextSetAndFormatsMinutes() {
        var before: [String: Any] = ["cur": 0, "entries": [["sets": [["done": false], ["done": false]]]], "nativeSetStartedAt": 10.0]
        var after = before
        after["entries"] = [["sets": [["done": true], ["done": false]]]]
        TrainingSetClock.update(&after, previous: before, now: now)
        XCTAssertEqual(after["nativeSetStartedAt"] as? Double, now.timeIntervalSince1970)
        before = after
        after["name"] = "Edited"
        TrainingSetClock.update(&after, previous: before, now: now.addingTimeInterval(10))
        XCTAssertEqual(after["nativeSetStartedAt"] as? Double, now.timeIntervalSince1970)
        XCTAssertEqual(TrainingSetClock.minutesSeconds(80, roundUp: true), "1:20")
        XCTAssertEqual(TrainingSetClock.minutesSeconds(620), "10:20")
        XCTAssertEqual(TrainingSetClock.minutesSeconds(-1, roundUp: true), "0:00")
        XCTAssertEqual(TrainingSetClock.minutesSeconds(0.1, roundUp: true), "0:01")
    }

    private func watchCommand(_ action: String) throws -> WatchTrainingCommand {
        let state = store.watchSnapshot()
        return WatchTrainingCommand(account: state.account, sessionID: try XCTUnwrap(state.sessionID), revision: state.revision,
            action: action, entry: action == "skipRest" ? try XCTUnwrap(state.restEntry) : try XCTUnwrap(state.nextSet?.entry),
            index: action == "complete" ? state.nextSet?.index : nil, side: state.nextSet?.side)
    }

    func testCompletionProtectsEndRestAcrossWatchAndActivityForExactlyThreeSeconds() throws {
        let complete = try watchCommand("complete")
        XCTAssertEqual(store.performWatchCommand(complete, now: now)["accepted"] as? Bool, true)
        let deadline = try XCTUnwrap(store.trainingActionReadyAt)
        XCTAssertEqual(deadline.timeIntervalSince(now), 3, accuracy: 0.00001)
        XCTAssertEqual(store.watchSnapshot().actionReadyAt, store.workoutActivityState()?.actionReadyAt)
        let skip = try XCTUnwrap(store.workoutActivityState()?.restCommand)
        XCTAssertNotNil(store.performActivityCommand(skip, now: now.addingTimeInterval(2.999)))
        XCTAssertNotNil(store.restUntil)
        // A replayed completion is still acknowledged without extending protection.
        XCTAssertEqual(store.performWatchCommand(complete, now: now.addingTimeInterval(1))["accepted"] as? Bool, true)
        XCTAssertEqual(store.trainingActionReadyAt, deadline)
        XCTAssertNil(store.performActivityCommand(skip, now: deadline))
        XCTAssertNil(store.restUntil)
        XCTAssertEqual(try XCTUnwrap(store.trainingActionReadyAt).timeIntervalSince(deadline), 3, accuracy: 0.00001)
    }

    func testEndRestProtectsCompletionAcrossActivityAndWatchIncludingColdLaunch() throws {
        store.startRest(entry: 0, seconds: 90)
        XCTAssertNil(store.performActivityCommand(try XCTUnwrap(store.workoutActivityState()?.restCommand), now: now))
        let complete = try watchCommand("complete")
        XCTAssertEqual(store.performWatchCommand(complete, now: now.addingTimeInterval(2.999))["accepted"] as? Bool, false)
        XCTAssertEqual(store.draft?.completedSets, 0)
        let restored = GymStore(userID: "shared-action-test", storage: LocalTrainingStorage(root: root))
        restored.state = store.state; restored.restoreDraft()
        XCTAssertEqual(restored.trainingActionReadyAt, store.trainingActionReadyAt)
        XCTAssertEqual(restored.performWatchCommand(complete, now: now.addingTimeInterval(2))["accepted"] as? Bool, false)
        XCTAssertEqual(restored.performWatchCommand(complete, now: try XCTUnwrap(restored.trainingActionReadyAt))["accepted"] as? Bool, true)
        XCTAssertEqual(restored.draft?.completedSets, 1)
    }

    func testNaturalExpiryKeepsEndRestActionWithoutStartingProtection() throws {
        store.startRest(entry: 0, seconds: 90)
        store.restUntil = now.addingTimeInterval(-1)
        let snapshot = store.watchSnapshot()
        XCTAssertFalse(snapshot.isResting(at: now))
        XCTAssertEqual(snapshot.primaryAction(commandState: .idle), .endRest)
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

    func testTimedFinalSetAdvancesAndFinalExerciseStaysSelected() throws {
        store.draft = try TrainingDraft.fromWeb(["id": "timed", "start": 1000, "cur": 0,
            "entries": [
                ["id": "plank", "target": ["mode": "time"], "sets": [["mode": "time", "sec": 30, "done": false]]],
                ["id": "bench", "sets": [["w": 40, "r": 10, "done": false]]]
            ]], unit: "kg")
        store.startWorkTimer(entry: 0, set: 0)
        store.finishWorkTimer()
        XCTAssertNil(store.workTimer)
        XCTAssertNil(store.restUntil)
        XCTAssertEqual(store.draft?.activeJSON["cur"] as? Int, 1)

        XCTAssertTrue(store.liveRowAction(entry: 1, set: 0, action: ["action": "toggle"]))
        XCTAssertEqual(store.draft?.activeJSON["cur"] as? Int, 1)
        XCTAssertEqual(store.draft?.allSetsCompleted, true)
        XCTAssertNil(store.restUntil)
    }

    func testCountdownFormattingAndProtectionShareBoundaryWithoutNegativeValues() {
        let end = TrainingActionTiming.deadline(after: now)
        let timing = TrainingActionTiming(restEnd: nil, readyAt: end)
        let style = TrainingCountdownSecondsStyle(end: end)
        for elapsed in [0.0, 0.1, 1.0, 2.999, 3.0, 4.0] {
            let date = now.addingTimeInterval(elapsed)
            XCTAssertEqual(style.format(date), "\(timing.protectionSeconds(at: date))S")
            XCTAssertEqual(timing.isProtected(at: date), elapsed < 3)
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

    func testLiveActivityStatusUsesWorkoutTimingOrZero() throws {
        var state = try XCTUnwrap(store.workoutActivityState())
        let startedAt = Date(timeIntervalSince1970: 1000)
        state.setStartedAt = startedAt
        XCTAssertEqual(state.trainingContent().action?.status, .workout(startedAt: startedAt))

        state.setStartedAt = nil
        XCTAssertEqual(state.trainingContent().action?.status, .workout(startedAt: nil))
    }

    func testLiveActivityStatusKeepsRestIncludingExpiryAndProtection() throws {
        var state = try XCTUnwrap(store.workoutActivityState())
        state.setStartedAt = Date(timeIntervalSince1970: 1000)
        for end in [Date(timeIntervalSince1970: 1000), Date().addingTimeInterval(90)] {
            state.restEnd = end
            state.actionReadyAt = Date().addingTimeInterval(3)
            XCTAssertEqual(state.trainingContent().action?.status, .rest(endsAt: end))
            XCTAssertEqual(state.trainingContent(systemDeadlinePassed: true).action?.status, .rest(endsAt: end))
        }
    }

    func testLiveActivityHasNoActionWithoutTrainingTarget() throws {
        var state = try XCTUnwrap(store.workoutActivityState())
        state.restEnd = nil
        state.restCommand = nil
        state.command = nil
        state.setWeight = nil
        state.setStartedAt = nil
        XCTAssertNil(state.trainingContent().action?.status)

        state.busyTitle = "正在保存"
        XCTAssertNil(state.trainingContent().action?.status)
    }

    func testLiveActivitySavingKeepsWorkoutAction() throws {
        var state = try XCTUnwrap(store.workoutActivityState())
        state.command = nil
        state.setStartedAt = nil
        state.busyTitle = "正在保存"
        let content = TrainingViewModel(content: state.trainingContent()).content
        XCTAssertEqual(content.action?.status, .workout(startedAt: nil))
        XCTAssertEqual(content.action?.title, state.commandTitle)
        XCTAssertNotEqual(content.action?.title, state.busyTitle)
        XCTAssertEqual(content.action?.disabled, true)
    }

    func testDisabledRestStillRendersActionText() throws {
        func render(title: String, language: String) throws -> Data {
            let view = TrainingActionLabel(title: title, symbol: "forward.end.fill",
                status: .rest(endsAt: Date(timeIntervalSince1970: 1000)),
                disabled: true, tint: .green)
                .environment(\.locale, AppLanguage.locale(for: language))
                .frame(width: 184)
                .environment(\.colorScheme, .dark)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            return try XCTUnwrap(renderer.uiImage?.pngData())
        }

        for (language, title) in [("zh", "结束"), ("en", "Finish")] {
            let image = try render(title: title, language: language)
            XCTAssertNotEqual(image, try render(title: "", language: language))
            let attachment = XCTAttachment(data: image, uniformTypeIdentifier: "public.png")
            attachment.name = "rest-action-\(language)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    func testTrainingActionUsesShortTitlesAndStatusKeys() {
        let original = AppLanguage.preferences.language
        AppLanguage.preferences.language = "zh"
        defer { AppLanguage.preferences.language = original }
        XCTAssertEqual(WatchTrainingAction.complete.title, "完成")
        XCTAssertEqual(WatchTrainingAction.endRest.title, "结束")
        XCTAssertEqual(TrainingActionStatus.workout(startedAt: nil).titleKey, "TRAINING_STATUS_WORKOUT")
        XCTAssertEqual(TrainingActionStatus.rest(endsAt: now).titleKey, "TRAINING_STATUS_REST")
        XCTAssertEqual(String(localized: "TRAINING_STATUS_WORKOUT", bundle: AppLanguage.bundle, locale: AppLanguage.locale), "正在训练")
        XCTAssertEqual(String(localized: "TRAINING_STATUS_REST", bundle: AppLanguage.bundle, locale: AppLanguage.locale), "组间休息")
        XCTAssertEqual(String(localized: "TRAINING_STATUS_WORKOUT", bundle: AppLanguage.bundle(for: "en"), locale: AppLanguage.locale(for: "en")), "TRAIN")
        XCTAssertEqual(String(localized: "TRAINING_STATUS_REST", bundle: AppLanguage.bundle(for: "en"), locale: AppLanguage.locale(for: "en")), "REST")
    }

    func testLiveActivityProtectionExpiresButBusyStateRemainsDisabled() throws {
        var state = try XCTUnwrap(store.workoutActivityState())
        state.actionReadyAt = Date().addingTimeInterval(60)
        let protected = TrainingViewModel(content: state.trainingContent())
        XCTAssertEqual(protected.content.action?.disabled, true)

        // 系统到期后只解除展示保护，基础禁用状态仍由数据源决定。
        let systemExpired = TrainingViewModel(content: state.trainingContent(systemDeadlinePassed: true))
        XCTAssertNil(systemExpired.content.action?.readyAt)
        XCTAssertEqual(systemExpired.content.action?.disabled, false)

        state.busyTitle = "Saving"
        let busy = TrainingViewModel(content: state.trainingContent(systemDeadlinePassed: true))
        XCTAssertEqual(busy.content.action?.disabled, true)

        state.busyTitle = nil
        state.actionReadyAt = Date().addingTimeInterval(-1)
        let expired = TrainingViewModel(content: state.trainingContent())
        XCTAssertEqual(expired.content.action?.disabled, false)
    }

    func testActionLabelInButtonHonorsExplicitAndParentDisabling() async throws {
        var observations: [(Bool, Bool)] = []
        func content(disabled: Bool = false, parentDisabled: Bool = false) -> some View {
            Button {} label: {
                TrainingActionLabel(title: "完成", symbol: "checkmark", status: .workout(startedAt: nil),
                    disabled: disabled, tint: .green)
                    .background(ActionAvailabilityProbe(disabled: disabled) { observations.append(($0, $1)) })
            }
            .disabled(disabled)
            .disabled(parentDisabled)
            .frame(width: 184)
        }

        let controller = UIHostingController(rootView: content())
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 184, height: 100)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        controller.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(observations.last?.0, false)
        XCTAssertEqual(observations.last?.1, true)

        controller.rootView = content(disabled: true)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(observations.last?.0, true)
        XCTAssertEqual(observations.last?.1, false)

        controller.rootView = content(parentDisabled: true)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(observations.last?.0, false)
        XCTAssertEqual(observations.last?.1, false)
    }

    func testLiveActivityContentFitsHeightBudgetAcrossStatesAndLanguages() throws {
        for language in ["zh", "en"] {
            for width: CGFloat in [296, 347, 384] {
                for island in [false, true] {
                    var baseline: CGFloat?
                    for phase in ["rest", "expired", "workout", "protected", "busy"] {
                        var state = try XCTUnwrap(store.workoutActivityState())
                        state.language = language
                        state.trainingName = language == "zh" ? "力量训练" : "Strength training"
                        state.exercise = language == "zh" ? "坐姿单臂哑铃肩上推举" : "Seated single-arm dumbbell shoulder press"
                        state.position = language == "zh" ? "第 2/6 个动作" : "Exercise 2/6"
                        state.setLabel = String(format: String(localized: "SET_COUNT_OF_COUNT", bundle: AppLanguage.bundle(for: language), locale: AppLanguage.locale(for: language)), locale: AppLanguage.locale(for: language), String(describing: 2), String(describing: 4))
                        state.setWeight = "40 kg"; state.setDetail = language == "zh" ? "10 次" : "10 reps"
                        state.commandTitle = language == "zh" ? "完成" : "Complete"
                        state.setStartedAt = phase == "workout" ? nil : state.setStartedAt
                        state.restEnd = phase == "workout" ? nil : now.addingTimeInterval(phase == "expired" ? -55 : 55)
                        state.setCompletionLabel = phase == "workout" ? nil : String(localized: "COMPLETED", bundle: AppLanguage.bundle(for: language), locale: AppLanguage.locale(for: language))
                        state.restCommand = phase == "workout" ? nil : "preview-rest"
                        state.actionReadyAt = phase == "protected" ? now.addingTimeInterval(5) : nil
                        state.busyTitle = phase == "busy" ? (language == "zh" ? "正在保存" : "Saving") : nil
                        let view = WorkoutActivityContent(viewModel: TrainingViewModel(content: state.trainingContent()),
                            command: state.trainingActionCommand, island: island)
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
