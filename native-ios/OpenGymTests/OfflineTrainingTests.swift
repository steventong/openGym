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
    func testHealthMergeRespectsUserDeletionAndRecoversEarlierSameDaySample() {
        let samples:[String:[String:Any]] = ["earlier":["kg":70,"time":1000,"day":"2026-10-20"],"later":["kg":71,"time":2000,"day":"2026-10-20"]]
        let deleted:[String:Any] = ["unit":"kg","bodyweight":[],"deleted":["bodyweight":["2026-10-20":3000]]]
        XCTAssertTrue((HealthWeightMerge.merge(deleted,samples:samples,deleted:[])["bodyweight"] as! [[String:Any]]).isEmpty)
        let first = HealthWeightMerge.merge(["unit":"kg","bodyweight":[]],samples:samples,deleted:[])
        let next = HealthWeightMerge.merge(first,samples:["earlier":samples["earlier"]!],deleted:["later"])
        XCTAssertEqual(number((next["bodyweight"] as! [[String:Any]])[0]["w"]),70)
    }
}
