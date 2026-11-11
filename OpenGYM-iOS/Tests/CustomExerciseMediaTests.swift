import XCTest
import UIKit
@testable import OpenGYM

@MainActor final class CustomExerciseMediaTests: XCTestCase {
    private let customID = "c-narrow-neutral-pullup"

    func testCopyingCatalogueExercisePreservesDefinitionAndMedia() throws {
        let source = try sourceExercise()
        let store = try makeStore(custom: [:])
        let raw = try store.exerciseCopyRecord(source, id: customID, name: "我的引体向上")
        XCTAssertEqual(raw["custom"] as? Bool, true)
        XCTAssertEqual(raw["primaries"] as? [String], ["upper-back"])
        XCTAssertEqual(raw["secondaries"] as? [String], ["biceps", "deltoids", "forearm"])
        XCTAssertEqual(raw["st"] as? [String], source.englishInstructions)
        XCTAssertEqual(raw["fv"] as? String, "3600")

        store.state["customEx"] = [raw]
        let copy = try XCTUnwrap(store.exercise(customID))
        XCTAssertEqual(copy.name, "我的引体向上")
        XCTAssertEqual(copy.english, source.english)
        XCTAssertEqual(copy.bodyPart, source.bodyPart)
        XCTAssertEqual(copy.equipment, source.equipment)
        XCTAssertEqual(copy.target, source.target)
        XCTAssertEqual(copy.category, source.category)
        XCTAssertEqual(copy.description, source.description)
        XCTAssertEqual(copy.instructions, source.instructions)
        XCTAssertEqual(copy.englishInstructions, source.englishInstructions)
        XCTAssertEqual(store.imageMediaID(copy.id), source.id)
        XCTAssertEqual(store.videoMediaID(copy.id), source.id)
        XCTAssertEqual(store.exercise(source.id), source)
        XCTAssertNotNil(store.customExerciseNameIssue(source.english.uppercased()))
        XCTAssertNotNil(store.customExerciseNameIssue(copy.name))
        XCTAssertNotNil(store.customExerciseNameIssue(String(repeating: "a", count: 81)))
        XCTAssertNotNil(store.customExerciseNameIssue(""))
        XCTAssertNil(store.customExerciseNameIssue("另一组引体向上"))
    }

    func testCopyingCustomExerciseKeepsOtherFieldsAndDropsSyncMetadata() throws {
        let source = try sourceExercise()
        var original = copiedExercise(source)
        original["url"] = "https://example.com/tutorial"
        original["muscleWeights"] = ["upper-back": 1, "biceps": 0.4]
        original["futureField"] = ["value": 3]
        original["_ts"] = 100
        original["_f"] = ["desc": 100]
        original["_u"] = ["n": 100]
        let store = try makeStore(custom: original)
        let exercise = try XCTUnwrap(store.exercise(customID))
        let copy = try store.exerciseCopyRecord(exercise, id: "c-copy", name: "备用引体向上")

        XCTAssertEqual(copy["id"] as? String, "c-copy")
        XCTAssertEqual(copy["n"] as? String, "备用引体向上")
        for (key, value) in original where !["id", "n", "_ts", "_f", "_u"].contains(key) {
            XCTAssertTrue(RecordPatch.equal(copy[key], value), key)
        }
        for key in ["_ts", "_f", "_u"] { XCTAssertNil(copy[key]) }
        XCTAssertTrue(RecordPatch.equal(store.customExercises.first, original))
    }

    func testCopyingAssistanceMachineKeepsLoadSemanticsAfterRename() throws {
        let store = try makeStore(custom: [:])
        let source = try XCTUnwrap(store.exercises.first {
            $0.equipment == "leverage machine" && $0.english.contains("assisted")
        })
        let copy = try store.exerciseCopyRecord(source, id: customID, name: "我的训练动作")
        XCTAssertEqual(copy["assisted"] as? Bool, true)
    }

