import XCTest
@testable import OpenGym

@MainActor final class WatchRemoteTests: XCTestCase {
    private var root: URL!
    private var store: GymStore!
    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        store = GymStore(userID: "watch-test", storage: LocalTrainingStorage(root: root))
        store.state = ["unit": "kg", "restSec": 90]
        store.draft = try TrainingDraft.fromWeb(["id": "session", "name": "训练", "start": 1000, "cur": 0,
            "entries": [["id": "0289", "target": ["mode": "reps"], "sets": [["w": 20, "r": 10, "done": false], ["w": 20, "r": 10, "done": false]]]]], unit: "kg")
    }
    override func tearDown() async throws { try? FileManager.default.removeItem(at: root); store = nil }
    private func completeCommand() throws -> WatchTrainingCommand {
        let snapshot = store.watchSnapshot(), row = try XCTUnwrap(snapshot.nextSet)
        return WatchTrainingCommand(account: snapshot.account, sessionID: try XCTUnwrap(snapshot.sessionID), revision: snapshot.revision, action: "complete", entry: row.entry, index: row.index, side: row.side)
    }
    func testCompletionStartsSharedRestAndDuplicateDoesNotToggleOrRestart() throws {
        let command = try completeCommand()
        let reply = store.performWatchCommand(command)
        XCTAssertEqual(reply["accepted"] as? Bool, true)
        let snapshot = try XCTUnwrap(WatchTrainingSnapshot.decode(reply))
        XCTAssertEqual(snapshot.nextSet?.index, 1)
        XCTAssertTrue(snapshot.acknowledged.contains(command.id))
        let end = try XCTUnwrap(snapshot.restEnd)
        XCTAssertEqual(end.timeIntervalSinceNow, 90, accuracy: 1)
        let duplicate = store.performWatchCommand(command)
        XCTAssertEqual(duplicate["accepted"] as? Bool, true)
        XCTAssertEqual(WatchTrainingSnapshot.decode(duplicate)?.restEnd, end)
        XCTAssertEqual((store.draft?.rawEntries[0]["sets"] as? [[String: Any]])?[0]["done"] as? Bool, true)
    }
    func testReceiptSurvivesRelaunch() throws {
        let command = try completeCommand()
        _ = store.performWatchCommand(command)
        let restored = GymStore(userID: "watch-test", storage: LocalTrainingStorage(root: root))
        restored.restoreDraft()
        let end = restored.restUntil
        XCTAssertEqual(restored.performWatchCommand(command)["accepted"] as? Bool, true)
        XCTAssertEqual(restored.restUntil, end)
    }
    func testStaleCommandCannotCompleteAfterCopyReorderOrAccountChange() throws {
        let command = try completeCommand()
        store.copyLiveSet(entry: 0, set: 0)
        XCTAssertEqual(store.performWatchCommand(command)["accepted"] as? Bool, false)
        XCTAssertEqual(store.draft?.completedSets, 0)
        let next = try completeCommand()
        store.userID = "another-account"
        XCTAssertEqual(store.performWatchCommand(next)["accepted"] as? Bool, false)
        XCTAssertEqual(store.draft?.completedSets, 0)
    }
    func testIncompleteInputAndRunningTimerBlockWatchCompletion() throws {
        store.liveRowAction(entry: 0, set: 0, action: ["action": "input", "path": "both.w", "text": "", "operation": ["action": "field", "key": "w"]])
        XCTAssertNotNil(store.watchSnapshot().nextSet?.blockedReason)
        XCTAssertEqual(store.performWatchCommand(try completeCommand())["accepted"] as? Bool, false)
        store.liveRowAction(entry: 0, set: 0, action: ["action": "field", "key": "w", "value": 20])
        store.startWorkTimer(entry: 0, set: 0)
        XCTAssertNotNil(store.watchSnapshot().nextSet?.blockedReason)
        XCTAssertEqual(store.performWatchCommand(try completeCommand())["accepted"] as? Bool, false)
    }
    func testSidesAdvanceIndividuallyAndRestStartsOnlyAfterBoth() throws {
        store.changeActive { raw in
            var entries = raw["entries"] as! [[String: Any]]
            let side: [String: Any] = ["w": 10, "r": 6, "done": false]
            entries[0]["sets"] = [["kind": "side", "sides": ["L": side, "R": side], "done": false], ["w": 10, "r": 10, "done": false]]
            raw["entries"] = entries
        }
        XCTAssertEqual(store.watchSnapshot().nextSet?.side, "L")
        XCTAssertEqual(store.performWatchCommand(try completeCommand())["accepted"] as? Bool, true)
        XCTAssertEqual(store.watchSnapshot().nextSet?.side, "R")
        XCTAssertNil(store.restUntil)
        XCTAssertEqual(store.performWatchCommand(try completeCommand())["accepted"] as? Bool, true)
        XCTAssertNotNil(store.restUntil)
    }
    func testWatchUsesEquipmentUnitsAndRoundTripsSmallVersionedPayload() throws {
        store.liveRowAction(entry: 0, set: 0, action: ["action": "weightUnit", "unit": "lb"])
        let snapshot = store.watchSnapshot()
        XCTAssertEqual(snapshot.nextSet?.weight, "44.09 lb")
        XCTAssertEqual(WatchTrainingSnapshot.decode(snapshot.payload), snapshot)
        XCTAssertLessThan((snapshot.payload["snapshot"] as! Data).count, 8000)
        var unsupported = snapshot; unsupported.version = 2
        XCTAssertNil(WatchTrainingSnapshot.decode(unsupported.payload))
    }
    func testFinishedSessionAndMismatchedSetCannotBeRecorded() throws {
        var command = try completeCommand(); command.index = 1
        XCTAssertEqual(store.performWatchCommand(command)["accepted"] as? Bool, false)
        let valid = try completeCommand(); store.draft = nil
        XCTAssertEqual(store.performWatchCommand(valid)["accepted"] as? Bool, false)
        XCTAssertNil(store.watchSnapshot().sessionID)
    }
    func testDeleteUndoRestoresExactInputsAndTimerButNeverOverwritesLaterChanges() throws {
        store.startRest(entry: 0, seconds: 90, set: 1)
        let entries = store.draft?.rawEntries, end = store.restUntil
        store.removeLiveSet(entry: 0, set: 0)
        XCTAssertTrue(store.canUndoSetRemoval)
        store.undoSetRemoval()
        XCTAssertTrue(RecordPatch.equal(entries, store.draft?.rawEntries))
        XCTAssertEqual(store.restUntil, end)
        XCTAssertEqual((store.draft?.activeJSON["nativeRest"] as? [String: Any])?["set"] as? Int, 1)
        store.removeLiveSet(entry: 0, set: 0)
        store.liveRowAction(entry: 0, set: 0, action: ["action": "field", "key": "r", "value": 12])
        XCTAssertFalse(store.canUndoSetRemoval)
        store.undoSetRemoval()
        XCTAssertEqual((store.draft?.rawEntries[0]["sets"] as? [[String: Any]])?.count, 1)
    }
    func testWeightCascadeProtectsCompletedManualAndUnfinishedInput() throws {
        store.changeActive { raw in
            var entries = raw["entries"] as! [[String: Any]]
            entries[0]["sets"] = [["w": 20, "r": 10], ["w": 20, "r": 10], ["w": 25, "r": 10, "weightOrigin": "manual"], ["w": 20, "r": 10, "done": true], ["w": 20, "r": 10, TrainingInput.key: ["both.w": ""]]]
            raw["entries"] = entries
        }
        store.liveRowAction(entry: 0, set: 0, action: ["action": "field", "key": "w", "value": 30])
        let rows = store.draft?.rawEntries[0]["sets"] as! [[String: Any]]
        XCTAssertEqual(rows.map { number($0["w"]) }, [30, 30, 25, 20, 20])
        XCTAssertEqual((rows[4][TrainingInput.key] as? [String: String])?["both.w"], "")
    }
}

