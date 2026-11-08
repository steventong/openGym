import XCTest
import SwiftUI
import UIKit
import Observation
@testable import OpenGYM

@MainActor final class HistoryNavigationTests: XCTestCase {
    func testStatisticsAndListCompareTheirOwnInputs() {
        let workouts: [[String: Any]] = [["id": "one", "name": "Workout", "entries": []]]
        let changed: [[String: Any]] = [["id": "one", "name": "Updated", "entries": []]]
        XCTAssertEqual(StatsView(workouts: workouts), StatsView(workouts: workouts))
        XCTAssertNotEqual(StatsView(workouts: workouts), StatsView(workouts: changed))
        XCTAssertEqual(WorkoutHistoryList(workouts: workouts, unsyncedIDs: []),
                       WorkoutHistoryList(workouts: workouts, unsyncedIDs: []))
        XCTAssertNotEqual(WorkoutHistoryList(workouts: workouts, unsyncedIDs: []),
                          WorkoutHistoryList(workouts: workouts, unsyncedIDs: ["one"]))
        XCTAssertNotEqual(WorkoutHistoryList(workouts: workouts, unsyncedIDs: []),
                          WorkoutHistoryList(workouts: changed, unsyncedIDs: []))
    }

    func testExerciseSummaryKeepsAllEntriesInOrderAndResolvesNamesLikePreview() throws {
        let exercise = try XCTUnwrap(Exercise.custom(["id": "cimp-bench", "n": "Bench press（杠铃卧推） · Gym A"]))
        let record = WorkoutRecord(raw: ["entries": [
            ["id": exercise.id, "n": "Saved name"],
            ["id": "deleted", "n": "AAAA"],
            ["id": exercise.id],
            ["id": "unknown"]
        ]])
        let fallback = String(localized: "EXERCISE", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
        XCTAssertEqual(record.exerciseSummary { $0 == exercise.id ? exercise : nil }, "杠铃卧推, AAAA, 杠铃卧推, \(fallback)")
        XCTAssertEqual(WorkoutRecord(raw: [:]).exerciseSummary { _ in nil }, "")
        XCTAssertEqual(WorkoutRecord(raw: ["entries": []]).exerciseSummary { _ in nil }, "")
    }

    func testExerciseSummaryWrapsButNeverGrowsBeyondTwoLines() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = GymStore(storage: LocalTrainingStorage(root: root))
        for width: CGFloat in [320, 390] {
            func render(_ names: [String]) throws -> UIImage {
                let record = WorkoutRecord(raw: ["id": "summary", "name": "Workout", "d": "2026-11-07",
                    "start": 1794000000000, "end": 1794003600000,
                    "entries": names.map { ["n": $0] }])
                let renderer = ImageRenderer(content:
                    WorkoutHistoryRow(record: record, unsynced: false, syncing: false, preview: {}, sync: {})
                        .frame(width: width)
                        .environment(store)
                        .environment(\.locale, AppLanguage.locale)
                        .preferredColorScheme(.dark))
                return try XCTUnwrap(renderer.uiImage)
            }
            let oneLine = try render(["AAAA"])
            let names = Array(repeating: "AAAA, bbbbb, ccccc, ddddd", count: 8)
            let twoLines = try render(names)
            let longer = try render(names + names)
            XCTAssertGreaterThan(twoLines.size.height, oneLine.size.height, "Names should wrap to a second line")
            XCTAssertEqual(twoLines.size.height, longer.size.height, accuracy: 0.5, "More exercises must truncate, not add a third line")
            let attachment = XCTAttachment(image: twoLines)
            attachment.name = "history-exercises-two-lines-\(Int(width))"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    func testSegmentsSwitchPagesAndPreserveSearchInBothLanguages() async throws {
        let original = AppLanguage.preferences.language
        defer { AppLanguage.preferences.language = original }
        for (language, titles) in [("zh", ["统计", "列表"]), ("en", ["Stats", "List"])] {
            AppLanguage.preferences.language = language
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let store = GymStore(storage: LocalTrainingStorage(root: root))
            let names = language == "zh"
                ? ["杠铃卧推", "上斜哑铃卧推", "坐姿器械推胸", "绳索夹胸", "绳索下压", "哑铃飞鸟"]
                : ["Barbell bench press", "Incline dumbbell press", "Machine chest press", "Cable fly", "Triceps pushdown", "Dumbbell fly"]
            store.state = ["workouts": (1...2).map { index -> [String: Any] in
                ["id": "history-\(index)", "name": "Workout \(index)", "d": "2026-11-07",
                 "start": 1794000000000, "end": 1794003600000,
                 "entries": names.map { ["n": $0, "sets": [["done": true]]] }]
            }]
            let controller = UIHostingController(rootView:
                TabView {
                    Tab { HistoryView() } label: { Label("HISTORY", systemImage: "clock.arrow.circlepath") }
                }
                .environment(store)
                .environment(\.locale, AppLanguage.locale)
                .background(GymTheme.background)
                .foregroundStyle(.white)
                .tint(GymTheme.green)
                .preferredColorScheme(.dark))
            let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let previousWindow = scene.keyWindow
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
            window.rootViewController = controller
            window.makeKeyAndVisible()
            defer {
                window.isHidden = true
                previousWindow?.makeKey()
            }
            controller.view.frame = window.bounds

            func settle() async throws {
                controller.view.setNeedsLayout()
                controller.view.layoutIfNeeded()
                try await Task.sleep(for: .milliseconds(350))
            }
            func visibleFields() -> [UITextField] {
                descendants(of: UITextField.self, in: controller.view).filter { field in
                    !field.isHidden && field.alpha > 0 && field.window != nil &&
                        field.convert(field.bounds, to: window).intersects(window.bounds)
                }
            }
            func attach(_ name: String) {
                let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                    window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                }
                let attachment = XCTAttachment(image: image)
                attachment.name = "history-\(name)-\(language)"
                attachment.lifetime = .keepAlways
                add(attachment)
            }

            try await settle()
            let picker = try XCTUnwrap(descendants(of: UISegmentedControl.self, in: controller.view).first)
            XCTAssertEqual(picker.numberOfSegments, 2)
            XCTAssertEqual(picker.titleForSegment(at: 0), titles[0])
            XCTAssertEqual(picker.titleForSegment(at: 1), titles[1])
            XCTAssertEqual(picker.selectedSegmentIndex, 0)
            XCTAssertTrue(visibleFields().isEmpty, "The statistics page must not contain the history search")
            attach("stats")

            picker.selectedSegmentIndex = 1
            picker.sendActions(for: .valueChanged)
            try await settle()
            attach("list")
            let search = try XCTUnwrap(visibleFields().first)
            search.becomeFirstResponder()
            search.text = "Workout 2"
            search.sendActions(for: .editingChanged)
            window.endEditing(true)
            try await settle()

            picker.selectedSegmentIndex = 0
            picker.sendActions(for: .valueChanged)
            try await settle()
            XCTAssertTrue(visibleFields().isEmpty)
            picker.selectedSegmentIndex = 1
            picker.sendActions(for: .valueChanged)
            try await settle()
            XCTAssertEqual(visibleFields().first?.text, "Workout 2", "Changing sub tabs must keep the search")
        }
    }

    func testHistoryAutomaticallyLoadsBatchesAtBottomIncludingSearchResults() async throws {
        for (query, count, matchingCount) in [("", 65, 65), ("Match", 70, 35)] {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let store = GymStore(storage: LocalTrainingStorage(root: root))
            let workouts: [[String: Any]] = (1...count).map { index in
                ["id": "page-\(index)", "name": "\(index.isMultiple(of: 2) ? "Match" : "Other") \(index)",
                 "d": "2026-11-07", "start": 1794000000000, "end": 1794003600000,
                 "entries": [["n": "AAAA", "sets": [["done": true]]]]]
            }
            let controller = UIHostingController(rootView:
                WorkoutHistoryList(workouts: workouts, unsyncedIDs: []).equatable()
                    .environment(store)
                    .environment(\.locale, AppLanguage.locale)
                    .background(GymTheme.background)
                    .foregroundStyle(.white)
                    .preferredColorScheme(.dark))
            let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let previous = scene.keyWindow
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
            window.rootViewController = controller
            window.makeKeyAndVisible()
            defer { window.isHidden = true; previous?.makeKey() }
            controller.view.frame = window.bounds

            func settle() async throws {
                controller.view.setNeedsLayout()
                controller.view.layoutIfNeeded()
                try await Task.sleep(for: .milliseconds(600))
            }
            try await settle()
            let search = try XCTUnwrap(descendants(of: UITextField.self, in: controller.view).first)
            if !query.isEmpty {
                search.becomeFirstResponder()
                search.text = query
                search.sendActions(for: .editingChanged)
                window.endEditing(true)
                try await settle()
            }
            let scroll = try XCTUnwrap(descendants(of: UIScrollView.self, in: controller.view).first {
                $0.contentSize.height > $0.bounds.height
            })
            let initialHeight = scroll.contentSize.height
            let initialOffset = scroll.contentOffset.y
            try await settle()
            XCTAssertEqual(scroll.contentSize.height, initialHeight, accuracy: 2, "Do not load more while staying at the top")
            XCTAssertEqual(scroll.contentOffset.y, initialOffset, accuracy: 2)

            var previousHeight = initialHeight
            for _ in stride(from: 30, to: matchingCount, by: 30) {
                let bottom = max(-scroll.adjustedContentInset.top,
                    scroll.contentSize.height + scroll.adjustedContentInset.bottom - scroll.bounds.height)
                scroll.setContentOffset(CGPoint(x: 0, y: bottom), animated: false)
                try await settle()
                if scroll.contentSize.height <= previousHeight + 100 {
                    let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                        window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                    }
                    let attachment = XCTAttachment(image: image)
                    attachment.name = "pagination-bottom-\(query)-\(Int(previousHeight))"
                    attachment.lifetime = .keepAlways
                    add(attachment)
                }
                XCTAssertGreaterThan(scroll.contentSize.height, previousHeight + 100, "Reaching the bottom must append the next batch without a tap; query=\(query)")
                XCTAssertGreaterThan(scroll.contentOffset.y, initialOffset + 100, "Loading must not jump back to the top")
                previousHeight = scroll.contentSize.height
            }
            let bottom = max(-scroll.adjustedContentInset.top,
                scroll.contentSize.height + scroll.adjustedContentInset.bottom - scroll.bounds.height)
            scroll.setContentOffset(CGPoint(x: 0, y: bottom), animated: false)
            try await settle()
            // Visiting the final rows settles LazyVStack's estimated heights.
            let completeHeight = scroll.contentSize.height
            let completeBottom = max(-scroll.adjustedContentInset.top,
                completeHeight + scroll.adjustedContentInset.bottom - scroll.bounds.height)
            scroll.setContentOffset(CGPoint(x: 0, y: completeBottom), animated: false)
            try await settle()
            XCTAssertEqual(scroll.contentSize.height, completeHeight, accuracy: 2, "Stop when all matching workouts are displayed")
        }
    }

