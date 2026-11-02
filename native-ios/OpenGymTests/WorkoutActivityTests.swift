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
        XCTAssertEqual(state.commandTitle, "完成本组")
        XCTAssertEqual(state, store.workoutActivityState())
        XCTAssertLessThan(try JSONEncoder().encode(state).count, 4096)
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

    func testLastSetOffersNextExerciseThenSaveInApp() throws {
        store.changeActive { raw in
            var entries = raw["entries"] as! [[String: Any]]
            entries.append(["id": "custom-bench", "sets": [["w": 20, "r": 8, "done": false]]])
            raw["entries"] = entries
        }
        for _ in 0..<2 { XCTAssertNil(store.performActivityCommand(try XCTUnwrap(store.workoutActivityState()?.command))) }
        XCTAssertEqual(store.workoutActivityState()?.commandTitle, "下一个动作")
        if let skip = store.workoutActivityState()?.restCommand { XCTAssertNil(store.performActivityCommand(skip)) }
        XCTAssertNil(store.performActivityCommand(try XCTUnwrap(store.workoutActivityState()?.command)))
        XCTAssertEqual(store.watchSnapshot().nextSet?.entry, 1)
        XCTAssertNil(store.performActivityCommand(try XCTUnwrap(store.workoutActivityState()?.command)))
        XCTAssertNil(store.workoutActivityState()?.command)
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
}
