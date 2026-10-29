import XCTest
@testable import OpenGym

final class OfflineTrainingTests: XCTestCase {
    var root: URL!
    override func setUpWithError() throws { root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true) }
    override func tearDownWithError() throws { StubProtocol.handler = nil; try? FileManager.default.removeItem(at:root) }
    @MainActor private func store() throws -> GymStore {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [StubProtocol.self]
        let api = APIClient(address:try ServerAddress("https://test.invalid"),token:"test",session:URLSession(configuration:config))
        let store = GymStore(client:api,userID:"offline-test",storage:LocalTrainingStorage(root:root))
        store.serverURL = "https://test.invalid"; store.userName = "Offline test"; return store
    }
    private func body(_ request: URLRequest) throws -> [String:Any] {
        if let data = request.httpBody { return try JSONSerialization.jsonObject(with:data) as! [String:Any] }
        let stream = try XCTUnwrap(request.httpBodyStream); stream.open(); defer { stream.close() }
        var data = Data(), buffer = [UInt8](repeating:0,count:8192)
        while stream.hasBytesAvailable { let n = stream.read(&buffer,maxLength:buffer.count); if n <= 0 {break}; data.append(buffer,count:n) }
        return try JSONSerialization.jsonObject(with:data) as! [String:Any]
    }
    private func workout() -> [String:Any] {
        ["id":"w1","name":"原训练","d":"2026-10-20","start":1_792_476_000_000.0,"end":1_792_476_060_000.0,
         "entries":[["id":"0289","target":["mode":"reps"],"sets":[["w":15,"r":10,"done":true]]]],"prs":[],"future":"keep"]
    }
    @MainActor func testFreestyleStartsWithoutPlansAndRestoresEmptyDraft() throws {
        let first = try store()
        first.state = ["unit": "lb", "routines": [], "bodyweight": [["w": 150]]]
        first.startFreestyle()
        let draft = try XCTUnwrap(first.draft)
        XCTAssertEqual(draft.name, "自由训练"); XCTAssertEqual(draft.unit, "lb")
        XCTAssertTrue(draft.rawEntries.isEmpty); XCTAssertNil(draft.routineID)
        XCTAssertEqual(draft.routineIDs, []); XCTAssertEqual(first.selectedTab, 2)
        XCTAssertEqual(number(draft.activeJSON["bw"]), 150)
        let restored = try store(); restored.restoreDraft()
        XCTAssertEqual(restored.draft?.id, draft.id)
        XCTAssertTrue(RecordPatch.equal(restored.draft?.activeJSON, draft.activeJSON))
    }
    @MainActor func testFreestyleRequiresAccountAndResumesExistingPlan() throws {
        let s = try store(); s.userName = nil
        s.startFreestyle()
        XCTAssertNil(s.draft); XCTAssertTrue(s.showSettings)
        s.userName = "Test"; s.showSettings = false
        s.state = ["routines": [["id": "plan", "name": "原计划", "ex": [["id": "0289", "sets": 1, "reps": 8, "weight": 20]]]]]
        s.start(s.routines[0])
        let existing = try XCTUnwrap(s.draft)
        XCTAssertEqual(existing.routineID, "plan")
        s.selectedTab = 0; s.startFreestyle()
        XCTAssertTrue(RecordPatch.equal(s.draft?.activeJSON, existing.activeJSON))
        XCTAssertEqual(s.selectedTab, 2)
    }
    @MainActor func testFreestyleAddsExerciseAndSavesWithoutCreditingPlan() async throws {
        let s = try store()
        var server: [String: Any] = ["unit": "kg", "routines": [["id": "plan", "name": "计划", "ex": []]],
            "workouts": [], "week": ["4": ["plan"]], "dayPlan": [dayString(): ["plan"]],
            "rotation": ["id": "rotation", "sequence": ["plan"]], "scheduleMode": "rotation",
            "queue": ["ids": ["plan"], "rotationId": "rotation", "startsOn": dayString(), "since": 0]]
        let original = server
        s.state = server; s.startFreestyle()
        let id = try XCTUnwrap(s.draft?.id)
        s.manageLiveExercise(action: "add", index: 0, id: "0289")
        XCTAssertEqual(s.draft?.rawEntries.count, 1)
        XCTAssertNil(s.draft?.rawEntries.first?["rid"])
        s.liveRowAction(entry: 0, set: 0, action: ["action": "field", "key": "w", "value": 20])
        s.liveRowAction(entry: 0, set: 0, action: ["action": "field", "key": "r", "value": 8])
        s.liveRowAction(entry: 0, set: 0, action: ["action": "toggle"])
        XCTAssertEqual(s.draft?.completedSets, 1)
        StubProtocol.handler = { request in
            if request.httpMethod == "GET" { return (200, ["state": server, "rev": 1]) }
            server = try self.body(request)["state"] as! [String: Any]
            return (200, ["ok": true])
        }
        await s.finish()
        XCTAssertNil(s.draft); XCTAssertNil(s.error)
        let saved = try XCTUnwrap((server["workouts"] as? [[String: Any]])?.first)
        XCTAssertEqual(saved["id"] as? String, id); XCTAssertEqual(saved["name"] as? String, "自由训练")
        XCTAssertEqual(saved["routineIds"] as? [String], []); XCTAssertTrue(saved["routineId"] is NSNull)
        XCTAssertEqual(number(saved["vol"]), 160)
        for key in ["routines", "week", "dayPlan", "rotation", "queue"] {
            XCTAssertTrue(RecordPatch.equal(server[key], original[key]), key)
        }
        let restored = try store(); restored.restoreDraft()
        XCTAssertNil(restored.draft)
    }
    @MainActor func testColdOfflineRestartRestoresAccountProfileLiveInputAndHistoryForm() throws {
        let first = try store(), original = workout()
        first.state = ["unit":"kg","workouts":[original],"routines":[]];first.cacheProfile()
        var form = HistoryForm(original:original,unit:"kg");form.name = "未提交的名称 ";form.minutes = "12.";form.note = "还没输入完的备注"
        form.entries[0].sets[0].raw[TrainingInput.key] = ["both.w":""]
        XCTAssertTrue(first.keepHistoryEdit(original:original,proposed:form.proposed,unit:"kg",form:form.fields))
        first.draft = try TrainingDraft.fromWeb(["id":"active","name":"训练中","start":1_792_476_000_000.0,"entries":[["id":"0289","sets":[["w":12,"r":10,"done":false,TrainingInput.key:["both.w":"12."]]]]]],unit:"kg")
        first.startRest(entry:0,seconds:90)
        let second = try store();second.userID = nil;second.userName = nil;second.restoreOfflineAccount()
        XCTAssertEqual(second.userName,"Offline test");XCTAssertEqual(second.workouts.count,1)
        let restored = HistoryForm(original:original,unit:"kg",saved:second.historyEdits["w1"])
        XCTAssertEqual(restored.name,"未提交的名称 ");XCTAssertEqual(restored.minutes,"12.");XCTAssertEqual(restored.note,form.note)
        XCTAssertEqual((restored.entries[0].sets[0].raw[TrainingInput.key] as? [String:String])?["both.w"],"")
        XCTAssertEqual(second.draft?.id,"active");XCTAssertEqual(second.restEntry,0);XCTAssertNotNil(second.restUntil)
        XCTAssertEqual(((second.draft?.rawEntries[0]["sets"] as? [[String:Any]])?[0][TrainingInput.key] as? [String:String])?["both.w"],"12.")
        XCTAssertTrue(RecordPatch.equal((second.state["workouts"] as? [[String:Any]])?[0],original))
    }
    @MainActor func testDeleteCurrentWorkoutClearsTimersAndSurvivesRestart() throws {
        let s = try store()
        let state: [String: Any] = ["workouts": [workout()], "routines": [["id": "routine"]]]
        s.state = state
        s.draft = try TrainingDraft.fromWeb(["id": "delete-current", "start": 1000,
            "nativeTimer": ["entry": 0, "set": 0, "end": 9999999999.0],
            "nativeRest": ["entry": 0, "end": 9999999999.0],
            "entries": [["id": "0289", "sets": [["w": 25, "r": 15, "done": true]]]]], unit: "kg")
        s.deleteCurrentWorkout()
        XCTAssertNil(s.draft); XCTAssertNil(s.workTimer); XCTAssertNil(s.restUntil)
        XCTAssertTrue(RecordPatch.equal(s.state, state))
        let restarted = try store(); restarted.restoreDraft()
        XCTAssertNil(restarted.draft)
        // Recovery from the previous copy must also keep the deleted workout gone.
        let url = try XCTUnwrap(s.accountFolder).appendingPathComponent("live-draft.json")
        try Data("damaged".utf8).write(to: url)
        let recovered = try store(); recovered.restoreDraft()
        XCTAssertNil(recovered.draft)
    }
    @MainActor func testDeleteCurrentWorkoutRetainsDraftWhenDiskWriteFails() throws {
        let s = try store()
        s.draft = try TrainingDraft.fromWeb(["id": "keep-current", "start": 1000, "entries": []], unit: "kg")
        let folder = try XCTUnwrap(s.accountFolder)
        try FileManager.default.removeItem(at: folder)
        try Data([1]).write(to: folder)
        s.deleteCurrentWorkout()
        XCTAssertEqual(s.draft?.id, "keep-current"); XCTAssertNotNil(s.error)
    }
    @MainActor func testDeleteCurrentWorkoutIsBlockedDuringSubmission() throws {
        let s = try store()
        s.draft = try TrainingDraft.fromWeb(["id": "submitting", "start": 1000, "entries": []], unit: "kg")
        s.syncing = true; s.deleteCurrentWorkout()
        XCTAssertEqual(s.draft?.id, "submitting")
        let restarted = try store(); restarted.restoreDraft()
        XCTAssertEqual(restarted.draft?.id, "submitting")
    }
    func testAtomicStorageRecoveryAndAccountIsolation() throws {
        let storage = LocalTrainingStorage(root:root)
        let file = storage.folder(server:"https://one",user:"a").appendingPathComponent("doc.json")
        try storage.write(["text":"first"],to:file);try storage.write(["text":"second"],to:file)
        try Data("damaged".utf8).write(to:file)
        XCTAssertEqual(try storage.read(file)?["text"] as? String,"first")
        XCTAssertNil(try storage.read(storage.folder(server:"https://two",user:"a").appendingPathComponent("doc.json")))
        XCTAssertNotEqual(storage.folder(server:"https://one",user:"a"),storage.folder(server:"https://one",user:"b"))
    }
    @MainActor func testFailedDiskWritePreventsSubmissionAndKeepsInputInMemory() async throws {
        let blocked = root.appendingPathComponent("not-a-folder");try Data([1]).write(to:blocked)
        let s = GymStore(userID:"test",storage:LocalTrainingStorage(root:blocked))
        var edited = workout();edited["name"] = "不要丢失"
        let ok = await s.saveWorkout(original:workout(),proposed:edited,expectedUnit:"kg")
        XCTAssertFalse(ok);XCTAssertNotNil(s.localSaveError)
        XCTAssertEqual((s.historyEdits["w1"]?["proposed"] as? [String:Any])?["name"] as? String,"不要丢失")
    }
    @MainActor func testServerDownRetainsDraftAndRepeatSubmitAfterRestartDoesNotDuplicate() async throws {
        let first = try store();var edited = workout();edited["note"] = "离线写入"
        StubProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        let failed = await first.saveWorkout(original:workout(),proposed:edited,expectedUnit:"kg")
        XCTAssertFalse(failed);XCTAssertEqual(first.historyEdits["w1"]?["submitted"] as? Bool,true)
        let second = try store();second.restoreLocalTraining()
        var server:[String:Any] = ["unit":"kg","workouts":[workout()],"routines":[],"futureServer":"keep"]
        var writes = 0
        StubProtocol.handler = { request in
            if request.httpMethod == "GET" { return (200,["state":server,"rev":1]) }
            server = try self.body(request)["state"] as! [String:Any];writes += 1;return (200,["ok":true])
        }
        let ok = await second.submitHistoryEdit("w1")
        XCTAssertTrue(ok);XCTAssertEqual(writes,1);XCTAssertNil(second.historyEdits["w1"])
        XCTAssertEqual((server["workouts"] as? [[String:Any]])?.count,1)
        XCTAssertEqual((server["workouts"] as? [[String:Any]])?[0]["note"] as? String,"离线写入")
        XCTAssertEqual(server["futureServer"] as? String,"keep")
    }
    @MainActor func testLostPutResponseRetriesRecomputedHistoryWithoutSecondWrite() async throws {
        let s = try store(), old = workout();var changed = old
        changed["entries"] = [["id":"0289","target":["mode":"reps"],"sets":[["w":20,"r":12,"done":true,TrainingInput.key:["both.w":"20."]]]]]
        var server:[String:Any] = ["unit":"kg","workouts":[old],"routines":[],"exWeights":[:]],writes = 0
        StubProtocol.handler = { request in
            if request.httpMethod == "GET" {return (200,["state":server,"rev":writes+1])}
            server = try self.body(request)["state"] as! [String:Any];writes += 1;throw URLError(.networkConnectionLost)
        }
        let failed = await s.saveWorkout(original:old,proposed:changed,expectedUnit:"kg")
        XCTAssertFalse(failed);XCTAssertEqual(writes,1)
        let restarted = try store();restarted.restoreLocalTraining()
        let retried = await restarted.submitHistoryEdit("w1")
        XCTAssertTrue(retried);XCTAssertEqual(writes,1);XCTAssertNil(restarted.historyEdits["w1"])
        let saved = (server["workouts"] as! [[String:Any]])[0]
        XCTAssertEqual(number(saved["vol"]),240)
        XCTAssertNil(((saved["entries"] as! [[String:Any]])[0]["sets"] as! [[String:Any]])[0][TrainingInput.key])
    }
    @MainActor func testConcurrentServerEditKeepsLocalInputAndDoesNotOverwriteRemote() async throws {
        let s = try store(), old = workout();var edited = old;edited["name"] = "本机名称"
        var remote = old;remote["name"] = "远端名称"
        StubProtocol.handler = { request in XCTAssertEqual(request.httpMethod,"GET");return (200,["state":["unit":"kg","workouts":[remote]],"rev":2]) }
        let ok = await s.saveWorkout(original:old,proposed:edited,expectedUnit:"kg")
        XCTAssertFalse(ok);XCTAssertEqual((s.historyEdits["w1"]?["proposed"] as? [String:Any])?["name"] as? String,"本机名称")
    }
    @MainActor func testLiteralNumericInputSurvivesInvalidValuesAndNeverSubmitsStaleNumber() throws {
        let row:[String:Any] = ["w":10,"r":8,"done":false]
        let blank = try TrainingInput.edit(row:row,action:["action":"input","path":"both.w","text":"","operation":["action":"field","key":"w"]],target:[:],state:[:],editing:false)
        XCTAssertEqual(number(blank["w"]),10);XCTAssertThrowsError(try TrainingInput.validate(blank))
        XCTAssertThrowsError(try TrainingInput.edit(row:blank,action:["action":"toggle"],target:[:],state:[:],editing:false))
        let filled = try TrainingInput.edit(row:blank,action:["action":"input","path":"both.w","text":"12,5","operation":["action":"field","key":"w"]],target:[:],state:[:],editing:false)
        XCTAssertEqual(number(filled["w"]),12.5);XCTAssertNoThrow(try TrainingInput.validate(filled))
        XCTAssertEqual(TrainingInput.display(filled,path:"both.w",number:12.5),"12,5")
    }
    @MainActor func testRestTimerStaysWithCompletedCardAndPersistsSelection() throws {
        let s = try store();s.state = ["restSec":90]
        s.draft = try TrainingDraft.fromWeb(["id":"rest","name":"test","start":1000,"cur":0,"entries":[
            ["id":"0289","target":["restSec":90],"sets":[["w":10,"r":8,"done":false],["w":10,"r":8,"done":false]]],
            ["id":"1047","sets":[["w":20,"r":8,"done":false]]]]],unit:"kg")
        s.liveRowAction(entry:0,set:0,action:["action":"toggle"])
        XCTAssertEqual(s.restEntry,0);XCTAssertNotNil(s.restUntil)
        s.selectLiveEntry(1);XCTAssertEqual(s.draft?.activeJSON["cur"] as? Int,1);XCTAssertEqual(s.restEntry,0)
        let recovered = try store();recovered.restoreDraft();XCTAssertEqual(recovered.draft?.activeJSON["cur"] as? Int,1);XCTAssertEqual(recovered.restEntry,0)
    }
    @MainActor func testRemovingLiveSetsPreservesRemainingInputAndRestoresEmptyDraft() throws {
        let s = try store()
        let retained: [String: Any] = ["w": 25, "r": 8, "done": false, TrainingInput.key: ["both.w": "25."]]
        s.draft = try TrainingDraft.fromWeb(["id": "delete-sets", "start": 1000, "cur": 0, "nativeFinishAt": 2000,
            "entries": [["id": "0289", "target": ["mode": "reps"], "sets": [["w": 10, "r": 8, "done": true], retained]]]], unit: "kg")
        s.removeLiveSet(entry: 0, set: 0)
        XCTAssertTrue(RecordPatch.equal(s.draft?.rawEntries[0]["sets"], [retained]))
        XCTAssertNil(s.draft?.activeJSON["nativeFinishAt"])
        let restored = try store(); restored.restoreDraft()
        XCTAssertTrue(RecordPatch.equal(restored.draft?.rawEntries[0]["sets"], [retained]))
        restored.removeLiveSet(entry: 0, set: 0)
        XCTAssertEqual((restored.draft?.rawEntries[0]["sets"] as? [[String: Any]])?.count, 0)
        restored.addLiveSet(entry: 0)
        let rows = try XCTUnwrap(restored.draft?.rawEntries[0]["sets"] as? [[String: Any]])
        XCTAssertEqual(rows.count, 1); XCTAssertEqual(rows[0]["done"] as? Bool, false)
    }
    @MainActor func testRemovingTimedPairShiftsTimerAndCancelsOnlyItsOwner() throws {
        let s = try store()
        let rows: [[String: Any]] = ["L", "R", "L", "R"].map { ["side": $0, "sec": 30, "mode": "time", "done": false] }
        s.draft = try TrainingDraft.fromWeb(["id": "timer-delete", "start": 1000,
            "entries": [["id": "0289", "sets": rows], ["id": "1047", "sets": [["r": 8, "done": false]]]]], unit: "kg")
        s.startWorkTimer(entry: 0, set: 3); s.pauseWorkTimer()
        s.removeLiveSet(entry: 1, set: 0)
        XCTAssertEqual(s.workTimer?["set"] as? Int, 3)
        s.removeLiveSet(entry: 0, set: 0)
        XCTAssertEqual((s.draft?.rawEntries[0]["sets"] as? [[String: Any]])?.count, 2)
        XCTAssertEqual(s.workTimer?["set"] as? Int, 1)
        XCTAssertEqual(s.workTimer?["paused"] as? Bool, true)
        let restored = try store(); restored.restoreDraft()
        XCTAssertEqual(restored.workTimer?["set"] as? Int, 1)
        restored.removeLiveSet(entry: 0, set: 1)
        XCTAssertNil(restored.workTimer); restored.settleTimer()
        XCTAssertEqual((restored.draft?.rawEntries[0]["sets"] as? [[String: Any]])?.count, 0)
    }
    @MainActor func testRemovingSetAdjustsRestOwnerAndAllowsNewCompletionRest() throws {
        let s = try store(); s.state = ["restSec": 90]
        let rows: [[String: Any]] = [["r": 8, "done": true], ["r": 8, "done": true], ["r": 8, "done": false]]
        s.draft = try TrainingDraft.fromWeb(["id": "rest-delete", "start": 1000, "nativeHighWater": ["0": 2],
            "entries": [["id": "0289", "sets": rows], ["id": "1047", "sets": [["r": 8, "done": false]]]]], unit: "kg")
        s.startRest(entry: 0, seconds: 90, set: 1)
        s.removeLiveSet(entry: 0, set: 0)
        XCTAssertEqual((s.draft?.activeJSON["nativeRest"] as? [String: Any])?["set"] as? Int, 0)
        s.removeLiveSet(entry: 0, set: 0)
        XCTAssertNil(s.restUntil)
        s.liveRowAction(entry: 0, set: 0, action: ["action": "toggle"])
        XCTAssertEqual(s.restEntry, 0); XCTAssertNotNil(s.restUntil)
    }
    @MainActor func testHistoryAndLiveUseSameSetShapeAndPairedRemoval() throws {
        let sets: [[String: Any]] = ["L", "R"].map { ["side": $0, "sec": 30, "mode": "time", "done": true, TrainingInput.key: ["both.sec": "30."]] }
        var entry = HistoryEntryDraft(["id": "0289", "target": ["mode": "time", "sec": 30, "side": true], "sets": sets])
        let originalIDs = entry.sets.map(\.id)
        try entry.addSet()
        XCTAssertEqual(entry.sets.count, 4)
        XCTAssertEqual(Array(entry.sets.prefix(2)).map(\.id), originalIDs)
        XCTAssertEqual(entry.sets.map { $0.raw["side"] as? String }, ["L", "R", "L", "R"])
        XCTAssertTrue(entry.sets.allSatisfy { $0.raw["done"] as? Bool == true })
        XCTAssertNil(entry.sets[2].raw[TrainingInput.key]); XCTAssertNotNil(entry.sets[0].raw[TrainingInput.key])
        try entry.removeSet(id: entry.sets[3].id)
        XCTAssertEqual(entry.sets.map(\.id), originalIDs)
        try entry.removeSet(id: entry.sets[0].id)
        XCTAssertTrue(entry.sets.isEmpty)
        try entry.addSet()
        XCTAssertEqual(entry.sets.count, 2)
        XCTAssertEqual(entry.sets.map { $0.raw["side"] as? String }, ["L", "R"])
        XCTAssertEqual(entry.sets[0].raw["mode"] as? String, "time")
        XCTAssertEqual(number(entry.sets[0].raw["sec"]), 30)
        let s = try store()
        s.draft = try TrainingDraft.fromWeb(["id": "copy", "start": 1000, "entries": [["id": "0289", "sets": sets]]], unit: "kg")
        s.addLiveSet(entry: 0)
        let liveRows = try XCTUnwrap(s.draft?.rawEntries[0]["sets"] as? [[String: Any]])
        XCTAssertEqual(liveRows.count, 4)
        XCTAssertTrue(liveRows.suffix(2).allSatisfy { $0["done"] as? Bool == false })
        XCTAssertNil(liveRows[2][TrainingInput.key])
    }
    @MainActor func testPreviousExerciseUsesExactGymIDAndOnlyEarlierCompletedWork() throws {
        let s = try store()
        let custom:[String:Any] = ["id":"gym-a","n":"Bench · Gym A","eq":"dumbbell","bp":"chest"]
        s.state = ["unit":"kg","customEx":[custom],"workouts":[
            ["id":"a","d":"2026-10-20","start":1000,"entries":[["id":"gym-a","sets":[["w":15,"r":12,"done":true],["w":30,"r":99,"done":false]]]]],
            ["id":"b","d":"2026-10-21","start":2000,"entries":[["id":"gym-b","sets":[["w":90,"r":4,"done":true]]]]]]]
        let text = s.previousExerciseText(["id":"gym-a"],before:3000,exclude:"new")
        XCTAssertTrue(text.contains("2026-10-20"));XCTAssertTrue(text.contains("15"));XCTAssertFalse(text.contains("90"));XCTAssertFalse(text.contains("99"))
    }
    func testHealthWeightLatestPerDayConversionManualProtectionAndIdempotence() {
        let samples:[String:[String:Any]] = ["old":["kg":70,"time":1000,"day":"2026-10-20"],"new":["kg":71,"time":2000,"day":"2026-10-20"],"manual":["kg":80,"time":3000,"day":"2026-10-21"]]
        let state:[String:Any] = ["unit":"lb","bodyweight":[["d":"2026-10-21","w":150,"t":900]],"workouts":[["id":"keep"]]]
        let result = HealthWeightMerge.merge(state,samples:samples,deleted:[])
        let weights = result["bodyweight"] as! [[String:Any]]
        XCTAssertEqual(weights.count,2);XCTAssertEqual(number(weights[0]["w"]),156.528,accuracy:0.001);XCTAssertEqual(number(weights[1]["w"]),150)
        XCTAssertTrue(RecordPatch.equal(result,HealthWeightMerge.merge(result,samples:samples,deleted:[])))
        var overridden = result;var changed = weights;changed[0]["w"] = 160;overridden["bodyweight"] = changed
        XCTAssertTrue(RecordPatch.equal(overridden,HealthWeightMerge.merge(overridden,samples:samples,deleted:["new"])))
        let removed = HealthWeightMerge.merge(result,samples:[:],deleted:["new"])
        XCTAssertEqual((removed["bodyweight"] as? [[String:Any]])?.count,1)
        XCTAssertTrue(RecordPatch.equal(result,HealthWeightMerge.merge(result,samples:[:],deleted:[])),"No readable HealthKit samples must not erase stored data")
    }
    @MainActor func testLiveFinishLostResponseRestartsAndRetriesWithSameIDAndEndTime() async throws {
        let first = try store()
        first.draft = try TrainingDraft.fromWeb(["id":"finished-offline","name":"测试训练","d":"2026-10-20","start":1_792_476_000_000.0,"entries":[["id":"0289","target":["mode":"reps"],"sets":[["w":15,"r":10,"done":true,"at":1_792_476_060_000.0]]]]],unit:"kg")
        var server:[String:Any] = ["unit":"kg","workouts":[],"routines":[],"exWeights":[:]], writes = 0
        StubProtocol.handler = { request in
            if request.httpMethod == "GET" { return (200,["state":server,"rev":writes+1]) }
            server = try self.body(request)["state"] as! [String:Any];writes += 1;throw URLError(.networkConnectionLost)
        }
        await first.finish();XCTAssertNotNil(first.draft);XCTAssertEqual(writes,1)
        let second = try store();second.restoreDraft();XCTAssertEqual(second.draft?.id,"finished-offline")
        await second.finish();XCTAssertNil(second.draft);XCTAssertEqual(writes,1)
        XCTAssertEqual((server["workouts"] as? [[String:Any]])?.count,1)
    }
    @MainActor func testNewInputAfterLostResponseCanBeSubmittedWithoutLosingEitherVersion() async throws {
        let s = try store(), old = workout();var changed = old;changed["name"] = "第一次修改"
        var server:[String:Any] = ["unit":"kg","workouts":[old],"routines":[]],writes = 0
        StubProtocol.handler = { request in
            if request.httpMethod == "GET" { return (200,["state":server,"rev":writes+1]) }
            server = try self.body(request)["state"] as! [String:Any];writes += 1
            if writes == 1 { throw URLError(.networkConnectionLost) };return (200,["ok":true])
        }
        let failed = await s.saveWorkout(original:old,proposed:changed,expectedUnit:"kg");XCTAssertFalse(failed)
        changed["name"] = "继续编辑后的最新内容"
        let saved = await s.saveWorkout(original:old,proposed:changed,expectedUnit:"kg")
        XCTAssertTrue(saved);XCTAssertEqual(writes,2)
        XCTAssertEqual((server["workouts"] as? [[String:Any]])?[0]["name"] as? String,"继续编辑后的最新内容")
    }
    @MainActor func testIncompleteDurationCannotBeRetriedFromPendingList() async throws {
        let s = try store(), old = workout();var edited = old;edited["name"] = "保留"
        XCTAssertTrue(s.keepHistoryEdit(original:old,proposed:edited,unit:"kg",form:["minutes":""],submit:true))
        StubProtocol.handler = { _ in XCTFail("Incomplete input must never be sent");throw URLError(.cancelled) }
        let saved = await s.submitHistoryEdit("w1");XCTAssertFalse(saved);XCTAssertNotNil(s.historyEdits["w1"])
    }
    @MainActor func testEquipmentWeightUnitRoundTripsWithoutChangingStoredLoad() throws {
        let original: [String: Any] = ["w": 20, "r": 8, "done": true, TrainingInput.key: ["both.w": "20.", "both.r": "8"]]
        var row = original
        for _ in 0..<20 {
            row = try TrainingInput.edit(row: row, action: ["action": "weightUnit", "unit": "lb"], target: [:], state: ["unit": "kg"], editing: false)
            XCTAssertEqual(TrainingInput.weightDisplay(row, path: "both.w", value: number(row["w"]), storedUnit: "kg"), "44.09")
            row = try TrainingInput.edit(row: row, action: ["action": "weightUnit", "unit": "kg"], target: [:], state: ["unit": "kg"], editing: false)
        }
        XCTAssertEqual(number(row["w"]), 20)
        XCTAssertEqual(row["done"] as? Bool, true)
        XCTAssertEqual((row[TrainingInput.key] as? [String: String])?["both.r"], "8")
        let blank = ["w": 20, TrainingInput.key: ["both.w": ""]] as [String: Any]
        XCTAssertThrowsError(try TrainingInput.edit(row: blank, action: ["action": "weightUnit", "unit": "lb"], target: [:], state: [:], editing: false))
    }

    @MainActor func testMixedEquipmentUnitsSaveCorrectVolumeAndRestoreSelection() throws {
        let s = try store()
        s.state = ["unit": "kg", "workouts": [], "routines": []]
        let active: [String: Any] = ["id": "units", "name": "不同器械", "d": "2026-10-29", "start": 1000,
            "entries": [["id": "0025", "sets": [["w": 20, "r": 10, "done": true]]],
                        ["id": "0025", "sets": [["w": 20, "r": 10, "done": true]]]]]
        s.draft = try TrainingDraft.fromWeb(active, unit: "kg")
        s.liveRowAction(entry: 1, set: 0, action: ["action": "weightUnit", "unit": "lb"])
        s.liveRowAction(entry: 1, set: 0, action: ["action": "input", "path": "both.w", "text": "100", "operation": ["action": "field", "key": "w"]])
        let restored = try store()
        restored.restoreLocalTraining()
        let draft = try XCTUnwrap(restored.draft)
        let kg = (draft.rawEntries[0]["sets"] as! [[String: Any]])[0]
        let lb = (draft.rawEntries[1]["sets"] as! [[String: Any]])[0]
        XCTAssertEqual(TrainingInput.weightUnit(kg, fallback: "kg"), "kg")
        XCTAssertEqual(TrainingInput.weightUnit(lb, fallback: "kg"), "lb")
        XCTAssertEqual(number(lb["w"]), 45.359237, accuracy: 0.000001)
        XCTAssertEqual(TrainingInput.weightDisplay(lb, path: "both.w", value: number(lb["w"]), storedUnit: "kg"), "100")
        let saved = try WebRules.shared.call("finishAdvanced", payload: ["state": s.state, "active": TrainingInput.clean(draft.activeJSON), "now": 61000, "today": "2026-10-29"]) as! [String: Any]
        let workout = (saved["workouts"] as! [[String: Any]])[0]
        XCTAssertEqual(number(workout["vol"]), 653.59237, accuracy: 0.00001)
        let form = HistoryForm(original: workout, unit: "kg")
        XCTAssertEqual(TrainingInput.weightUnit(form.entries[1].sets[0].raw, fallback: "kg"), "lb")
        XCTAssertEqual(saved["unit"] as? String, "kg")
    }

    @MainActor func testEquipmentUnitsConvertSideDropsAndPreserveNonWeightFields() throws {
        let side: [String: Any] = ["w": 20, "r": 5, "done": true, "drops": [["w": 10, "r": 4]]]
        var row: [String: Any] = ["sides": ["L": side, "R": side], "mode": "reps", "type": "dropset", TrainingInput.weightUnitKey: "lb"]
        row = try TrainingInput.edit(row: row, action: ["action": "input", "path": "drop.L.0.w", "text": "50", "patchKey": "w", "operation": ["action": "dropEdit", "side": "L", "index": 0]], target: [:], state: ["unit": "kg"], editing: true)
        let sides = row["sides"] as! [String: [String: Any]]
        XCTAssertEqual(number((sides["L"]!["drops"] as! [[String: Any]])[0]["w"]), 22.6796185, accuracy: 0.000001)
        XCTAssertEqual(number((sides["R"]!["drops"] as! [[String: Any]])[0]["w"]), 10)
        row = try TrainingInput.edit(row: row, action: ["action": "input", "path": "R.w", "text": "100", "operation": ["action": "field", "side": "R", "key": "w"]], target: [:], state: ["unit": "kg"], editing: false)
        XCTAssertEqual(number((row["sides"] as! [String: [String: Any]])["R"]?["w"]), 45.359237, accuracy: 0.000001)
        let copied = try WebRules.shared.call("copyAdvancedSet", payload: ["sets": [row]]) as! [[String: Any]]
        XCTAssertEqual(TrainingInput.weightUnit(copied[1], fallback: "kg"), "lb")
        XCTAssertNil(copied[1][TrainingInput.key])
        let cardio = try TrainingInput.edit(row: ["mode": "cardio", TrainingInput.weightUnitKey: "kg"], action: ["action": "input", "path": "both.speed", "text": "8", "operation": ["action": "field", "key": "speed"]], target: [:], state: ["unit": "lb", "speedUnit": "kmh"], editing: false)
        XCTAssertEqual(number(cardio["speed"]), 8)
        let pounds = try TrainingInput.edit(row: [TrainingInput.weightUnitKey: "kg"], action: ["action": "input", "path": "both.w", "text": "20,5", "operation": ["action": "field", "key": "w"]], target: [:], state: ["unit": "lb"], editing: false)
        XCTAssertEqual(number(pounds["w"]), 20.5 / 0.45359237, accuracy: 0.000001)
    }

    func testHealthMergeRespectsUserDeletionAndRecoversEarlierSameDaySample() {
        let samples:[String:[String:Any]] = ["earlier":["kg":70,"time":1000,"day":"2026-10-20"],"later":["kg":71,"time":2000,"day":"2026-10-20"]]
        let deleted:[String:Any] = ["unit":"kg","bodyweight":[],"deleted":["bodyweight":["2026-10-20":3000]]]
        XCTAssertTrue((HealthWeightMerge.merge(deleted,samples:samples,deleted:[])["bodyweight"] as! [[String:Any]]).isEmpty)
        let first = HealthWeightMerge.merge(["unit":"kg","bodyweight":[]],samples:samples,deleted:[])
        let next = HealthWeightMerge.merge(first,samples:["earlier":samples["earlier"]!],deleted:["later"])
        XCTAssertEqual(number((next["bodyweight"] as! [[String:Any]])[0]["w"]),70)
    }
}
