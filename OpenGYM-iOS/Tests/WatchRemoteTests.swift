import XCTest
@testable import OpenGYM

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
    private func endRestCommand() throws -> WatchTrainingCommand {
        let snapshot = store.watchSnapshot()
        return WatchTrainingCommand(account: snapshot.account, sessionID: try XCTUnwrap(snapshot.sessionID),
            revision: snapshot.revision, action: "skipRest", entry: try XCTUnwrap(snapshot.restEntry))
    }
    func testRestStateExpiresWithoutWaitingForAnotherPhoneSnapshot() throws {
        let now = Date(timeIntervalSince1970: 1000)
        var snapshot = store.watchSnapshot(now: now)
        XCTAssertFalse(snapshot.isResting(at: now))
        snapshot.restEnd = now.addingTimeInterval(90)
        XCTAssertTrue(snapshot.isResting(at: now))
        XCTAssertTrue(snapshot.isResting(at: now.addingTimeInterval(89)))
        XCTAssertFalse(snapshot.isResting(at: now.addingTimeInterval(90)))
        XCTAssertFalse(snapshot.isResting(at: now.addingTimeInterval(100)))
    }
    func testForegroundRestAlertsAtDeadlineWithoutNotificationAndOnlyOnce() throws {
        let now = Date(timeIntervalSince1970: 1000), end = Date(timeIntervalSince1970: 1090)
        let snapshot = WatchTrainingSnapshot(account: "a", sessionID: "s", restEnd: end)
        let key = try XCTUnwrap(snapshot.restReminderKey)
        var reminder = WatchForegroundRestReminder()
        XCTAssertEqual(reminder.update(snapshot, active: true, now: now), end)
        XCTAssertFalse(reminder.consume(key: key, now: end.addingTimeInterval(-0.01)))
        XCTAssertTrue(reminder.consume(key: key, now: end))
        XCTAssertFalse(reminder.consume(key: key, now: end.addingTimeInterval(5)), "Late system delivery must not vibrate again")
        XCTAssertNil(reminder.update(snapshot, active: true, now: end.addingTimeInterval(5)))
    }
    func testWorkoutRestStillAlertsAfterLoweringWristOnlyOnce() throws {
        let now = Date(timeIntervalSince1970: 1000), end = now.addingTimeInterval(90)
        let snapshot = WatchTrainingSnapshot(sessionID: "s", restEnd: end)
        let key = try XCTUnwrap(snapshot.restReminderKey)
        var reminder = WatchForegroundRestReminder()
        _ = reminder.update(snapshot, active: true, workoutRunning: true, now: now)
        XCTAssertEqual(reminder.update(snapshot, active: false, workoutRunning: true, now: now.addingTimeInterval(30)), end)
        XCTAssertTrue(reminder.consume(key: key, now: end))
        XCTAssertFalse(reminder.consume(key: key, now: end.addingTimeInterval(1)))
        XCTAssertNil(reminder.update(snapshot, active: true, workoutRunning: true, now: end.addingTimeInterval(2)))
    }
    func testBackgroundWorkoutStopDisarmsDirectRestHaptic() throws {
        let now = Date(timeIntervalSince1970: 1000), end = now.addingTimeInterval(90)
        let snapshot = WatchTrainingSnapshot(sessionID: "s", restEnd: end)
        var reminder = WatchForegroundRestReminder()
        XCTAssertEqual(reminder.update(snapshot, active: false, workoutRunning: true, now: now), end)
        XCTAssertNil(reminder.update(snapshot, active: false, workoutRunning: false, now: now.addingTimeInterval(30)))
        XCTAssertFalse(reminder.consume(key: try XCTUnwrap(snapshot.restReminderKey), now: end))
    }
    func testForegroundRestNotificationWinningRaceDoesNotDuplicateTimer() throws {
        let now = Date(timeIntervalSince1970: 1000), end = now.addingTimeInterval(90)
        let snapshot = WatchTrainingSnapshot(sessionID: "s", restEnd: end)
        var reminder = WatchForegroundRestReminder()
        _ = reminder.update(snapshot, active: true, now: now)
        let key = try XCTUnwrap(snapshot.restReminderKey)
        XCTAssertTrue(reminder.consume(key: key, now: end)) // notification callback wins
        XCTAssertFalse(reminder.consume(key: key, now: end)) // foreground deadline follows
    }
    func testForegroundRestKeepsArmedDeadlineAcrossSnapshotRefreshAtExpiry() throws {
        let now = Date(timeIntervalSince1970: 1000), end = now.addingTimeInterval(90)
        let snapshot = WatchTrainingSnapshot(sessionID: "s", restEnd: end)
        var reminder = WatchForegroundRestReminder()
        _ = reminder.update(snapshot, active: true, now: now)
        XCTAssertEqual(reminder.update(snapshot, active: true, now: end.addingTimeInterval(0.1)), end)
        XCTAssertTrue(reminder.consume(key: try XCTUnwrap(snapshot.restReminderKey), now: end.addingTimeInterval(0.1)))
    }
    func testForegroundRestDoesNotReplayExpiredRestOnLaunchOrResume() throws {
        let now = Date(timeIntervalSince1970: 1000), end = now.addingTimeInterval(90)
        let snapshot = WatchTrainingSnapshot(sessionID: "s", restEnd: end)
        let key = try XCTUnwrap(snapshot.restReminderKey)
        var reminder = WatchForegroundRestReminder()
        XCTAssertNil(reminder.update(snapshot, active: true, now: end.addingTimeInterval(5)))
        XCTAssertFalse(reminder.consume(key: key, now: end.addingTimeInterval(5)))
        _ = reminder.update(snapshot, active: true, now: now)
        XCTAssertNil(reminder.update(snapshot, active: false, now: now.addingTimeInterval(30)))
        XCTAssertFalse(reminder.consume(key: key, now: end))
        XCTAssertNil(reminder.update(snapshot, active: true, now: end.addingTimeInterval(5)))
        XCTAssertFalse(reminder.consume(key: key, now: end.addingTimeInterval(5)))
    }
    func testForegroundRestRearmsWhenReturningBeforeDeadline() throws {
        let now = Date(timeIntervalSince1970: 1000), end = now.addingTimeInterval(90)
        let snapshot = WatchTrainingSnapshot(sessionID: "s", restEnd: end)
        var reminder = WatchForegroundRestReminder()
        _ = reminder.update(snapshot, active: true, now: now)
        _ = reminder.update(snapshot, active: false, now: now.addingTimeInterval(10))
        XCTAssertEqual(reminder.update(snapshot, active: true, now: now.addingTimeInterval(30)), end)
        XCTAssertTrue(reminder.consume(key: try XCTUnwrap(snapshot.restReminderKey), now: end))
    }
    func testForegroundRestRejectsOldDeadlineAfterExtensionSkipAndAccountChange() throws {
        let now = Date(timeIntervalSince1970: 1000), end = now.addingTimeInterval(90)
        var snapshot = WatchTrainingSnapshot(account: "a", sessionID: "s", restEnd: end)
        var reminder = WatchForegroundRestReminder()
        _ = reminder.update(snapshot, active: true, now: now)
        let original = try XCTUnwrap(snapshot.restReminderKey)
        snapshot.restEnd = end.addingTimeInterval(15)
        _ = reminder.update(snapshot, active: true, now: now)
        XCTAssertFalse(reminder.consume(key: original, now: end))
        let extended = try XCTUnwrap(snapshot.restReminderKey)
        snapshot.account = "b"
        _ = reminder.update(snapshot, active: true, now: now)
        XCTAssertFalse(reminder.consume(key: extended, now: end.addingTimeInterval(15)))
        let otherAccount = try XCTUnwrap(snapshot.restReminderKey)
        snapshot.restEnd = nil
        XCTAssertNil(reminder.update(snapshot, active: true, now: now))
        XCTAssertFalse(reminder.consume(key: otherAccount, now: end.addingTimeInterval(15)))
    }
    func testPrimaryActionSwitchesInPlaceAcrossRestCompletionAndPendingReply() throws {
        let now = Date(timeIntervalSince1970: 1000), command = try completeCommand()
        var snapshot = store.watchSnapshot()
        XCTAssertEqual(snapshot.primaryAction(commandState: .idle), .complete)
        snapshot.restEnd = now.addingTimeInterval(90)
        XCTAssertEqual(snapshot.primaryAction(commandState: .idle), .endRest)
        XCTAssertEqual(snapshot.primaryAction(commandState: .sending(command)), .sending)
        XCTAssertEqual(snapshot.primaryAction(commandState: .awaitingConfirmation(command)), .retry)
        snapshot.restEnd = now.addingTimeInterval(-1)
        XCTAssertFalse(snapshot.isResting(at: now))
        XCTAssertEqual(snapshot.primaryAction(commandState: .idle), .endRest, "Expiry still waits for the phone to end rest")
        snapshot.restEnd = nil; snapshot.nextSet = nil; snapshot.nextEntry = 1
        XCTAssertEqual(snapshot.primaryAction(commandState: .idle), .next)
        snapshot.nextEntry = nil
        XCTAssertEqual(snapshot.primaryAction(commandState: .idle), .finished)
    }
    func testFinishedScreenFollowsConfirmedLastSetAndReturnsToTrainingWhenReopened() throws {
        XCTAssertFalse(store.watchSnapshot().isFinished)
        _ = store.performReadyWatchCommand(try completeCommand())
        XCTAssertFalse(store.watchSnapshot().isFinished)
        _ = store.performReadyWatchCommand(try endRestCommand())
        _ = store.performReadyWatchCommand(try completeCommand())

        let finished = store.watchSnapshot()
        XCTAssertNotNil(finished.sessionID, "The completion screen must not wait for the phone to save the workout")
        XCTAssertTrue(finished.isFinished)
        XCTAssertNil(finished.restEnd)

        XCTAssertTrue(store.liveRowAction(entry: 0, set: 1, action: ["action": "toggle"]))
        XCTAssertFalse(store.watchSnapshot().isFinished)
    }
    func testFinishedScreenExcludesWaitingAndEmptyDraft() throws {
        XCTAssertFalse(WatchTrainingSnapshot().isFinished)
        store.draft = try TrainingDraft.fromWeb(["id": "empty", "name": "训练", "start": 1000,
            "cur": 0, "entries": []], unit: "kg")
        XCTAssertFalse(store.watchSnapshot().isFinished)
        store.draft = nil
        XCTAssertFalse(store.watchSnapshot().isFinished)
    }
    func testFinishedScreenWaitsForRestAndRemainingExercises() {
        var snapshot = WatchTrainingSnapshot(sessionID: "session", exercise: "卧推")
        XCTAssertTrue(snapshot.isFinished)
        snapshot.restEnd = Date().addingTimeInterval(90)
        XCTAssertFalse(snapshot.isFinished)
        snapshot.restEnd = Date().addingTimeInterval(-1)
        XCTAssertFalse(snapshot.isFinished, "Expired rest still waits for the phone to end it")
        snapshot.restEnd = nil
        snapshot.nextEntry = 1
        XCTAssertFalse(snapshot.isFinished)
    }
    func testPendingConfirmationTakesPriorityOverEveryTrainingAction() throws {
        let command = try completeCommand()
        let snapshots = [store.watchSnapshot(),
            WatchTrainingSnapshot(sessionID: "session", restEnd: Date().addingTimeInterval(90)),
            WatchTrainingSnapshot(nextEntry: 1), WatchTrainingSnapshot()]
        for snapshot in snapshots {
            XCTAssertEqual(snapshot.primaryAction(commandState: .sending(command)), .sending)
            XCTAssertEqual(snapshot.primaryAction(commandState: .awaitingConfirmation(command)), .retry)
        }
    }
    func testUnconfirmedCommandKeepsIdentityAcrossPersistenceAndRetry() throws {
        let command = try completeCommand()
        var state = WatchCommandState.sending(command)
        XCTAssertTrue(state.markUnconfirmed(commandID: command.id))
        XCTAssertEqual(state, .awaitingConfirmation(command))
        let data = try JSONEncoder().encode(XCTUnwrap(state.command))
        let restored = try JSONDecoder().decode(WatchTrainingCommand.self, from: data)
        state = .awaitingConfirmation(restored)
        XCTAssertEqual(store.watchSnapshot().primaryAction(commandState: state), .retry)
        state = .sending(try XCTUnwrap(state.command))
        XCTAssertEqual(state.command, command, "Retry must preserve the original command, not create a new ID")
        XCTAssertTrue(state.markUnconfirmed(commandID: command.id))
        XCTAssertEqual(state, .awaitingConfirmation(command))
    }
    func testUnconfirmedCommandIgnoresObsoleteAndRepeatedFailures() throws {
        let command = try completeCommand(), other = try completeCommand()
        var state = WatchCommandState.idle
        XCTAssertFalse(state.markUnconfirmed(commandID: command.id))
        XCTAssertEqual(state, .idle)
        state = .sending(command)
        XCTAssertFalse(state.markUnconfirmed(commandID: other.id))
        XCTAssertEqual(state, .sending(command))
        XCTAssertTrue(state.markUnconfirmed(commandID: command.id))
        XCTAssertFalse(state.markUnconfirmed(commandID: command.id))
        XCTAssertEqual(state, .awaitingConfirmation(command))
        state = .sending(other)
        XCTAssertFalse(state.markUnconfirmed(commandID: command.id))
        XCTAssertEqual(state, .sending(other))
    }
    func testDeliveredRestStaysConsumedAcrossBackgroundAndForeground() throws {
        let now = Date(timeIntervalSince1970: 1000), end = now.addingTimeInterval(90)
        let snapshot = WatchTrainingSnapshot(sessionID: "session", restEnd: end)
        let key = try XCTUnwrap(snapshot.restReminderKey)
        var reminder = WatchForegroundRestReminder()
        _ = reminder.update(snapshot, active: true, now: now)
        XCTAssertTrue(reminder.consume(key: key, now: end))
        XCTAssertNil(reminder.update(snapshot, active: false, now: end.addingTimeInterval(1)))
        XCTAssertTrue(reminder.didAlert)
        XCTAssertNil(reminder.update(snapshot, active: true, workoutRunning: true, now: end.addingTimeInterval(2)))
        XCTAssertFalse(reminder.consume(key: key, now: end.addingTimeInterval(2)))
    }
    func testNewRestRearmsAfterPreviousRestWasDelivered() throws {
        let now = Date(timeIntervalSince1970: 1000), end = now.addingTimeInterval(90)
        var snapshot = WatchTrainingSnapshot(sessionID: "session", restEnd: end)
        let original = try XCTUnwrap(snapshot.restReminderKey)
        var reminder = WatchForegroundRestReminder()
        _ = reminder.update(snapshot, active: true, now: now)
        XCTAssertTrue(reminder.consume(key: original, now: end))
        let nextEnd = end.addingTimeInterval(120)
        snapshot.restEnd = nextEnd
        XCTAssertEqual(reminder.update(snapshot, active: false, workoutRunning: true, now: end), nextEnd)
        XCTAssertFalse(reminder.didAlert)
        XCTAssertFalse(reminder.consume(key: original, now: nextEnd))
        XCTAssertTrue(reminder.consume(key: try XCTUnwrap(snapshot.restReminderKey), now: nextEnd))
        XCTAssertFalse(reminder.consume(key: try XCTUnwrap(snapshot.restReminderKey), now: nextEnd))
    }
    func testEndRestPreservesNextSetAndDuplicateCannotEndNewRest() throws {
        _ = store.performReadyWatchCommand(try completeCommand())
        let row = store.watchSnapshot().nextSet
        let command = try endRestCommand()
        let reply = store.performReadyWatchCommand(command)
        XCTAssertEqual(reply["accepted"] as? Bool, true)
        XCTAssertNil(WatchTrainingSnapshot.decode(reply)?.restEnd)
        XCTAssertEqual(store.watchSnapshot().nextSet, row)
        XCTAssertEqual(store.draft?.completedSets, 1)
        store.startRest(entry: 0, seconds: 120)
        let end = store.restUntil
        XCTAssertEqual(store.performReadyWatchCommand(command)["accepted"] as? Bool, true)
        XCTAssertEqual(store.restUntil, end)
        let restored = GymStore(userID: "watch-test", storage: LocalTrainingStorage(root: root))
        restored.restoreDraft()
        XCTAssertEqual(restored.performReadyWatchCommand(command)["accepted"] as? Bool, true)
        XCTAssertEqual(restored.restUntil, end)
    }
    func testEndRestRejectsChangedTimerWrongOwnerAndUnavailableStorage() throws {
        store.startRest(entry: 0, seconds: 90)
        let stale = try endRestCommand()
        store.adjustRest(by: 30)
        let end = store.restUntil
        XCTAssertEqual(store.performReadyWatchCommand(stale)["accepted"] as? Bool, false)
        var wrongOwner = try endRestCommand(); wrongOwner.entry = 1
        XCTAssertEqual(store.performReadyWatchCommand(wrongOwner)["accepted"] as? Bool, false)
        let current = try endRestCommand()
        store.syncing = true
        XCTAssertEqual(store.performReadyWatchCommand(current)["accepted"] as? Bool, false)
        store.syncing = false
        store.localSaveError = "test write failure"
        XCTAssertEqual(store.performReadyWatchCommand(current)["accepted"] as? Bool, false)
        store.localSaveError = nil
        XCTAssertEqual(store.restUntil, end)
        XCTAssertEqual(store.draft?.completedSets, 0)
    }
    func testLastSetLoadsNextExerciseAndReplayNeverChangesSelection() throws {
        store.changeActive { raw in
            var entries = raw["entries"] as! [[String: Any]]
            entries.append(["id": "0025", "sets": [["w": 30, "r": 8, "done": true]]])
            entries.append(["id": "0025", "sets": [["w": 30, "r": 8, "done": false]]])
            raw["entries"] = entries
        }
        _ = store.performReadyWatchCommand(try completeCommand())
        _ = store.performReadyWatchCommand(try endRestCommand())
        let command = try completeCommand()
        let reply = store.performReadyWatchCommand(command)
        XCTAssertEqual(reply["accepted"] as? Bool, true)
        let snapshot = try XCTUnwrap(WatchTrainingSnapshot.decode(reply))
        XCTAssertEqual(snapshot.nextSet?.entry, 2)
        XCTAssertEqual(snapshot.nextSet?.index, 0)
        XCTAssertEqual(snapshot.nextSet?.weight, "30 kg")
        XCTAssertNil(snapshot.nextEntry)
        store.selectLiveEntry(0)
        XCTAssertEqual(store.performReadyWatchCommand(command)["accepted"] as? Bool, true)
        XCTAssertEqual(store.draft?.activeJSON["cur"] as? Int, 0)
        store.selectLiveEntry(2)
        XCTAssertEqual(store.performReadyWatchCommand(try completeCommand())["accepted"] as? Bool, true)
        XCTAssertNil(store.watchSnapshot().nextSet)
        XCTAssertNil(store.watchSnapshot().nextEntry)
        XCTAssertTrue(store.watchSnapshot().message.contains("保存"))
    }
    func testCompletionStartsSharedRestAndDuplicateDoesNotToggleOrRestart() throws {
        let command = try completeCommand()
        let reply = store.performReadyWatchCommand(command)
        XCTAssertEqual(reply["accepted"] as? Bool, true)
        let snapshot = try XCTUnwrap(WatchTrainingSnapshot.decode(reply))
        XCTAssertEqual(snapshot.nextSet?.index, 1)
        XCTAssertTrue(snapshot.acknowledged.contains(command.id))
        let end = try XCTUnwrap(snapshot.restEnd)
        XCTAssertEqual(end.timeIntervalSinceNow, 90, accuracy: 1)
        let duplicate = store.performReadyWatchCommand(command)
        XCTAssertEqual(duplicate["accepted"] as? Bool, true)
        XCTAssertEqual(WatchTrainingSnapshot.decode(duplicate)?.restEnd, end)
        XCTAssertEqual((store.draft?.rawEntries[0]["sets"] as? [[String: Any]])?[0]["done"] as? Bool, true)
    }
    func testReceiptSurvivesRelaunch() throws {
        let command = try completeCommand()
        _ = store.performReadyWatchCommand(command)
        let restored = GymStore(userID: "watch-test", storage: LocalTrainingStorage(root: root))
        restored.restoreDraft()
        let end = restored.restUntil
        XCTAssertEqual(restored.performReadyWatchCommand(command)["accepted"] as? Bool, true)
        XCTAssertEqual(restored.restUntil, end)
    }
    func testStaleCommandCannotCompleteAfterCopyReorderOrAccountChange() throws {
        let command = try completeCommand()
        store.copyLiveSet(entry: 0, set: 0)
        XCTAssertEqual(store.performReadyWatchCommand(command)["accepted"] as? Bool, false)
        XCTAssertEqual(store.draft?.completedSets, 0)
        let next = try completeCommand()
        store.userID = "another-account"
        XCTAssertEqual(store.performReadyWatchCommand(next)["accepted"] as? Bool, false)
        XCTAssertEqual(store.draft?.completedSets, 0)
    }
    func testIncompleteInputAndRunningTimerBlockWatchCompletion() throws {
        store.liveRowAction(entry: 0, set: 0, action: ["action": "input", "path": "both.w", "text": "", "operation": ["action": "field", "key": "w"]])
        XCTAssertNotNil(store.watchSnapshot().nextSet?.blockedReason)
        XCTAssertEqual(store.performReadyWatchCommand(try completeCommand())["accepted"] as? Bool, false)
        store.liveRowAction(entry: 0, set: 0, action: ["action": "field", "key": "w", "value": 20])
        store.startWorkTimer(entry: 0, set: 0)
        XCTAssertNotNil(store.watchSnapshot().nextSet?.blockedReason)
        XCTAssertEqual(store.performReadyWatchCommand(try completeCommand())["accepted"] as? Bool, false)
    }
    func testSidesAdvanceIndividuallyAndRestStartsOnlyAfterBoth() throws {
        store.changeActive { raw in
            var entries = raw["entries"] as! [[String: Any]]
            let side: [String: Any] = ["w": 10, "r": 6, "done": false]
            entries[0]["sets"] = [["kind": "side", "sides": ["L": side, "R": side], "done": false], ["w": 10, "r": 10, "done": false]]
            raw["entries"] = entries
        }
        XCTAssertEqual(store.watchSnapshot().nextSet?.side, "L")
        XCTAssertEqual(store.performReadyWatchCommand(try completeCommand())["accepted"] as? Bool, true)
        XCTAssertEqual(store.watchSnapshot().nextSet?.side, "R")
        XCTAssertNil(store.restUntil)
        XCTAssertEqual(store.performReadyWatchCommand(try completeCommand())["accepted"] as? Bool, true)
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
        XCTAssertEqual(store.performReadyWatchCommand(command)["accepted"] as? Bool, false)
        let valid = try completeCommand(); store.draft = nil
        XCTAssertEqual(store.performReadyWatchCommand(valid)["accepted"] as? Bool, false)
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

// These command regression tests represent separate deliberate taps after protection.
// Exact boundary, duplicate-during-protection and cross-surface cases have dedicated tests.
private extension GymStore {
    func performReadyWatchCommand(_ command: WatchTrainingCommand) -> [String: Any] {
        performWatchCommand(command, now: max(Date(), trainingActionReadyAt ?? .distantPast))
    }
}
