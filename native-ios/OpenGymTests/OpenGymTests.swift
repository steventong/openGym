import XCTest
@testable import OpenGym

final class StubProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int,[String:Any]))?
    override class func canInit(with request:URLRequest) -> Bool { true }
    override class func canonicalRequest(for request:URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status,body) = try Self.handler!(request)
            client?.urlProtocol(self,didReceive:HTTPURLResponse(url:request.url!,statusCode:status,httpVersion:nil,headerFields:["Content-Type":"application/json"])!,cacheStoragePolicy:.notAllowed)
            client?.urlProtocol(self,didLoad:try JSONSerialization.data(withJSONObject:body)); client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self,didFailWithError:error) }
    }
    override func stopLoading() {}
}
final class OpenGymTests: XCTestCase {
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
    @MainActor func store() throws -> GymStore {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [StubProtocol.self]
        let client = APIClient(address:try ServerAddress("https://test.invalid"),token:"test-only-token",session:URLSession(configuration:config))
        return GymStore(client:client,userID:"test")
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
    @MainActor func testConflictRetriesOnLatestStateAndPreservesUnknownFields() async throws {
        let store = try store(); var revision = 1; var writes = 0
        var server: [String:Any] = ["unit":"kg","routines":[],"workouts":[],"futureField":["keep":true],"_wid":"first"]
        StubProtocol.handler = { request in
            if request.httpMethod == "GET" { return (200,["state":server,"rev":revision]) }
            writes += 1
            // URLSession supplies streamed bodies to URLProtocol.
            let data: Data
            if let body = request.httpBody { data = body } else {
                let stream = request.httpBodyStream!; stream.open(); defer { stream.close() }
                var result = Data(); var buffer = [UInt8](repeating:0,count:4096)
                while stream.hasBytesAvailable { let n = stream.read(&buffer,maxLength:buffer.count); if n <= 0 { break }; result.append(buffer,count:n) }; data = result
            }
            let body = try JSONSerialization.jsonObject(with:data) as! [String:Any]
            XCTAssertEqual(request.value(forHTTPHeaderField:"Authorization"),"Bearer test-only-token")
            if writes == 1 {
                revision = 2; server["routines"] = [["id":"web-added","name":"网页的新计划","ex":[]]]; server["_wid"] = "second"
                return (409,["error":"conflict","state":server,"rev":revision])
            }
            XCTAssertEqual(body["baseRev"] as? Int,2); XCTAssertEqual(body["baseWid"] as? String,"second")
            server = body["state"] as! [String:Any]; revision = 3
            return (200,["ok":true,"rev":revision])
        }
        let ok = await store.addRoutine(name:"native-added",exerciseIDs:["0150"])
        XCTAssertTrue(ok); XCTAssertEqual(writes,2)
        XCTAssertEqual((server["routines"] as? [[String:Any]])?.count,2)
        XCTAssertEqual((server["futureField"] as? [String:Bool])?["keep"],true)
    }
    @MainActor func testFailedSaveKeepsCompletedDraft() async throws {
        let store = try store()
        StubProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        store.draft = TrainingDraft(name:"offline",entries:[TrainingEntry(id:"0150",name:"下拉",sets:[TrainingSet(done:true)])],unit:"kg")
        let id = store.draft?.id
        await store.finish()
        XCTAssertEqual(store.draft?.id,id); XCTAssertNotNil(store.error)
        store.draft = nil
    }
    func testCatalogueLoadsAllOriginalIDs() throws {
        let bundle = Bundle(for:GymStore.self)
        let entries = try JSONDecoder().decode([Exercise].self,from:Data(contentsOf:bundle.url(forResource:"catalogue",withExtension:"json")!))
        XCTAssertEqual(entries.count,5632); XCTAssertEqual(Set(entries.map(\.id)).count,entries.count)
        XCTAssertEqual(entries.first { $0.id == "0150" }?.name,"绳索杠高位下拉")
    }
}
