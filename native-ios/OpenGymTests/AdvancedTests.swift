import XCTest
@testable import OpenGym
@MainActor final class AdvancedTests:XCTestCase {
    let day = "2026-10-23"
    let now = 1_792_699_200_000.0
    func state(_ configs:[[String:Any]])->[String:Any] { ["unit":"kg","restSec":90,"bodyweight":[],"workouts":[],"routines":[["id":"a","name":"A","excludeFromProgression":true,"ex":configs]],"week":[:],"dayPlan":[:]] }
    func begin(_ state:[String:Any],id:String = "test")->[String:Any] { try! WebRules.shared.call("beginAdvanced",payload:["state":state,"ids":["a"],"id":id,"now":now,"day":day]) as! [String:Any] }
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
}
