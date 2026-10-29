import XCTest
@testable import OpenGym
@MainActor final class AdvancedTests:XCTestCase {
    let day = "2026-10-23"
    let now = 1_792_699_200_000.0
    func state(_ configs:[[String:Any]])->[String:Any] { ["unit":"kg","restSec":90,"bodyweight":[],"workouts":[],"routines":[["id":"a","name":"A","excludeFromProgression":true,"ex":configs]],"week":[:],"dayPlan":[:]] }
    func begin(_ state:[String:Any],id:String = "test")->[String:Any] { try! WebRules.shared.call("beginAdvanced",payload:["state":state,"ids":["a"],"id":id,"now":now,"day":day]) as! [String:Any] }
    func testEmptyOrMissingPlanDoesNotSilentlyStartFreestyle() throws {
        for ids in [["a"], ["missing"]] {
            XCTAssertThrowsError(try WebRules.shared.call("beginAdvanced", payload: ["state": state([]), "ids": ids, "id": "test", "now": now, "day": day]))
        }
    }
    func testSideDropsMatchWebAndPartialSideCountsOnce() throws {
        let s = state([["id":"0150","sets":1,"reps":12,"weight":40,"side":true,"intensifier":["type":"dropset","count":2,"pct":20]]])
        var a = begin(s);var entries = a["entries"] as! [[String:Any]];var rows = entries[0]["sets"] as! [[String:Any]]
        let sides = rows[0]["sides"] as! [String:[String:Any]]
        XCTAssertEqual(number(sides["L"]?["r"]),6)
        XCTAssertEqual((sides["L"]?["drops"] as! [[String:Any]]).map{number($0["w"])},[30,25])
        rows[0] = try WebRules.shared.call("editAdvancedRow",payload:["row":rows[0],"action":"toggle","side":"L","now":now+10_000]) as! [String:Any]
        XCTAssertEqual(rows[0]["done"] as? Bool,false)
        entries[0]["sets"] = rows;a["entries"] = entries
        let next = try WebRules.shared.call("finishAdvanced",payload:["state":s,"active":a,"now":now+60_000,"today":day]) as! [String:Any]
        let work = (next["workouts"] as! [[String:Any]])[0]
        XCTAssertEqual(number(work["vol"]),570)
        XCTAssertEqual((work["entries"] as! [[String:Any]]).count,1)
    }
    func testRestPauseUsesWarmupAndTotalWithoutDoubleCounting() throws {
        let s = state([["id":"0150","sets":5,"reps":8,"weight":40,"intensifier":["type":"restpause","totalReps":12,"restSec":15]]])
        let a = begin(s);let e = (a["entries"] as! [[String:Any]])[0];let rows = e["sets"] as! [[String:Any]]
        XCTAssertEqual(rows.count,2);XCTAssertEqual(rows[0]["phase"] as? String,"warmup")
        XCTAssertEqual((rows[1]["clusters"] as! [[String:Any]]).reduce(0){$0+number($1["r"])},12)
        var active = a;var entry = e;entry["sets"] = rows.map { row -> [String:Any] in var r = row;r["done"] = true;return r };active["entries"] = [entry]
        let result = try WebRules.shared.call("finishAdvanced",payload:["state":s,"active":active,"now":now+60_000,"today":day]) as! [String:Any]
        XCTAssertEqual(number((result["workouts"] as! [[String:Any]])[0]["vol"]),480)
    }
    func testPyramidPerSideNormalizationAndTimedCardioShapes() throws {
        let normalized = try WebRules.shared.call("advancedConfig",payload:["config":["id":"0150","side":true,"pyramid":[11,"max",7],"pyramidWeight":[20,25,30],"intensifier":["type":"dropset"]]]) as! [String:Any]
        XCTAssertEqual((normalized["pyramid"] as! [Any]).map{String(describing:$0)},["12","max","8"]);XCTAssertNil(normalized["intensifier"])
        let a = begin(state([["id":"0150","mode":"time","sets":2,"sec":30,"side":true,"weight":0],["id":"3893","sets":1,"min":10,"speed":6]]))
        let entries = a["entries"] as! [[String:Any]],timed = entries[0]["sets"] as! [[String:Any]]
        XCTAssertEqual(timed.count,4);XCTAssertEqual(timed.map{$0["side"] as! String},["L","R","L","R"])
        XCTAssertEqual(number((entries[1]["sets"] as! [[String:Any]])[0]["min"]),10)
    }
    func testSupersetPairAndRestOnlyAtRoundBoundary() throws {
        let configs:[[String:Any]] = [["id":"0150","sets":2,"reps":8,"weight":20],["id":"0025","sets":2,"reps":8,"weight":30]]
        let grouped = try WebRules.shared.call("planGroup",payload:["rows":configs,"operation":"pair","index":0]) as! [[String:Any]]
        XCTAssertNotNil(grouped[0]["sg"]);XCTAssertEqual(grouped[0]["sg"] as? String,grouped[1]["sg"] as? String)
        let single = try WebRules.shared.call("planGroup",payload:["rows":[grouped[0]],"operation":"cleanup","index":0]) as! [[String:Any]]
        XCTAssertNil(single[0]["sg"])
        let s = state(grouped);var a = begin(s);var entries = a["entries"] as! [[String:Any]]
        var rows = entries[0]["sets"] as! [[String:Any]];rows[0]["done"] = true;entries[0]["sets"] = rows;a["entries"] = entries
        let first = try WebRules.shared.call("restForCompleted",payload:["active":a,"entry":0,"index":0,"state":s]) as! [String:Any]
        XCTAssertEqual(number(first["seconds"]),0);XCTAssertEqual(number(first["next"]),1)
        rows = entries[1]["sets"] as! [[String:Any]];rows[0]["done"] = true;entries[1]["sets"] = rows;a["entries"] = entries
        let second = try WebRules.shared.call("restForCompleted",payload:["active":a,"entry":1,"index":0,"state":s]) as! [String:Any]
        XCTAssertEqual(number(second["seconds"]),90)
    }
    func testRotationFinishingPassRefillsTomorrowAndSaveIsIdempotent() throws {
        var s = state([["id":"0150","sets":1,"reps":10,"weight":20]])
        s = try WebRules.shared.call("rotationChange",payload:["state":s,"action":"save","ids":["a"],"label":"Loop","today":day,"now":now]) as! [String:Any]
        var a = begin(s);var entries = a["entries"] as! [[String:Any]];var rows = entries[0]["sets"] as! [[String:Any]];rows[0]["done"] = true;entries[0]["sets"] = rows;a["entries"] = entries
        let next = try WebRules.shared.call("finishAdvanced",payload:["state":s,"active":a,"now":now+60_000,"today":day]) as! [String:Any]
        XCTAssertEqual((next["queue"] as! [String:Any])["startsOn"] as? String,"2026-10-24")
        let repeated = try WebRules.shared.call("finishAdvanced",payload:["state":next,"active":a,"now":now+120_000,"today":day]) as! [String:Any]
        XCTAssertEqual((repeated["workouts"] as! [[String:Any]]).count,1)
        XCTAssertTrue(RecordPatch.equal(next["queue"],repeated["queue"]))
    }
    func testFixedWeekPreservesExternalQueueAndReorderPreservesProgress() throws {
        var s = state([]);s["routines"] = [["id":"a","name":"A","ex":[]],["id":"b","name":"B","ex":[]]]
        s["queue"] = ["ids":["a","b"],"since":now,"startsOn":day,"label":"Coach"]
        let fixed = try WebRules.shared.call("rotationChange",payload:["state":s,"action":"week","today":day,"now":now]) as! [String:Any]
        XCTAssertTrue(RecordPatch.equal(fixed["queue"],s["queue"]))
        s = try WebRules.shared.call("rotationChange",payload:["state":s,"action":"save","ids":["a","b"],"label":"Loop","today":day,"now":now]) as! [String:Any]
        s["workouts"] = [["id":"w","d":day,"start":now,"routineIds":["a"],"entries":[]]]
        let moved = try WebRules.shared.call("rotationChange",payload:["state":s,"action":"save","ids":["b","a"],"label":"Loop","today":day,"now":now+1000]) as! [String:Any]
        let info = try WebRules.shared.call("rotationInfo",payload:["state":moved,"today":day]) as! [String:Any]
        let items = (info["view"] as! [String:Any])["items"] as! [[String:Any]]
        XCTAssertEqual(items.first{$0["id"] as? String == "a"}?["state"] as? String,"done")
    }
    func testAdvancedDraftAndTimerSurviveEncoding() throws {
        var a = begin(state([["id":"0150","mode":"time","sec":3,"sets":1]]));a["nativeTimer"] = ["entry":0,"set":0,"end":1000,"paused":true,"remaining":2]
        let draft = try TrainingDraft.fromWeb(a,unit:"kg")
        let restored = try JSONDecoder().decode(TrainingDraft.self,from:JSONEncoder().encode(draft))
        XCTAssertTrue(RecordPatch.equal(restored.activeJSON,a));XCTAssertEqual((restored.activeJSON["nativeTimer"] as? [String:Any])?["paused"] as? Bool,true)
    }
    func testHistoryClusterEditKeepsAggregateAndOriginalCompletionTime() throws {
        let row:[String:Any] = ["w":20,"r":12,"done":true,"at":1234,"type":"restpause","clusters":[["r":6,"restSec":15],["r":3,"restSec":15],["r":2,"restSec":15],["r":1,"restSec":15]]]
        let next = try WebRules.shared.call("editAdvancedRow",payload:["row":row,"action":"clusterEdit","index":0,"value":8,"editing":true]) as! [String:Any]
        XCTAssertEqual(number(next["r"]),14)
        let toggled = try WebRules.shared.call("editAdvancedRow",payload:["row":next,"action":"toggle","editing":true,"now":9999]) as! [String:Any]
        XCTAssertEqual(number(toggled["at"]),1234)
    }
    func testRestoredExpiredTimerLogsPlannedSecondsOnlyOnce() throws {
        var a = begin(state([["id":"0150","mode":"time","sec":30,"sets":1]]))
        let time = Date().timeIntervalSince1970
        a["nativeTimer"] = ["entry":0,"set":0,"start":time-150,"end":time-120,"planned":30,"remaining":30,"elapsed":0,"paused":false]
        let store = GymStore();store.draft = try TrainingDraft.fromWeb(a,unit:"kg")
        store.settleTimer();store.settleTimer()
        let row = (store.draft!.rawEntries[0]["sets"] as! [[String:Any]])[0]
        XCTAssertEqual(row["done"] as? Bool,true);XCTAssertEqual(number(row["sec"]),30);XCTAssertNil(store.workTimer)
    }
    func testCompletedExerciseWaitsForExplicitNavigationEvenBeforeWarmup() throws {
        let s = state([["id":"0150","sets":1,"reps":8,"weight":20], ["id":"0025","sets":1,"reps":8,"weight":30]])
        var active = begin(s)
        var entries = active["entries"] as! [[String:Any]]
        entries[0]["sets"] = [["w":20,"r":8,"done":false]]
        entries[1]["sets"] = [["w":10,"r":8,"done":false,"phase":"warmup"], ["w":30,"r":8,"done":false]]
        active["entries"] = entries; active["cur"] = 0
        let store = GymStore(); store.state = s; store.draft = try TrainingDraft.fromWeb(active,unit:"kg")
        store.liveRowAction(entry:0,set:0,action:["action":"toggle"])
        XCTAssertEqual(store.draft?.activeJSON["cur"] as? Int,0)
        XCTAssertNil(store.restUntil)
        XCTAssertEqual((store.draft?.rawEntries[0]["sets"] as? [[String:Any]])?[0]["done"] as? Bool,true)
        store.selectLiveEntry(1)
        XCTAssertEqual(store.draft?.activeJSON["cur"] as? Int,1)
    }
    func testIncompleteSupersetStillAdvancesToPartner() throws {
        let configs:[[String:Any]] = [["id":"0150","sets":2,"reps":8,"weight":20], ["id":"0025","sets":2,"reps":8,"weight":30]]
        let grouped = try WebRules.shared.call("planGroup",payload:["rows":configs,"operation":"pair","index":0]) as! [[String:Any]]
        let s = state(grouped)
        let store = GymStore(); store.state = s; store.draft = try TrainingDraft.fromWeb(begin(s),unit:"kg")
        store.liveRowAction(entry:0,set:0,action:["action":"toggle"])
        XCTAssertEqual(store.draft?.activeJSON["cur"] as? Int,1)
        XCTAssertNil(store.restUntil)
    }
}

