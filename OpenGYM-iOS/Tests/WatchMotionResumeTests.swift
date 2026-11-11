import XCTest
@testable import OpenGYM

@MainActor final class WatchMotionResumeTests: XCTestCase {
    private var root: URL!
    private var store: GymStore!
    private var restStart: Date!
    private var onset: Date!
    private var received: Date!
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        suite = "WatchMotionResumeTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        store = GymStore(userID: "watch-motion-test", storage: LocalTrainingStorage(root: root), defaults: defaults)
        store.autoEndRestEnabled = true
        store.state = ["unit": "kg", "restSec": 90]
        store.draft = try TrainingDraft.fromWeb(["id": "session", "start": 1000, "cur": 0,
            "entries": [["id": "bench", "sets": [["w": 40, "r": 10, "done": false], ["w": 40, "r": 10, "done": false]]]]], unit: "kg")
        XCTAssertTrue(store.liveRowAction(entry: 0, set: 0, action: ["action": "toggle"]))
        restStart = try XCTUnwrap(store.watchSnapshot().restStartedAt)
        onset = restStart.addingTimeInterval(5)
        received = restStart.addingTimeInterval(20)
    }

    override func tearDown() async throws {
        store = nil
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
        try? FileManager.default.removeItem(at: root)
    }

    private func command() throws -> WatchTrainingCommand {
        let snapshot = store.watchSnapshot()
        return WatchTrainingCommand(account: snapshot.account, sessionID: try XCTUnwrap(snapshot.sessionID),
            revision: snapshot.revision, action: "resumeFromMotion", entry: try XCTUnwrap(snapshot.restEntry), detectedStartedAt: onset)
    }

    func testPreferenceDefaultsOffPersistsAndRoundTripsThroughSnapshot() throws {
        defaults.removePersistentDomain(forName: suite)
        let fresh = GymStore(userID: "watch-motion-test", storage: LocalTrainingStorage(root: root), defaults: defaults)
        XCTAssertFalse(fresh.autoEndRestEnabled)
        XCTAssertFalse(try XCTUnwrap(WatchTrainingSnapshot.decode(fresh.watchSnapshot().payload)).autoEndRestEnabled)
        fresh.autoEndRestEnabled = true
        let restored = GymStore(userID: "watch-motion-test", storage: LocalTrainingStorage(root: root), defaults: defaults)
        restored.restoreDraft()
        XCTAssertTrue(restored.autoEndRestEnabled)
        XCTAssertTrue(try XCTUnwrap(WatchTrainingSnapshot.decode(restored.watchSnapshot().payload)).autoEndRestEnabled)
        restored.autoEndRestEnabled = false
        let disabled = GymStore(storage: LocalTrainingStorage(root: root), defaults: defaults)
        XCTAssertFalse(disabled.autoEndRestEnabled)
        XCTAssertFalse(disabled.watchSnapshot().autoEndRestEnabled)
    }

    func testDisablingRejectsInFlightMotionWithoutChangingRestAndStillAllowsManualEnd() throws {
        let motion = try command()
        let before = store.draft?.activeJSON
        store.autoEndRestEnabled = false
        XCTAssertFalse(store.watchSnapshot().autoEndRestEnabled)
        XCTAssertEqual(store.performWatchCommand(motion, now: received)["accepted"] as? Bool, false)
        XCTAssertTrue(RecordPatch.equal(store.draft?.activeJSON, before))
        XCTAssertNotNil(store.restUntil)
        var manual = motion
        manual.id = UUID().uuidString
        manual.action = "skipRest"
        manual.detectedStartedAt = nil
        XCTAssertEqual(store.performWatchCommand(manual, now: received)["accepted"] as? Bool, true)
        XCTAssertNil(store.restUntil)
        XCTAssertEqual(store.draft?.completedSets, 1)
    }

    func testDisablingStillAcknowledgesAlreadyAppliedMotionWithoutReplayingIt() throws {
        let motion = try command()
        XCTAssertEqual(store.performWatchCommand(motion, now: received)["accepted"] as? Bool, true)
        store.startRest(entry: 0, seconds: 90)
        let before = store.draft?.activeJSON
        store.autoEndRestEnabled = false
        XCTAssertEqual(store.performWatchCommand(motion, now: received)["accepted"] as? Bool, true)
        XCTAssertTrue(RecordPatch.equal(store.draft?.activeJSON, before))
        XCTAssertNotNil(store.restUntil)
    }

    func testResumePersistsFirstMovementAcrossSurfacesAndRelaunchWithoutCompletingSet() throws {
        let command = try command()
        XCTAssertEqual(WatchTrainingCommand.decode(command.payload), command)
        let nextSet = store.watchSnapshot().nextSet
        let response = store.performWatchCommand(command, now: received)
        XCTAssertEqual(response["accepted"] as? Bool, true)
        XCTAssertNil(store.restUntil)
        XCTAssertEqual(store.draft?.completedSets, 1)
        XCTAssertEqual(store.watchSnapshot().nextSet, nextSet)
        XCTAssertEqual(try XCTUnwrap(store.watchSnapshot().setStartedAt).timeIntervalSince(onset), 0, accuracy: 0.000001)
        XCTAssertEqual(store.workoutActivityState()?.setStartedAt, store.watchSnapshot().setStartedAt)
        XCTAssertEqual(try XCTUnwrap(store.trainingActionReadyAt).timeIntervalSince(received), 3, accuracy: 0.000001)
        let restored = GymStore(userID: "watch-motion-test", storage: LocalTrainingStorage(root: root), defaults: defaults)
        restored.restoreDraft()
        XCTAssertEqual(try XCTUnwrap(restored.watchSnapshot().setStartedAt).timeIntervalSince(onset), 0, accuracy: 0.000001)
        XCTAssertEqual(restored.draft?.completedSets, 1)
    }

    func testDuplicateCannotRewriteOnsetOrEndFollowingRest() throws {
        let command = try command()
        XCTAssertEqual(store.performWatchCommand(command, now: received)["accepted"] as? Bool, true)
        XCTAssertEqual(store.performWatchCommand(command, now: received.addingTimeInterval(10))["accepted"] as? Bool, true)
        XCTAssertEqual(try XCTUnwrap(store.watchSnapshot().setStartedAt).timeIntervalSince(onset), 0, accuracy: 0.000001)
        store.startRest(entry: 0, seconds: 120)
        let end = store.restUntil
        XCTAssertEqual(store.performWatchCommand(command, now: received.addingTimeInterval(20))["accepted"] as? Bool, true)
        XCTAssertEqual(store.restUntil, end)
    }

    func testRejectsMissingOutOfRangeAndNonFiniteTimestampsWithoutMutation() throws {
        let original = store.draft?.activeJSON
        for time in [nil, restStart.addingTimeInterval(-0.001), received.addingTimeInterval(0.001),
                     Date(timeIntervalSince1970: .nan), Date(timeIntervalSince1970: .infinity)] as [Date?] {
            var command = try command()
            command.detectedStartedAt = time
            XCTAssertEqual(store.performWatchCommand(command, now: received)["accepted"] as? Bool, false)
            XCTAssertTrue(RecordPatch.equal(store.draft?.activeJSON, original))
        }
    }

    func testRejectsChangedRestAccountSessionTargetAndMissingNextSet() throws {
        let stale = try command()
        store.adjustRest(by: 15)
        let original = store.draft?.activeJSON
        XCTAssertEqual(store.performWatchCommand(stale, now: received)["accepted"] as? Bool, false)
        for change in 0..<3 {
            var command = try command()
            switch change {
            case 0: command.account = "another-account"
            case 1: command.sessionID = "another-session"
            default: command.entry = 1
            }
            XCTAssertEqual(store.performWatchCommand(command, now: received)["accepted"] as? Bool, false)
            XCTAssertTrue(RecordPatch.equal(store.draft?.activeJSON, original))
        }
        store.changeActive { raw in
            var entries = raw["entries"] as! [[String: Any]]
            entries[0]["sets"] = [["w": 40, "r": 10, "done": true]]
            raw["entries"] = entries
        }
        XCTAssertEqual(store.performWatchCommand(try command(), now: received)["accepted"] as? Bool, false)
        XCTAssertNotNil(store.restUntil)
    }

    func testRejectsMotionAfterManualEndAndDuringSaving() throws {
        let stale = try command()
        store.endRestFromTextButton(at: received)
        let start = store.watchSnapshot().setStartedAt
        XCTAssertEqual(store.performWatchCommand(stale, now: received.addingTimeInterval(10))["accepted"] as? Bool, false)
        XCTAssertEqual(store.watchSnapshot().setStartedAt, start)
        store.startRest(entry: 0, seconds: 90)
        let command = try command()
        store.syncing = true
        XCTAssertEqual(store.performWatchCommand(command, now: received)["accepted"] as? Bool, false)
        store.syncing = false
        store.localSaveError = "test write failure"
        XCTAssertEqual(store.performWatchCommand(command, now: received)["accepted"] as? Bool, false)
        XCTAssertNotNil(store.restUntil)
        XCTAssertEqual(store.draft?.completedSets, 1)
    }

    func testMotionCannotBackdateIntoProtectionEvenIfConfirmationArrivesLater() throws {
        store.protectTrainingAction(at: restStart)
        var command = try command()
        command.detectedStartedAt = restStart.addingTimeInterval(2.999)
        XCTAssertEqual(store.performWatchCommand(command, now: received)["accepted"] as? Bool, false)
        command.detectedStartedAt = restStart.addingTimeInterval(3)
        XCTAssertEqual(store.performWatchCommand(command, now: received)["accepted"] as? Bool, true)
    }

    func testManualRestCreationAlsoPublishesStartAndAdjustmentKeepsItStable() throws {
        store.startExerciseRest(entry: 0, seconds: 30)
        let start = try XCTUnwrap(store.watchSnapshot().restStartedAt)
        store.adjustRest(by: 15)
        XCTAssertEqual(store.watchSnapshot().restStartedAt, start)
        XCTAssertEqual(try XCTUnwrap(store.watchSnapshot().restEnd).timeIntervalSince(start), 45, accuracy: 0.01)
    }
}
