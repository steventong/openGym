import XCTest
import SwiftUI
import UIKit
@testable import OpenGym
final class EditingTests:XCTestCase {
    @MainActor func testCalendarMarkersPreferRecordsOverPlansAndRespectRestOverrides() throws {
        let store = GymStore()
        let dates = try ["2026-11-02", "2026-11-03", "2026-11-04", "2026-11-05", "2026-11-06"].map { try XCTUnwrap(dateFromDay($0)) }
        store.state = ["routines": [["id": "plan", "name": "训练", "ex": []]],
            "week": ["1": ["plan"], "2": ["plan"], "3": ["plan"]],
            "dayPlan": ["2026-11-04": "rest", "2026-11-05": "deleted-plan"],
            "workouts": [["id": "record", "d": "2026-11-03"], ["id": "freestyle", "d": "2026-11-06"]]]
        XCTAssertEqual(store.trainingDayMarkers(on: dates), [.planned, .completed, .none, .none, .completed])
        XCTAssertEqual(store.trainingDayMarkers(on: []), [])
        store.state["workouts"] = []
        XCTAssertEqual(store.trainingDayMarkers(on: dates), [.planned, .planned, .none, .none, .none])
    }

    @MainActor func testCalendarMarkersFollowLocalHistoryDateCorrectionsAndSingleDayPlans() throws {
        let store = GymStore()
        let first = try XCTUnwrap(dateFromDay("2026-11-03")), second = try XCTUnwrap(dateFromDay("2026-11-04"))
        store.state = ["routines": [["id": "plan", "name": "训练", "ex": []]], "week": [:],
            "dayPlan": ["2026-11-03": "plan"], "workouts": [["id": "record", "d": "2026-11-03"]]]
        store.historyEdits = ["record": ["proposed": ["id": "record", "d": "2026-11-04"]]]
        XCTAssertEqual(store.trainingDayMarkers(on: [first, second]), [.planned, .completed])
    }

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
    private func requestBody(_ request:URLRequest) throws -> [String:Any] {
        let data:Data
        if let body = request.httpBody { data = body } else {
            let stream = try XCTUnwrap(request.httpBodyStream)
            stream.open(); defer { stream.close() }
            var result = Data(), buffer = [UInt8](repeating:0,count:4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer,maxLength:buffer.count)
                if count <= 0 { break }
                result.append(buffer,count:count)
            }
            data = result
        }
        return try XCTUnwrap(JSONSerialization.jsonObject(with:data) as? [String:Any])
    }
    @MainActor private func deletionStore() throws -> GymStore {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [StubProtocol.self]
        let api = APIClient(address:try ServerAddress("https://test.invalid"),token:"test",session:URLSession(configuration:config))
        return GymStore(client:api,userID:"routine-deletion-test")
    }
    @MainActor func testDeleteRoutineCleansScheduleAndKeepsHistoryDraftAndLoopProgress() async throws {
        let store = try deletionStore()
        var server:[String:Any] = [
            "routines":[["id":"a","name":"A","ex":[]],["id":"b","name":"B","ex":[]]],
            "week":["0":"a","1":["a","b"],"2":["a"],"3":"b","4":["b","a","b"]],
            "dayPlan":["2026-10-25":"a","2026-10-26":"b","2026-10-27":"rest","2020-01-01":"a"],
            "workouts":[["id":"history","routineId":"a","routineIds":["a","b"],"entries":[]]],
            "active":["routineId":"a","entries":[]],"futureField":["keep":true],
            "rotation":["id":"loop","sequence":["a","b"],"label":"Loop"],
            "queue":["rotationId":"loop","ids":["a","b"],"since":1,"startsOn":"2026-10-25","label":"Loop"],
            "deleted":["routines":["old":12]],"edited":["week.5":20],"_wid":"snapshot"
        ]
        let before = server
        store.state = server
        store.draft = TrainingDraft(routineID:"a",name:"A",entries:[TrainingEntry(id:"0150",name:"Pull",sets:[TrainingSet(done:true)])],unit:"kg")
        let draft = try JSONEncoder().encode(store.draft)
        defer { store.draft = nil; StubProtocol.handler = nil }
        StubProtocol.handler = { request in
            if request.httpMethod == "GET" { return (200,["state":server,"rev":7]) }
            let body = try self.requestBody(request)
            XCTAssertEqual(body["baseRev"] as? Int,7)
            XCTAssertEqual(body["baseWid"] as? String,"snapshot")
            XCTAssertNil(body["stamped"])
            server = try XCTUnwrap(body["state"] as? [String:Any])
            return (200,["ok":true])
        }
        let deleted = await store.deleteRoutine(id:"a")
        XCTAssertTrue(deleted)
        XCTAssertEqual(store.routines.map(\.id),["b"])
        XCTAssertTrue(RecordPatch.equal(server["week"],["1":["b"],"3":"b","4":["b","b"]]))
        XCTAssertTrue(RecordPatch.equal(server["dayPlan"],["2026-10-26":"b","2026-10-27":"rest"]))
        for key in ["workouts","active","futureField","rotation","queue","deleted","edited"] {
            XCTAssertTrue(RecordPatch.equal(server[key],before[key]),key)
        }
        XCTAssertTrue(RecordPatch.equal(try JSONSerialization.jsonObject(with:JSONEncoder().encode(store.draft)),try JSONSerialization.jsonObject(with:draft)))
        let scheduled = try WebRules.shared.call("schedule",payload:["state":server,"dates":["2026-10-25","2026-10-26"],"today":"2026-10-25"]) as! [[String]]
        XCTAssertEqual(scheduled,[[],["b"]])
        let repeated = await store.deleteRoutine(id:"a")
        XCTAssertTrue(repeated)
        let last = await store.deleteRoutine(id:"b")
        XCTAssertTrue(last); XCTAssertTrue(store.routines.isEmpty)
        let empty = try WebRules.shared.call("schedule",payload:["state":server,"dates":["2026-10-25"],"today":"2026-10-25"]) as! [[String]]
        XCTAssertEqual(empty,[[]])
    }
    @MainActor func testDeleteRoutineRetriesWithoutOverwritingConcurrentSchedule() async throws {
        let store = try deletionStore(); var writes = 0
        var server:[String:Any] = ["routines":[["id":"a"],["id":"b"]],"week":["1":["a"]],"_wid":"first"]
        defer { StubProtocol.handler = nil }
        StubProtocol.handler = { request in
            if request.httpMethod == "GET" { return (200,["state":server,"rev":writes+1]) }
            writes += 1
            if writes == 1 {
                server["routines"] = [["id":"a"],["id":"b"],["id":"new","note":"remote"]]
                server["week"] = ["1":["a","new"],"2":["b"]]
                server["dayPlan"] = ["2026-10-26":"new"]
                server["futureField"] = "remote"; server["_wid"] = "second"
                return (409,["error":"conflict"])
            }
            let body = try self.requestBody(request)
            XCTAssertEqual(body["baseRev"] as? Int,2); XCTAssertEqual(body["baseWid"] as? String,"second")
            server = try XCTUnwrap(body["state"] as? [String:Any])
            return (200,["ok":true])
        }
        let deleted = await store.deleteRoutine(id:"a")
        XCTAssertTrue(deleted); XCTAssertEqual(writes,2)
        XCTAssertEqual(store.routines.map(\.id),["b","new"])
        XCTAssertTrue(RecordPatch.equal(server["week"],["1":["new"],"2":["b"]]))
        XCTAssertTrue(RecordPatch.equal(server["dayPlan"],["2026-10-26":"new"]))
        XCTAssertEqual(server["futureField"] as? String,"remote")
    }
    @MainActor func testFailedDeleteKeepsLocalPlanAndReportsError() async throws {
        let store = try deletionStore()
        let before:[String:Any] = ["routines":[["id":"a","name":"A"]],"week":["1":["a"]]]
        store.state = before
        defer { StubProtocol.handler = nil }
        for failRead in [true,false] {
            StubProtocol.handler = { request in
                if failRead { throw URLError(.notConnectedToInternet) }
                if request.httpMethod == "GET" { return (200,["state":before,"rev":1]) }
                return (500,["error":"Unable to save"])
            }
            let deleted = await store.deleteRoutine(id:"a")
            XCTAssertFalse(deleted); XCTAssertNotNil(store.editError)
            XCTAssertTrue(RecordPatch.equal(store.state,before)); XCTAssertFalse(store.syncing)
        }
    }

}


