import XCTest
@testable import OpenGYM

final class PersonalFeaturesTests:XCTestCase {
    @MainActor func testTrainedExercisesRequireCompletedHistoryIncludingOneSide() {
        let store = GymStore()
        store.state = [
            "routines": [["id": "plan", "ex": [["id": "planned"]]]],
            "favEx": ["favourite"],
            "workouts": [["id": "history", "entries": [
                ["id": "ordinary", "sets": [["done": true]]],
                ["id": "ordinary", "sets": [["done": true]]],
                ["id": "one-side", "sets": [["sides": ["L": ["done": true], "R": ["done": false]]]]],
                ["id": "unfinished", "sets": [["done": false]]],
                ["id": "neither-side", "sets": [["done": true, "sides": ["L": ["done": false], "R": ["done": false]]]]],
                ["id": "empty", "sets": []],
                ["id": "", "sets": [["done": true]]]
            ]]]
        ]
        XCTAssertEqual(store.trainedExerciseIDs, ["ordinary", "one-side"])
        store.state = [:]
        XCTAssertTrue(store.trainedExerciseIDs.isEmpty)
    }
    @MainActor func testTrainedExercisesFollowLocalHistoryCorrections() {
        let store = GymStore()
        store.state = ["workouts": [workout()]]
        XCTAssertEqual(store.trainedExerciseIDs, ["0025"])
        store.historyEdits = ["w": ["proposed": ["entries": [["id": "replacement", "sets": [["done": true]]]]]]]
        XCTAssertEqual(store.trainedExerciseIDs, ["replacement"])
        store.historyEdits = [:]
        XCTAssertEqual(store.trainedExerciseIDs, ["0025"])
    }
    func testTrendPointIdentitySurvivesRedrawAndValueChanges() {
        let date = Date(timeIntervalSince1970:1000)
        func points(_ value:Double) -> [TrendPoint] {
            TrendPoint.identified([
                TrendPoint(date:date,value:value,series:"第 1 组"),
                TrendPoint(date:date,value:60,series:"第 1 组"),
                TrendPoint(date:date,value:70,series:"第 2 组")
            ])
        }
        let original = points(50), updated = points(55)
        XCTAssertEqual(original.map(\.id),updated.map(\.id))
        XCTAssertEqual(Set(original.map(\.id)).count,3)
        let prepended = TrendPoint.identified([TrendPoint(date:date.addingTimeInterval(-100),value:40)] + updated)
        XCTAssertEqual(Array(prepended.dropFirst().map(\.id)),original.map(\.id))
        XCTAssertEqual(TrendPoint(date:date,value:70).id,TrendPoint(date:date,value:71).id)
    }
    @MainActor private func rule(_ action:String,_ state:[String:Any],_ extra:[String:Any] = [:]) throws -> [String:Any] {
        try WebRules.shared.call("personalInfo",payload:extra.merging(["state":state,"action":action]){_,new in new}) as! [String:Any]
    }
    private func workout(_ id:String = "w",_ weight:Double = 60)->[String:Any] {
        ["id":id,"name":"测试训练","d":"2026-10-20","start":1792400000000,"end":1792403600000,"vol":480,"entries":[["id":"0025","target":["mode":"reps"],"sets":[["w":weight,"r":8,"done":true]]]],"prs":["0025"]]
    }
    @MainActor func testGlobalUnitConversionKeepsInventoryAndUnknownFields() throws {
        let source:[String:Any] = ["unit":"kg","workouts":[workout()],"bodyweight":[["d":"2026-10-20","w":78.6]],"targetW":75,"plates":["kg":["20":2]],"measurements":[["d":"2026-10-20","waist":80]],"future":["keep":true]]
        let next = try WebRules.shared.call("personalChange",payload:["action":"unit","state":source,"unit":"lb","convert":true]) as! [String:Any]
        XCTAssertEqual(next["unit"] as? String,"lb")
        XCTAssertEqual(number((next["bodyweight"] as! [[String:Any]])[0]["w"]),173.3,accuracy:0.01)
        XCTAssertTrue(RecordPatch.equal(source["plates"],next["plates"]))
        XCTAssertTrue(RecordPatch.equal(source["measurements"],next["measurements"]))
        XCTAssertNotNil(next["future"])
        let w = (next["workouts"] as! [[String:Any]])[0]
        XCTAssertGreaterThan(number(w["vol"]),1000)
    }
    @MainActor func testProgressKeepsBodyweightRepsAndCompletedSideOnly() throws {
        let state:[String:Any] = ["workouts":[["id":"w","d":"2026-10-20","start":10000,"entries":[["id":"0025","sets":[["w":0,"r":8,"done":true],["w":100,"r":8,"done":false]]]]]]]
        let result = try rule("progress",state,["id":"0025"])
        XCTAssertEqual(result["unit"] as? String,String(localized: "REPS_A", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
        XCTAssertEqual(number((result["points"] as! [[String:Any]])[0]["y"]),8)
    }
    @MainActor func testProgressExcludesWarmupAndUsesConfiguredFormula() throws {
        var w = workout();w["entries"] = [["id":"0025","sets":[["w":200,"r":1,"done":true,"phase":"warmup"],["w":60,"r":8,"done":true]]]]
        let result = try rule("progress",["workouts":[w],"oneRmFormula":"brzycki"],["id":"0025"])
        XCTAssertEqual(number((result["points"] as! [[String:Any]])[0]["y"]),60)
        XCTAssertNotEqual(number((result["best"] as! [String:Any])["est"]),76)
    }
    @MainActor func testWorkoutSharingUsesNamesAndCompletedWork() throws {
        let result = try rule("workoutText",[:],["workout":workout(),"names":["0025":"卧推"]])
        let text = result["text"] as! String
        XCTAssertTrue(text.contains("卧推"));XCTAssertFalse(text.contains("[object Object]"));XCTAssertTrue(text.contains("60"))
    }
    func testHistorySummaryCountsCompletedSidesLikeWeb() {
        let record = WorkoutRecord(raw:["entries":[["sets":[
            ["done":true], ["done":false], ["done":true,"phase":"warmup"],
            ["sides":["L":["done":true],"R":["done":false]]],
            ["sides":["L":["done":true],"R":["done":true]]],
            ["sides":["L":["done":false],"R":["done":false]]]
        ]]]])
        XCTAssertEqual(record.completedSetCount,5)
        XCTAssertEqual(WorkoutRecord(raw:[:]).completedSetCount,0)
    }
    @MainActor func testPlanRoundTripConvertsUnitsAndExcludesPrivateData() throws {
        let state:[String:Any] = ["unit":"kg","routines":[["id":"r","name":"计划","ex":[["id":"0025","sets":3,"reps":8,"weight":60]]]],"favEx":["0025"],"coach":["secret":"private"]]
        let exported = try rule("exportPlan",state)
        XCTAssertNil(exported["coach"]);XCTAssertNil(exported["favEx"])
        let parsed = try rule("parsePlan",["unit":"lb"],["raw":exported])
        let cfg = ((parsed["routines"] as! [[String:Any]])[0]["ex"] as! [[String:Any]])[0]
        XCTAssertGreaterThan(number(cfg["weight"]),130)
    }
    @MainActor func testRepeatPreservesSourceAndClearsCompletion() throws {
        let w = workout()
        let result = try WebRules.shared.call("personalRepeat",payload:["state":[:],"workout":w,"id":"new","day":"2026-10-29","now":123456]) as! [String:Any]
        let active = result["active"] as! [String:Any],entries = active["entries"] as! [[String:Any]],sets = entries[0]["sets"] as! [[String:Any]]
        XCTAssertEqual(active["id"] as? String,"new");XCTAssertFalse(sets.contains(where:rawCompleted));XCTAssertEqual(active["routineIds"] as? [String],[])
        XCTAssertTrue(((w["entries"] as! [[String:Any]])[0]["sets"] as! [[String:Any]])[0]["done"] as! Bool)
    }
    @MainActor func testCustomDeletionRejectsEachUseIndependently() throws {
        let id = "custom"
        let entries: [[String: Any]] = [["id": id, "sets": [["done": false]]]]
        let associations: [String: Any] = [
            "routines": [["ex": entries]], "workouts": [["entries": entries]], "active": ["entries": entries],
            "favEx": [id], "exNotes": [id: "seat 4"], "barWeights": [id: 0],
            "loadKind": [id: ["kind": "single"]], "dbLoad": [id: ["mode": "each"]],
            "balanceOverrides": ["test:role": ["id": id]]
        ]
        let exercise = ["id": id, "n": "Custom exercise"]
        for (key, value) in associations {
            let state: [String: Any] = ["customEx": [exercise], key: value]
            let result = try WebRules.shared.call("personalChange", payload: ["action": "deleteCustom", "state": state, "id": id]) as? [String: Any]
            XCTAssertEqual(result?["inUse"] as? Bool, true, "Deletion should be blocked by \(key)")
            XCTAssertNil(result?["state"])
        }
    }

    @MainActor func testCustomDeletionPreservesUnrelatedRecordsAndAllowsClearedSettings() throws {
        let id = "custom"
        let other = ["id": "other", "n": "Another custom exercise"]
        let state: [String: Any] = [
            "customEx": [["id": id, "n": "Custom exercise"], other],
            "routines": [["id": "r", "ex": [["id": "other"]]]],
            "workouts": [workout("recent", 20), workout("older", 10)],
            "favEx": ["other"], "loadKind": [id: ["kind": NSNull(), "_ts": 123]],
            "dbLoad": [id: ["mode": NSNull(), "_ts": 456]], "futureField": true
        ]
        let result = try WebRules.shared.call("personalChange", payload: [
            "action": "deleteCustom", "state": state, "id": id, "localEntries": [["id": "other"]]
        ]) as? [String: Any]
        let next = try XCTUnwrap(result?["state"] as? [String: Any])
        var expected = state
        expected["customEx"] = [other]
        XCTAssertTrue(RecordPatch.equal(next, expected))
    }

    @MainActor func testOnlyDraftsReferencingTheCustomExerciseBlockDeletion() throws {
        let store = GymStore()
        let id = "custom"
        store.historyEdits = ["w": ["proposed": ["entries": [["id": "unrelated"]]]]]
        XCTAssertNil(store.customExerciseDeletionIssue(id))
        store.historyEdits["w"] = ["proposed": ["entries": [["id": id]]]]
        XCTAssertNotNil(store.customExerciseDeletionIssue(id))
        store.historyEdits = [:]
        store.draft = try TrainingDraft.fromWeb(["id": "live", "entries": [["id": id, "sets": []]]], unit: "kg")
        XCTAssertNotNil(store.customExerciseDeletionIssue(id))
    }
    @MainActor func testDeletingWorkoutRepairsTrackedWeightAndKeepsOtherHistory() throws {
        let state:[String:Any] = ["workouts":[workout("a",80),workout("b",60)],"exWeights":["0025":["w":80,"d":"2026-10-20"]]]
        let next = try WebRules.shared.call("personalChange",payload:["action":"deleteWorkout","state":state,"id":"a"]) as! [String:Any]
        XCTAssertEqual((next["workouts"] as! [Any]).count,1)
        XCTAssertEqual(number(((next["exWeights"] as! [String:Any])["0025"] as! [String:Any])["w"]),60)
    }
    func testPersonalPatchKeepsOtherInventoryUnitsAndRefreshesStamp() throws {
        let old:[String:Any] = ["plates":["kg":["20":2,"_ts":1]]]
        let proposed:[String:Any] = ["plates":["kg":["20":3,"_ts":10]]]
        let remote:[String:Any] = ["plates":["kg":["20":2,"_ts":1],"lb":["45":6,"_ts":4]],"future":true]
        let next = try PersonalPatch.apply(original:old,proposed:proposed,current:remote)
        let plates = next["plates"] as! [String:Any]
        XCTAssertEqual(number((plates["kg"] as! [String:Any])["_ts"]),10);XCTAssertNotNil(plates["lb"]);XCTAssertNotNil(next["future"])
        XCTAssertThrowsError(try PersonalPatch.apply(original:old,proposed:proposed,current:["plates":["kg":["20":9]]]))
    }
    @MainActor func testProgressionValidationRejectsInvalidRanges() throws {
        XCTAssertThrowsError(try WebRules.shared.call("validatePersonalConfig",payload:["config":["id":"0025","prog":"double","repsMin":12,"reps":8]]))
        XCTAssertThrowsError(try WebRules.shared.call("validatePersonalConfig",payload:["config":["id":"0025","prog":"linear","inc":0]]))
        XCTAssertNoThrow(try WebRules.shared.call("validatePersonalConfig",payload:["config":["id":"0025","prog":"double","repsMin":6,"reps":10,"inc":2.5]]))
    }
    @MainActor func testBestReferenceDiffersFromLastWithoutChangingHistory() throws {
        var later = workout("b",40);later["start"] = 1792500000000
        let s:[String:Any] = ["logRef":"best","workouts":[workout("a",60),later]]
        let result = try WebRules.shared.call("personalReference",payload:["state":s,"entry":["id":"0025","target":["mode":"reps"]],"before":1792600000000,"exclude":"new"]) as! [String:Any]
        XCTAssertEqual(result["kind"] as? String,String(localized: "BEST_A", bundle: AppLanguage.bundle, locale: AppLanguage.locale));XCTAssertTrue((result["label"] as? String ?? "").contains("60"))
    }
    @MainActor func testProfileUnitSwitchBlockedByLocalDraft() async throws {
        let store = GymStore();store.draft = TrainingDraft(name:"training",entries:[],unit:"kg")
        let result = await store.switchProfileUnit(to:"lb",convert:true)
        XCTAssertFalse(result);XCTAssertNotNil(store.draft);XCTAssertNotNil(store.editError)
    }
}

extension PersonalFeaturesTests {
    @MainActor func testDateRecordSaveRebases409WithoutDroppingOtherDates() async throws {
        let cfg = URLSessionConfiguration.ephemeral;cfg.protocolClasses = [StubProtocol.self]
        let client = APIClient(address:try ServerAddress("https://test.invalid"),token:"test",session:URLSession(configuration:cfg))
        let store = GymStore(client:client,userID:"personal-test",storage:LocalTrainingStorage(root:FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)))
        var server:[String:Any] = ["unit":"kg","measurements":[["d":"2026-10-20","waist":80]],"future":"keep"], writes = 0
        StubProtocol.handler = {req in
            if req.httpMethod == "GET" {return (200,["state":server,"rev":writes])}
            writes += 1
            if writes == 1 {server["measurements"] = [["d":"2026-10-20","waist":80],["d":"2026-10-21","waist":81]];return (409,["error":"conflict"])}
            let body = try Self.decodeBody(req);server = body["state"] as! [String:Any];return (200,["ok":true])
        }
        let ok = await store.savePersonalRecord(collection:"measurements",key:"d",original:["d":"2026-10-20","waist":80],proposed:["d":"2026-10-20","waist":79],unit:"kg")
        XCTAssertTrue(ok);XCTAssertEqual(writes,2);XCTAssertEqual((server["measurements"] as! [Any]).count,2);XCTAssertEqual(server["future"] as? String,"keep")
    }
    @MainActor func testDateRecordRejectsConcurrentEditAndDuplicateDate() async throws {
        let cfg = URLSessionConfiguration.ephemeral;cfg.protocolClasses = [StubProtocol.self]
        let store = GymStore(client:APIClient(address:try ServerAddress("https://test.invalid"),token:"test",session:URLSession(configuration:cfg)),userID:"personal-conflict")
        StubProtocol.handler = {req in XCTAssertEqual(req.httpMethod,"GET");return (200,["state":["unit":"kg","measurements":[["d":"2026-10-20","waist":85],["d":"2026-10-21","waist":82]]],"rev":1])}
        let conflict = await store.savePersonalRecord(collection:"measurements",key:"d",original:["d":"2026-10-20","waist":80],proposed:["d":"2026-10-20","waist":79],unit:"kg")
        XCTAssertFalse(conflict)
        let duplicate = await store.savePersonalRecord(collection:"measurements",key:"d",original:nil,proposed:["d":"2026-10-21","waist":70],unit:"kg")
        XCTAssertFalse(duplicate)
    }
    @MainActor func testEquipmentFilteringUnderstandsBenchAndBodyweight() throws {
        let result = try rule("equipment",["equipFilterOn":true,"activeEquipId":"home","equipProfiles":[["id":"home","equipment":["dumbbell"],"accV":1]]])
        let ids = result["available"] as! [String]
        XCTAssertFalse(ids.contains("0025"));XCTAssertFalse(ids.isEmpty)
        XCTAssertTrue((result["equipment"] as! [String]).contains("bench"))
    }
    private static func decodeBody(_ request:URLRequest) throws -> [String:Any] {
        if let data = request.httpBody {return try JSONSerialization.jsonObject(with:data) as! [String:Any]}
        let stream = try XCTUnwrap(request.httpBodyStream);stream.open();defer{stream.close()}
        var data = Data(),buffer = [UInt8](repeating:0,count:4096)
        while stream.hasBytesAvailable {let n = stream.read(&buffer,maxLength:buffer.count);if n<=0{break};data.append(buffer,count:n)}
        return try JSONSerialization.jsonObject(with:data) as! [String:Any]
    }
}

extension PersonalFeaturesTests {
    func testMeasurementRetryRecognizesSavedValuesWithDifferentTimestamp() throws {
        let old:[String:Any] = ["d":"2026-10-20","waist":80,"t":1]
        let intended:[String:Any] = ["d":"2026-10-20","waist":79,"t":10]
        let saved:[String:Any] = ["d":"2026-10-20","waist":79,"t":9]
        let next = try PersonalRecordPatch.apply(original:old,proposed:intended,current:saved)
        XCTAssertEqual(number(next["t"]),9)
        XCTAssertThrowsError(try PersonalRecordPatch.apply(original:old,proposed:intended,current:["d":"2026-10-20","waist":82,"t":9]))
        XCTAssertTrue(PersonalRecordPatch.sameValues(saved,intended))
    }
}

extension PersonalFeaturesTests {
    @MainActor func testUnitConversionPreservesHealthSampleOwnership() throws {
        let row:[String:Any] = ["d":"2026-10-20","w":75,"t":123,"healthKit":["id":"sample","value":75,"time":123,"kg":75]]
        let next = try WebRules.shared.call("personalChange",payload:["action":"unit","state":["unit":"kg","bodyweight":[row]],"unit":"lb","convert":true]) as! [String:Any]
        XCTAssertTrue(HealthWeightMerge.untouched((next["bodyweight"] as! [[String:Any]])[0]))
    }
    @MainActor func testLegacyCustomMetadataResolvesTargetOnEdit() throws {
        let result = try rule("customMetadata",[:],["exercise":["id":"custom","n":"Test press","bp":"chest","tg":"pectorals","eq":"dumbbell"]])
        XCTAssertTrue((result["groups"] as! [String]).contains("chest"))
    }
}
