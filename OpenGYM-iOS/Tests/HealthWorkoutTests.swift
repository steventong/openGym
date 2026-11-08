import XCTest
import HealthKit
@testable import OpenGYM

@MainActor final class HealthWorkoutTests: XCTestCase {
    private var root: URL!
    override func setUp() async throws { root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
    override func tearDown() async throws { StubProtocol.handler = nil; try? FileManager.default.removeItem(at: root) }

    private func request(_ id: String = "account:training", owner: HealthWorkoutRequest.Owner = .watch) -> HealthWorkoutRequest {
        HealthWorkoutRequest(id: id, start: Date(timeIntervalSince1970: 1000), owner: owner)
    }
    private func fixture() throws -> (GymStore, HealthWorkoutJournal, String) {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [StubProtocol.self]
        let client = APIClient(address: try ServerAddress("https://test.invalid"), token: "test", session: URLSession(configuration: config))
        let store = GymStore(client: client, userID: "health-test", storage: LocalTrainingStorage(root: root))
        store.serverURL = "https://test.invalid"; store.userName = "Health test"
        store.state = ["unit": "kg", "workouts": [], "routines": []]
        store.draft = try TrainingDraft.fromWeb(["id": "training", "name": "训练", "start": Date().addingTimeInterval(-300).timeIntervalSince1970 * 1000,
            "entries": [["id": "0289", "sets": [["w": 20, "r": 8, "done": true]]]]], unit: "kg")
        let id = "\(store.watchSnapshot().account):training"
        let journal = HealthWorkoutJournal(name: "test", root: root.appendingPathComponent("health"))
        var ledger = HealthWorkoutLedger()
        ledger.merge(HealthWorkoutRequest(id: id, start: store.draft!.start, owner: .watch))
        try journal.write(ledger)
        store.workoutHealth = WorkoutHealthSync(store: store, journal: journal, dispatch: { _ in })
        return (store, journal, id)
    }
    func testEndArrivingBeforeStartNeverStartsDelayedSession() {
        var ledger = HealthWorkoutLedger(), end = request()
        end.phase = .finished; end.end = end.start.addingTimeInterval(600)
        XCTAssertTrue(ledger.merge(end))
        XCTAssertFalse(ledger.merge(request()))
        XCTAssertEqual(ledger.pending, [end])
        ledger.receive(HealthWorkoutReport(id: end.id, state: .saved))
        XCTAssertTrue(ledger.pending.isEmpty)
        XCTAssertFalse(ledger.merge(request()))
    }
    func testWorkoutTitleSurvivesWatchTransferAndJournalWithLegacyFallback() throws {
        var named = request()
        named.title = "胸背训练 A"
        XCTAssertEqual(HealthWorkoutWire.requests(from: HealthWorkoutWire.requests([named])), [named])
        let journal = HealthWorkoutJournal(name: "titles", root: root)
        var ledger = HealthWorkoutLedger(); ledger.merge(named)
        try journal.write(ledger)
        let restored = try XCTUnwrap(try journal.read().requests[named.id])
        XCTAssertEqual(HealthWorkoutAccess.metadata(restored)[HKMetadataKeyWorkoutBrandName] as? String, named.title)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(named)) as? [String: Any])
        legacy.removeValue(forKey: "title")
        let decoded = try JSONDecoder().decode(HealthWorkoutRequest.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertNil(decoded.title)
        XCTAssertEqual(HealthWorkoutAccess.metadata(decoded)[HKMetadataKeyWorkoutBrandName] as? String, "openGym")
    }
    func testFinishCapturesRenamedTrainingAndRetryKeepsItsTitle() throws {
        let (store, journal, id) = try fixture()
        store.changeActive { $0["name"] = "腿部训练 B" }
        let draft = try XCTUnwrap(store.draft)
        XCTAssertTrue(store.workoutHealth.finish(draft, at: Date()))
        let finished = try XCTUnwrap(try journal.read().requests[id])
        XCTAssertEqual(finished.title, draft.name)
        XCTAssertEqual(finished.title, "腿部训练 B")
        XCTAssertEqual(HealthWorkoutAccess.metadata(finished)[HKMetadataKeyWorkoutBrandName] as? String, draft.name)
        store.changeActive { $0["name"] = "之后修改" }
        XCTAssertTrue(store.workoutHealth.finish(try XCTUnwrap(store.draft), at: Date()))
        XCTAssertEqual(try journal.read().requests[id], finished)
    }
    func testOwnerAndFirstEndAreStableAcrossRetryAndConflictingCancel() {
        var ledger = HealthWorkoutLedger(), end = request()
        ledger.merge(end)
        XCTAssertFalse(ledger.merge(request(owner: .phone)))
        end.phase = .finished; end.end = end.start.addingTimeInterval(600); ledger.merge(end)
        var later = end; later.end = end.end!.addingTimeInterval(3600)
        XCTAssertFalse(ledger.merge(later))
        later.phase = .discarded; XCTAssertFalse(ledger.merge(later))
        XCTAssertEqual(ledger.requests[end.id], end)
    }
    func testCancelledSessionCannotBeResurrectedOrSavedByLateStart() {
        var ledger = HealthWorkoutLedger(), cancel = request()
        cancel.phase = .discarded; cancel.end = cancel.start.addingTimeInterval(60)
        ledger.merge(cancel); ledger.receive(HealthWorkoutReport(id: cancel.id, state: .discarded))
        XCTAssertFalse(ledger.merge(request()))
        ledger.receive(HealthWorkoutReport(id: cancel.id, state: .running, activeCalories: 12))
        XCTAssertEqual(ledger.reports[cancel.id]?.state, .discarded)
        XCTAssertTrue(ledger.pending.isEmpty)
    }
    func testMissingCaloriesStayNilWhileMeasuredZeroIsPreserved() throws {
        var ledger = HealthWorkoutLedger(); ledger.merge(request())
        ledger.receive(HealthWorkoutReport(id: request().id, state: .running))
        XCTAssertNil(ledger.reports[request().id]?.activeCalories)
        ledger.receive(HealthWorkoutReport(id: request().id, state: .running, activeCalories: 0))
        XCTAssertEqual(ledger.reports[request().id]?.activeCalories, 0)
        ledger.receive(HealthWorkoutReport(id: request().id, state: .running, activeCalories: -.infinity, heartRate: .nan))
        XCTAssertNil(ledger.reports[request().id]?.activeCalories)
        XCTAssertNil(ledger.reports[request().id]?.heartRate)
        XCTAssertNoThrow(try JSONEncoder().encode(ledger))
    }
    func testTotalCaloriesRequireBothMeasuredComponentsInKcal() {
        XCTAssertEqual(HealthWorkoutReport.totalCalories(active: 128, resting: 28), 156)
        XCTAssertEqual(HealthWorkoutReport.totalCalories(active: 0, resting: 0), 0)
        XCTAssertNil(HealthWorkoutReport.totalCalories(active: 128, resting: nil))
        XCTAssertNil(HealthWorkoutReport.totalCalories(active: nil, resting: 28))
        XCTAssertNil(HealthWorkoutReport.totalCalories(active: -1, resting: 28))
        XCTAssertNil(HealthWorkoutReport.totalCalories(active: 128, resting: .infinity))
        XCTAssertNil(HealthWorkoutReport.totalCalories(active: .greatestFiniteMagnitude, resting: .greatestFiniteMagnitude))
    }
    func testTotalCaloriesSurviveWireAndJournalWhileOldReportsRemainReadable() throws {
        let report = HealthWorkoutReport(id: request().id, state: .running, activeCalories: 128, totalCalories: 156, heartRate: 124)
        XCTAssertEqual(HealthWorkoutWire.report(from: HealthWorkoutWire.report(report)), report)
        let journal = HealthWorkoutJournal(name: "metrics", root: root)
        var ledger = HealthWorkoutLedger(); ledger.merge(request()); ledger.receive(report)
        try journal.write(ledger)
        XCTAssertEqual(try journal.read().reports[report.id]?.totalCalories, 156)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(report)) as? [String: Any])
        legacy.removeValue(forKey: "totalCalories")
        let decoded = try JSONDecoder().decode(HealthWorkoutReport.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertNil(decoded.totalCalories)
        XCTAssertEqual(decoded.activeCalories, 128)
        ledger.receive(HealthWorkoutReport(id: request().id, state: .running, totalCalories: .nan))
        XCTAssertNil(ledger.reports[request().id]?.totalCalories)
        XCTAssertNoThrow(try JSONEncoder().encode(ledger))
    }
    func testStaleReportsDoNotReplaceNewMetricsOrTerminalResult() {
        var ledger = HealthWorkoutLedger(); ledger.merge(request())
        let newer = HealthWorkoutReport(id: request().id, state: .running, activeCalories: 45)
        ledger.receive(newer)
        var stale = newer; stale.activeCalories = 2; stale.updatedAt = newer.updatedAt.addingTimeInterval(-60)
        ledger.receive(stale); XCTAssertEqual(ledger.reports[request().id]?.activeCalories, 45)
        ledger.receive(HealthWorkoutReport(id: request().id, state: .saved, activeCalories: 50))
        ledger.receive(HealthWorkoutReport(id: request().id, state: .failed, message: "old callback"))
        XCTAssertEqual(ledger.reports[request().id]?.state, .saved)
    }
    func testJournalRestartRetainsTerminalRequestsAndReceiptsAndExcludesBackup() throws {
        let journal = HealthWorkoutJournal(name: "replay", root: root)
        var ledger = HealthWorkoutLedger(), end = request()
        end.phase = .finished; end.end = end.start.addingTimeInterval(60); ledger.merge(end)
        try journal.write(ledger)
        var reloaded = try journal.read(); XCTAssertEqual(reloaded.pending, [end])
        reloaded.receive(HealthWorkoutReport(id: end.id, state: .saved)); try journal.write(reloaded)
        XCTAssertTrue(try journal.read().pending.isEmpty)
        XCTAssertEqual(try root.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
    }
    func testWireRejectsInvalidDatesAndRetainsMultiplePendingWorkouts() {
        var invalid = request(); invalid.phase = .finished; invalid.end = invalid.start.addingTimeInterval(-1)
        let good = request("second")
        let payload = HealthWorkoutWire.requests([invalid, good])
        XCTAssertEqual(HealthWorkoutWire.requests(from: payload), [good])
        XCTAssertEqual(HealthWorkoutWire.requests(from: ["healthWorkouts": Data("broken".utf8)]), [])
    }
    func testServerFailureStillStopsHealthAndRetryKeepsOriginalEnd() async throws {
        let (store, journal, id) = try fixture()
        var dispatched: [HealthWorkoutRequest] = []
        store.workoutHealth = WorkoutHealthSync(store: store, journal: journal, dispatch: { dispatched = $0 })
        StubProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        await store.finish()
        XCTAssertNotNil(store.draft)
        let first = try XCTUnwrap(try journal.read().requests[id])
        XCTAssertEqual(first.phase, .finished); XCTAssertNotNil(first.end)
        XCTAssertEqual(dispatched.first?.phase, .finished)
        await store.finish()
        XCTAssertEqual(try journal.read().requests[id], first)
        let restored = WorkoutHealthSync(store: store, journal: journal, dispatch: { dispatched = $0 })
        restored.retry(); XCTAssertEqual(dispatched.first, first)
    }
    func testColdLaunchReconcilesFrozenFinishBeforeDispatch() throws {
        let (store, journal, id) = try fixture()
        let end = Date()
        store.changeActive { $0["nativeFinishAt"] = end.timeIntervalSince1970 * 1000 }
        var dispatched: [HealthWorkoutRequest] = []
        let restored = WorkoutHealthSync(store: store, journal: journal, dispatch: { dispatched = $0 })
        restored.retry()
        XCTAssertEqual(dispatched.first?.phase, .finished)
        XCTAssertEqual(dispatched.first?.title, store.draft?.name)
        XCTAssertEqual(try journal.read().requests[id]?.end?.timeIntervalSince1970 ?? 0, end.timeIntervalSince1970, accuracy: 0.001)
    }
    func testDeletingDraftPersistsDiscardBeforeClearingLocalTraining() throws {
        let (store, journal, id) = try fixture()
        store.deleteCurrentWorkout()
        XCTAssertNil(store.draft)
        XCTAssertEqual(try journal.read().requests[id]?.phase, .discarded)
    }
    func testDiskFailureRetainsDraftAndDoesNotDispatchStop() throws {
        let (store, journal, id) = try fixture()
        var dispatched = false
        store.workoutHealth = WorkoutHealthSync(store: store, journal: journal, dispatch: { _ in dispatched = true })
        try FileManager.default.removeItem(at: journal.url.deletingLastPathComponent())
        try Data([0]).write(to: journal.url.deletingLastPathComponent())
        store.deleteCurrentWorkout()
        XCTAssertNotNil(store.draft); XCTAssertNotNil(store.error); XCTAssertFalse(dispatched)
        XCTAssertEqual(store.workoutHealth.ledger.requests[id]?.phase, .running)
    }
    func testReportsFromNonOwningDeviceOrDifferentAccountAreIgnored() throws {
        let (store, _, id) = try fixture()
        store.workoutHealth.receive(HealthWorkoutReport(id: id, state: .saved, activeCalories: 500), owner: .phone)
        XCTAssertNil(store.workoutHealth.ledger.reports[id])
        store.workoutHealth.receive(HealthWorkoutReport(id: "different:training", state: .saved, activeCalories: 500), owner: .watch)
        XCTAssertNil(store.workoutHealth.current)
        store.workoutHealth.receive(HealthWorkoutReport(id: id, state: .running, activeCalories: 15), owner: .watch)
        XCTAssertEqual(store.workoutHealth.report(for: store.draft!)?.activeCalories, 15)
    }
}
