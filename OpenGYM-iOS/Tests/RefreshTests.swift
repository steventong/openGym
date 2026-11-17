import XCTest
@testable import OpenGYM

@MainActor final class RefreshTests: XCTestCase {
    private func localStore(_ persistence: PersistenceController = PersistenceController(inMemory: true)) throws -> GymStore {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return GymStore(userID: "sync-test", storage: LocalTrainingStorage(root: root), persistence: persistence)
    }

    func testRefreshReadsDataSavedByAnotherDeviceAndRecordsTheChange() async throws {
        let persistence = PersistenceController(inMemory: true)
        let store = try localStore(persistence), other = try localStore(persistence)
        try store.reloadDocument()
        store.lastDocumentChange = Date(timeIntervalSince1970: 1)
        let saved = await other.mutate { source in
            var next = source; next["customEx"] = [["id": "gym-specific", "n": "DPC GYM"]]; return next
        }
        XCTAssertTrue(saved)
        let result = await store.refresh()
        try result.get()
        XCTAssertEqual(store.customExercises.first?["id"] as? String, "gym-specific")
        XCTAssertGreaterThan(try XCTUnwrap(store.lastDocumentChange).timeIntervalSince1970, 1)
    }

    func testCustomExerciseDeletionRechecksReferencesAfterAnotherDeviceUsesIt() async throws {
        let persistence = PersistenceController(inMemory: true)
        let store = try localStore(persistence), other = try localStore(persistence)
        let exercise = ["id": "custom", "n": "Custom exercise"]
        let seeded = await store.mutate { source in var next = source; next["customEx"] = [exercise]; return next }
        XCTAssertTrue(seeded)
        XCTAssertNil(store.customExerciseDeletionIssue("custom"))
        // 确认可以删除之后，另一台设备把这个动作排进了计划。
        try other.reloadDocument()
        let used = await other.mutate { source in
            var next = source; next["routines"] = [["id": "remote-routine", "ex": [["id": "custom"]]]]; return next
        }
        XCTAssertTrue(used)
        try store.reloadDocument()
        let deleted = await store.deleteCustomExercise(exercise)
        XCTAssertFalse(deleted)
        XCTAssertEqual(store.customExercises.first?["id"] as? String, "custom")
        XCTAssertEqual(store.editError, String(localized: "CUSTOM_EXERCISE_STILL_IN_USE", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
        try other.reloadDocument()
        XCTAssertEqual(other.customExercises.first?["id"] as? String, "custom")
    }
}