extension EditingTests {
    @MainActor func testHistoryFieldsCommitOnBlurAndFlushWithoutPerKeystrokeWrites() async throws {
        let buffer = InputCommitBuffer()
        var value = "", writes: [String] = []
        let field = BufferedTextField("Weight", text: Binding(get: { value }, set: { value = $0; writes.append($0) }))
            .environment(\.inputCommitBuffer, buffer)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: field)
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        try await Task.sleep(for: .milliseconds(100))
        let input = try XCTUnwrap(descendant(UITextField.self, in: window))
        XCTAssertTrue(input.becomeFirstResponder())
        for character in "12.50" { input.insertText(String(character)) }
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(input.text, "12.50")
        XCTAssertEqual(value, "")
        XCTAssertTrue(writes.isEmpty, "Typing must not enter the model or persistence path")

        input.resignFirstResponder()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(writes, ["12.50"])

        // Closing/saving/backgrounding flushes synchronously, even if focus hasn't changed.
        XCTAssertTrue(input.becomeFirstResponder())
        input.insertText("1")
        buffer.commitAll()
        XCTAssertEqual(value, "12.501")
        XCTAssertEqual(writes.count, 2)
        XCTAssertTrue(input.isFirstResponder)
        input.resignFirstResponder()
        try await Task.sleep(for: .milliseconds(100))
        buffer.commitAll()
        XCTAssertEqual(writes.count, 2, "Later blur/disappearance must not recreate a submitted draft")
    }

    @MainActor func testMultilineInputFlushesAndUnbufferedFieldsRemainImmediate() async throws {
        let buffer = InputCommitBuffer()
        var note = "", live = ""
        let fields = VStack {
            BufferedTextField("Note", text: Binding(get: { note }, set: { note = $0 }), axis: .vertical)
                .environment(\.inputCommitBuffer, buffer)
            BufferedTextField("Live", text: Binding(get: { live }, set: { live = $0 }))
        }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: fields)
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        try await Task.sleep(for: .milliseconds(100))
        let noteInput = try XCTUnwrap(descendant(UITextView.self, in: window))
        XCTAssertTrue(noteInput.becomeFirstResponder())
        noteInput.insertText("训练备注\n第二行")
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(note, "")
        buffer.commitAll()
        XCTAssertEqual(note, "训练备注\n第二行")
        let liveInput = try XCTUnwrap(descendant(UITextField.self, in: window))
        XCTAssertTrue(liveInput.becomeFirstResponder())
        liveInput.insertText("25")
        XCTAssertEqual(live, "25")
        liveInput.resignFirstResponder()
    }

    @MainActor func testNumericInputDefersParsedValueUntilSaveAndSupportsDiscard() async throws {
        let buffer = InputCommitBuffer()
        var value = 20.0, writes = 0
        let field = BufferedNumberField("Weight", value: Binding(get: { value }, set: { value = $0; writes += 1 }))
            .environment(\.inputCommitBuffer, buffer)
            .environment(\.locale, Locale(identifier: "en_US"))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: field)
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        try await Task.sleep(for: .milliseconds(100))
        let input = try XCTUnwrap(descendant(UITextField.self, in: window))
        XCTAssertTrue(input.becomeFirstResponder())
        input.selectedTextRange = input.textRange(from: input.beginningOfDocument, to: input.endOfDocument)
        input.insertText("42.5")
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(value, 20)
        XCTAssertEqual(writes, 0)
        XCTAssertTrue(buffer.hasPending)
        buffer.commitAll()
        XCTAssertEqual(value, 42.5)
        XCTAssertEqual(writes, 1)
        XCTAssertFalse(buffer.hasPending)
        input.insertText("1")
        try await Task.sleep(for: .milliseconds(100))
        buffer.discardAll()
        input.resignFirstResponder()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(value, 42.5)
        XCTAssertEqual(writes, 1)
    }

    @MainActor func testSearchDoesNotFilterWhileTypingAndCommitsOnReturn() async throws {
        var query = "", searches: [String] = []
        let field = CommittedSearchField("Search", text: Binding(get: { query }, set: { query = $0; searches.append($0) }))
            .submitLabel(.search)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: field)
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        try await Task.sleep(for: .milliseconds(100))
        let input = try XCTUnwrap(descendant(UITextField.self, in: window))
        XCTAssertTrue(input.becomeFirstResponder())
        for character in "bench press" { input.insertText(String(character)) }
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(searches.isEmpty)
        _ = input.delegate?.textFieldShouldReturn?(input)
        input.sendActions(for: .editingDidEndOnExit)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(searches, ["bench press"])
        input.resignFirstResponder()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(searches.count, 1)
    }

    @MainActor private func descendant<T: UIView>(_ type: T.Type, in root: UIView) -> T? {
        if let match = root as? T { return match }
        for child in root.subviews {
            if let match = descendant(type, in: child) { return match }
        }
        return nil
    }
}