    func testCustomExerciseReusesCatalogueMediaAndInstructionsWithoutChangingIdentity() throws {
        let source = try sourceExercise()
        let store = try makeStore(custom: copiedExercise(source))
        store.serverURL = "https://gym.example/base"
        let custom = try XCTUnwrap(store.exercise(customID))
        XCTAssertEqual(custom.id, customID)
        XCTAssertEqual(custom.name, "窄距平行握引体向上")
        XCTAssertEqual(custom.english, source.english)
        XCTAssertEqual(custom.instructions, source.instructions)
        XCTAssertEqual(custom.englishInstructions, source.englishInstructions)
        XCTAssertEqual(custom.description, source.description)
        XCTAssertEqual(custom.bodyPart, source.bodyPart)
        XCTAssertEqual(custom.equipment, source.equipment)
        XCTAssertEqual(custom.target, source.target)
        XCTAssertEqual(store.exercise(source.id), source)
        XCTAssertEqual(store.imageMediaID(customID), source.id)
        XCTAssertEqual(store.videoMediaID(customID), source.id)
        XCTAssertEqual(store.remoteImageURL(customID)?.absoluteString, "https://gym.example/base/exercise-media/still/0253.webp")
        XCTAssertEqual(store.remoteVideoURL(customID)?.absoluteString, "https://gym.example/base/exercise-media/clip/0253.mp4")
        XCTAssertTrue(custom.searchText.localizedCaseInsensitiveContains("NARROW PARALLEL GRIP"))
        XCTAssertTrue(custom.searchText.contains(customID))
        XCTAssertNotEqual(custom.id, source.id)
        let roundTrip = try JSONDecoder().decode(Exercise.self, from: JSONEncoder().encode(custom))
        XCTAssertEqual(roundTrip, custom)
    }

    func testLegacyCustomAndCatalogueRecordsRemainCompatible() throws {
        let store = try makeStore(custom: ["id": customID, "n": "我的动作", "bp": "back"])
        let custom = try XCTUnwrap(store.exercise(customID))
        XCTAssertEqual(custom.english, "")
        XCTAssertTrue(custom.instructions.isEmpty)
        XCTAssertNil(custom.englishInstructions)
        XCTAssertNil(custom.imageFile)
        XCTAssertNil(custom.videoFile)
        XCTAssertNil(store.imageMediaID(customID))
        XCTAssertNil(store.videoMediaID(customID))
        XCTAssertNil(store.remoteImageURL(customID))
        XCTAssertNil(store.remoteVideoURL(customID))
        XCTAssertNil(store.videoURL(customID))
        XCTAssertEqual(store.imageMediaID("0253"), "0253")
        XCTAssertEqual(store.videoMediaID("0253"), "0253")
        XCTAssertNil(try sourceExercise().imageFile)
        XCTAssertNil(try sourceExercise().videoFile)
    }

    func testMediaReferencesRejectPathsURLsUnknownIDsAndWrongExtensions() throws {
        var custom = copiedExercise(try sourceExercise())
        let store = try makeStore(custom: custom)
        store.serverURL = "https://gym.example"
        for invalid in ["../0253", "/0253", "https://example.com/0253", "0253?x=1", "0253\n", "０２５３", "99999", customID, "025", "002533"] {
            custom["img"] = invalid + ".webp"
            custom["gif"] = invalid + ".mp4"
            store.state = ["customEx": [custom]]
            XCTAssertNil(store.imageMediaID(customID), invalid)
            XCTAssertNil(store.videoMediaID(customID), invalid)
            XCTAssertNil(store.remoteImageURL(customID), invalid)
            XCTAssertNil(store.remoteVideoURL(customID), invalid)
            XCTAssertNil(store.videoURL(customID), invalid)
        }
        custom["img"] = "0253.mp4"
        custom["gif"] = "0253.webp"
        store.state = ["customEx": [custom]]
        XCTAssertNil(store.imageMediaID(customID))
        XCTAssertNil(store.videoMediaID(customID))
    }

