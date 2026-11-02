import Foundation
extension TrainingDraft {
    var activeJSON: [String:Any] {
        if let webData, let raw = try? JSONSerialization.jsonObject(with:webData) as? [String:Any] { return identified(raw, legacy: true) }
        return identified(["id":id,"d":dayString(start),"start":start.timeIntervalSince1970*1000,"name":name,"routineId":routineID as Any? ?? NSNull(),"routineIds":routineIDs ?? routineID.map { [$0] } ?? [],"entries":entries.map { e -> [String:Any] in
            var raw:[String:Any] = ["id":e.id,"sets":e.sets.map(\.json),"target":["mode":"reps","restSec":e.restSec ?? 90]]
            if let rid = e.routineID { raw["rid"] = rid };return raw
        }], legacy: true)
    }
    var rawEntries: [[String:Any]] { activeJSON["entries"] as? [[String:Any]] ?? [] }
    mutating func setActive(_ raw:[String:Any]) throws {
        webData = try JSONSerialization.data(withJSONObject: identified(raw, legacy: false))
        if let updated = raw["name"] as? String { name = updated }
    }
    // Native-only identities survive edits, moves and undo. Copied rows must get
    // new identities even when the web copy helper preserves unknown fields.
    // Legacy reads are deterministic until the next write persists the IDs.
    private func identified(_ source: [String: Any], legacy: Bool) -> [String: Any] {
        var raw = source
        var entries = raw["entries"] as? [[String: Any]] ?? []
        var entryIDs = Set<String>()
        func identity(_ value: Any?, fallback: String, used: inout Set<String>) -> String {
            if let value = value as? String, !value.isEmpty, used.insert(value).inserted { return value }
            var candidate = legacy ? fallback : UUID().uuidString
            while !used.insert(candidate).inserted { candidate += "-new" }
            return candidate
        }
        for index in entries.indices {
            let entryID = identity(entries[index]["nativeViewID"], fallback: "\(id)-entry-\(index)", used: &entryIDs)
            entries[index]["nativeViewID"] = entryID
            var rows = entries[index]["sets"] as? [[String: Any]] ?? []
            var rowIDs = Set<String>()
            for row in rows.indices {
                rows[row]["nativeViewID"] = identity(rows[row]["nativeViewID"], fallback: "\(entryID)-set-\(row)", used: &rowIDs)
            }
            entries[index]["sets"] = rows
        }
        raw["entries"] = entries
        // Older drafts may contain an undo snapshot without view IDs. Migrate
        // its matching expectation too, so merely reading the draft cannot
        // invalidate an otherwise valid undo operation.
        if var undo = raw["nativeSetUndo"] as? [String: Any], let expected = undo["expected"],
           RecordPatch.equal(expected, source["entries"]) {
            undo["expected"] = entries
            raw["nativeSetUndo"] = undo
        }
        return raw
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
