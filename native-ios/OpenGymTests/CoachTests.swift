import XCTest
import SwiftUI
@testable import OpenGym

final class CoachTests: XCTestCase {
    override func tearDown() { StubProtocol.handler = nil; super.tearDown() }
    private var state: [String: Any] {
        ["unit":"kg","routines":[["id":"r1","name":"力量","ex":[["id":"0289","sets":3,"reps":10,"weight":20]]]],"week":["1":"r1"],"dayPlan":["2099-01-01":"r1"],"workouts":[["id":"w1","d":"2026-10-20","start":1000,"entries":[]]],"futureField":["keep":true]]
    }
    private var plan: [String: Any] {
        ["id":"p1","kind":"create","bundle":["opengym_plan":1,"name":"新计划","routines":[["id":"new","name":"全身","ex":[["id":"0289","sets":4,"reps":8,"why":"逐渐增加训练量"]]]],"week":["2":"new"]]]
    }
    @MainActor private func info(_ state: [String: Any], _ proposal: [String: Any]? = nil) throws -> [String: Any] {
        var p: [String: Any] = ["state":state];p["proposal"] = proposal
        return try XCTUnwrap(WebRules.shared.call("coachInfo",payload:p) as? [String: Any])
    }
    @MainActor private func mutate(_ state: [String: Any],_ action: String,_ extra: [String: Any] = [:]) throws -> [String: Any] {
        var p = extra;p["state"] = state;p["action"] = action
        let result = try WebRules.shared.call("coachMutation",payload:p)
        return try XCTUnwrap(result as? [String: Any])
    }
    @MainActor func testConsentMatchesWebVersionAndPreservesOtherFields() throws {
        let s = try mutate(state,"consent",["operationId":"agree"])
        XCTAssertTrue(try info(s)["consent"] as? Bool == true)
        XCTAssertEqual(number(s.coachObject("coach").coachObject("consent")["version"]),2)
        XCTAssertTrue(RecordPatch.equal(s["futureField"],state["futureField"]))
        var old = s;old["coach"] = ["consent":["agreedAt":"2026-01-01","version":1]]
        XCTAssertFalse(try info(old)["consent"] as? Bool == true)
    }
    @MainActor func testPlanImportIsIdempotentAndUndoPreservesWorkouts() throws {
        let hash = try info(state).coachText("planHash")
        let applied = try mutate(state,"resolve",["proposal":plan,"planHash":hash,"schedule":true,"operationId":"resolve-p1"])
        XCTAssertEqual(applied.coachObjects("routines").count,2)
        XCTAssertNil(applied.coachObject("week")["1"])
        XCTAssertNotNil(applied.coachObject("week")["2"])
        XCTAssertNil(applied.coachObject("dayPlan")["2099-01-01"])
        XCTAssertTrue(RecordPatch.equal(applied["workouts"],state["workouts"]))
        let retried = try mutate(applied,"resolve",["proposal":plan,"planHash":hash,"schedule":true,"operationId":"another-attempt"])
        XCTAssertEqual(retried.coachObjects("routines").count,2)
        XCTAssertEqual(retried.coachObject("coach").coachObjects("log").count,1)
        let reverted = try mutate(applied,"revert",["planHash":info(applied).coachText("planHash"),"operationId":"undo-p1"])
        XCTAssertTrue(RecordPatch.equal(reverted["routines"],state["routines"]))
        XCTAssertTrue(RecordPatch.equal(reverted["week"],state["week"]))
        XCTAssertTrue(RecordPatch.equal(reverted["dayPlan"],state["dayPlan"]))
        XCTAssertTrue(RecordPatch.equal(reverted["workouts"],state["workouts"]))
        let twice = try mutate(reverted,"revert",["planHash":hash,"operationId":"undo-p1"])
        XCTAssertEqual(twice.coachObject("coach").coachObjects("log").count,2)
    }
    @MainActor func testKeepScheduleAndRefuseChangedPlanOrExpiredProposal() throws {
        let hash = try info(state).coachText("planHash")
        let s = try mutate(state,"resolve",["proposal":plan,"planHash":hash,"schedule":false])
        XCTAssertTrue(RecordPatch.equal(s["week"],state["week"]))
        XCTAssertTrue(RecordPatch.equal(s["dayPlan"],state["dayPlan"]))
        var changed = state;changed["week"] = ["4":"r1"]
        XCTAssertThrowsError(try mutate(changed,"resolve",["proposal":plan,"planHash":hash,"schedule":true]))
        var expired = plan;expired["expiresAt"] = 1
        XCTAssertThrowsError(try mutate(state,"resolve",["proposal":expired,"planHash":hash]))
    }
    @MainActor func testReviewSelectionAndStaleProtection() throws {
        let proposal: [String: Any] = ["id":"review","kind":"review","planHash":try info(state).coachText("planHash"),"changes":[
            ["id":"sets","type":"sets","target":["routineId":"r1","exId":"0289"],"before":3,"after":4,"why":"增加训练量"],
            ["id":"reps","type":"reps","target":["routineId":"r1","exId":"0289"],"before":10,"after":8,"why":"侧重力量"]]]
        let s = try mutate(state,"resolve",["proposal":proposal,"accepted":["sets"]])
        let ex = s.coachObjects("routines")[0].coachObjects("ex")[0]
        XCTAssertEqual(number(ex["sets"]),4);XCTAssertEqual(number(ex["reps"]),10)
        let decisions = s.coachObject("coach").coachObjects("log")[0].coachObjects("decisions")
        XCTAssertEqual(decisions.map{$0.coachText("status")},["accepted","rejected"])
        var changed = state; changed["routines"] = [["id":"r1","name":"力量","ex":[["id":"0289","sets":5,"reps":10]]]]
        XCTAssertThrowsError(try mutate(changed,"resolve",["proposal":proposal,"accepted":["sets"]]))
        XCTAssertEqual(try info(changed,proposal).coachObject("proposal").coachObjects("changes")[0].coachText("status"),"stale")
    }
    @MainActor func testDismissalDebriefAndOutcomeDoNotChangeTraining() throws {
        let declined = try mutate(state,"resolve",["proposal":plan,"dismissed":true])
        XCTAssertTrue(RecordPatch.equal(declined["routines"],state["routines"]))
        XCTAssertTrue(declined.coachObject("coach").coachObjects("log")[0]["dismissed"] as? Bool == true)
        let debrief: [String: Any] = ["id":"debrief","kind":"debrief","score":8,"summary":"很好","highlights":["动作稳定"],"workout":["id":"w1"]]
        let s = try mutate(declined,"resolve",["proposal":debrief])
        XCTAssertTrue(RecordPatch.equal(s["workouts"],state["workouts"]))
        XCTAssertEqual(s.coachObject("coach").coachObjects("log").last?.coachText("kind"),"debrief")
        let outcome: [String: Any] = ["last":["id":"failed","outcome":"failed"],"text":"失败"]
        let failed = try mutate(s,"outcome",outcome)
        let retry = try mutate(failed,"outcome",outcome)
        XCTAssertEqual(retry.coachObject("coach").coachObjects("chat").filter{$0.coachText("id")=="job-failed"}.count,1)
    }
    @MainActor private func store() throws -> GymStore {
        let config = URLSessionConfiguration.ephemeral;config.protocolClasses = [StubProtocol.self]
        let client = APIClient(address:try ServerAddress("https://coach.test"),token:"qa",session:URLSession(configuration:config))
        return GymStore(client:client,userID:"coach-test",storage:LocalTrainingStorage(root:FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)))
    }
    private func body(_ request: URLRequest) throws -> [String: Any] {
        if let data = request.httpBody { return try JSONSerialization.jsonObject(with:data) as! [String: Any] }
        let stream = try XCTUnwrap(request.httpBodyStream);stream.open();defer{stream.close()}
        var data = Data(),buffer = [UInt8](repeating:0,count:4096)
        while stream.hasBytesAvailable { let n=stream.read(&buffer,maxLength:buffer.count);if n<=0{break};data.append(buffer,count:n) }
        return try JSONSerialization.jsonObject(with:data) as! [String: Any]
    }
    @MainActor func testFailedStateWriteNeverResolvesAndRetryDoesNotDuplicatePlan() async throws {
        let store = try store();store.state = state
        let session = CoachSession(store:store);session.status = ["pending":plan]
        var server = state, writes=0, resolves=0, loseResponse=true
        let p = plan
        StubProtocol.handler = { request in
            switch request.url!.path {
            case "/api/data":
                if request.httpMethod == "PUT" {
                    writes += 1;server = try self.body(request).coachObject("state")
                    if loseResponse { throw URLError(.networkConnectionLost) }
                    return (200,["ok":true])
                }
                return (200,["state":server,"rev":writes])
            case "/api/coach/status":return (200,["pending":p])
            case "/api/coach/pending/resolve":resolves += 1;return (200,["ok":true])
            case "/api/config":return (200,["coach":["enabled":false]])
            default:return (200,[:])
            }
        }
        await session.resolve(plan)
        XCTAssertEqual(resolves,0);XCTAssertNotNil(session.error);XCTAssertEqual(writes,1)
        loseResponse=false
        await session.resolve(plan)
        XCTAssertEqual(resolves,1);XCTAssertEqual(server.coachObjects("routines").count,2);XCTAssertEqual(writes,1)
    }
    @MainActor func testConflictRebasesAndDoesNotOverwriteNewTraining() async throws {
        let store = try store(), session = CoachSession(store:store)
        var server=state, attempts=0
        StubProtocol.handler = { request in
            if request.httpMethod == "GET" { return (200,["state":server,"rev":attempts]) }
            attempts += 1
            if attempts == 1 { server["newField"]="remote";return (409,["error":"conflict"]) }
            server = try self.body(request).coachObject("state");return (200,["ok":true])
        }
        try await session.change("consent",operationID:"consent-retry")
        XCTAssertEqual(attempts,2);XCTAssertEqual(server.coachText("newField"),"remote")
        XCTAssertTrue(RecordPatch.equal(server["workouts"],state["workouts"]))
    }
    @MainActor func testQuickJobFailureIsRecordedOnceWithoutSeeingRunningState() async throws {
        let store = try store(),session = CoachSession(store:store)
        var server=state
        StubProtocol.handler = { request in
            switch request.url!.path {
            case "/api/config":return (200,["coach":["enabled":true]])
            case "/api/data":
                if request.httpMethod=="PUT"{server=try self.body(request).coachObject("state");return (200,["ok":true])}
                return (200,["state":server,"rev":1])
            case "/api/coach/status":return (200,["last":["id":"fast-fail","outcome":"failed","errorClass":"auth"]])
            default:return (200,[:])
            }
        }
        await session.refresh();await session.refresh()
        let chat=server.coachObject("coach").coachObjects("chat")
        XCTAssertEqual(chat.count,1);XCTAssertEqual(chat[0].coachText("kind"),"error")
        XCTAssertTrue(chat[0].coachText("text").contains("认证"))
    }
    @MainActor func testAccountSwitchInvalidatesOldCoachWithoutSendingRequests() async throws {
        let store = try store(), session = CoachSession(store:store)
        store.userID = "different-account"
        var requests = 0
        StubProtocol.handler = { _ in requests += 1;return (200,[:]) }
        await session.refresh()
        let result = await session.agree()
        XCTAssertFalse(result);XCTAssertEqual(requests,0);XCTAssertFalse(session.valid)
    }
    @MainActor func testProviderRefusalUsesChineseMessageAndExistingPairedToken() async throws {
        let store = try store()
        StubProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField:"Authorization"),"Bearer qa")
            return (429,["code":"cap","error":"daily limit reached"])
        }
        do { _ = try await store.coachRequest("api/coach/review",method:"POST",body:["note":"QA"]);XCTFail("Expected refusal") }
        catch { XCTAssertTrue(error.localizedDescription.contains("上限")) }
    }

    @MainActor func testCoachWaitsForBackgroundSyncInsteadOfShowingSpuriousError() async throws {
        let store = try store(), session = CoachSession(store:store)
        let source = state
        store.syncing = true
        StubProtocol.handler = { request in
            switch request.url!.path {
            case "/api/config":return (200,["coach":["enabled":true]])
            case "/api/data":return (200,["state":source,"rev":1])
            default:return (200,[:])
            }
        }
        Task { try? await Task.sleep(for:.milliseconds(50));store.syncing = false }
        await session.refresh()
        XCTAssertTrue(session.loaded);XCTAssertNil(session.error)
        XCTAssertEqual(store.routines.count,1)
    }

    @MainActor func testSmallScreenSnapshots() async throws {
        let store = try store();store.state = state;store.userName = "Coach QA"
        let session = CoachSession(store:store)
        let proposal: [String: Any] = ["id":"visual","kind":"review","summary":"建议逐步增加训练量，同时保持动作质量。","changes":[["id":"sets","type":"sets","target":["routineId":"r1","exId":"0289"],"before":3,"after":4,"why":"当前完成稳定，适当增加一组。","routineName":"QA 原有训练"]],"notes":["根据恢复情况调整。"]]
        try await snapshot(PlanView().environment(store),name:"coach-small-plan",size:CGSize(width:375,height:667))
        try await snapshot(ScrollView { CoachProposalView(session:session,proposal:proposal).padding(16) }.environment(store),name:"coach-small-review",size:CGSize(width:375,height:850))
        try await snapshot(SettingsView().environment(store),name:"coach-small-settings",size:CGSize(width:375,height:900))
    }
    @MainActor private func snapshot<V: View>(_ view: V,name: String,size: CGSize) async throws {
        let controller = UIHostingController(rootView:view.preferredColorScheme(.dark).tint(GymTheme.green))
        let window = UIWindow(frame:CGRect(origin:.zero,size:size));window.rootViewController = controller
        window.makeKeyAndVisible();controller.view.frame=window.bounds;controller.view.layoutIfNeeded()
        try await Task.sleep(for:.milliseconds(250))
        let image = UIGraphicsImageRenderer(size:size).image { _ in controller.view.drawHierarchy(in:window.bounds,afterScreenUpdates:true) }
        let data = try XCTUnwrap(image.pngData());XCTAssertGreaterThan(data.count,1000)
        let attachment = XCTAttachment(image:image);attachment.name=name;attachment.lifetime = .keepAlways;add(attachment)
        try data.write(to:FileManager.default.temporaryDirectory.appendingPathComponent(name+".png"))
        window.isHidden=true
    }

}
