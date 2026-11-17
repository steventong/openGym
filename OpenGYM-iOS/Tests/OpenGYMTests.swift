import CoreData
import XCTest
import Observation
@testable import OpenGYM

private final class ObservationChangeCount: @unchecked Sendable {
    private let lock = NSLock()
    private var changes = 0
    var value:Int { lock.withLock { changes } }
    func record() { lock.withLock { changes += 1 } }
}

extension PersistenceController {
    /// 测试用数据库：放在临时文件里，可以切换成只读，模拟“读得到、存不进去”，
    /// 用来验证保存失败时草稿和本机输入不丢。
    static func onDisk(in folder: URL) throws -> PersistenceController {
        let persistence = PersistenceController(inMemory: true)
        let coordinator = persistence.container.persistentStoreCoordinator
        for store in coordinator.persistentStores { try coordinator.remove(store) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try persistence.open(folder.appendingPathComponent("test.sqlite"), readOnly: false)
        return persistence
    }
    func setReadOnly(_ readOnly: Bool) throws {
        let coordinator = container.persistentStoreCoordinator
        guard let store = coordinator.persistentStores.first, let url = store.url else { throw CocoaError(.fileNoSuchFile) }
        try coordinator.remove(store)
        container.viewContext.reset()
        try open(url, readOnly: readOnly)
    }
    private func open(_ url: URL, readOnly: Bool) throws {
        _ = try container.persistentStoreCoordinator.addPersistentStore(type: .sqlite, at: url,
            options: [NSPersistentHistoryTrackingKey: true as NSNumber, NSReadOnlyPersistentStoreOption: readOnly as NSNumber])
    }
}

final class OpenGYMTests: XCTestCase {
    func testAddressRejectsCredentialAndInsecureRemoteURLs() throws {
        for url in ["http://example.com", "https://user:secret@example.com", "https://example.com?key=x", "file:///tmp/data"] { XCTAssertThrowsError(try ServerAddress(url)) }
        XCTAssertEqual(try ServerAddress("http://localhost:8080").endpoint("api/data").absoluteString,"http://localhost:8080/api/data")
        XCTAssertEqual(try ServerAddress("https://example.com/gym/").endpoint("api/data").absoluteString,"https://example.com/gym/api/data")
    }
    func testFinishedWorkoutMatchesServerShapeAndExcludesUnfinishedExercises() throws {
        let date = Date(timeIntervalSince1970:1_700_000_000)
        let draft = TrainingDraft(routineID:"r1",name:"test",start:date,entries:[TrainingEntry(id:"0150",name:"下拉",sets:[TrainingSet(weight:20,reps:10,done:true,completedAt:1_700_000_010_000)]),TrainingEntry(id:"0025",name:"卧推",sets:[TrainingSet()])],unit:"kg")
        let data = draft.workoutJSON(now:date.addingTimeInterval(60))
        XCTAssertEqual((data["entries"] as? [[String:Any]])?.count,1)
        XCTAssertEqual(data["routineIds"] as? [String],["r1"])
        XCTAssertEqual(number(data["end"]) - number(data["start"]),60_000)
        XCTAssertTrue(JSONSerialization.isValidJSONObject(data))
    }
    @MainActor func localStore(_ persistence: PersistenceController = PersistenceController(inMemory: true)) -> GymStore {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return GymStore(userID:"test",storage:LocalTrainingStorage(root:root),persistence:persistence)
    }
    func testForgottenSessionDoesNotCountHoursAwayOrDiscardLateLoggedSets() throws {
        let start = Date(timeIntervalSince1970:1_700_000_000)
        let startMS = start.timeIntervalSince1970 * 1000
        let draft = TrainingDraft(name:"test",start:start,entries:[TrainingEntry(id:"0150",name:"下拉",sets:[
            TrainingSet(done:true,completedAt:startMS + 60_000),
            TrainingSet(done:true,completedAt:startMS + 180_000),
            TrainingSet(done:true,completedAt:startMS + 3 * 3_600_000)
        ])],unit:"kg")
        let data = draft.workoutJSON(now:start.addingTimeInterval(6 * 3600))
        XCTAssertEqual(number(data["end"]) - number(data["start"]),180_000)
        let entries = data["entries"] as! [[String:Any]]
        XCTAssertEqual((entries[0]["sets"] as? [[String:Any]])?.count,3)
    }
    @MainActor func testSaveAfterAnotherDeviceChangeKeepsBothAndPreservesUnknownFields() async throws {
        let persistence = PersistenceController(inMemory: true)
        let store = localStore(persistence), other = localStore(persistence)
        let seeded = await store.mutate { _ in ["unit":"kg","routines":[],"workouts":[],"futureField":["keep":true],"_wid":"first"] }
        XCTAssertTrue(seeded)
        // 另一台设备加了计划；本机读到后再保存，两边的计划都在。
        try other.reloadDocument()
        let remote = await other.mutate { source in
            var next = source; next["routines"] = [["id":"web-added","name":"网页的新计划","ex":[]]]; next["_wid"] = "second"; return next
        }
        XCTAssertTrue(remote)
        try store.reloadDocument()
        let ok = await store.addRoutine(name:"native-added",exerciseIDs:["0150"])
        XCTAssertTrue(ok)
        try other.reloadDocument()
        XCTAssertEqual(other.routines.map(\.name),["网页的新计划","native-added"])
        XCTAssertEqual((other.state["futureField"] as? [String:Bool])?["keep"],true)
        XCTAssertEqual(other.state["_wid"] as? String,"second")
    }
    @MainActor func testFailedSaveKeepsCompletedDraft() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        let persistence = try PersistenceController.onDisk(in: folder)
        let store = localStore(persistence)
        store.state = ["unit":"kg","routines":[],"workouts":[]]
        store.draft = try TrainingDraft.fromWeb(["id":"unsaved","name":"offline","start":1_792_476_000_000.0,
            "entries":[["id":"0150","sets":[["w":20,"r":10,"done":true,"at":1_792_476_060_000.0]]]]],unit:"kg")
        try persistence.setReadOnly(true)
        await store.finish()
        XCTAssertEqual(store.draft?.id,"unsaved"); XCTAssertNotNil(store.error)
        XCTAssertTrue((store.state["workouts"] as? [[String:Any]] ?? []).isEmpty)
        // 数据库恢复后，同一份草稿可以保存。
        try persistence.setReadOnly(false)
        store.error = nil
        await store.finish()
        XCTAssertNil(store.draft); XCTAssertNil(store.error)
        XCTAssertEqual((store.state["workouts"] as? [[String:Any]])?.map { $0["id"] as? String },["unsaved"])
    }
    func testCatalogueLoadsAllOriginalIDs() throws {
        let bundle = Bundle(for:GymStore.self)
        let entries = try JSONDecoder().decode([Exercise].self,from:Data(contentsOf:bundle.url(forResource:"catalogue",withExtension:"json")!))
        XCTAssertEqual(entries.count,5632); XCTAssertEqual(Set(entries.map(\.id)).count,entries.count)
        XCTAssertEqual(entries.first { $0.id == "0150" }?.name,"绳索杠高位下拉")
    }