    func testHistoryPreviewMenuSnapshotsInBothLanguages() async throws {
        let original = AppLanguage.preferences.language
        defer { AppLanguage.preferences.language = original }
        for language in ["en", "zh"] {
            AppLanguage.preferences.language = language
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let store = GymStore(userID: "history-ui", storage: LocalTrainingStorage(root: root))
            let record = WorkoutRecord(raw: ["id": "menu-record", "name": "Workout", "d": "2026-11-07",
                "start": 1794000000000, "end": 1794003600000, "entries": []])
            store.state = ["workouts": [record.raw]]
            store.historyHealth = HistoryHealthSync(available: true, authorize: {}, deletePrevious: { _ in XCTFail("Rendering must not delete a workout") }, save: { _ in XCTFail("Rendering must not write a workout") })
            let controller = UIHostingController(rootView: WorkoutHistoryPreview(record: record)
                .environment(store).environment(\.locale, AppLanguage.locale).preferredColorScheme(.dark))
            let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let previous = scene.keyWindow
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
            window.rootViewController = controller
            window.makeKeyAndVisible()
            defer { window.isHidden = true; previous?.makeKey() }
            controller.view.frame = window.bounds
            try await Task.sleep(for: .milliseconds(350))
            controller.view.layoutIfNeeded()
            XCTAssertTrue(controller.isViewLoaded)
            XCTAssertGreaterThan(controller.view.bounds.width, 0)
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = "history-preview-menu-\(language)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    func testHistoryInfoOpensBuiltInAndCustomDetailsWithoutEditingRecords() async throws {
        let originalLanguage = AppLanguage.preferences.language
        defer { AppLanguage.preferences.language = originalLanguage }
        AppLanguage.preferences.language = "zh"
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = GymStore(storage: LocalTrainingStorage(root: root))
        store.serverURL = ""
        let catalogueURL = try XCTUnwrap(Bundle.main.url(forResource: "catalogue", withExtension: "json"))
        let catalogue = try JSONDecoder().decode([Exercise].self, from: Data(contentsOf: catalogueURL))
        store.registerCatalogue(catalogue)
        let source = try XCTUnwrap(store.exercise("0253"))
        let customID = "c-history-neutral-pullup"
        let record = WorkoutRecord(raw: ["id": "info-record", "name": "Workout", "d": "2026-11-07",
            "start": 1794000000000, "end": 1794003600000,
            "entries": ["0253", customID, "missing-exercise"].map { ["id": $0, "sets": []] as [String: Any] }])
        store.state = ["workouts": [record.raw], "customEx": [["id": customID, "n": "窄距平行握引体向上",
            "english": source.english, "bp": "back", "eq": "body weight", "tg": "upper back",
            "desc": source.description, "instructions": source.instructions, "img": "0253.webp", "gif": "0253.mp4"]]]
        let baseline = store.state
        for (index, id) in ["0253", customID].enumerated() {
            let presentation = InfoPresentationState()
            let card = WorkoutHistoryExerciseCard(entry: ["id": id, "sets": []], index: index, unit: "kg") {
                presentation.detail = store.exercise(id)
            }
            let content = card.environment(store).sheet(item: Binding(get: { presentation.detail }, set: { presentation.detail = $0 })) {
                ExerciseDetail(exercise: $0).environment(store)
            }
            try await withHistoryWindow(content) { controller, window in
                // Exercise the exact callback used by the card's Button, without private SwiftUI AX APIs.
                card.showDetails()
                try await Task.sleep(for: .milliseconds(450))
                XCTAssertEqual(presentation.detail?.id, id)
                XCTAssertEqual(presentation.detail?.name, id == customID ? "窄距平行握引体向上" : source.name)
                XCTAssertNotNil(controller.presentedViewController, "The detail must present from the history layer")
                let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                    window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                }
                let attachment = XCTAttachment(image: image)
                attachment.name = "history-exercise-detail-\(id)"
                attachment.lifetime = .keepAlways
                add(attachment)
                let dismissed = expectation(description: "History exercise detail dismissed")
                controller.dismiss(animated: false) { dismissed.fulfill() }
                await fulfillment(of: [dismissed], timeout: 3)
                presentation.detail = nil
                XCTAssertNil(controller.presentedViewController)
                XCTAssertTrue(RecordPatch.equal(store.state, baseline))
                XCTAssertTrue(store.historyEdits.isEmpty)
            }
        }
        XCTAssertNil(store.exercise("missing-exercise"))
    }