extension AdvancedTests {
    func testInclineControlsFollowExerciseAndKeepExistingGradesEditable() throws {
        for (id, expected) in [("2259", true), ("3893", false)] {
            let info = try WebRules.shared.call("rowInfo", payload: ["row": ["mode": "cardio"], "target": ["id": id]]) as! [String: Any]
            XCTAssertEqual(info["incline"] as? Bool, expected)
        }
        let existing = try WebRules.shared.call("rowInfo", payload: ["row": ["mode": "cardio", "incline": 3], "target": ["id": "3893"]]) as! [String: Any]
        XCTAssertEqual(existing["incline"] as? Bool, true)
    }
    func testInputSteppersRespectEquipmentSidesAndDisplayUnits() throws {
        let state: [String: Any] = ["unit": "kg", "dumbbells": ["kg": ["weights": [9, 11, 13]]]]
        XCTAssertEqual(TrainingInput.steppedText("9", path: "both.w", direction: 1, target: ["id": "0289"], state: state, unit: "kg"), "11")
        XCTAssertEqual(TrainingInput.steppedText("8", path: "L.r", direction: 1, target: ["side": true], state: state, unit: "kg"), "9")
        XCTAssertEqual(TrainingInput.steppedText("8", path: "both.r", direction: 1, target: ["side": true], state: state, unit: "kg"), "10")
        XCTAssertEqual(TrainingInput.steppedText("10", path: "both.w", direction: 1, target: ["inc": 0.45359237], state: state, unit: "lb"), "11")
        XCTAssertEqual(TrainingInput.steppedText("0", path: "both.w", direction: -1, target: [:], state: state, unit: "kg"), "0")
        XCTAssertNil(TrainingInput.steppedText("", path: "both.w", direction: 1, target: [:], state: state, unit: "kg"))
    }
    func testSpeedInputConvertsMphAndHonorsIndependentPreference() throws {
        let imperial: [String: Any] = ["unit": "lb"]
        let action: [String: Any] = ["action": "input", "path": "both.speed", "text": "6", "operation": ["action": "field", "key": "speed"]]
        let row = try TrainingInput.edit(row: ["mode": "cardio", "min": 20], action: action, target: [:], state: imperial, editing: false)
        XCTAssertEqual(number(row["speed"]), 9.66, accuracy: 0.001)
        XCTAssertEqual(TrainingInput.speedDisplay(number(row["speed"]), state: imperial), 6)
        let metric = try TrainingInput.edit(row: row, action: action, target: [:], state: ["unit": "lb", "speedUnit": "kmh"], editing: false)
        XCTAssertEqual(number(metric["speed"]), 6)
        XCTAssertEqual(TrainingInput.speedUnit(["unit": "kg", "speedUnit": "mph"]), "mph")
    }
    func testInclineCanBeEditedClearedAndInvalidInputIsPreserved() throws {
        func edit(_ row: [String: Any], _ text: String) throws -> [String: Any] {
            try TrainingInput.edit(row: row, action: ["action": "input", "path": "both.incline", "text": text, "operation": ["action": "field", "key": "incline"]], target: [:], state: [:], editing: false)
        }
        let row = try edit(["mode": "cardio", "min": 20, "speed": 6], "4.5")
        XCTAssertEqual(number(row["incline"]), 4.5)
        let invalid = try edit(row, "100")
        XCTAssertEqual(number(invalid["incline"]), 4.5)
        XCTAssertThrowsError(try TrainingInput.validate(invalid))
        let cleared = try edit(invalid, "")
        XCTAssertNil(cleared["incline"])
        XCTAssertNoThrow(try TrainingInput.validate(cleared))
    }
    func testCopySelectedPairPreservesNeighborsAndClearsCopiedInput() throws {
        let sets: [[String: Any]] = [
            ["side": "L", "sec": 30, "done": true, "at": 1000, TrainingInput.key: ["both.sec": "30."]],
            ["side": "R", "sec": 40, "done": true],
            ["w": 20, "r": 8, "done": true, TrainingInput.key: ["both.w": "20."]]
        ]
        let result = try WebRules.shared.call("copySelectedSet", payload: ["sets": sets, "index": 1]) as! [String: Any]
        let copied = result["sets"] as! [[String: Any]]
        XCTAssertEqual(copied.count, 5); XCTAssertEqual(result["at"] as? Int, 2)
        XCTAssertTrue(RecordPatch.equal(copied[0], sets[0])); XCTAssertTrue(RecordPatch.equal(copied[4], sets[2]))
        XCTAssertEqual(copied[2]["side"] as? String, "L"); XCTAssertEqual(copied[3]["side"] as? String, "R")
        XCTAssertEqual(copied[2]["done"] as? Bool, false); XCTAssertNil(copied[2]["at"]); XCTAssertNil(copied[2][TrainingInput.key])
        var form = HistoryEntryDraft(["id": "0289", "sets": sets])
        let oldID = form.sets[2].id
        try form.copySet(at: 1)
        XCTAssertEqual(form.sets[4].id, oldID); XCTAssertEqual(form.sets[2].raw["done"] as? Bool, true)
    }
    func testCopyAndRestChangesPersistAndPreserveTimerOwnership() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = LocalTrainingStorage(root: root)
        let store = GymStore(userID: "input-parity", storage: storage)
        store.draft = try TrainingDraft.fromWeb(begin(state([["id": "0289", "sets": 3, "reps": 8, "weight": 20]])), unit: "kg")
        store.startRest(entry: 0, seconds: 90, set: 2)
        let end = try XCTUnwrap(store.restUntil)
        store.copyLiveSet(entry: 0, set: 0)
        XCTAssertEqual((store.draft?.activeJSON["nativeRest"] as? [String: Any])?["set"] as? Int, 3)
        store.adjustRest(by: 15)
        XCTAssertEqual(try XCTUnwrap(store.restUntil).timeIntervalSince(end), 15, accuracy: 0.1)
        store.changeActive { $0["name"] = "New name"; $0["note"] = "keep this note" }
        let restored = GymStore(userID: "input-parity", storage: storage); restored.restoreDraft()
        XCTAssertEqual(restored.draft?.name, "New name")
        XCTAssertEqual(restored.draft?.activeJSON["note"] as? String, "keep this note")
        XCTAssertEqual((restored.draft?.rawEntries[0]["sets"] as? [[String: Any]])?.count, 4)
        restored.startExerciseRest(entry: 0, seconds: 120)
        XCTAssertEqual((restored.draft?.rawEntries[0]["target"] as? [String: Any])?["restSec"] as? Int, 120)
        restored.adjustRest(by: -200)
        XCTAssertNil(restored.restUntil)
    }
    func testCopyRejectsIncompleteOtherSideOfTimedPair() throws {
        var form = HistoryEntryDraft(["id": "0289", "sets": [["side": "L", "sec": 30], ["side": "R", "sec": 30, TrainingInput.key: ["both.sec": ""]]]])
        XCTAssertThrowsError(try form.copySet(at: 0))
        XCTAssertEqual(form.sets.count, 2)
    }
    func testLiveSupersetControlsPreserveSets() throws {
        let original = begin(state([["id": "0289", "sets": 2, "weight": 20], ["id": "1047", "sets": 2, "weight": 10]]))
        let paired = try WebRules.shared.call("manageTrainingExercises", payload: ["active": original, "action": "pair", "index": 1, "direction": -1]) as! [String: Any]
        let entries = paired["entries"] as! [[String: Any]]
        XCTAssertNotNil(entries[0]["sg"]); XCTAssertEqual(entries[0]["sg"] as? String, entries[1]["sg"] as? String)
        XCTAssertTrue(RecordPatch.equal(entries[0]["sets"], (original["entries"] as! [[String: Any]])[0]["sets"]))
        let unpaired = try WebRules.shared.call("manageTrainingExercises", payload: ["active": paired, "action": "unpair", "index": 0]) as! [String: Any]
        XCTAssertTrue((unpaired["entries"] as! [[String: Any]]).allSatisfy { $0["sg"] == nil })
    }
}