    @MainActor func testImportedHistoryResolvesGymSpecificNamesWithoutChangingRecords() throws {
        let store = GymStore()
        let bundle = Bundle(for: GymStore.self)
        let catalogue = try JSONDecoder().decode([Exercise].self, from: Data(contentsOf: bundle.url(forResource: "catalogue", withExtension: "json")!))
        let peakID = "cimp72bfd0875b9eaa5e62b1", dpcID = "cimp-bench-dpc"
        let peakName = "Dumbbell Bench Press（哑铃卧推） · Peak Fitness TRX"
        let dpcName = "Dumbbell Bench Press（哑铃卧推） · DPC Club Gym"
        let document: [String: Any] = [
            "customEx": [["id": peakID, "n": peakName, "bp": "chest", "eq": "dumbbell", "tg": "pectorals", "desc": "健身房：Peak Fitness TRX。"],
                         ["id": dpcID, "n": dpcName, "bp": "chest"]],
            "workouts": [["id": "imported", "entries": [["id": peakID, "sets": [["w": 15, "r": 12, "done": true]]], ["id": dpcID, "sets": []]]]],
            "futureField": ["keep": true]
        ]
        // Account data may arrive before the bundled catalogue.
        store.state = document
        store.registerCatalogue(catalogue)
        let history = try XCTUnwrap(store.workouts.first?["entries"] as? [[String: Any]])
        XCTAssertEqual(history.compactMap { store.exercise($0["id"] as! String)?.name }, [peakName, dpcName])
        XCTAssertEqual(history.enumerated().compactMap { index, entry in store.exercise(entry["id"] as! String)?.recordLabel(at: index) },
                       ["1.哑铃卧推(Dumbbell Bench Press)", "2.哑铃卧推(Dumbbell Bench Press)"])
        XCTAssertEqual(store.exercise(peakID)?.equipment, "dumbbell")
        XCTAssertEqual(store.exercise(peakID)?.description, "健身房：Peak Fitness TRX。")
        XCTAssertTrue(store.exercises.contains { $0.id == dpcID && $0.searchText.contains("DPC Club Gym") })
        XCTAssertEqual(store.exercises.count, catalogue.count + 2)
        XCTAssertEqual(store.exercise("0150")?.name, "绳索杠高位下拉")
        XCTAssertTrue(NSDictionary(dictionary: store.state).isEqual(to: document))
    }

