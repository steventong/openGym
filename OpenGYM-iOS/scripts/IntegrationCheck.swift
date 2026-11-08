// Execute the same native networking/store code against the running local server.
// Only the isolated simulator test account is accepted; never prints credentials.
import Foundation
@main struct IntegrationCheck {
    @MainActor static func main() async throws {
        let file = URL(fileURLWithPath:CommandLine.arguments[1])
        let session = try JSONSerialization.jsonObject(with:Data(contentsOf:file)) as! [String:Any]
        let user = session["user"] as! [String:Any]
        guard user["name"] as? String == "iOS 模拟器测试", let token = session["token"] as? String, let uid = user["id"] as? String else { fatalError("Only the isolated test account is allowed") }
        let api = APIClient(address:try ServerAddress("http://localhost:8080"),token:token)
        let before = try await api.request("api/data")
        let old = before["state"] as! [String:Any]
        let store = GymStore(client:api,userID:uid)
        store.draft = TrainingDraft(name:"原生接口验证 · 模拟器测试",entries:[TrainingEntry(id:"0150",name:"绳索杠高位下拉",sets:[TrainingSet(weight:20,reps:10,done:true,completedAt:Date().timeIntervalSince1970 * 1000)])],unit:"kg")
        let id = store.draft!.id
        await store.finish()
        guard store.draft == nil else { fatalError(store.error ?? "Save failed") }
        let after = try await api.request("api/data")
        let state = after["state"] as! [String:Any]
        let workout = (state["workouts"] as! [[String:Any]]).first { $0["id"] as? String == id }
        guard workout != nil, (state["routines"] as? [[String:Any]])?.count == (old["routines"] as? [[String:Any]])?.count,
              (state["nativeTestSentinel"] as? [String:String])?["keep"] == "unknown fields must survive native writes" else { fatalError("State parity check failed") }
        print("PASS: native GymStore.finish → PUT /api/data → GET /api/data, workout persisted, existing routines and unknown fields preserved, draft cleared only after successful save.")
    }
}
