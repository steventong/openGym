import Foundation

/// Retain literal keystrokes (including an empty field or trailing decimal separator) locally.
/// Only valid numbers enter the calculation model; submission rejects unfinished fields.
enum TrainingInput {
    static let key = "_nativeInputs"
    static func value(_ text: String) -> Double? {
        let normalized = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard !normalized.isEmpty, let n = Double(normalized), n.isFinite, n >= 0 else { return nil }
        return n
    }
    static func display(_ row: [String: Any], path: String, number: Double) -> String {
        (row[key] as? [String: String])?[path] ?? String(format: "%.8g", number)
    }
    static func valid(_ text: String, path: String) -> Bool {
        guard let n = value(text) else { return false }
        switch path.split(separator: ".").last {
        case "w": return n <= 2000
        case "r": return n <= 1000
        case "rpe", "rir": return n <= 10
        case "sec": return n <= 86400
        case "min": return n <= 1440
        default: return true
        }
    }
    static func validate(_ object: Any) throws {
        if let map = object as? [String: Any] {
            if let inputs = map[key] as? [String: String], inputs.contains(where: { !valid($0.value,path:$0.key) }) {
                throw APIError.response(0, "还有未填完的数字，请检查重量、次数或时长。原输入已保留。")
            }
            for (k, v) in map where k != key { try validate(v) }
        } else if let list = object as? [Any] { for v in list { try validate(v) } }
    }
    static func clean(_ object: Any) -> Any {
        if let map = object as? [String: Any] { return map.filter { $0.key != key && !$0.key.hasPrefix("native") }.mapValues(clean) }
        if let list = object as? [Any] { return list.map(clean) }
        return object
    }
    @MainActor static func edit(row: [String: Any], action: [String: Any], target: [String: Any], state: [String: Any], editing: Bool) throws -> [String: Any] {
        var raw = row, operation = action, inputs = row[key] as? [String: String] ?? [:]
        if action["action"] as? String == "input", let path = action["path"] as? String, let text = action["text"] as? String {
            inputs[path] = text; raw[key] = inputs
            guard valid(text,path:path), let number = value(text) else { return raw }
            operation = action["operation"] as? [String: Any] ?? [:]
            if let field = action["patchKey"] as? String { operation["patch"] = [field: number] }
            else { operation["value"] = number }
        } else {
            let type = action["action"] as? String ?? ""
            if type == "toggle" { try validate(row) }
            if type == "dropRemove" || type == "clusterRemove", let index = action["index"] as? Int {
                let prefix = type == "dropRemove" ? "drop" : "cluster"
                var shifted: [String: String] = [:]
                for (path, text) in inputs {
                    var bits = path.split(separator: ".").map(String.init)
                    if bits.count >= 3, bits[0] == prefix, let i = Int(bits[2]) {
                        if i == index { continue }; if i > index { bits[2] = String(i - 1) }
                    }
                    shifted[bits.joined(separator: ".")] = text
                }
                inputs = shifted
            }
            if type == "field", let field = action["key"] as? String {
                inputs.removeValue(forKey: "\(action["side"] as? String ?? "both").\(field)")
            }
        }
        operation["row"] = clean(raw); operation["target"] = target; operation["state"] = state
        operation["editing"] = editing; operation["now"] = Date().timeIntervalSince1970 * 1000
        var result = try WebRules.shared.call("editAdvancedRow", payload: operation) as! [String: Any]
        if !inputs.isEmpty { result[key] = inputs }
        return result
    }
}
