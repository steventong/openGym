import Foundation
extension TrainingDraft {
    var activeJSON: [String:Any] {
        if let webData, let raw = try? JSONSerialization.jsonObject(with:webData) as? [String:Any] { return raw }
        return ["id":id,"d":dayString(start),"start":start.timeIntervalSince1970*1000,"name":name,"routineId":routineID as Any? ?? NSNull(),"routineIds":routineIDs ?? routineID.map { [$0] } ?? [],"entries":entries.map { e -> [String:Any] in
            var raw:[String:Any] = ["id":e.id,"sets":e.sets.map(\.json),"target":["mode":"reps","restSec":e.restSec ?? 90]]
            if let rid = e.routineID { raw["rid"] = rid };return raw
        }]
    }
    var rawEntries: [[String:Any]] { activeJSON["entries"] as? [[String:Any]] ?? [] }
    mutating func setActive(_ raw:[String:Any]) throws {
        webData = try JSONSerialization.data(withJSONObject:raw)
        if let updated = raw["name"] as? String { name = updated }
    }
    static func fromWeb(_ raw:[String:Any],unit:String) throws -> TrainingDraft {
        var draft = TrainingDraft(routineID:raw["routineId"] as? String,name:raw["name"] as? String ?? "训练",start:Date(timeIntervalSince1970:number(raw["start"])/1000),entries:[],unit:unit,routineIDs:raw["routineIds"] as? [String])
        draft.id = raw["id"] as? String ?? UUID().uuidString;try draft.setActive(raw);return draft
    }
}
func rawCompleted(_ row:[String:Any]) -> Bool {
    if let sides = row["sides"] as? [String:[String:Any]] { return sides["L"]?["done"] as? Bool == true || sides["R"]?["done"] as? Bool == true }
    return row["done"] as? Bool == true
}
