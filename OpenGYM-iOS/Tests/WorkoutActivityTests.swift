import XCTest
import ActivityKit
@testable import OpenGYM

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

    func testRestoredActivityDoesNotStartWithExpiredProtectionAsStaleDate() throws {
        let now = Date()
        var state = try XCTUnwrap(store.workoutActivityState())
        for deadline in [now.addingTimeInterval(-3600), now] {
            state.actionReadyAt = deadline
            let content = WorkoutActivityCoordinator.content(for: state, now: now)
            XCTAssertNil(content.staleDate)
            XCTAssertEqual(content.state, state)
        }
        state.actionReadyAt = now.addingTimeInterval(5)
        XCTAssertEqual(WorkoutActivityCoordinator.content(for: state, now: now).staleDate, state.actionReadyAt)
    }

    func testExpiredActivityMetadataRefreshesEvenWhenWorkoutHasNotChanged() throws {
        let now = Date()
        var state = try XCTUnwrap(store.workoutActivityState())
        state.actionReadyAt = now.addingTimeInterval(-60)
        let stale = ActivityContent(state: state, staleDate: state.actionReadyAt, relevanceScore: 1)
        let current = WorkoutActivityCoordinator.content(for: state, now: now)
        XCTAssertEqual(stale.state, current.state)
        XCTAssertTrue(WorkoutActivityCoordinator.needsUpdate(stale, to: current))
        XCTAssertFalse(WorkoutActivityCoordinator.needsUpdate(current, to: current))
    }

    // Opt-in integration probe: exercises the actual WidgetKit renderer, which
    // in-process SwiftUI layout tests cannot validate. Use only on a QA simulator.
    func testSystemRendererAfterCompletingSet() async throws {
        #if targetEnvironment(simulator)
        guard UserDefaults.standard.bool(forKey: "OpenGymActivityRendererQA") else {
            throw XCTSkip("Enable OpenGymActivityRendererQA on the QA simulator to capture system rendering.")
        }
        // The host app's unrelated empty store must not end the probe activity
        // when the tester backgrounds the app to inspect the Dynamic Island.
        let runtime = WorkoutActivityRuntime.store
        let runtimeCoordinator = runtime.liveActivity
        runtime.liveActivity = nil
        defer { runtime.liveActivity = runtimeCoordinator }
        let snapshot = store.watchSnapshot()
        let initial = try XCTUnwrap(store.workoutActivityState())
        let activity = try Activity.request(attributes: WorkoutActivityAttributes(account: snapshot.account,
            sessionID: try XCTUnwrap(snapshot.sessionID)), content: ActivityContent(state: initial, staleDate: nil), pushType: nil)
        let coordinator = WorkoutActivityCoordinator(store: store)
        store.liveActivity = coordinator
        defer { store.liveActivity = nil }
        do {
            try await Task.sleep(for: .seconds(3))
            XCTAssertNil(store.performActivityCommand(try XCTUnwrap(initial.command)))
            let resting = try XCTUnwrap(store.workoutActivityState())
            XCTAssertNotNil(resting.restEnd)
            await coordinator.flush()
            print("ACTIVITY_RENDER_QA_REST_UPDATED")
            try await Task.sleep(for: .seconds(30))
            XCTAssertNil(activity.content.staleDate, "Protection expiry must publish without waiting for system stale delivery")
            XCTAssertFalse(activity.content.state.actionTiming.isProtected(at: Date()))
            XCTAssertNil(store.performActivityCommand(try XCTUnwrap(resting.restCommand)))
            let ready = try XCTUnwrap(store.workoutActivityState())
            XCTAssertNil(ready.restEnd)
            await coordinator.flush()
            print("ACTIVITY_RENDER_QA_READY_UPDATED")
            try await Task.sleep(for: .seconds(20))
            XCTAssertNil(activity.content.staleDate)
            XCTAssertFalse(activity.content.state.actionTiming.isProtected(at: Date()))
            await activity.end(nil, dismissalPolicy: .immediate)
        } catch {
            await activity.end(nil, dismissalPolicy: .immediate)
            throw error
        }
        #else
        throw XCTSkip("System renderer probe is simulator-only.")
        #endif
    }

    func testDisplaysTrainingExerciseSetAndUsesStableSmallPayload() throws {
        let state = try XCTUnwrap(store.workoutActivityState())
        XCTAssertEqual(state.trainingName, "胸背训练")
        XCTAssertEqual(state.exercise, "杠铃卧推")
        XCTAssertEqual(state.setLabel, "第 1/2 组")
        XCTAssertEqual(state.compactSet, "第 1/2 组")
        XCTAssertEqual(state.compactSet, store.watchSnapshot().nextSet?.label)
        XCTAssertEqual(state.detail, "40 kg · 10 次")
        XCTAssertEqual(state.setWeight, "40 kg")
        XCTAssertEqual(state.setDetail, "10 次")
        XCTAssertEqual(state.commandTitle, "完成")
        XCTAssertEqual(state, store.workoutActivityState())
        XCTAssertLessThan(try JSONEncoder().encode(state).count, 4096)
    }

    func testOlderActivityContentStillDecodesWithoutSummaryFields() throws {
        let state = try XCTUnwrap(store.workoutActivityState())
        var raw = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
        raw.removeValue(forKey: "setWeight")
        raw.removeValue(forKey: "setDetail")
        raw.removeValue(forKey: "setCompletionLabel")
        raw.removeValue(forKey: "busyTitle")
        let decoded = try JSONDecoder().decode(WorkoutActivityAttributes.ContentState.self, from: JSONSerialization.data(withJSONObject: raw))
        XCTAssertNil(decoded.setWeight)
        XCTAssertNil(decoded.setDetail)
        XCTAssertNil(decoded.setCompletionLabel)
        XCTAssertNil(decoded.busyTitle)
        XCTAssertEqual(decoded.detail, "40 kg · 10 次")
        XCTAssertEqual(decoded.command, state.command)
    }

    func testSavingDisablesCurrentActionAndRestoresCommandsWithoutChangingTraining() throws {
        store.startRest(entry: 0, seconds: 90)
        let before = try XCTUnwrap(store.workoutActivityState())
        store.syncing = true
        let saving = try XCTUnwrap(store.workoutActivityState())
        XCTAssertEqual(saving.busyTitle, "正在保存")
        XCTAssertNil(saving.command)
        XCTAssertNil(saving.restCommand)
        XCTAssertEqual(saving.setLabel, before.setLabel)
        XCTAssertEqual(saving.setWeight, before.setWeight)
        XCTAssertEqual(saving.restEnd, before.restEnd)
        let content = TrainingViewModel(content: saving.trainingContent()).content
        XCTAssertEqual(content.action?.status, .rest(endsAt: try XCTUnwrap(saving.restEnd)))
        XCTAssertEqual(content.action?.title, "结束")
        XCTAssertEqual(content.action?.title, before.trainingContent().action?.title)
        XCTAssertEqual(content.action?.disabled, true)
        store.syncing = false
        let after = try XCTUnwrap(store.workoutActivityState())
        XCTAssertNil(after.busyTitle)
        XCTAssertEqual(after.command, before.command)
        XCTAssertEqual(after.restCommand, before.restCommand)
        XCTAssertEqual(store.draft?.completedSets, 0)
    }

    func testBlockedStatesHaveShortActionTitlesForOpeningTheApp() throws {
        store.localSaveError = "private save failure"
        XCTAssertEqual(store.workoutActivityState()?.commandTitle, String(localized: "COULD_NOT_SAVE", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
        XCTAssertNil(store.workoutActivityState()?.command)
        store.localSaveError = nil
        store.liveRowAction(entry: 0, set: 0, action: ["action": "input", "path": "both.w", "text": "", "operation": ["action": "field", "key": "w"]])
        XCTAssertEqual(store.workoutActivityState()?.commandTitle, "补全数据")
        XCTAssertNil(store.workoutActivityState()?.command)
    }

    func testCompleteStartsRestAndDuplicateNeverCompletesNextSet() throws {
        let command = try XCTUnwrap(store.workoutActivityState()?.command)
        XCTAssertNil(store.performReadyActivityCommand(command))
        let rest = try XCTUnwrap(store.workoutActivityState())
        XCTAssertEqual(rest.compactSet, "第 1/2 组")
        XCTAssertEqual(rest.setLabel, "第 1/2 组")
        XCTAssertEqual(rest.setCompletionLabel, "已完成")
        XCTAssertEqual(try XCTUnwrap(rest.restEnd).timeIntervalSinceNow, 90, accuracy: 1)
        XCTAssertEqual(rest.restExercise, "杠铃卧推")
        XCTAssertNotNil(rest.restCommand)
        XCTAssertLessThan(try JSONEncoder().encode(rest).count, 4096)
        XCTAssertNil(store.performReadyActivityCommand(command))
        XCTAssertEqual(store.draft?.completedSets, 1)
        XCTAssertEqual(store.restUntil, rest.restEnd)
    }

    func testSetSummaryAdvancesOnlyAfterEndingRestAndSurvivesRelaunch() throws {
        // Different targets ensure the label and data stay on the same set.
        store.replaceLiveRow(entry: 0, set: 1, row: ["w": 55, "r": 6, "done": false])
        XCTAssertNil(store.performReadyActivityCommand(try XCTUnwrap(store.workoutActivityState()?.command)))
        store.restUntil = Date().addingTimeInterval(-10)
        let restored = GymStore(userID: "activity-test", storage: LocalTrainingStorage(root: root))
        restored.state = store.state
        restored.restoreDraft()
        let snapshot = restored.watchSnapshot()
        XCTAssertEqual(snapshot.nextSet?.index, 1)
        XCTAssertEqual(snapshot.displayedSet?.index, 0)
        XCTAssertEqual(snapshot.setCompletionLabel, "已完成")
        XCTAssertEqual(WatchTrainingSnapshot.decode(snapshot.payload)?.displayedSet, snapshot.displayedSet)
        let resting = try XCTUnwrap(restored.workoutActivityState())
        XCTAssertEqual(resting.setLabel, "第 1/2 组")
        XCTAssertEqual(resting.setCompletionLabel, "已完成")
        XCTAssertEqual(resting.compactSet, "第 1/2 组")
        XCTAssertEqual(resting.setWeight, "40 kg")
        XCTAssertEqual(resting.setDetail, "10 次")
        XCTAssertNil(restored.performReadyActivityCommand(try XCTUnwrap(resting.restCommand)))
        XCTAssertEqual(restored.watchSnapshot().displayedSet?.index, 1)
        let ready = try XCTUnwrap(restored.workoutActivityState())
        XCTAssertEqual(ready.setLabel, "第 2/2 组")
        XCTAssertNil(ready.setCompletionLabel)
        XCTAssertNil(restored.watchSnapshot().setCompletionLabel)
        XCTAssertEqual(ready.compactSet, "第 2/2 组")
        XCTAssertEqual(ready.setWeight, "55 kg")
        XCTAssertEqual(ready.setDetail, "6 次")
        XCTAssertNil(restored.performReadyActivityCommand(try XCTUnwrap(ready.command)))
        XCTAssertEqual(restored.draft?.completedSets, 2)
    }

    func testManualRestWithoutCompletedSetKeepsUpcomingSummary() throws {
        store.startRest(entry: 0, seconds: 90)
        XCTAssertNil(store.watchSnapshot().restSet)
        XCTAssertNil(store.watchSnapshot().setCompletionLabel)
        XCTAssertNil(store.workoutActivityState()?.setCompletionLabel)
        XCTAssertEqual(store.watchSnapshot().displayedSet, store.watchSnapshot().nextSet)
        XCTAssertEqual(store.workoutActivityState()?.setLabel, "第 1/2 组")
    }

    func testSkipRestPreservesSetsAndRejectsOldTimerCommand() throws {
        XCTAssertNil(store.performReadyActivityCommand(try XCTUnwrap(store.workoutActivityState()?.command)))
        let oldSkip = try XCTUnwrap(store.workoutActivityState()?.restCommand)
        store.adjustRest(by: 30)
        let extended = store.restUntil
        XCTAssertNotNil(store.performReadyActivityCommand(oldSkip))
        XCTAssertEqual(store.restUntil, extended)
        let skip = try XCTUnwrap(store.workoutActivityState()?.restCommand)
        XCTAssertNil(store.performReadyActivityCommand(skip))
        XCTAssertNil(store.restUntil)
        XCTAssertEqual(store.draft?.completedSets, 1)
        XCTAssertNotNil(store.performReadyActivityCommand(skip))
        XCTAssertEqual(store.draft?.completedSets, 1)
    }

    func testCompletionRemainsValidAfterRestChangesBeforeActivityRedraws() throws {
        store.startRest(entry: 0, seconds: 90)
        let command = try XCTUnwrap(store.workoutActivityState()?.command)
        store.adjustRest(by: 30)
        XCTAssertEqual(command, store.workoutActivityState()?.command)
        store.restUntil = nil
        XCTAssertEqual(command, store.workoutActivityState()?.command)
        XCTAssertNil(store.performReadyActivityCommand(command))
        XCTAssertEqual(store.draft?.completedSets, 1)
        let end = store.restUntil
        XCTAssertNil(store.performReadyActivityCommand(command))
        XCTAssertEqual(store.draft?.completedSets, 1)
        XCTAssertEqual(store.restUntil, end)
    }

    func testCompletionSurvivesColdLaunchAfterSkippingRest() throws {
        store.startRest(entry: 0, seconds: 90)
        let command = try XCTUnwrap(store.workoutActivityState()?.command)
        let skip = try XCTUnwrap(store.workoutActivityState()?.restCommand)
        XCTAssertNil(store.performReadyActivityCommand(skip))
        let restored = GymStore(userID: "activity-test", storage: LocalTrainingStorage(root: root))
        restored.state = store.state
        restored.restoreDraft()
        XCTAssertNil(restored.performReadyActivityCommand(command))
        XCTAssertEqual(restored.draft?.completedSets, 1)
    }

    func testRestChangeDoesNotAllowAnEditedSetOrOldWorkTimer() throws {
        store.startRest(entry: 0, seconds: 90)
        let command = try XCTUnwrap(store.workoutActivityState()?.command)
        store.adjustRest(by: 30)
        store.liveRowAction(entry: 0, set: 0, action: ["action": "field", "key": "w", "value": 45])
        XCTAssertNotNil(store.performReadyActivityCommand(command))
        let edited = try XCTUnwrap(store.workoutActivityState()?.command)
        store.startWorkTimer(entry: 0, set: 0)
        XCTAssertNotNil(store.performReadyActivityCommand(edited))
        XCTAssertEqual(store.draft?.completedSets, 0)
    }

    func testUndoOffersANewCommandWhileOldDuplicateStaysHarmless() throws {
        let command = try XCTUnwrap(store.workoutActivityState()?.command)
        XCTAssertNil(store.performReadyActivityCommand(command))
        store.liveRowAction(entry: 0, set: 0, action: ["action": "toggle"])
        XCTAssertEqual(store.draft?.completedSets, 0)
        let retry = try XCTUnwrap(store.workoutActivityState()?.command)
        XCTAssertNotEqual(command, retry)
        XCTAssertNil(store.performReadyActivityCommand(command))
        XCTAssertEqual(store.draft?.completedSets, 0)
        XCTAssertNil(store.performReadyActivityCommand(try XCTUnwrap(store.workoutActivityState()?.restCommand)))
        XCTAssertNil(store.performReadyActivityCommand(retry))
        XCTAssertEqual(store.draft?.completedSets, 1)
    }

    func testLegacyPayloadStillUsesStrictRevisionValidation() throws {
        let snapshot = store.watchSnapshot()
        let legacy = WatchTrainingCommand(id: "legacy-activity", account: snapshot.account,
            sessionID: try XCTUnwrap(snapshot.sessionID), revision: snapshot.revision,
            action: "complete", entry: 0, index: 0)
        let encoded = try JSONEncoder().encode(legacy).base64EncodedString()
        store.startRest(entry: 0, seconds: 90)
        XCTAssertNotNil(store.performReadyActivityCommand(encoded))
        XCTAssertEqual(store.draft?.completedSets, 0)
        store.restUntil = nil
        XCTAssertNil(store.performReadyActivityCommand(encoded))
        XCTAssertEqual(store.draft?.completedSets, 1)
    }

    func testColdLaunchRestoresDraftAndCommandReceipt() throws {
        let command = try XCTUnwrap(store.workoutActivityState()?.command)
        let restored = GymStore(userID: "activity-test", storage: LocalTrainingStorage(root: root))
        restored.state = store.state
        restored.restoreDraft()
        XCTAssertNil(restored.performReadyActivityCommand(command))
        let again = GymStore(userID: "activity-test", storage: LocalTrainingStorage(root: root))
        again.restoreDraft()
        XCTAssertNil(again.performReadyActivityCommand(command))
        XCTAssertEqual(again.draft?.completedSets, 1)
        XCTAssertEqual(again.restUntil, restored.restUntil)
    }

    func testStaleCommandsCannotCompleteEditedReorderedOrDifferentAccountSets() throws {
        let command = try XCTUnwrap(store.workoutActivityState()?.command)
        store.liveRowAction(entry: 0, set: 0, action: ["action": "field", "key": "w", "value": 45])
        XCTAssertNotNil(store.performReadyActivityCommand(command))
        let edited = try XCTUnwrap(store.workoutActivityState()?.command)
        store.copyLiveSet(entry: 0, set: 0)
        XCTAssertNotNil(store.performReadyActivityCommand(edited))
        let copied = try XCTUnwrap(store.workoutActivityState()?.command)
        store.userID = "other"
        XCTAssertNotNil(store.performReadyActivityCommand(copied))
        XCTAssertEqual(store.draft?.completedSets, 0)
    }

    func testBlockedInputTimerSyncAndStorageFailureCannotComplete() throws {
        let command = try XCTUnwrap(store.workoutActivityState()?.command)
        store.syncing = true
        XCTAssertNil(store.workoutActivityState()?.command)
        XCTAssertNotNil(store.performReadyActivityCommand(command))
        store.syncing = false
        store.localSaveError = "test write failure"
        XCTAssertNil(store.workoutActivityState()?.command)
        XCTAssertNotNil(store.performReadyActivityCommand(command))
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
        XCTAssertNil(store.performReadyActivityCommand(try XCTUnwrap(store.workoutActivityState()?.command)))
        XCTAssertNil(store.restUntil)
        XCTAssertTrue(try XCTUnwrap(store.workoutActivityState()?.setLabel).contains("右侧"))
        XCTAssertNil(store.performReadyActivityCommand(try XCTUnwrap(store.workoutActivityState()?.command)))
        XCTAssertNotNil(store.restUntil)
    }

    func testLastSetAutomaticallySelectsNextExerciseThenRemovesActionControl() throws {
        store.changeActive { raw in
            var entries = raw["entries"] as! [[String: Any]]
            entries.append(["id": "custom-bench", "sets": [["w": 20, "r": 8, "done": false]]])
            raw["entries"] = entries
        }
        XCTAssertNil(store.performReadyActivityCommand(try XCTUnwrap(store.workoutActivityState()?.command)))
        XCTAssertNil(store.performReadyActivityCommand(try XCTUnwrap(store.workoutActivityState()?.restCommand)))
        let lastSet = try XCTUnwrap(store.workoutActivityState()?.command)
        XCTAssertNil(store.performReadyActivityCommand(lastSet))
        XCTAssertEqual(store.workoutActivityState()?.commandTitle, "完成")
        XCTAssertEqual(store.watchSnapshot().nextSet?.entry, 1)
        XCTAssertEqual(store.workoutActivityState()?.setLabel, "第 1/1 组")
        // The next exercise starts behind a transition rest owned by that exercise.
        XCTAssertNotNil(store.restUntil)
        XCTAssertEqual(store.restEntry, 1)
        XCTAssertNil(store.performReadyActivityCommand(try XCTUnwrap(store.workoutActivityState()?.restCommand)))
        XCTAssertNil(store.restUntil)
        XCTAssertNil(store.performReadyActivityCommand(lastSet))
        XCTAssertEqual(store.draft?.completedSets, 2)
        XCTAssertEqual(store.watchSnapshot().nextSet?.entry, 1)
        XCTAssertNil(store.performReadyActivityCommand(try XCTUnwrap(store.workoutActivityState()?.command)))
        let completed = try XCTUnwrap(store.workoutActivityState())
        XCTAssertNil(completed.command)
        XCTAssertNil(completed.trainingContent().action)
        XCTAssertTrue(completed.message.contains("保存"))
    }

    func testEndedOrDeletedWorkoutHasNoActivityOrValidCommands() throws {
        let command = try XCTUnwrap(store.workoutActivityState()?.command)
        store.startRest(entry: 0, seconds: 90)
        store.deleteCurrentWorkout()
        XCTAssertNil(store.workoutActivityState())
        XCTAssertNotNil(store.performReadyActivityCommand(command))
        XCTAssertNil(store.restUntil)
    }

    func testMalformedCommandsAndUnknownActionsCannotMutate() throws {
        XCTAssertNotNil(store.performReadyActivityCommand("invalid"))
        let encoded = try XCTUnwrap(store.workoutActivityState()?.command)
        var command = try JSONDecoder().decode(WatchTrainingCommand.self, from: XCTUnwrap(Data(base64Encoded: encoded)))
        command.action = "delete"
        XCTAssertNotNil(store.performReadyActivityCommand(try JSONEncoder().encode(command).base64EncodedString()))
        XCTAssertEqual(store.draft?.completedSets, 0)
    }

    func testDiagnosticsCorrelateDuplicateTapsWithoutLoggingTrainingData() throws {
        let command = try XCTUnwrap(store.workoutActivityState()?.command)
        var records: [WorkoutActivityDiagnostics.Record] = []
        WorkoutActivityDiagnostics.$observer.withValue({ records.append($0) }) {
            XCTAssertNil(store.performReadyActivityCommand(command))
            XCTAssertNil(store.performReadyActivityCommand(command))
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
            XCTAssertNotNil(store.performReadyActivityCommand("not-base64"))
            store.syncing = true
            XCTAssertNotNil(store.performReadyActivityCommand(command))
            store.syncing = false
            store.localSaveError = "private error text"
            XCTAssertNotNil(store.performReadyActivityCommand(command))
            store.localSaveError = nil
            store.liveRowAction(entry: 0, set: 0, action: ["action": "field", "key": "w", "value": 45])
            XCTAssertNotNil(store.performReadyActivityCommand(command))
        }
        XCTAssertTrue(records.contains { $0.event == "activity.command.rejected" && $0.fields["reason"] == "invalid_payload" })
        XCTAssertEqual(records.filter { $0.event == "remote.command.end" }.map { $0.fields["outcome"] }, ["syncing", "save_error", "revision_mismatch"])
        store.startRest(entry: 0, seconds: 90)
        var skip = try JSONDecoder().decode(WatchTrainingCommand.self, from: XCTUnwrap(Data(base64Encoded: try XCTUnwrap(store.workoutActivityState()?.restCommand))))
        skip.entry = 1
        let payload = try JSONEncoder().encode(skip).base64EncodedString()
        WorkoutActivityDiagnostics.$observer.withValue({ records.append($0) }) {
            XCTAssertNotNil(store.performReadyActivityCommand(payload))
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
            XCTAssertNotNil(store.performReadyActivityCommand(command))
        }
        let failure = try XCTUnwrap(records.first { $0.event == "draft.save.failed" })
        XCTAssertNotNil(failure.fields["error_code"])
        XCTAssertNotNil(failure.fields["error_domain"])
        XCTAssertFalse(failure.fields.values.contains { $0.contains(root.path) })
        XCTAssertTrue(records.contains { $0.event == "remote.command.end" && $0.fields["outcome"] == "save_failed" && $0.fields["accepted"] == "false" })
    }
}

private extension GymStore {
    func performReadyActivityCommand(_ command: String) -> String? {
        performActivityCommand(command, now: max(Date(), trainingActionReadyAt ?? .distantPast))
    }
}
