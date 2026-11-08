import XCTest
import SwiftUI
import UIKit
import Observation
@testable import OpenGYM

@MainActor final class TrainingContentTests: XCTestCase {
    private func content() -> TrainingContentData {
        .init(exercise: "Bench press", position: "Exercise 1/3",
            summary: .init(weight: "40 kg", detail: "8 reps", label: "Set 1 of 3"),
            action: .init(title: "Complete", symbol: "checkmark", status: .workout(startedAt: nil)),
            locale: AppLanguage.locale(for: "en"))
    }

    private func activityState() -> WorkoutActivityAttributes.ContentState {
        .init(trainingName: "Workout", exercise: "Bench press", position: "Exercise 1/3",
            setLabel: "Set 1 of 3", compactSet: "1/3", detail: "40 kg · 8 reps", message: "",
            restEnd: nil, restExercise: "", command: "complete", commandTitle: "Complete", restCommand: nil,
            setWeight: "40 kg", setDetail: "8 reps", language: "en")
    }

    func testWatchAndActivityProduceTheSameWorkoutContent() {
        let row = WatchTrainingSet(entry: 0, index: 0, label: "Set 1 of 3", weight: "40 kg", detail: "8 reps")
        let snapshot = WatchTrainingSnapshot(language: "en", sessionID: "test", exercise: "Bench press",
            exercisePosition: "Exercise 1/3", nextSet: row)
        XCTAssertEqual(snapshot.trainingContent(action: .complete, disabled: false), activityState().trainingContent())
    }

    func testBothSourcesDisplayTheSetThatStartedRestRatherThanTheNextSet() {
        let end = Date(timeIntervalSince1970: 1000)
        let completed = WatchTrainingSet(entry: 0, index: 0, label: "Set 1 of 3", weight: "40 kg", detail: "8 reps")
        let next = WatchTrainingSet(entry: 0, index: 1, label: "Set 2 of 3", weight: "45 kg", detail: "10 reps")
        let snapshot = WatchTrainingSnapshot(language: "en", sessionID: "test", exercise: "Bench press",
            exercisePosition: "Exercise 1/3", nextSet: next, restSet: completed, restEnd: end)
        var state = activityState()
        state.restEnd = end
        state.restCommand = "rest"
        let watch = snapshot.trainingContent(action: .endRest, disabled: false)
        XCTAssertEqual(watch, state.trainingContent())
        XCTAssertEqual(watch.summary?.weight, "40 kg")
        XCTAssertEqual(watch.action?.status, .rest(endsAt: end))
    }

    func testProtectionUsesOneBoundaryAndNeverOverridesBaseDisabling() {
        let start = Date(timeIntervalSince1970: 1000)
        let deadline = TrainingActionTiming.deadline(after: start)
        var data = content()
        data.action?.readyAt = deadline
        XCTAssertEqual(data.evaluated(at: deadline.addingTimeInterval(-0.001)).action?.disabled, true)
        XCTAssertEqual(data.evaluated(at: deadline).action?.disabled, false)
        XCTAssertEqual(data.evaluated(at: deadline.addingTimeInterval(1)).action?.disabled, false)
        data.action?.disabled = true
        XCTAssertEqual(data.evaluated(at: deadline).action?.disabled, true)
    }

    func testSystemExpiryOnlyChangesDisplayDeadlineAndKeepsSavingDisabled() {
        var state = activityState()
        let deadline = Date().addingTimeInterval(60)
        state.actionReadyAt = deadline
        XCTAssertEqual(TrainingViewModel(content: state.trainingContent()).content.action?.disabled, true)
        let expired = TrainingViewModel(content: state.trainingContent(systemDeadlinePassed: true)).content
        XCTAssertEqual(expired.action?.disabled, false)
        XCTAssertNil(expired.action?.readyAt)
        XCTAssertEqual(state.actionReadyAt, deadline)
        state.busyTitle = "Saving"
        XCTAssertEqual(TrainingViewModel(content: state.trainingContent(systemDeadlinePassed: true)).content.action?.disabled, true)
    }

    func testViewModelRefreshesAtTheProtectionDeadline() async {
        var data = content()
        data.action?.readyAt = Date().addingTimeInterval(0.1)
        let model = TrainingViewModel(content: data)
        XCTAssertEqual(model.content.action?.disabled, true)
        await model.refreshAfterProtectionEnds()
        XCTAssertEqual(model.content.action?.disabled, false)
    }