    func testRecordLabelsPreserveVariantsAndNumberEachSessionIndependently() throws {
        let raw: [String: Any] = ["id": "cimp-example", "n": "Cable Triceps Pushdown (V-Bar)（绳索三头肌下压(V形把手)） · DPC Club Gym · 档位（非kg）"]
        let imported = try XCTUnwrap(Exercise.custom(raw))
        XCTAssertEqual(imported.recordLabel(at: 0), "1.绳索三头肌下压(V形把手)(Cable Triceps Pushdown (V-Bar))")
        XCTAssertEqual(imported.recordLabel(at: 3), "4.绳索三头肌下压(V形把手)(Cable Triceps Pushdown (V-Bar))")
        XCTAssertEqual(imported.recordLabel(at: 0), "1.绳索三头肌下压(V形把手)(Cable Triceps Pushdown (V-Bar))")
        let builtIn = Exercise(id: "0289", name: "哑铃卧推", english: "dumbbell bench press", bodyPart: "chest", equipment: "dumbbell", target: "pectorals", category: "strength", instructions: [], description: "")
        XCTAssertEqual(imported.titleParts.primary, "绳索三头肌下压(V形把手)")
        XCTAssertEqual(imported.titleParts.secondary, "Cable Triceps Pushdown (V-Bar)")
        XCTAssertEqual(imported.clipboardName, "绳索三头肌下压(V形把手)（Cable Triceps Pushdown (V-Bar)）")
        XCTAssertEqual(builtIn.titleParts.primary, "哑铃卧推")
        XCTAssertEqual(builtIn.titleParts.secondary, "dumbbell bench press")
        XCTAssertEqual(builtIn.clipboardName, "哑铃卧推（dumbbell bench press）")
        XCTAssertEqual(builtIn.recordLabel(at: 1), "2.哑铃卧推(dumbbell bench press)")
        XCTAssertEqual(Exercise.custom(["id": "custom", "n": "我的动作 · 慢速"] )?.recordName, "我的动作 · 慢速")
        XCTAssertEqual(Exercise.custom(["id": "cimp-example", "n": "哑铃卧推(Dumbbell Bench Press)"] )?.recordName, "哑铃卧推(Dumbbell Bench Press)")
    }