extension WatchRemoteTests {
    func testPlateLoadingKeepsBaseAndReportsMissingOwnedPlates() throws {
        let info = try WebRules.shared.call("nativePlateInfo", payload: ["state": ["unit": "kg", "plates": ["kg": ["10": 1]], "barWeights": ["0025": 20]], "target": ["id": "0025"], "weight": 60]) as! [String: Any]
        let load = info["load"] as! [String: Any]
        XCTAssertEqual(info["custom"] as? Bool, true)
        XCTAssertEqual(number(info["base"]), 20)
        XCTAssertEqual(load["kind"] as? String, "pairs")
        XCTAssertEqual(load["plates"] as? [Double], [10])
        XCTAssertEqual(number(load["missing"]), 10)
    }
    func testSideCascadeDoesNotRewriteOppositeLimbOrWarmup() throws {
        let side: [String: Any] = ["w": 20, "r": 8, "done": false]
        let rows: [[String: Any]] = [
            ["kind": "side", "sides": ["L": ["w": 30, "r": 8], "R": side]],
            ["w": 10, "r": 8, "phase": "warmup"],
            ["kind": "side", "sides": ["L": side, "R": side]]
        ]
        let next = try WebRules.shared.call("cascadeNativeWeight", payload: ["sets": rows, "index": 0, "side": "L"]) as! [[String: Any]]
        XCTAssertEqual(number(next[1]["w"]), 10)
        let sides = next[2]["sides"] as! [String: [String: Any]]
        XCTAssertEqual(number(sides["L"]?["w"]), 30)
        XCTAssertEqual(number(sides["R"]?["w"]), 20)
    }
}