    func testHistoryEditorRendersWithoutChangingRecords() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = GymStore(storage: LocalTrainingStorage(root: root))
        let record = WorkoutRecord(raw: ["id": "safe-menu", "name": "Workout", "d": "2026-11-07",
            "start": 1794000000000, "end": 1794003600000, "entries": []])
        store.state = ["workouts": [record.raw]]
        try await withHistoryWindow(HistoryEditor(record: record, unit: "kg").environment(store)) { controller, window in
            XCTAssertTrue(self.descendants(of: UITextField.self, in: controller.view).contains { $0.text == "Workout" })
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = "history-safe-editor-menu"
            attachment.lifetime = .keepAlways
            add(attachment)
            XCTAssertTrue(RecordPatch.equal(store.state["workouts"], [record.raw]))
            XCTAssertTrue(store.historyEdits.isEmpty)
        }
    }

    private func withHistoryWindow<Content: View>(_ content: Content,
        perform: (UIHostingController<Content>, UIWindow) async throws -> Void) async throws {
        let controller = UIHostingController(rootView: content)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKey() }
        controller.view.frame = window.bounds
        try await Task.sleep(for: .milliseconds(350))
        controller.view.layoutIfNeeded()
        try await perform(controller, window)
    }

    @MainActor @Observable final class InfoPresentationState {
        var detail: Exercise?
    }

    private func descendants<T: UIView>(of type: T.Type, in view: UIView) -> [T] {
        (view as? T).map { [$0] } ?? view.subviews.flatMap { descendants(of: type, in: $0) }
    }
}
