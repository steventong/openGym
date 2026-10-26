import Foundation

/// Three-way field patch: unrelated remote changes survive; edits to the same value are rejected.
enum RecordPatch {
    static let metadata: Set<String> = ["_ts","_f","_u"]
    static func clean(_ value: Any) -> Any {
        if let d = value as? [String:Any] { return d.filter { !metadata.contains($0.key) }.mapValues(clean) }
        if let a = value as? [Any] { return a.map(clean) }
        return value
    }
    static func equal(_ a: Any?,_ b: Any?) -> Bool {
        guard let a else { return b == nil }; guard let b else { return false }
        return NSDictionary(dictionary:["v":clean(a)]).isEqual(to:["v":clean(b)])
    }
    static func apply(original:[String:Any], proposed:[String:Any], current:[String:Any]) throws -> [String:Any] {
        var result = current
        for key in Set(original.keys).union(proposed.keys).subtracting(metadata) {
            let old = original[key], new = proposed[key], remote = current[key]
            if equal(old,new) || equal(new,remote) { continue }
            if let old = old as? [String:Any], let new = new as? [String:Any], let remote = remote as? [String:Any] {
                result[key] = try apply(original:old,proposed:new,current:remote)
            } else {
                guard equal(old,remote) else { throw APIError.response(409,"这项内容已在其他设备修改。你的本机编辑已保留，请核对两个版本后再提交。") }
                result[key] = new
            }
        }
        return result
    }
}
struct RawRow: Identifiable {
    var id = UUID()
    var raw: [String:Any]
}
struct WorkoutRecord: Identifiable {
    let raw: [String:Any]
    var id: String { Self.key(raw) }
    static func key(_ raw:[String:Any]) -> String {
        if let id = raw["id"] as? String { return id }
        return "\(raw["d"] as? String ?? "undefined")|\(raw["start"].map { String(describing:$0) } ?? "undefined")"
    }
}
enum EditValidation {
    static func routine(_ raw:[String:Any]) throws {
        guard !(raw["name"] as? String ?? "").trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else { throw APIError.response(0,"请输入计划名称。") }
        guard let entries = raw["ex"] as? [[String:Any]], !entries.isEmpty else { throw APIError.response(0,"计划至少需要一个动作。") }
        for row in entries where ordinaryConfig(row) {
            guard validNumber(row["sets"] ?? 3,1...30), validNumber(row["reps"] ?? 10,1...1000), validNumber(row["weight"] ?? 0,0...2000), validNumber(row["restSec"] ?? 90,0...900) else { throw APIError.response(0,"请检查组数、次数、重量和休息时间的范围。") }
        }
    }
    static func validNumber(_ value:Any?,_ range:ClosedRange<Double>) -> Bool {
        guard let n = value as? NSNumber else { return false }; return n.doubleValue.isFinite && range.contains(n.doubleValue)
    }
    static func ordinaryConfig(_ raw:[String:Any]) -> Bool {
        (raw["mode"] as? String ?? "reps") == "reps" && raw["pyramid"] == nil && raw["intensifier"] == nil && raw["side"] == nil && raw["sec"] == nil && raw["min"] == nil && raw["speed"] == nil
    }
    static func ordinarySet(_ raw:[String:Any], entry:[String:Any]) -> Bool {
        let target = entry["target"] as? [String:Any] ?? entry
        return (raw["mode"] as? String ?? target["mode"] as? String ?? "reps") == "reps" && raw["sec"] == nil && raw["min"] == nil && raw["sides"] == nil && raw["drops"] == nil && raw["clusters"] == nil
    }
}
