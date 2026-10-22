import XCTest
@testable import OpenGym
final class EditingTests:XCTestCase {
    func testFieldMergeKeepsRemoteNotesAndRejectsConcurrentSetChanges() throws {
        let old:[String:Any] = ["name":"Old","ex":[["id":"0150","sets":3,"reps":10,"weight":20,"extension":true]],"_ts":1]
        var edited = old; edited["name"] = "New"
        var remote = old; remote["note"] = "web note"; remote["_ts"] = 100
        let next = try RecordPatch.apply(original:old,proposed:edited,current:remote)
        XCTAssertEqual(next["note"] as? String,"web note")
        XCTAssertEqual(next["name"] as? String,"New")
        edited["ex"] = [["id":"0150","sets":4]]
        remote["ex"] = [["id":"0150","sets":5]]
        XCTAssertThrowsError(try RecordPatch.apply(original:old,proposed:edited,current:remote))
    }
    func testScheduleMergePreservesOtherDaysAndRemovesRestDayKey() throws {
        let old:[String:Any] = ["week":["1":["a"],"3":["b"]]]
        let edited:[String:Any] = ["week":["3":["b"]],"dayPlan":["2026-10-24":"rest"]]
        let remote:[String:Any] = ["week":["1":["a"],"3":["b"],"5":["c"]],"other":"keep"]
        let next = try RecordPatch.apply(original:old,proposed:edited,current:remote)
        let week = next["week"] as! [String:Any]
        XCTAssertNil(week["1"]); XCTAssertEqual(week["5"] as? [String],["c"])
        XCTAssertEqual(next["other"] as? String,"keep")
    }
    @MainActor func testWebScheduleSupportsMultipleRoutinesAndSingleDayOverrides() throws {
        let state:[String:Any] = ["routines":[["id":"a"],["id":"b"]],"week":["1":["a","b"]],"dayPlan":["2026-10-26":"rest","2026-11-02":"b"],"workouts":[]]
        let result = try WebRules.shared.call("schedule",payload:["state":state,"dates":["2026-10-19","2026-10-26","2026-11-02"],"today":"2026-10-23"]) as! [[String]]
        XCTAssertEqual(result,[["a","b"],[],["b"]])
    }
    @MainActor func testWebHistoryRebuildsVolumeAndPRWithoutLosingMetadata() throws {
        func workout(_ id:String,_ start:Double,_ weight:Double)->[String:Any] {
            ["id":id,"name":id,"d":"2026-10-20","start":start,"end":start+60_000,"entries":[["id":"0025","sets":[["w":weight,"r":10,"done":true]],"extension":"keep"]],"prs":["0025"],"media":[["hash":"test"]]]
        }
        let previous = workout("a",1000,100)
        let state:[String:Any] = ["workouts":[workout("b",2000,80),workout("a",1000,60)],"exWeights":["0025":["w":100,"d":"2026-10-20"]],"futureField":true]
        let next = try WebRules.shared.call("repairHistory",payload:["state":state,"changedID":"a","touched":["0025"],"recomputeEntries":true,"previous":previous]) as! [String:Any]
        let list = next["workouts"] as! [[String:Any]]
        XCTAssertEqual(list[0]["id"] as? String,"a")
        XCTAssertEqual(number(list[0]["vol"]),600)
        XCTAssertEqual((list[0]["entries"] as! [[String:Any]])[0]["extension"] as? String,"keep")
        XCTAssertNotNil(list[0]["media"])
        XCTAssertEqual(list[1]["prs"] as? [String],["0025"])
        XCTAssertEqual(number(((next["exWeights"] as! [String:Any])["0025"] as! [String:Any])["w"]),80)
    }
    @MainActor func testMovedHistoryRevokesFalseLaterPRButKeepsImportedBadgesEmpty() throws {
        func w(_ id:String,_ start:Double,_ weight:Double,_ prs:[String])->[String:Any] { ["id":id,"d":"2026-10-20","start":start,"entries":[["id":"0025","sets":[["w":weight,"r":5,"done":true]]]],"prs":prs] }
        let result = try WebRules.shared.call("repairHistory",payload:["state":["workouts":[w("b",2,70,["0025"]),w("imported",3,100,[]),w("a",1,90,[])]],"changedID":"a","touched":["0025"],"recomputeEntries":false]) as! [String:Any]
        let list = result["workouts"] as! [[String:Any]]
        XCTAssertEqual(list[0]["prs"] as? [String],["0025"])
        XCTAssertEqual(list[1]["prs"] as? [String],[])
        XCTAssertEqual(list[2]["prs"] as? [String],[])
    }
    @MainActor func testLiveStoreRejectsDeletedWorkoutAndPreservesEditorDraft() async throws {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [StubProtocol.self]
        let api = APIClient(address:try ServerAddress("https://test.invalid"),token:"test",session:URLSession(configuration:config))
        let store = GymStore(client:api,userID:"test")
        StubProtocol.handler = { request in XCTAssertEqual(request.httpMethod,"GET"); return (200,["state":["unit":"kg","workouts":[]],"rev":4]) }
        let old:[String:Any] = ["id":"removed","name":"old"]
        let result = await store.saveWorkout(original:old,proposed:["id":"removed","name":"new"],expectedUnit:"kg")
        XCTAssertFalse(result); XCTAssertNotNil(store.editError)
    }
    func testLegacyIdentityAndCombinedWorkoutKeepStableRoutineLinks() throws {
        let raw:[String:Any] = ["d":"2026-10-20","start":1000]
        XCTAssertEqual(WorkoutRecord.key(raw),"2026-10-20|1000")
        let draft = TrainingDraft(routineID:"a",name:"A + B",entries:[TrainingEntry(id:"0025",name:"Bench",sets:[TrainingSet(done:true)],routineID:"a"),TrainingEntry(id:"0150",name:"Pull",sets:[TrainingSet(done:true)],routineID:"b")],unit:"kg",routineIDs:["a","b"])
        let data = draft.workoutJSON()
        XCTAssertEqual(data["routineIds"] as? [String],["a","b"])
        XCTAssertEqual((data["entries"] as! [[String:Any]])[1]["rid"] as? String,"b")
    }
}
