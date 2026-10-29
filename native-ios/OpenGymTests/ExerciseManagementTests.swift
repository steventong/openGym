import XCTest
@testable import OpenGym

final class ExerciseManagementTests: XCTestCase {
    @MainActor private func edit(_ active: [String: Any], _ action: String, index: Int = 0, direction: Int = 0, id: String? = nil) throws -> [String: Any] {
        var payload: [String: Any] = ["active": active, "state": ["unit": "kg"], "action": action, "index": index, "direction": direction]
        payload["id"] = id
        return try XCTUnwrap(WebRules.shared.call("manageTrainingExercises", payload: payload) as? [String: Any])
    }
    private func entry(_ id: String = "0289", done: Bool = false) -> [String: Any] {
        ["id": id, "rid": "routine-a", "target": ["id": id, "mode": "reps"], "sets": [["w": 15, "r": 10, "done": done]]]
    }
    @MainActor func testReorderDuplicateIDsRemapsTimersAndProgressByOccurrence() throws {
        var first = entry(); first["note"] = "first"
        var second = entry(); second["note"] = "second"
        let active: [String: Any] = ["entries": [first, second], "cur": 0, "nativeTimer": ["entry": 0, "set": 0, "paused": true], "nativeRest": ["entry": 1, "set": 0], "nativeHighWater": ["0": 3, "1": 5], "nativeFinishAt": 123]
        let result = try edit(active, "move", direction: 1)
        XCTAssertEqual((result["entries"] as? [[String: Any]])?[1]["note"] as? String, "first")
        XCTAssertEqual(result["cur"] as? Int, 1)
        XCTAssertEqual((result["nativeTimer"] as? [String: Any])?["entry"] as? Int, 1)
        XCTAssertEqual((result["nativeRest"] as? [String: Any])?["entry"] as? Int, 0)
        XCTAssertEqual((result["nativeHighWater"] as? [String: Any])?["1"] as? Int, 3)
        XCTAssertNil(result["nativeFinishAt"])
    }
    @MainActor func testDeletionClearsOwnedTimerAndDissolvesOrphanSuperset() throws {
        var first = entry(), second = entry("1047")
        first["sg"] = "pair"; second["sg"] = "pair"; second["target"] = ["sg": "pair", "sgRest": 45, "future": "keep"]
        let result = try edit(["entries": [first, second], "cur": 1, "nativeTimer": ["entry": 0, "set": 0], "nativeRest": ["entry": 1, "set": 0]], "remove")
        let kept = try XCTUnwrap((result["entries"] as? [[String: Any]])?.first)
        XCTAssertNil(result["nativeTimer"])
        XCTAssertEqual((result["nativeRest"] as? [String: Any])?["entry"] as? Int, 0)
        XCTAssertNil(kept["sg"]); XCTAssertNil((kept["target"] as? [String: Any])?["sg"])
        XCTAssertEqual((kept["target"] as? [String: Any])?["future"] as? String, "keep")
        XCTAssertEqual(result["cur"] as? Int, 0)
    }
    @MainActor func testReplacingPartialSidePreservesLoggedEntryAndInsertsFreshExercise() throws {
        var partial = entry()
        partial["sets"] = [["kind": "side", "sides": ["L": ["w": 12, "r": 8, "done": true], "R": ["w": 12, "r": 8, "done": false]], "done": false]]
        let result = try edit(["entries": [partial, entry("1047")], "nativeRest": ["entry": 1, "set": 0]], "replace", id: "0001")
        let rows = try XCTUnwrap(result["entries"] as? [[String: Any]])
        XCTAssertEqual(rows.count, 3); XCTAssertTrue(RecordPatch.equal(rows[0], partial))
        XCTAssertEqual(rows[1]["id"] as? String, "0001"); XCTAssertEqual(rows[1]["rid"] as? String, "routine-a")
        XCTAssertFalse((rows[1]["sets"] as! [[String: Any]]).contains(where: rawCompleted))
        XCTAssertEqual((result["nativeRest"] as? [String: Any])?["entry"] as? Int, 2)
    }
    @MainActor func testUnloggedReplacementClearsOwnedTimerAndSameIDIsNoOp() throws {
        let active: [String: Any] = ["entries": [entry()], "nativeTimer": ["entry": 0, "set": 0], "nativeHighWater": ["0": 2]]
        XCTAssertTrue(RecordPatch.equal(try edit(active, "replace", id: "0289"), active))
        let result = try edit(active, "replace", id: "0001")
        XCTAssertEqual((result["entries"] as? [[String: Any]])?.count, 1)
        XCTAssertNil(result["nativeTimer"]); XCTAssertNil((result["nativeHighWater"] as? [String: Any])?["0"])
    }
    @MainActor func testLoggedSupersetReplacementLeavesOriginalPartnersTogether() throws {
        var first = entry(done: true), second = entry("1047")
        first["sg"] = "pair"; second["sg"] = "pair"
        let result = try edit(["entries": [first, second]], "replace", id: "0001")
        let entries = result["entries"] as! [[String: Any]]
        XCTAssertEqual(entries[0]["sg"] as? String, "pair"); XCTAssertEqual(entries[1]["sg"] as? String, "pair")
        XCTAssertEqual(entries[2]["id"] as? String, "0001"); XCTAssertNil(entries[2]["sg"])
        XCTAssertEqual(result["cur"] as? Int, 2)
    }
    @MainActor func testAddingUsesExerciseIDToBuildCardioSets() throws {
        let state: [String: Any] = ["customEx": [["id": "cardio-test", "n": "Test Cardio", "cat": "cardio", "eq": "body weight", "bp": "cardio", "tg": "cardiovascular system"]]]
        let result = try WebRules.shared.call("manageTrainingExercises", payload: ["active": ["entries": []], "state": state, "action": "add", "id": "cardio-test"]) as! [String: Any]
        let entry = (result["entries"] as! [[String: Any]])[0]
        XCTAssertEqual((entry["target"] as? [String: Any])?["id"] as? String, "cardio-test")
        XCTAssertNotNil(((entry["sets"] as? [[String: Any]])?.first)?["min"])
    }
    @MainActor func testRoutineReplacementKeepsPrescriptionAndUnknownFields() throws {
        let slot: [String: Any] = ["id": "0289", "sets": 4, "reps": 12, "restSec": 120, "note": "keep", "future": "keep"]
        let result = try WebRules.shared.call("replaceNativeRoutineExercise", payload: ["slot": slot, "id": "1047", "state": ["workouts": [], "routines": []], "rid": "routine-a"]) as! [String: Any]
        XCTAssertEqual(result["id"] as? String, "1047"); XCTAssertEqual(result["sets"] as? Int, 4)
        XCTAssertEqual(result["restSec"] as? Int, 120); XCTAssertEqual(result["note"] as? String, "keep")
        XCTAssertEqual(result["future"] as? String, "keep")
    }
    @MainActor func testRemoveLastThenAddCanRecoverAnEmptySession() throws {
        let empty = try edit(["entries": [entry()], "cur": 0], "remove")
        XCTAssertTrue((empty["entries"] as! [[String: Any]]).isEmpty)
        let result = try edit(empty, "add", id: "0001")
        XCTAssertEqual(result["cur"] as? Int, 0)
        XCTAssertFalse(((result["entries"] as! [[String: Any]])[0]["sets"] as! [[String: Any]]).isEmpty)
    }
    @MainActor func testLiveReorderSurvivesDiskRestore() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = LocalTrainingStorage(root: root)
        let store = GymStore(userID: "exercise-management", storage: storage)
        store.draft = try TrainingDraft.fromWeb(["id": "test", "start": 1000, "entries": [entry(), entry("1047")], "cur": 0], unit: "kg")
        store.startRest(entry: 0, seconds: 90, set: 0)
        store.manageLiveExercise(action: "move", index: 0, direction: 1)
        let restored = GymStore(userID: "exercise-management", storage: storage); restored.restoreDraft()
        XCTAssertEqual(restored.draft?.rawEntries[1]["id"] as? String, "0289")
        XCTAssertEqual(restored.restEntry, 1)
    }
    @MainActor func testHistoricalReorderAndReplacementPreserveLiteralInputAndSelection() throws {
        var old = entry(done: true)
        old["target"] = ["id": "0289", "mode": "reps", "side": true, "assisted": true]
        old["sets"] = [["w": 15, "r": 10, "done": true, TrainingInput.key: ["both.w": "15."]]]
        var form = HistoryForm(original: ["id": "history", "start": 1000, "end": 61000, "entries": [old, entry("1047")]], unit: "kg")
        try form.manageExercise(action: "move", direction: 1, state: [:])
        XCTAssertEqual(form.selected, 1)
        try form.manageExercise(action: "replace", id: "0001", state: [:])
        XCTAssertEqual(form.entries.count, 2); XCTAssertEqual(form.entries[1].raw["id"] as? String, "0001")
        XCTAssertEqual((form.entries[1].sets[0].raw[TrainingInput.key] as? [String: String])?["both.w"], "15.")
        XCTAssertEqual(form.entries[1].sets[0].raw["done"] as? Bool, true)
        XCTAssertNil((form.entries[1].raw["target"] as? [String: Any])?["assisted"])
        let restored = HistoryForm(original: form.original, unit: "kg", saved: ["proposed": form.proposed, "form": form.fields])
        XCTAssertEqual(restored.selected, 1); XCTAssertEqual(restored.entries[1].raw["id"] as? String, "0001")
    }
}
