import Foundation

/// Retain literal keystrokes (including an empty field or trailing decimal separator) locally.
/// Only valid numbers enter the calculation model; submission rejects unfinished fields.
enum TrainingInput {
    static let key = "_nativeInputs"
    // Values remain in the profile unit. This only records the unit used at the equipment.
    static let weightUnitKey = "weightInputUnit"
    static func speedUnit(_ state: [String: Any]) -> String {
        if let unit = state["speedUnit"] as? String, ["mph", "kmh"].contains(unit) { return unit }
        return state["unit"] as? String == "lb" ? "mph" : "kmh"
    }
    static func speedDisplay(_ value: Double, state: [String: Any]) -> Double {
        speedUnit(state) == "mph" ? (value / 1.609344 * 100).rounded() / 100 : value
    }
    static func weightUnit(_ row: [String: Any], fallback: String) -> String {
        let unit = row[weightUnitKey] as? String
        return unit == "kg" || unit == "lb" ? unit! : fallback
    }
    static func weight(_ value: Double, from: String, to: String) -> Double {
        guard from != to else { return value }
        return to == "lb" ? value / 0.45359237 : value * 0.45359237
    }
    static func weightDisplay(_ row: [String: Any], path: String, value: Double, storedUnit: String) -> String {
        let converted = weight(value, from: storedUnit, to: weightUnit(row, fallback: storedUnit))
        return display(row, path: path, number: (converted * 100).rounded() / 100)
    }
    static func validateWeightSwitch(_ row: [String: Any]) throws {
        let inputs = row[key] as? [String: String] ?? [:]
        guard !inputs.contains(where: { $0.key.hasSuffix(".w") && !valid($0.value, path: $0.key) }) else {
            throw APIError.response(0, "请先填完重量再切换单位，原输入已保留。")
        }
    }
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
        case "incline": return n <= 40
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
        if action["action"] as? String == "weightUnit", let unit = action["unit"] as? String, ["kg", "lb"].contains(unit) {
            try validateWeightSwitch(row)
            raw[weightUnitKey] = unit
            raw[key] = inputs.filter { !$0.key.hasSuffix(".w") }
            return raw
        }
        if action["action"] as? String == "input", let path = action["path"] as? String, let text = action["text"] as? String {
            inputs[path] = text; raw[key] = inputs
            operation = action["operation"] as? [String: Any] ?? [:]
            if path.hasSuffix(".incline"), text.trimmingCharacters(in: .whitespaces).isEmpty {
                inputs.removeValue(forKey: path); operation["value"] = NSNull()
            } else {
                guard valid(text,path:path), let number = value(text) else { return raw }
                let storedUnit = state["unit"] as? String ?? "kg"
                var value = path.hasSuffix(".w") ? weight(number, from: weightUnit(row, fallback: storedUnit), to: storedUnit) : number
                if path.hasSuffix(".speed"), speedUnit(state) == "mph" { value = (number * 1.609344 * 100).rounded() / 100 }
                if let field = action["patchKey"] as? String { operation["patch"] = [field: value] }
                else { operation["value"] = value }
            }
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
        if operation["key"] as? String == "rir" || operation["key"] as? String == "rpe" {
            let other = operation["key"] as? String == "rir" ? "rpe" : "rir"
            inputs.removeValue(forKey: "\(operation["side"] as? String ?? "both").\(other)")
        }
        operation["row"] = clean(raw); operation["target"] = target; operation["state"] = state
        operation["editing"] = editing; operation["now"] = Date().timeIntervalSince1970 * 1000
        var result = try WebRules.shared.call("editAdvancedRow", payload: operation) as! [String: Any]
        if !inputs.isEmpty { result[key] = inputs }
        return result
    }
    @MainActor static func steppedText(_ text: String, path: String, direction: Int, target: [String: Any], state: [String: Any], unit: String) -> String? {
        guard valid(text, path: path), let value = value(text), let field = path.split(separator: ".").last else { return nil }
        let side = path.split(separator: ".").contains(where: { $0 == "L" || $0 == "R" })
        guard let next = try? WebRules.shared.call("stepTrainingValue", payload: ["value": value, "key": String(field), "direction": direction, "target": target, "state": state, "unit": unit, "side": side]) as? [String: Any], let number = next["value"] as? NSNumber else { return nil }
        let result = String(format: "%.8g", number.doubleValue)
        return valid(result, path: path) ? result : nil
    }
}
