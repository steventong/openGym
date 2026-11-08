import XCTest
import SwiftUI
import UIKit
import Observation
@testable import OpenGYM

@MainActor final class ExerciseSearchTests: XCTestCase {
    func testBundledExerciseMatchesChineseEnglishAndIDInBothLanguages() throws {
        let exercises = try catalogueExercises()
        let original = AppLanguage.preferences.language
        defer { AppLanguage.preferences.language = original }
        for language in ["zh", "en"] {
            AppLanguage.preferences.language = language
            for query in ["窄距平行握", "chin-ups", "NARROW PARALLEL GRIP", "0253"] {
                XCTAssertEqual(matches(exercises, query).map(\.id), ["0253"], "\(language): \(query)")
            }
            for query in ["0254", "an exercise that does not exist", "不存在的动作"] {
                XCTAssertTrue(matches(exercises, query).isEmpty, "\(language): \(query)")
            }
            XCTAssertEqual(matches(exercises, "").count, exercises.count)
        }
        let exercise = try XCTUnwrap(exercises.first { $0.id == "0253" })
        XCTAssertTrue(exercise.searchText.contains("0253"), "IDs must retain their leading zero")
        for query in ["back", "upper back", "body weight"] {
            XCTAssertTrue(exercise.searchText.localizedCaseInsensitiveContains(query), query)
        }
    }

    func testCustomExerciseMatchesNameAndAlphanumericID() throws {
        let exercise = try XCTUnwrap(Exercise.custom([
            "id": "cSearch-Ab0253", "n": "窄距平行握引体向上 Neutral Pull-up",
            "bp": "back", "eq": "body weight", "tg": "lats"
        ]))
        for query in ["窄距平行握", "NEUTRAL PULL-UP", "cSearch-Ab0253", "CSEARCH-AB0253", "lats"] {
            XCTAssertTrue(exercise.searchText.localizedCaseInsensitiveContains(query), query)
        }
        XCTAssertFalse(exercise.searchText.localizedCaseInsensitiveContains("cSearch-Ab0254"))
        XCTAssertEqual(exercise.id, "cSearch-Ab0253")
    }

    func testSearchFiltersForEachKeystrokeAndDeletionWithoutReturnOrBlur() async throws {
        let state = SearchState(exercises: try catalogueExercises())
        try await withSearchField(state) { input in
            for query in ["0253", "chin-ups", "窄距平行握"] {
                state.query = ""
                try await settle()
                XCTAssertEqual(input.text, "")
                XCTAssertEqual(state.matches.count, state.exercises.count)
                var prefix = ""
                for character in query {
                    prefix.append(character)
                    input.insertText(String(character))
                    try await settle()
                    XCTAssertEqual(state.query, prefix)
                    XCTAssertTrue(state.matches.contains { $0.id == "0253" })
                    XCTAssertTrue(input.isFirstResponder, "Filtering must not dismiss the keyboard")
                }
                XCTAssertEqual(state.matches.map(\.id), ["0253"])
                input.deleteBackward()
                try await settle()
                XCTAssertEqual(state.query, String(query.dropLast()))
                XCTAssertTrue(input.isFirstResponder)
            }
            state.query = ""
            try await settle()
            XCTAssertEqual(input.text, "", "The clear action must also clear the visible field")
            XCTAssertEqual(state.matches.count, state.exercises.count)
            XCTAssertTrue(input.isFirstResponder)
            input.insertText("0651")
            try await settle()
            XCTAssertEqual(state.matches.map(\.id), ["0651"], "Clearing must leave the field ready for another search")
        }
    }

    func testSearchIgnoresParentFormBufferAndDoesNotCommitItsPendingEdits() async throws {
        let state = SearchState(exercises: try catalogueExercises())
        let buffer = InputCommitBuffer()
        var formCommits = 0
        buffer.stage(UUID()) { formCommits += 1 }
        try await withSearchField(state, buffer: buffer) { input in
            for character in "0253" {
                input.insertText(String(character))
                try await settle()
                XCTAssertEqual(state.query, input.text)
                XCTAssertTrue(buffer.hasPending)
                XCTAssertEqual(formCommits, 0)
            }
            XCTAssertEqual(state.matches.map(\.id), ["0253"])
            buffer.commitAll()
            XCTAssertEqual(formCommits, 1)
            XCTAssertFalse(buffer.hasPending, "Search must not stage edits in the enclosing form")
            XCTAssertTrue(input.isFirstResponder)
            input.deleteBackward()
            try await settle()
            XCTAssertEqual(state.query, "025")
            XCTAssertFalse(buffer.hasPending)
            XCTAssertEqual(formCommits, 1)
        }
    }

