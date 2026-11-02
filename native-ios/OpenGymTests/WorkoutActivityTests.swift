import XCTest
@testable import OpenGym

@MainActor final class WorkoutActivityTests: XCTestCase {
    private var root: URL!
    private var store: GymStore!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        store = GymStore(userID: "activity-test", storage: LocalTrainingStorage(root: root))
        store.state = ["unit": "kg", "restSec": 90, "customEx": [["id": "custom-bench", "n": "杠铃卧推", "bp": "chest", "eq": "barbell", "tg": "pectorals"]]]
        store.draft = try TrainingDraft.fromWeb(["id": "session", "name": "胸背训练", "start": 1000, "cur": 0,
            "entries": [["id": "custom-bench", "target": ["mode": "reps"], "sets": [["w": 40, "r": 10, "done": false], ["w": 40, "r": 10, "done": false]]]]], unit: "kg")
    }
    override func tearDown() async throws { store = nil; try? FileManager.default.removeItem(at: root) }

    func testDisplaysTrainingExerciseSetAndUsesStableSmallPayload() throws {
        let state = try XCTUnwrap(store.workoutActivityState())
        XCTAssertEqual(state.trainingName, "胸背训练")
        XCTAssertEqual(state.exercise, "杠铃卧推")
        XCTAssertEqual(state.setLabel, "第 1 / 2 组")
        XCTAssertEqual(state.compactSet, "1/2")
        XCTAssertEqual(state.detail, "40 kg · 10 次")
        XCTAssertEqual(state.setWeight, "40 kg")
        XCTAssertEqual(state.setDetail, "10 次")
        XCTAssertEqual(state.commandTitle, "完成本组")
        XCTAssertEqual(state, store.workoutActivityState())
        XCTAssertLessThan(try JSONEncoder().encode(state).count, 4096)
    }

    func testOlderActivityContentStillDecodesWithoutSummaryFields() throws {
        let state = try XCTUnwrap(store.workoutActivityState())
        var raw = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
        raw.removeValue(forKey: "setWeight")
        raw.removeValue(forKey: "setDetail")
        let decoded = try JSONDecoder().decode(WorkoutActivityAttributes.ContentState.self, from: JSONSerialization.data(withJSONObject: raw))
        XCTAssertNil(decoded.setWeight)
        XCTAssertNil(decoded.setDetail)
        XCTAssertEqual(decoded.detail, "40 kg · 10 次")
        XCTAssertEqual(decoded.command, state.command)
    }

    func testCompleteStartsRestAndDuplicateNeverCompletesNextSet() throws {
        let command = try XCTUnwrap(store.workoutActivityState()?.command)
        XCTAssertNil(store.performActivityCommand(command))
        let rest = try XCTUnwrap(store.workoutActivityState())
        XCTAssertEqual(rest.compactSet, "2/2")
        XCTAssertEqual(try XCTUnwrap(rest.restEnd).timeIntervalSinceNow, 90, accuracy: 1)
        XCTAssertEqual(rest.restExercise, "杠铃卧推")
        XCTAssertNotNil(rest.restCommand)
        XCTAssertLessThan(try JSONEncoder().encode(rest).count, 4096)
        XCTAssertNil(store.performActivityCommand(command))
        XCTAssertEqual(store.draft?.completedSets, 1)
        XCTAssertEqual(store.restUntil, rest.restEnd)
    }

    func testSkipRestPreservesSetsAndRejectsOldTimerCommand() throws {
        XCTAssertNil(store.performActivityCommand(try XCTUnwrap(store.workoutActivityState()?.command)))
        let oldSkip = try XCTUnwrap(store.workoutActivityState()?.restCommand)
        store.adjustRest(by: 30)
        let extended = store.restUntil
        XCTAssertNotNil(store.performActivityCommand(oldSkip))
        XCTAssertEqual(store.restUntil, extended)
        let skip = try XCTUnwrap(store.workoutActivityState()?.restCommand)
        XCTAssertNil(store.performActivityCommand(skip))
        XCTAssertNil(store.restUntil)
        XCTAssertEqual(store.draft?.completedSets, 1)
        XCTAssertNotNil(store.performActivityCommand(skip))
        XCTAssertEqual(store.draft?.completedSets, 1)
    }

    func testCompletionRemainsValidAfterRestChangesBeforeActivityRedraws() throws {
        store.startRest(entry: 0, seconds: 90)
        let command = try XCTUnwrap(store.workoutActivityState()?.command)
        store.adjustRest(by: 30)
        XCTAssertEqual(command, store.workoutActivityState()?.command)
        store.restUntil = nil
        XCTAssertEqual(command, store.workoutActivityState()?.command)
        XCTAssertNil(store.performActivityCommand(command))
        XCTAssertEqual(store.draft?.completedSets, 1)
        let end = store.restUntil
        XCTAssertNil(store.performActivityCommand(command))
        XCTAssertEqual(store.draft?.completedSets, 1)
        XCTAssertEqual(store.restUntil, end)
    }

    func testCompletionSurvivesColdLaunchAfterSkippingRest() throws {
        store.startRest(entry: 0, seconds: 90)
        let command = try XCTUnwrap(store.workoutActivityState()?.command)
        let skip = try XCTUnwrap(store.workoutActivityState()?.restCommand)
        XCTAssertNil(store.performActivityCommand(skip))
        let restored = GymStore(userID: "activity-test", storage: LocalTrainingStorage(root: root))
        restored.state = store.state
        restored.restoreDraft()
        XCTAssertNil(restored.performActivityCommand(command))
        XCTAssertEqual(restored.draft?.completedSets, 1)
    }

    func testRestChangeDoesNotAllowAnEditedSetOrOldWorkTimer() throws {
        store.startRest(entry: 0, seconds: 90)
        let command = try XCTUnwrap(store.workoutActivityState()?.command)
        store.adjustRest(by: 30)
        store.liveRowAction(entry: 0, set: 0, action: ["action": "field", "key": "w", "value": 45])
        XCTAssertNotNil(store.performActivityCommand(command))
        let edited = try XCTUnwrap(store.workoutActivityState()?.command)
        store.startWorkTimer(entry: 0, set: 0)
        XCTAssertNotNil(store.performActivityCommand(edited))
        XCTAssertEqual(store.draft?.completedSets, 0)
    }

    func testUndoOffersANewCommandWhileOldDuplicateStaysHarmless() throws {
        let command = try XCTUnwrap(store.workoutActivityState()?.command)
        XCTAssertNil(store.performActivityCommand(command))
        store.liveRowAction(entry: 0, set: 0, action: ["action": "toggle"])
        XCTAssertEqual(store.draft?.completedSets, 0)
        let retry = try XCTUnwrap(store.workoutActivityState()?.command)
        XCTAssertNotEqual(command, retry)
        XCTAssertNil(store.performActivityCommand(command))
        XCTAssertEqual(store.draft?.completedSets, 0)
        XCTAssertNil(store.performActivityCommand(retry))
        XCTAssertEqual(store.draft?.completedSets, 1)
    }

    func testLegacyPayloadStillUsesStrictRevisionValidation() throws {
        let snapshot = store.watchSnapshot()
        let legacy = WatchTrainingCommand(id: "legacy-activity", account: snapshot.account,
            sessionID: try XCTUnwrap(snapshot.sessionID), revision: snapshot.revision,
            action: "complete", entry: 0, index: 0)
        let encoded = try JSONEncoder().encode(legacy).base64EncodedString()
        store.startRest(entry: 0, seconds: 90)
        XCTAssertNotNil(store.performActivityCommand(encoded))
        XCTAssertEqual(store.draft?.completedSets, 0)
        store.restUntil = nil
        XCTAssertNil(store.performActivityCommand(encoded))
        XCTAssertEqual(store.draft?.completedSets, 1)
    }

    func testColdLaunchRestoresDraftAndCommandReceipt() throws {
        let command = try XCTUnwrap(store.workoutActivityState()?.command)
        let restored = GymStore(userID: "activity-test", storage: LocalTrainingStorage(root: root))
        restored.state = store.state
        restored.restoreDraft()
        XCTAssertNil(restored.performActivityCommand(command))
        let again = GymStore(userID: "activity-test", storage: LocalTrainingStorage(root: root))
        again.restoreDraft()
        XCTAssertNil(again.performActivityCommand(command))
        XCTAssertEqual(again.draft?.completedSets, 1)
        XCTAssertEqual(again.restUntil, restored.restUntil)
    }

    func testStaleCommandsCannotCompleteEditedReorderedOrDifferentAccountSets() throws {
        let command = try XCTUnwrap(store.workoutActivityState()?.command)
        store.liveRowAction(entry: 0, set: 0, action: ["action": "field", "key": "w", "value": 45])
        XCTAssertNotNil(store.performActivityCommand(command))
        let edited = try XCTUnwrap(store.workoutActivityState()?.command)
        store.copyLiveSet(entry: 0, set: 0)
        XCTAssertNotNil(store.performActivityCommand(edited))
        let copied = try XCTUnwrap(store.workoutActivityState()?.command)
        store.userID = "other"
        XCTAssertNotNil(store.performActivityCommand(copied))
        XCTAssertEqual(store.draft?.completedSets, 0)
    }

    func testBlockedInputTimerSyncAndStorageFailureCannotComplete() throws {
        let command = try XCTUnwrap(store.workoutActivityState()?.command)
        store.syncing = true
        XCTAssertNil(store.workoutActivityState()?.command)
        XCTAssertNotNil(store.performActivityCommand(command))
        store.syncing = false
        store.localSaveError = "test write failure"
        XCTAssertNil(store.workoutActivityState()?.command)
        XCTAssertNotNil(store.performActivityCommand(command))
        store.localSaveError = nil
        store.liveRowAction(entry: 0, set: 0, action: ["action": "input", "path": "both.w", "text": "", "operation": ["action": "field", "key": "w"]])
        XCTAssertNil(store.workoutActivityState()?.command)
        XCTAssertFalse(try XCTUnwrap(store.workoutActivityState()?.message).isEmpty)
        store.liveRowAction(entry: 0, set: 0, action: ["action": "field", "key": "w", "value": 40])
        store.startWorkTimer(entry: 0, set: 0)
        XCTAssertNil(store.workoutActivityState()?.command)
        XCTAssertEqual(store.draft?.completedSets, 0)
    }

    func testLeftAndRightCompleteIndividuallyBeforeRestStarts() throws {
        let side: [String: Any] = ["w": 10, "r": 8, "done": false]
        store.replaceLiveRow(entry: 0, set: 0, row: ["kind": "side", "sides": ["L": side, "R": side], "done": false])
        XCTAssertTrue(try XCTUnwrap(store.workoutActivityState()?.setLabel).contains("左侧"))
        XCTAssertNil(store.performActivityCommand(try XCTUnwrap(store.workoutActivityState()?.command)))
        XCTAssertNil(store.restUntil)
        XCTAssertTrue(try XCTUnwrap(store.workoutActivityState()?.setLabel).contains("右侧"))
        XCTAssertNil(store.performActivityCommand(try XCTUnwrap(store.workoutActivityState()?.command)))
        XCTAssertNotNil(store.restUntil)
    }

    func testLastSetAutomaticallySelectsNextExerciseThenOffersOpenApp() throws {
        store.changeActive { raw in
            var entries = raw["entries"] as! [[String: Any]]
            entries.append(["id": "custom-bench", "sets": [["w": 20, "r": 8, "done": false]]])
            raw["entries"] = entries
        }
        XCTAssertNil(store.performActivityCommand(try XCTUnwrap(store.workoutActivityState()?.command)))
        let lastSet = try XCTUnwrap(store.workoutActivityState()?.command)
        XCTAssertNil(store.performActivityCommand(lastSet))
        XCTAssertEqual(store.workoutActivityState()?.commandTitle, "完成本组")
        XCTAssertEqual(store.watchSnapshot().nextSet?.entry, 1)
        XCTAssertEqual(store.workoutActivityState()?.setLabel, "第 1 / 1 组")
        XCTAssertNil(store.restUntil)
        XCTAssertNil(store.performActivityCommand(lastSet))
        XCTAssertEqual(store.draft?.completedSets, 2)
        XCTAssertEqual(store.watchSnapshot().nextSet?.entry, 1)
        XCTAssertNil(store.performActivityCommand(try XCTUnwrap(store.workoutActivityState()?.command)))
        XCTAssertNil(store.workoutActivityState()?.command)
        XCTAssertEqual(store.workoutActivityState()?.commandTitle, "打开App")
        XCTAssertTrue(try XCTUnwrap(store.workoutActivityState()?.message).contains("保存"))
    }

    func testEndedOrDeletedWorkoutHasNoActivityOrValidCommands() throws {
        let command = try XCTUnwrap(store.workoutActivityState()?.command)
        store.startRest(entry: 0, seconds: 90)
        store.deleteCurrentWorkout()
        XCTAssertNil(store.workoutActivityState())
        XCTAssertNotNil(store.performActivityCommand(command))
        XCTAssertNil(store.restUntil)
    }

    func testMalformedCommandsAndUnknownActionsCannotMutate() throws {
        XCTAssertNotNil(store.performActivityCommand("invalid"))
        let encoded = try XCTUnwrap(store.workoutActivityState()?.command)
        var command = try JSONDecoder().decode(WatchTrainingCommand.self, from: XCTUnwrap(Data(base64Encoded: encoded)))
        command.action = "delete"
        XCTAssertNotNil(store.performActivityCommand(try JSONEncoder().encode(command).base64EncodedString()))
        XCTAssertEqual(store.draft?.completedSets, 0)
    }

    func testDiagnosticsCorrelateDuplicateTapsWithoutLoggingTrainingData() throws {
        let command = try XCTUnwrap(store.workoutActivityState()?.command)
        var records: [WorkoutActivityDiagnostics.Record] = []
        WorkoutActivityDiagnostics.$observer.withValue({ records.append($0) }) {
            XCTAssertNil(store.performActivityCommand(command))
            XCTAssertNil(store.performActivityCommand(command))
        }
        let starts = records.filter { $0.event == "activity.command.begin" }
        XCTAssertEqual(starts.count, 2)
        XCTAssertNotEqual(starts[0].traces, starts[1].traces)
        let decoded = records.filter { $0.event == "activity.command.decoded" }
        XCTAssertEqual(decoded[0].fields["command"], decoded[1].fields["command"])
        let outcomes = records.filter { $0.event == "remote.command.end" }
        XCTAssertEqual(outcomes.map { $0.fields["outcome"] }, ["applied", "duplicate_acknowledged"])
        XCTAssertTrue(records.contains { $0.event == "draft.save.end" && $0.traces == starts[0].traces && $0.fields["outcome"] == "saved" })
        XCTAssertFalse(records.contains { $0.event == "draft.save.begin" && $0.traces == starts[1].traces })
        let values = records.flatMap { Array($0.fields.values) }.joined(separator: "|")
        for sensitive in [command, "activity-test", "胸背训练", "杠铃卧推", "40 kg", "10 次", store.serverURL, root.path] {
            XCTAssertFalse(values.contains(sensitive))
        }
    }

    func testDiagnosticsDistinguishMalformedStaleBusyAndRestOwnerRejections() throws {
        var records: [WorkoutActivityDiagnostics.Record] = []
        let command = try XCTUnwrap(store.workoutActivityState()?.command)
        WorkoutActivityDiagnostics.$observer.withValue({ records.append($0) }) {
            XCTAssertNotNil(store.performActivityCommand("not-base64"))
            store.syncing = true
            XCTAssertNotNil(store.performActivityCommand(command))
            store.syncing = false
            store.localSaveError = "private error text"
            XCTAssertNotNil(store.performActivityCommand(command))
            store.localSaveError = nil
            store.liveRowAction(entry: 0, set: 0, action: ["action": "field", "key": "w", "value": 45])
            XCTAssertNotNil(store.performActivityCommand(command))
        }
        XCTAssertTrue(records.contains { $0.event == "activity.command.rejected" && $0.fields["reason"] == "invalid_payload" })
        XCTAssertEqual(records.filter { $0.event == "remote.command.end" }.map { $0.fields["outcome"] }, ["syncing", "save_error", "revision_mismatch"])
        store.startRest(entry: 0, seconds: 90)
        var skip = try JSONDecoder().decode(WatchTrainingCommand.self, from: XCTUnwrap(Data(base64Encoded: try XCTUnwrap(store.workoutActivityState()?.restCommand))))
        skip.entry = 1
        let payload = try JSONEncoder().encode(skip).base64EncodedString()
        WorkoutActivityDiagnostics.$observer.withValue({ records.append($0) }) {
            XCTAssertNotNil(store.performActivityCommand(payload))
        }
        XCTAssertTrue(records.contains { $0.event == "activity.command.rejected" && $0.fields["reason"] == "rest_owner_mismatch" })
        XCTAssertEqual(store.draft?.completedSets, 0)
    }

    func testDiagnosticsRecordStorageErrorCodeAndFailedCompletion() throws {
        let command = try XCTUnwrap(store.workoutActivityState()?.command)
        // Block directory creation to exercise an actual atomic-save failure.
        try FileManager.default.removeItem(at: root)
        try Data("blocked".utf8).write(to: root)
        var records: [WorkoutActivityDiagnostics.Record] = []
        WorkoutActivityDiagnostics.$observer.withValue({ records.append($0) }) {
            XCTAssertNotNil(store.performActivityCommand(command))
        }
        let failure = try XCTUnwrap(records.first { $0.event == "draft.save.failed" })
        XCTAssertNotNil(failure.fields["error_code"])
        XCTAssertNotNil(failure.fields["error_domain"])
        XCTAssertFalse(failure.fields.values.contains { $0.contains(root.path) })
        XCTAssertTrue(records.contains { $0.event == "remote.command.end" && $0.fields["outcome"] == "save_failed" && $0.fields["accepted"] == "false" })
    }
}
