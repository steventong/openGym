import CoreData
import XCTest
@testable import OpenGYM

@MainActor final class LocalStoreTests: XCTestCase {
    private var root: URL!
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        suite = "local-store-tests-" + UUID().uuidString
        defaults = UserDefaults(suiteName: suite)
    }
    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
        defaults.removePersistentDomain(forName: suite)
    }

    private func store(_ persistence: PersistenceController = PersistenceController(inMemory: true)) -> GymStore {
        GymStore(userID: "local", storage: LocalTrainingStorage(root: root), defaults: defaults, persistence: persistence)
    }
    private func workout(_ id: String, day: String, start: Double, exercise: String = "0025") -> [String: Any] {
        ["id": id, "d": day, "start": start, "end": start + 60_000, "name": id,
         "entries": [["id": exercise, "sets": [["w": 60, "r": 8, "done": true]]]]]
    }
    private func objects(_ entity: String, in persistence: PersistenceController) throws -> [NSManagedObject] {
        try persistence.container.viewContext.fetch(NSFetchRequest<NSManagedObject>(entityName: entity))
    }
    private let benchPress = Exercise(id: "0025", name: "杠铃卧推", english: "barbell bench press", bodyPart: "chest", equipment: "barbell",
                                      target: "pectorals", category: "strength", instructions: ["躺在卧推凳上。"], description: "A chest press.",
                                      englishInstructions: ["Lie on the bench."])

    // MARK: - 文档与记录

    func testCanonicalDocumentSortsRecordsAndKeepsUnknownSettings() {
        let document: [String: Any] = [
            "unit": "lb", "futureField": ["keep": true],
            "workouts": [workout("b", day: "2026-11-02", start: 2), workout("a", day: "2026-11-01", start: 9), ["note": "no identity fields"]],
            "bodyweight": [["d": "2026-11-02", "w": 81], ["d": "2026-11-01", "w": 80], ["d": "2026-11-02", "w": 82], ["w": 1]],
            "routines": [["id": "r2", "name": "B"], ["id": "r1", "name": "A"], ["name": "no id"]],
        ]
        let canonical = StateDocument.canonical(document)
        // 没有 id 的训练仍可由日期和开始时间识别，与页面读取规则一致。
        XCTAssertEqual((canonical["workouts"] as? [[String: Any]])?.compactMap { $0["id"] as? String }, ["a", "b"])
        XCTAssertEqual((canonical["workouts"] as? [[String: Any]])?.count, 3)
        let weights = canonical["bodyweight"] as? [[String: Any]]
        XCTAssertEqual(weights?.map { $0["d"] as? String }, ["2026-11-01", "2026-11-02"])
        XCTAssertEqual(weights?.last?["w"] as? Int, 82)
        XCTAssertEqual((canonical["routines"] as? [[String: Any]])?.map { $0["id"] as? String }, ["r2", "r1"])
        XCTAssertEqual(canonical["unit"] as? String, "lb")
        XCTAssertTrue(StateDocument.same(canonical["futureField"], ["keep": true]))
        XCTAssertNil(canonical["measurements"])
        XCTAssertTrue(StateDocument.same(StateDocument.canonical(canonical), canonical))
    }

    func testRepositoryRoundTripsDocumentAcrossInstances() throws {
        let persistence = PersistenceController(inMemory: true)
        let document = StateDocument.canonical([
            "unit": "kg", "restSec": 90, "keepAwake": false, "week": ["1": ["r1"]], "lang": "zh",
            "routines": [["id": "r1", "name": "上肢", "ex": [["id": "0025", "sets": 3, "reps": 8, "weight": 62.5]]]],
            "workouts": [workout("w1", day: "2026-11-01", start: 1_700_000_000_000)],
            "bodyweight": [["d": "2026-11-01", "w": 80.4, "t": 1]],
            "measurements": [["d": "2026-11-01", "waist": 82]],
            "customEx": [["id": "c1", "n": "自建动作", "bp": "chest", "eq": "barbell", "custom": true]],
        ])
        try StateRepository(persistence: persistence).save(document)
        let loaded = try StateRepository(persistence: persistence).load()
        XCTAssertTrue(StateDocument.same(loaded, document))
        XCTAssertEqual(try objects("StoredWorkout", in: persistence).first?.value(forKey: "day") as? String, "2026-11-01")
        XCTAssertEqual(try objects("StoredRoutine", in: persistence).first?.value(forKey: "name") as? String, "上肢")
        XCTAssertEqual(try objects("StoredExercise", in: persistence).first?.value(forKey: "origin") as? String, "custom")
    }

    func testSavingWritesOnlyChangedRecords() throws {
        let persistence = PersistenceController(inMemory: true)
        let repository = StateRepository(persistence: persistence)
        let first = Date(timeIntervalSince1970: 1_000), second = Date(timeIntervalSince1970: 2_000)
        var document = StateDocument.canonical(["unit": "kg", "restSec": 90,
            "workouts": [workout("w1", day: "2026-11-01", start: 1), workout("w2", day: "2026-11-02", start: 2)]])
        try repository.save(document, at: first)
        var workouts = document["workouts"] as! [[String: Any]]
        workouts[1]["note"] = "改过"; workouts.append(workout("w3", day: "2026-11-03", start: 3))
        document["workouts"] = Array(workouts.dropFirst()); document["restSec"] = 120
        try repository.save(StateDocument.canonical(document), at: second)

        let stamps = Dictionary(uniqueKeysWithValues: try objects("StoredWorkout", in: persistence).map { ($0.value(forKey: "id") as! String, $0.value(forKey: "updatedAt") as! Date) })
        XCTAssertEqual(stamps, ["w2": second, "w3": second])
        let settings = Dictionary(uniqueKeysWithValues: try objects("StoredSetting", in: persistence).map { ($0.value(forKey: "key") as! String, $0.value(forKey: "updatedAt") as! Date) })
        XCTAssertEqual(settings, ["unit": first, "restSec": second])
    }

    func testLoadingKeepsNewestOfDuplicateRecordsFromTwoDevices() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        for (name, date) in [("旧设备", 1.0), ("新设备", 2.0)] {
            let object = NSEntityDescription.insertNewObject(forEntityName: "StoredRoutine", into: context)
            object.setValue("r1", forKey: "id")
            object.setValue(try JSONSerialization.data(withJSONObject: ["id": "r1", "name": name]), forKey: "payload")
            object.setValue(Date(timeIntervalSince1970: date), forKey: "updatedAt")
        }
        try context.save()
        let loaded = try StateRepository(persistence: persistence).load()
        XCTAssertEqual((loaded["routines"] as? [[String: Any]])?.map { $0["name"] as? String }, ["新设备"])
        XCTAssertEqual(try objects("StoredRoutine", in: persistence).count, 1)
    }

    // MARK: - Store 读写

    func testMutationPersistsAndAnotherStoreReadsIt() async throws {
        let persistence = PersistenceController(inMemory: true)
        let first = store(persistence)
        try first.reloadDocument()
        let added = await first.addRoutine(name: "推", exerciseIDs: ["c-own"])
        XCTAssertTrue(added)
        let recorded = await first.mutate { source in var next = source; next["futureField"] = ["keep": true]; return next }
        XCTAssertTrue(recorded)

        let second = store(persistence)
        try second.reloadDocument()
        XCTAssertEqual(second.routines.map(\.name), ["推"])
        XCTAssertTrue(StateDocument.same(second.state["futureField"], ["keep": true]))
        XCTAssertTrue(StateDocument.same(second.state, first.state))
    }

    func testFailedOperationOrVerificationLeavesDocumentUntouched() async throws {
        let persistence = PersistenceController(inMemory: true)
        let s = store(persistence)
        try s.reloadDocument()
        let before = s.state
        let thrown = await s.mutate(reportError: false) { _ in throw APIError.response(0, "规则拒绝") }
        XCTAssertFalse(thrown)
        XCTAssertEqual(s.editError, "规则拒绝")
        let unverified = await s.mutate(reportError: false, verify: { _ in false }) { source in var next = source; next["unit"] = "lb"; return next }
        XCTAssertFalse(unverified)
        XCTAssertTrue(StateDocument.same(s.state, before))
        XCTAssertTrue(StateDocument.same(try StateRepository(persistence: persistence).load(), before))
    }

    // MARK: - 动作库副本

    func testUsingCatalogueExerciseCopiesItAndEditingReplacesTheCopy() async throws {
        let s = store()
        s.registerCatalogue([benchPress])
        try s.reloadDocument()
        XCTAssertNil(s.state[StateDocument.exerciseCopies])

        let added = await s.addRoutine(name: "推", exerciseIDs: ["0025", "c-own"])
        XCTAssertTrue(added)
        let copies = s.state[StateDocument.exerciseCopies] as? [[String: Any]]
        XCTAssertEqual(copies?.compactMap { $0["id"] as? String }, ["0025"])
        XCTAssertEqual(s.exercise("0025"), benchPress)
        XCTAssertEqual(s.exercises.map(\.id), ["0025"])

        // 编辑后成为同 ID 的自定义动作，副本不再保留；计划仍指向同一个动作。
        var edited = try s.editableRecord(for: benchPress)
        XCTAssertEqual(edited["id"] as? String, "0025")
        edited["n"] = "我的卧推"
        let saved = await s.savePersonalRecord(collection: "customEx", key: "id", original: nil, proposed: edited)
        XCTAssertTrue(saved, s.editError ?? "")
        XCTAssertNil(s.state[StateDocument.exerciseCopies])
        XCTAssertEqual(s.exercise("0025")?.name, "我的卧推")
        XCTAssertEqual(s.exercise("0025")?.english, "barbell bench press")
        XCTAssertEqual(s.exercises.map(\.id), ["0025"])
        XCTAssertEqual(s.imageMediaID("0025"), "0025")
    }

    func testCopiedExerciseStaysAvailableWhenCatalogueNoLongerHasIt() async throws {
        let persistence = PersistenceController(inMemory: true)
        let first = store(persistence)
        first.registerCatalogue([benchPress])
        try first.reloadDocument()
        let finished = await first.mutate { source in var next = source; next["workouts"] = [self.workout("w1", day: "2026-11-01", start: 1)]; return next }
        XCTAssertTrue(finished)

        let second = store(persistence)
        try second.reloadDocument()
        XCTAssertEqual(second.exercise("0025"), benchPress)
    }

    func testFreshInstallUsesLocalProfileAndEmptyDocument() {
        let s = store()
        s.userID = nil
        s.prepareOfflineLaunch()
        XCTAssertEqual(s.userID, LocalProfile.user)
        XCTAssertTrue(s.routines.isEmpty)
        XCTAssertNil(s.localSaveError)
    }
}