    func testLibrarySearchUsesDoneAndRetainsFocusWhileTyping() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = GymStore(storage: LocalTrainingStorage(root: root))
        store.registerCatalogue(try catalogueExercises())
        try await withPage(LibraryView().environment(store)) { _, input in
            XCTAssertEqual(input.returnKeyType, .done)
            for character in "0253" {
                input.insertText(String(character))
                try await settle()
                XCTAssertTrue(input.isFirstResponder)
            }
            XCTAssertEqual(input.text, "0253")
        }
    }

    func testHistoryFiltersImmediatelyForNameDateAndExerciseWithoutSearchKey() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = GymStore(storage: LocalTrainingStorage(root: root))
        store.registerCatalogue(try catalogueExercises())
        let workouts: [[String: Any]] = [
            ["id": "pull", "name": "Pull session", "d": "2026-11-07", "start": 1794000000000,
             "end": 1794003600000, "entries": [["id": "0253", "sets": [["done": true]]]]],
            ["id": "push", "name": "Push session", "d": "2026-11-06", "start": 1793913600000,
             "end": 1793917200000, "entries": [["id": "0025", "sets": [["done": true]]]]]
        ]
        try await withPage(WorkoutHistoryList(workouts: workouts, unsyncedIDs: []).environment(store)) { controller, input in
            XCTAssertEqual(input.returnKeyType, .done)
            let allRows = try rowsSnapshot(in: controller, below: input)
            let allData = try XCTUnwrap(allRows.pngData())
            var filteredData: Data?
            for query in ["Pull", "2026-11-07", "窄距平行握", "CHIN-UPS", "0253"] {
                input.insertText(query)
                try await settle()
                let filtered = try rowsSnapshot(in: controller, below: input)
                let data = try XCTUnwrap(filtered.pngData())
                XCTAssertNotEqual(data, allData, "The rows below the search field must update before Return: \(query)")
                if let filteredData { XCTAssertEqual(data, filteredData, "Each query should show the same Pull session") }
                else {
                    filteredData = data
                    for (name, image) in [("history-all-before-search", allRows), ("history-filtered-without-submit", filtered)] {
                        let attachment = XCTAttachment(image: image)
                        attachment.name = name
                        attachment.lifetime = .keepAlways
                        add(attachment)
                    }
                }
                XCTAssertTrue(input.isFirstResponder, "History must filter without dismissing the keyboard")
                input.selectedTextRange = input.textRange(from: input.beginningOfDocument, to: input.endOfDocument)
                input.deleteBackward()
                try await settle()
                XCTAssertEqual(input.text, "")
                XCTAssertEqual(try rowsSnapshot(in: controller, below: input).pngData(), allData,
                               "Deleting the query must restore both history rows immediately")
            }
        }
    }

    /// Compare only the list region, excluding the changing search text and keyboard.
    private func rowsSnapshot(in controller: UIViewController, below input: UITextField) throws -> UIImage {
        let view = try XCTUnwrap(controller.view)
        view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: view.bounds).image { _ in
            view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
        }
        let top = input.convert(input.bounds, to: view).maxY + 8
        let rect = CGRect(x: 0, y: top * image.scale, width: view.bounds.width * image.scale,
                          height: min(220, view.bounds.height - top) * image.scale)
        let cropped = try XCTUnwrap(image.cgImage?.cropping(to: rect))
        return UIImage(cgImage: cropped, scale: image.scale, orientation: .up)
    }

    private func catalogueExercises() throws -> [Exercise] {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "catalogue", withExtension: "json"))
        let catalogue = try JSONDecoder().decode([Exercise].self, from: Data(contentsOf: url))
        let exercises = catalogue.filter { ["0253", "0651", "0025"].contains($0.id) }
        XCTAssertEqual(exercises.count, 3)
        return exercises
    }

    private func matches(_ exercises: [Exercise], _ query: String) -> [Exercise] {
        exercises.filter { query.isEmpty || $0.searchText.localizedCaseInsensitiveContains(query) }
    }

    private func withSearchField(_ state: SearchState, buffer: InputCommitBuffer? = nil,
                                 perform: (UITextField) async throws -> Void) async throws {
        let field = ExerciseSearchField("Search", text: Binding(get: { state.query }, set: { state.query = $0 }))
            .environment(\.inputCommitBuffer, buffer)
        try await withPage(field) { _, input in
            XCTAssertEqual(input.returnKeyType, .done)
            try await perform(input)
        }
    }

    private func withPage<Content: View>(_ page: Content,
                                        perform: (UIHostingController<Content>, UITextField) async throws -> Void) async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousWindow = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        let controller = UIHostingController(rootView: page)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer {
            window.endEditing(true)
            window.isHidden = true
            window.rootViewController = nil
            previousWindow?.makeKey()
        }
        try await settle()
        let input = try XCTUnwrap(descendant(UITextField.self, in: window))
        XCTAssertTrue(input.becomeFirstResponder())
        try await Task.sleep(for: .milliseconds(350))
        try await perform(controller, input)
    }

    private func settle() async throws {
        try await Task.sleep(for: .milliseconds(100))
    }

    private func descendant<T: UIView>(_ type: T.Type, in root: UIView) -> T? {
        if let match = root as? T { return match }
        return root.subviews.lazy.compactMap { self.descendant(type, in: $0) }.first
    }

    @MainActor @Observable final class SearchState {
        var query = ""
        let exercises: [Exercise]
        init(exercises: [Exercise]) { self.exercises = exercises }
        var matches: [Exercise] {
            exercises.filter { query.isEmpty || $0.searchText.localizedCaseInsensitiveContains(query) }
        }
    }
}