    @MainActor func testSyncedCustomRenameDeletionAndAccountSwitchReplaceCachedNames() throws {
        let store = GymStore()
        let builtIn = Exercise(id: "0289", name: "哑铃卧推", english: "dumbbell bench press", bodyPart: "chest", equipment: "dumbbell", target: "pectorals", category: "strength", instructions: [], description: "")
        store.registerCatalogue([builtIn])
        store.state = ["customEx": [["id": "cimp-history", "n": "原名称"], ["id": "0289", "n": "自定义覆盖名称"]]]
        XCTAssertEqual(store.exercise("cimp-history")?.name, "原名称")
        XCTAssertEqual(store.exercise("0289")?.name, "自定义覆盖名称")
        store.state["customEx"] = [["id": "cimp-history", "n": "修正后的名称"]]
        XCTAssertEqual(store.exercise("cimp-history")?.name, "修正后的名称")
        XCTAssertEqual(store.exercise("0289")?.name, "哑铃卧推")
        store.state = [:]
        XCTAssertNil(store.exercise("cimp-history"))
        XCTAssertEqual(store.exercises, [builtIn])
    }

    @MainActor func testCustomCatalogueSkipsInvalidRowsAndHandlesDuplicateIDs() {
        let store = GymStore()
        store.state = ["customEx": [NSNull(), ["id": "", "n": "无编号"], ["id": "invalid", "n": " "],
                                   ["id": "cimp-valid", "n": "旧名称"], ["id": "cimp-valid", "n": "最终名称"]] as [Any]]
        XCTAssertEqual(store.exercises.count, 1)
        XCTAssertEqual(store.exercise("cimp-valid")?.name, "最终名称")
        XCTAssertNil(store.exercise("invalid"))
    }

    @MainActor func testUnrelatedSyncDoesNotInvalidateExerciseViews() throws {
        let store = GymStore()
        let exercise = try XCTUnwrap(Exercise.custom(["id":"builtin","n":"测试动作"]))
        store.registerCatalogue([exercise])
        store.state = ["customEx":[["id":"custom","n":"自定义动作","_ts":1]]]
        let invalidated = ObservationChangeCount()
        withObservationTracking {
            _ = store.exercises
            _ = store.exercise("custom")
        } onChange: { invalidated.record() }
        store.state["workouts"] = [["id":"new-workout"]]
        store.state["bodyweight"] = [["d":"2026-11-02","w":70]]
        store.state["customEx"] = [["id":"custom","n":"自定义动作","_ts":2]]
        store.registerCatalogue([exercise])
        XCTAssertEqual(invalidated.value,0)
        XCTAssertEqual(store.exercise("custom")?.name,"自定义动作")
    }

    @MainActor func testUnchangedSaveAndRefreshDoNotInvalidateMenuDependencies() async throws {
        let store = localStore()
        let seeded = await store.mutate { _ in ["unit": "kg", "bodyweight": [], "workouts": []] }
        XCTAssertTrue(seeded)
        let changes = ObservationChangeCount()
        withObservationTracking {
            _ = store.profileIdentity; _ = store.localSaveError; _ = store.syncing
            _ = store.state; _ = store.draft
        } onChange: { changes.record() }
        await store.refresh()
        // 健康体重等后台同步经常保存一份没有变化的资料。
        let saved = await store.mutate(reportError: false) { source in source }
        XCTAssertTrue(saved)
        XCTAssertEqual(changes.value, 0)
        XCTAssertFalse(store.syncing)
    }

    @MainActor func testIdenticalRefreshDoesNotInvalidateStateButNewStampsDo() async throws {
        let persistence = PersistenceController(inMemory: true)
        let store = localStore(persistence), other = localStore(persistence)
        let seeded = await other.mutate { _ in ["unit":"kg","_ts":1,"_wid":"first","workouts":[]] }
        XCTAssertTrue(seeded)
        try store.reloadDocument()
        let loaded = try XCTUnwrap(store.lastDocumentChange)
        let changes = ObservationChangeCount()
        withObservationTracking { _ = store.state } onChange: { changes.record() }
        await store.refresh()
        XCTAssertEqual(changes.value,0)
        XCTAssertEqual(store.lastDocumentChange,loaded)

        // 另一台设备只改了同步标记，也要读进来。
        let stamped = await other.mutate { source in var next = source; next["_ts"] = 2; next["_wid"] = "second"; return next }
        XCTAssertTrue(stamped)
        await store.refresh()
        XCTAssertEqual(changes.value,1)
        XCTAssertEqual(store.state["_wid"] as? String,"second")
        XCTAssertGreaterThan(try XCTUnwrap(store.lastDocumentChange),loaded)
    }
}
