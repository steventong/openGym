import XCTest
import HealthKit
@testable import OpenGYM

@MainActor final class HistoryHealthSyncTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000)
    private var record: WorkoutRecord {
        WorkoutRecord(raw: ["id": "history-one", "name": "腿部训练 B", "d": "1970-01-01",
            "start": 1_000_125, "end": 1_600_875, "entries": []])
    }

    func testRequestPreservesTitleAndMillisecondsWithoutStartingCollection() throws {
        let request = try HistoryHealthRequest.make(record, account: "account", now: now)
        XCTAssertEqual(request.title, "腿部训练 B")
        XCTAssertEqual(request.start.timeIntervalSince1970, 1_000.125, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(request.end).timeIntervalSince1970, 1_600.875, accuracy: 0.001)
        XCTAssertEqual(request.owner, .phone)
        XCTAssertEqual(request.phase, .finished)
        XCTAssertTrue(request.isValid)
        XCTAssertEqual(HealthWorkoutAccess.configuration.activityType, .traditionalStrengthTraining)
        let metadata = HealthWorkoutAccess.metadata(request)
        XCTAssertEqual(Set(metadata.keys), [HKMetadataKeySyncIdentifier, HKMetadataKeySyncVersion, HKMetadataKeyWorkoutBrandName])
        XCTAssertEqual(metadata[HKMetadataKeyWorkoutBrandName] as? String, request.title)
    }

    func testRepeatedExportHasStableAccountAndWorkoutScopedIdentifier() throws {
        let first = try HistoryHealthRequest.make(record, account: "account", now: now)
        let second = try HistoryHealthRequest.make(record, account: "account", now: now)
        XCTAssertEqual(first.syncIdentifier, second.syncIdentifier)
        XCTAssertEqual(first.id, "account:history:history-one")
        let a = try HistoryHealthRequest.make(record, account: "a", now: now)
        let b = try HistoryHealthRequest.make(record, account: "b", now: now)
        XCTAssertNotEqual(a.syncIdentifier, b.syncIdentifier)
        var changed = record.raw
        changed["name"] = "Updated workout"
        changed["start"] = 1_100_000
        changed["end"] = 1_700_000
        XCTAssertEqual(try HistoryHealthRequest.make(WorkoutRecord(raw: changed), account: "account", now: now).syncIdentifier, first.syncIdentifier)
        changed["id"] = "history-two"
        XCTAssertNotEqual(try HistoryHealthRequest.make(WorkoutRecord(raw: changed), account: "account", now: now).syncIdentifier, first.syncIdentifier)
        let live = HealthWorkoutRequest(id: "account:history-one", start: first.start, owner: .phone)
        XCTAssertNotEqual(live.syncIdentifier, first.syncIdentifier)
    }

    func testRejectsMissingMalformedBooleanAndNonfiniteTimes() {
        for key in ["start", "end"] {
            var missing = record.raw
            missing.removeValue(forKey: key)
            XCTAssertThrowsError(try HistoryHealthRequest.make(WorkoutRecord(raw: missing), account: "account", now: now))
            for invalid in [NSNull(), "1000000", true, Double.nan, Double.infinity, -1, 0] as [Any] {
                var raw = record.raw
                raw[key] = invalid
                XCTAssertThrowsError(try HistoryHealthRequest.make(WorkoutRecord(raw: raw), account: "account", now: now), "\(key): \(invalid)")
            }
        }
    }

    func testRejectsZeroReversedFutureAndExcessiveDuration() {
        for (start, end) in [(1_000_000.0, 1_000_000.0), (1_600_000, 1_000_000), (1_000_000, 2_000_001), (1_000_000, 87_400_001)] {
            var raw = record.raw
            raw["start"] = start; raw["end"] = end
            XCTAssertThrowsError(try HistoryHealthRequest.make(WorkoutRecord(raw: raw), account: "account", now: now))
        }
    }

    func testAcceptsFullDayAndLegacyHistoryIdentifier() throws {
        var raw = record.raw
        raw.removeValue(forKey: "id")
        raw["end"] = 87_400_125
        let request = try HistoryHealthRequest.make(WorkoutRecord(raw: raw), account: "account", now: Date(timeIntervalSince1970: 100_000))
        XCTAssertTrue(request.id.contains(WorkoutRecord.key(raw)))
        XCTAssertEqual(try XCTUnwrap(request.end).timeIntervalSince(request.start), 86_400, accuracy: 0.001)
    }

    func testRejectsMissingAccountIdentityAndBlankTitle() {
        XCTAssertThrowsError(try HistoryHealthRequest.make(record, account: "", now: now))
        for (key, value) in [("id", ""), ("id", "  "), ("name", ""), ("name", " \n ")] {
            var raw = record.raw
            raw[key] = value
            XCTAssertThrowsError(try HistoryHealthRequest.make(WorkoutRecord(raw: raw), account: "account", now: now))
        }
    }

    func testSuccessfulExportAuthorizesDeletesAndSavesOnce() async throws {
        var events: [String] = []
        var deleted: [String] = []
        var saved: [HealthWorkoutRequest] = []
        let service = HistoryHealthSync(available: true, authorize: { events.append("authorize") }, deletePrevious: {
            events.append("delete"); deleted.append($0)
        }, save: {
            events.append("save"); saved.append($0)
        })
        try await service.sync(record, account: "account")
        XCTAssertEqual(events, ["authorize", "delete", "save"])
        XCTAssertEqual(deleted, saved.map(\.syncIdentifier))
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved.first?.phase, .finished)
        XCTAssertEqual(saved.first?.owner, .phone)
        XCTAssertFalse(service.busy)
    }

    func testAuthorizationDenialDoesNotDeleteOrWriteAndRestoresBusy() async {
        var deletes = 0
        var saves = 0
        let service = HistoryHealthSync(available: true, authorize: { throw NSError(domain: "test", code: 9) }, deletePrevious: { _ in deletes += 1 }, save: { _ in saves += 1 })
        do { try await service.sync(record, account: "account"); XCTFail("Authorization must fail") }
        catch { XCTAssertEqual((error as NSError).code, 9) }
        XCTAssertEqual(deletes, 0)
        XCTAssertEqual(saves, 0)
        XCTAssertFalse(service.busy)
    }

    func testWriteFailureDoesNotAutomaticallyReplayAndRetryDeletesTheSameIdentifier() async throws {
        var requests: [HealthWorkoutRequest] = []
        var deleted: [String] = []
        let service = HistoryHealthSync(available: true, authorize: {}, deletePrevious: { deleted.append($0) }, save: { request in
            requests.append(request)
            if requests.count == 1 { throw NSError(domain: "test", code: 10) }
        })
        do { try await service.sync(record, account: "account"); XCTFail("First write must fail") }
        catch { XCTAssertEqual((error as NSError).code, 10) }
        XCTAssertFalse(service.busy)
        await Task.yield()
        XCTAssertEqual(requests.count, 1, "There is no background/manual export retry queue")
        XCTAssertEqual(deleted.count, 1)
        try await service.sync(record, account: "account")
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[0].syncIdentifier, requests[1].syncIdentifier)
        XCTAssertEqual(deleted, requests.map(\.syncIdentifier))
        XCTAssertFalse(service.busy)
    }

    func testConcurrentTapCannotCreateSecondExport() async throws {
        let entered = expectation(description: "save started")
        var release: CheckedContinuation<Void, Never>?
        var saves = 0
        var authorizations = 0
        let service = HistoryHealthSync(available: true, authorize: { authorizations += 1 }, deletePrevious: { _ in }, save: { _ in
            saves += 1
            await withCheckedContinuation { continuation in
                release = continuation
                entered.fulfill()
            }
        })
        let first = Task { try await service.sync(record, account: "account") }
        await fulfillment(of: [entered], timeout: 2)
        XCTAssertTrue(service.busy)
        do { try await service.sync(record, account: "account"); XCTFail("Second tap must be blocked") }
        catch { }
        XCTAssertEqual(saves, 1)
        XCTAssertEqual(authorizations, 1)
        release?.resume()
        try await first.value
        XCTAssertFalse(service.busy)
    }

    func testManualExportDoesNotReopenAnAutomaticSavedReceipt() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = GymStore(userID: "manual-health", storage: LocalTrainingStorage(root: root))
        let account = try XCTUnwrap(store.accountFolder?.lastPathComponent)
        let automaticRequest = HealthWorkoutRequest(id: "\(account):\(record.id)", start: Date(timeIntervalSince1970: 1_000), owner: .watch)
        let journal = HealthWorkoutJournal(name: "automatic", root: root)
        var ledger = HealthWorkoutLedger()
        ledger.merge(automaticRequest)
        ledger.receive(HealthWorkoutReport(id: automaticRequest.id, state: .saved))
        try journal.write(ledger)
        let before = try Data(contentsOf: journal.url)
        var dispatched = 0
        store.workoutHealth = WorkoutHealthSync(store: store, journal: journal, dispatch: { _ in dispatched += 1 })
        let enabled = store.workoutHealth.enabled
        var saved: HealthWorkoutRequest?
        store.historyHealth = HistoryHealthSync(available: true, authorize: {}, deletePrevious: { _ in }, save: { saved = $0 })
        try await store.historyHealth.sync(record, account: account)
        XCTAssertNotNil(saved)
        XCTAssertNotEqual(saved?.syncIdentifier, automaticRequest.syncIdentifier)
        XCTAssertEqual(try Data(contentsOf: journal.url), before)
        XCTAssertTrue(store.workoutHealth.ledger.pending.isEmpty)
        XCTAssertEqual(store.workoutHealth.enabled, enabled)
        XCTAssertEqual(dispatched, 0)
    }

    func testRepeatedSyncReplacesOnlyExactIdentifierAndLeavesUnknownIDsAlone() async throws {
        let expected = try HistoryHealthRequest.make(record, account: "account", now: now).syncIdentifier
        let otherAccount = try HistoryHealthRequest.make(record, account: "other-account", now: now).syncIdentifier
        let automatic = HealthWorkoutRequest(id: "account:history-one", start: Date(timeIntervalSince1970: 1_000), owner: .watch).syncIdentifier
        let oldRandom = expected + ":" + UUID().uuidString
        let untouched = [otherAccount, automatic, oldRandom, "unknown-id", ""]
        var stored = [expected, expected] + untouched
        let service = HistoryHealthSync(available: true, authorize: {}, deletePrevious: { identifier in
            XCTAssertEqual(identifier, expected)
            stored.removeAll { $0 == identifier }
        }, save: { stored.append($0.syncIdentifier) })
        for _ in 0..<2 {
            try await service.sync(record, account: "account")
            XCTAssertEqual(stored.filter { $0 == expected }.count, 1)
            XCTAssertEqual(stored.filter { $0 != expected }, untouched)
        }
    }

    func testMissingMatchingIdentifierSkipsRemovalAndStillSaves() async throws {
        var stored = ["unrelated-workout"]
        var removed = 0
        var saves = 0
        let service = HistoryHealthSync(available: true, authorize: {}, deletePrevious: { identifier in
            let count = stored.count
            stored.removeAll { $0 == identifier }
            removed += count - stored.count
        }, save: { request in
            saves += 1
            stored.append(request.syncIdentifier)
        })
        try await service.sync(record, account: "account")
        XCTAssertEqual(removed, 0)
        XCTAssertEqual(saves, 1)
        XCTAssertEqual(stored.first, "unrelated-workout")
        XCTAssertEqual(stored.count, 2)
    }

    func testDeleteFailureStopsNewSaveAndExplicitRetryUsesTheSameIdentifier() async throws {
        var deleted: [String] = []
        var saves = 0
        let service = HistoryHealthSync(available: true, authorize: {}, deletePrevious: { identifier in
            deleted.append(identifier)
            if deleted.count == 1 { throw NSError(domain: "test", code: 11) }
        }, save: { _ in saves += 1 })
        do { try await service.sync(record, account: "account"); XCTFail("Delete failure must stop this sync") }
        catch { XCTAssertEqual((error as NSError).code, 11) }
        XCTAssertEqual(saves, 0)
        XCTAssertFalse(service.busy)
        await Task.yield()
        XCTAssertEqual(deleted.count, 1)
        try await service.sync(record, account: "account")
        XCTAssertEqual(deleted.count, 2)
        XCTAssertEqual(deleted[0], deleted[1])
        XCTAssertEqual(saves, 1)
        XCTAssertFalse(service.busy)
    }

    func testConcurrentTapWhileDeletingCannotStartAnotherSync() async throws {
        let entered = expectation(description: "delete started")
        var release: CheckedContinuation<Void, Never>?
        var deletes = 0
        var saves = 0
        let service = HistoryHealthSync(available: true, authorize: {}, deletePrevious: { _ in
            deletes += 1
            await withCheckedContinuation { continuation in
                release = continuation
                entered.fulfill()
            }
        }, save: { _ in saves += 1 })
        let first = Task { try await service.sync(record, account: "account") }
        await fulfillment(of: [entered], timeout: 2)
        XCTAssertTrue(service.busy)
        do { try await service.sync(record, account: "account"); XCTFail("A second sync must not run during deletion") }
        catch { }
        XCTAssertEqual(deletes, 1)
        XCTAssertEqual(saves, 0)
        release?.resume()
        try await first.value
        XCTAssertEqual(saves, 1)
        XCTAssertFalse(service.busy)
    }

    func testUnavailableOrInvalidInputNeverAuthorizesDeletesOrSaves() async {
        var authorizations = 0
        var deletes = 0
        var saves = 0
        for available in [false, true] {
            let service = HistoryHealthSync(available: available, authorize: { authorizations += 1 }, deletePrevious: { _ in deletes += 1 }, save: { _ in saves += 1 })
            do { try await service.sync(record, account: ""); XCTFail("Must fail before authorization") }
            catch { }
            XCTAssertFalse(service.busy)
        }
        XCTAssertEqual(authorizations, 0)
        XCTAssertEqual(deletes, 0)
        XCTAssertEqual(saves, 0)
    }
}