    func testChangingAndRemovingReferencesUpdatesResolutionWithoutChangingHistory() throws {
        var custom = copiedExercise(try sourceExercise())
        let store = try makeStore(custom: custom)
        let workout: [String: Any] = ["id": "history", "entries": [["id": customID, "sets": [["w": 0, "r": 8, "done": true]]]]]
        store.state = ["customEx": [custom], "workouts": [workout]]
        custom["img"] = "0651.webp"
        store.state["customEx"] = [custom]
        XCTAssertEqual(store.imageMediaID(customID), "0651")
        XCTAssertEqual(store.videoMediaID(customID), "0253", "Image and video references are independent")
        custom["gif"] = "0289.mp4"
        store.state["customEx"] = [custom]
        XCTAssertEqual(store.videoMediaID(customID), "0289")
        custom.removeValue(forKey: "img")
        custom.removeValue(forKey: "gif")
        store.state["customEx"] = [custom]
        XCTAssertNil(store.imageMediaID(customID))
        XCTAssertNil(store.videoMediaID(customID))
        XCTAssertTrue(RecordPatch.equal(store.state["workouts"], [workout]))
        XCTAssertEqual(store.exercise(customID)?.id, customID)
        XCTAssertEqual(store.imageMediaID("0253"), "0253")
    }

    func testMediaRequiresALoadedCatalogueAndMalformedOptionalFieldsStaySafe() throws {
        let store = GymStore()
        var custom = copiedExercise(try sourceExercise())
        store.state = ["customEx": [custom]]
        XCTAssertNil(store.imageMediaID(customID))
        XCTAssertNil(store.videoMediaID(customID))
        store.registerCatalogue(try catalogue())
        XCTAssertEqual(store.imageMediaID(customID), "0253")
        custom["img"] = 253
        custom["gif"] = ["0253.mp4"]
        custom["instructions"] = [1]
        custom["englishInstructions"] = NSNull()
        custom["english"] = NSNull()
        store.state = ["customEx": [custom]]
        XCTAssertNil(store.imageMediaID(customID))
        XCTAssertNil(store.videoMediaID(customID))
        XCTAssertTrue(try XCTUnwrap(store.exercise(customID)).instructions.isEmpty)
    }

    func testOriginalAndCustomExercisesShareValidatedOfflineFiles() async throws {
        var custom = copiedExercise(try sourceExercise())
        custom["img"] = "0289.webp"
        custom["gif"] = "0289.mp4"
        let store = try makeStore(custom: custom)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        for ext in ["webp", "mp4"] {
            let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "0289", withExtension: ext))
            try FileManager.default.copyItem(at: fixture, to: directory.appendingPathComponent("0289.\(ext)"))
        }
        let images = ExerciseImageCache(directory: directory)
        let videos = ExerciseVideoCache(directory: directory)
        for id in ["0289", customID] {
            let imageID = try XCTUnwrap(store.imageMediaID(id))
            let videoID = try XCTUnwrap(store.videoMediaID(id))
            let image = try await images.image(for: imageID, remoteURL: nil)
            XCTAssertGreaterThan(image.size.width, 0)
            let video = try await videos.video(for: videoID, remoteURL: nil)
            XCTAssertEqual(video.lastPathComponent, "0289.mp4")
            XCTAssertEqual(images.cachedURL(for: imageID)?.lastPathComponent, "0289.webp")
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted(), ["0289.mp4", "0289.webp"])
        XCTAssertEqual(store.exercise(customID)?.id, customID)
    }

    private func catalogue() throws -> [Exercise] {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "catalogue", withExtension: "json"))
        return try JSONDecoder().decode([Exercise].self, from: Data(contentsOf: url))
    }

    private func sourceExercise() throws -> Exercise {
        try XCTUnwrap(catalogue().first { $0.id == "0253" })
    }

    private func copiedExercise(_ source: Exercise) -> [String: Any] {
        ["id": customID, "n": "窄距平行握引体向上", "custom": true,
         "english": source.english, "bp": source.bodyPart, "eq": source.equipment,
         "tg": source.target, "cat": source.category, "desc": source.description,
         "instructions": source.instructions, "englishInstructions": source.englishInstructions ?? [],
         "img": "0253.webp", "gif": "0253.mp4"]
    }

    private func makeStore(custom: [String: Any]) throws -> GymStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let store = GymStore(storage: LocalTrainingStorage(root: directory))
        store.registerCatalogue(try catalogue())
        store.state = ["customEx": [custom]]
        return store
    }
}
