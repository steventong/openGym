import XCTest
@testable import OpenGYM

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
    @MainActor func testBatchReorderPreservesDuplicateOccurrencesAndRemapsAllReferences() throws {
        var first = entry(), second = entry(), third = entry("1047")
        first["note"] = "first"; second["note"] = "second"; third["note"] = "third"
        first["sg"] = "pair"; second["sg"] = "pair"
        let active: [String: Any] = ["entries": [first, second, third], "cur": 1,
            "nativeTimer": ["entry": 0, "set": 0], "nativeRest": ["entry": 2, "set": 0],
            "nativeHighWater": ["0": 3, "1": 5, "2": 7]]
        let result = try ExerciseOrder.apply([2, 0, 1], to: active)
        let entries = try XCTUnwrap(result["entries"] as? [[String: Any]])
        XCTAssertEqual(entries.compactMap { $0["note"] as? String }, ["third", "first", "second"])
        XCTAssertEqual(result["cur"] as? Int, 2)
        XCTAssertEqual((result["nativeTimer"] as? [String: Any])?["entry"] as? Int, 1)
        XCTAssertEqual((result["nativeRest"] as? [String: Any])?["entry"] as? Int, 0)
        XCTAssertEqual((result["nativeHighWater"] as? [String: Int]), ["0": 7, "1": 3, "2": 5])
        XCTAssertEqual(entries[1]["sg"] as? String, "pair")
        XCTAssertEqual(entries[2]["sg"] as? String, "pair")
        let separated = try ExerciseOrder.apply([0, 2, 1], to: active)["entries"] as! [[String: Any]]
        XCTAssertTrue(separated.allSatisfy { $0["sg"] == nil })
    }

    @MainActor func testBatchReorderRejectsInvalidPermutations() throws {
        let active: [String: Any] = ["entries": [entry(), entry("1047")]]
        for order in [[0], [0, 0], [0, 2], [-1, 0]] {
            XCTAssertThrowsError(try ExerciseOrder.apply(order, to: active))
        }
    }

    @MainActor func testSheetOrderUsesLatestSetsAndPersistsOnceWithoutLosingSelection() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = LocalTrainingStorage(root: root)
        let store = GymStore(userID: "reorder-sheet", storage: storage)
        store.draft = try TrainingDraft.fromWeb(["id": "sheet", "start": 1000, "cur": 0,
            "entries": [entry(), entry("1047"), entry()]], unit: "kg")
        let baseline = store.draft!.rawEntries
        store.setLiveNote(entry: 0, text: "updated while sheet is open")
        try store.reorderLiveExercises([2, 0, 1], expectedEntries: baseline, sessionID: "sheet")
        let restored = GymStore(userID: "reorder-sheet", storage: storage)
        restored.restoreDraft()
        XCTAssertEqual(restored.draft?.rawEntries[1]["note"] as? String, "updated while sheet is open")
        XCTAssertEqual(restored.draft?.activeJSON["cur"] as? Int, 1)
        XCTAssertThrowsError(try store.reorderLiveExercises([2, 0, 1], expectedEntries: baseline, sessionID: "sheet"))
        XCTAssertThrowsError(try store.reorderLiveExercises([0, 1, 2], expectedEntries: store.draft!.rawEntries, sessionID: "other"))
    }

    @MainActor func testHistoryBatchReorderPreservesViewIdentityAndLiteralInput() throws {
        var first = entry(done: true)
        first["sets"] = [["w": 15, "r": 10, "done": true, TrainingInput.key: ["both.w": "15."]]]
        var form = HistoryForm(original: ["entries": [first, entry("1047"), entry()]], unit: "kg")
        let identity = form.entries[0].id, setID = form.entries[0].sets[0].id
        try form.reorderExercises([1, 2, 0])
        XCTAssertEqual(form.selected, 2)
        XCTAssertEqual(form.entries[2].id, identity)
        XCTAssertEqual(form.entries[2].sets[0].id, setID)
        XCTAssertEqual((form.entries[2].sets[0].raw[TrainingInput.key] as? [String: String])?["both.w"], "15.")
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
    @MainActor func testAddingUsesLatestCompletedSameExerciseAndSetCount() throws {
        func workout(_ id: String, start: Int, exercise: String = "0289", weight: Int, count: Int) -> [String: Any] {
            ["id": id, "start": start, "entries": [["id": exercise,
                "target": ["mode": "reps", "sets": 9, "reps": 10],
                "sets": [["w": 5, "r": 10, "done": true, "phase": "warmup"]]
                    + Array(repeating: ["w": weight, "r": 8, "done": true], count: count)
                    + [["w": 99, "r": 10, "done": false]]]]]
        }
        let state: [String: Any] = ["unit": "kg", "workouts": [
            workout("future", start: 5000, weight: 90, count: 6),
            workout("latest", start: 3000, weight: 25, count: 4),
            workout("old", start: 1000, weight: 10, count: 2),
            workout("other", start: 3500, exercise: "1047", weight: 70, count: 5),
            workout("active", start: 3900, weight: 80, count: 7)
        ]]
        let result = try XCTUnwrap(WebRules.shared.call("manageTrainingExercises", payload: [
            "active": ["id": "active", "start": 4000, "entries": []], "state": state, "action": "add", "id": "0289"
        ]) as? [String: Any])
        let added = try XCTUnwrap((result["entries"] as? [[String: Any]])?.first)
        let rows = try XCTUnwrap(added["sets"] as? [[String: Any]])
        XCTAssertEqual(rows.count, 4)
        XCTAssertEqual((added["target"] as? [String: Any])?["sets"] as? Int, 4)
        XCTAssertEqual(rows.map { number($0["w"]) }, [25, 25, 25, 25])
        XCTAssertTrue(rows.allSatisfy { $0["done"] as? Bool == false })
    }
    @MainActor func testAddingTimedSideHistoryDoesNotDoubleSetCount() throws {
        let previous: [String: Any] = ["id": "0289", "target": ["mode": "time", "side": true, "sets": 2],
            "sets": ["L", "R", "L", "R"].map { ["side": $0, "sec": 30, "w": 5, "done": true] as [String: Any] }]
        let result = try XCTUnwrap(WebRules.shared.call("manageTrainingExercises", payload: [
            "active": ["start": 2000, "entries": []],
            "state": ["workouts": [["start": 1000, "entries": [previous]]]], "action": "add", "id": "0289"
        ]) as? [String: Any])
        let added = try XCTUnwrap((result["entries"] as? [[String: Any]])?.first)
        XCTAssertEqual((added["target"] as? [String: Any])?["sets"] as? Int, 2)
        let rows = try XCTUnwrap(added["sets"] as? [[String: Any]])
        XCTAssertEqual(rows.count, 4)
        XCTAssertEqual(rows.compactMap { $0["side"] as? String }, ["L", "R", "L", "R"])
        XCTAssertTrue(rows.allSatisfy { $0["done"] as? Bool == false })
    }
    @MainActor func testAddingPreservesEachPreviousCompletedSetWeightAndReps() throws {
        let previous: [String: Any] = ["id": "0289", "sets": [
            ["w": 20, "r": 10, "done": true],
            ["w": 25, "r": 8, "done": true],
            ["w": 30, "r": 6, "done": true],
            ["w": 40, "r": 6, "done": false]
        ]]
        let result = try XCTUnwrap(WebRules.shared.call("manageTrainingExercises", payload: [
            "active": ["entries": []], "state": ["workouts": [["start": 1000, "entries": [previous]]]],
            "action": "add", "id": "0289"
        ]) as? [String: Any])
        let added = try XCTUnwrap((result["entries"] as? [[String: Any]])?.first)
        let rows = try XCTUnwrap(added["sets"] as? [[String: Any]])
        XCTAssertEqual(rows.map { number($0["w"]) }, [20, 25, 30])
        XCTAssertEqual(rows.map { number($0["r"]) }, [10, 8, 6])
        XCTAssertTrue(rows.allSatisfy { $0["done"] as? Bool == false })
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
