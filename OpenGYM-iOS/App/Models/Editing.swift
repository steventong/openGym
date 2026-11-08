import Foundation

/// Three-way field patch: unrelated remote changes survive. Conflicts require explicit local preference.
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
    static func apply(original:[String:Any], proposed:[String:Any], current:[String:Any], preferLocal: Bool = false) throws -> [String:Any] {
        var result = current
        for key in Set(original.keys).union(proposed.keys).subtracting(metadata) {
            let old = original[key], new = proposed[key], remote = current[key]
            if equal(old,new) || equal(new,remote) { continue }
            if let old = old as? [String:Any], let new = new as? [String:Any], let remote = remote as? [String:Any] {
                result[key] = try apply(original:old,proposed:new,current:remote,preferLocal:preferLocal)
            } else {
                guard preferLocal || equal(old,remote) else { throw APIError.response(409,String(localized: "THIS_ITEM_CHANGED_ON_ANOTHER_DEVICE_YOUR_LOCAL_EDITS_ARE_SAFE_COMPARE", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) }
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
    func exerciseSummary(resolve: (String) -> Exercise?) -> String {
        (raw["entries"] as? [[String: Any]] ?? []).map { entry in
            resolve(entry["id"] as? String ?? "")?.titleParts.primary
                ?? entry["n"] as? String
                ?? String(localized: "EXERCISE", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
        }.joined(separator: ", ")
    }
    var completedSetCount: Int {
        (raw["entries"] as? [[String:Any]] ?? []).reduce(0) { total, entry in
            total + (entry["sets"] as? [[String:Any]] ?? []).reduce(0) { count, row in
                if let sides = row["sides"] as? [String:[String:Any]] {
                    return count + [sides["L"],sides["R"]].compactMap { $0 }.filter { $0["done"] as? Bool == true }.count
                }
                return count + (row["done"] as? Bool == true ? 1 : 0)
            }
        }
    }
    static func key(_ raw:[String:Any]) -> String {
        if let id = raw["id"] as? String { return id }
        return "\(raw["d"] as? String ?? "undefined")|\(raw["start"].map { String(describing:$0) } ?? "undefined")"
    }
}
enum EditValidation {
    static func routine(_ raw:[String:Any]) throws {
        guard !(raw["name"] as? String ?? "").trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else { throw APIError.response(0,String(localized: "ENTER_A_ROUTINE_NAME", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) }
        guard let entries = raw["ex"] as? [[String:Any]], !entries.isEmpty else { throw APIError.response(0,String(localized: "ADD_AT_LEAST_ONE_EXERCISE_TO_THE_ROUTINE", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) }
        for row in entries where ordinaryConfig(row) {
            guard validNumber(row["sets"] ?? 3,1...30), validNumber(row["reps"] ?? 10,1...1000), validNumber(row["weight"] ?? 0,0...2000), validNumber(row["restSec"] ?? 90,0...900) else { throw APIError.response(0,String(localized: "CHECK_THE_RANGES_FOR_SETS_REPS_WEIGHT_AND_REST_TIME", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) }
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