    func testSnapshotLanguageSelectsCopyWithoutDependingOnGlobalLanguage() {
        let original = AppLanguage.preferences.language
        AppLanguage.preferences.language = "zh"
        defer { AppLanguage.preferences.language = original }
        let row = WatchTrainingSet(entry: 0, index: 0, label: "Set 1", weight: "40 kg", detail: "8 reps")
        let snapshot = WatchTrainingSnapshot(language: "en", nextSet: row)
        let data = snapshot.trainingContent(action: .complete, disabled: false)
        XCTAssertEqual(data.action?.title, "Complete")
        XCTAssertEqual(data.locale, AppLanguage.locale(for: "en"))
    }

    func testObservableSourceUpdatesTheActualSharedContent() async throws {
        let source = MutableSource(trainingContent: content())
        let model = TrainingViewModel(source: source)
        let controller = UIHostingController(rootView: WorkoutActivityContent(viewModel: model, command: "preview"))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 347, height: 160)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKey() }
        controller.view.backgroundColor = .black
        controller.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        let before = UIGraphicsImageRenderer(bounds: controller.view.bounds).pngData { _ in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }
        source.trainingContent.exercise = "Different exercise"
        source.trainingContent.summary?.weight = "60 kg"
        try await Task.sleep(for: .milliseconds(150))
        controller.view.layoutIfNeeded()
        let after = UIGraphicsImageRenderer(bounds: controller.view.bounds).pngData { _ in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }
        XCTAssertEqual(model.content.exercise, "Different exercise")
        XCTAssertNotEqual(before, after)
    }

    func testSharedLayoutsFitTheirBudgetsAcrossStatesAndLanguages() throws {
        for language in ["zh", "en"] {
            for resting in [false, true] {
                var data = content()
                data.locale = AppLanguage.locale(for: language)
                data.exercise = language == "zh" ? "坐姿单臂哑铃肩上推举" : "Seated single-arm dumbbell shoulder press"
                data.position = language == "zh" ? "第 1/3 个动作" : "Exercise 1/3"
                data.summary?.detail = language == "zh" ? "8 次" : "8 reps"
                data.summary?.label = language == "zh" ? "第 1/3 组" : "Set 1 of 3"
                data.action?.title = resting ? (language == "zh" ? "结束" : "Finish") : (language == "zh" ? "完成" : "Complete")
                data.action?.symbol = resting ? "forward.end.fill" : "checkmark"
                data.action?.status = resting ? .rest(endsAt: Date(timeIntervalSince1970: 1000)) : .workout(startedAt: nil)
                let action = try XCTUnwrap(data.action)
                for layout in [TrainingContentLayout.expanded, .compact, .compactWithoutHeader] {
                    let size = layout == .expanded ? CGSize(width: 184, height: 224) : CGSize(width: 323, height: 136)
                    let view = TrainingContentView(content: data, layout: layout,
                        metrics: MetricsSample(visible: layout == .expanded),
                        primaryAction: TrainingActionLabel(title: action.title, symbol: action.symbol,
                            status: action.status, disabled: action.disabled, tint: TrainingDisplayStyle.green))
                        .frame(width: size.width)
                        .environment(\.colorScheme, .dark).background(.black)
                    let controller = UIHostingController(rootView: view)
                    let fitted = controller.sizeThatFits(in: size)
                    XCTAssertLessThanOrEqual(fitted.height, size.height)
                    XCTAssertLessThanOrEqual(fitted.width, size.width)
                    let renderer = ImageRenderer(content: view)
                    renderer.proposedSize = .init(width: size.width, height: size.height)
                    renderer.scale = 2
                    let image = try XCTUnwrap(renderer.uiImage)
                    let attachment = XCTAttachment(image: image)
                    attachment.name = "content-\(layout)-\(language)-\(resting ? "rest" : "workout")"
                    attachment.lifetime = .keepAlways
                    add(attachment)
                }
            }
        }
    }

    @Observable fileprivate final class MutableSource: TrainingContentSource {
        var trainingContent: TrainingContentData
        init(trainingContent: TrainingContentData) { self.trainingContent = trainingContent }
    }

    private struct MetricsSample: View {
        let visible: Bool
        var body: some View {
            if visible {
                HStack {
                    Text(verbatim: "124 bpm")
                    Text(verbatim: "128 kcal")
                    Text(verbatim: "156 kcal")
                }.font(.caption2).frame(height: 29)
            }
        }
    }
}
