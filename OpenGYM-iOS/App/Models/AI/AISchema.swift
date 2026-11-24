import Foundation

/// 工具参数的结构：既生成发给模型的 JSON Schema，也校验模型给出的参数，避免两处规则不一致。
indirect enum AISchema {
    struct Field {
        let name: String
        let schema: AISchema
        var required = false
    }
    case string(String, options: [String] = [], limit: Int = 2000)
    /// `yyyy-MM-dd`
    case date(String)
    case number(String, ClosedRange<Double>)
    case integer(String, ClosedRange<Int>)
    case boolean(String)
    case array(String, of: AISchema, limit: Int = 200)
    case object(String, [Field])

    var json: [String: Any] {
        switch self {
        case let .string(description, options, _):
            var result: [String: Any] = ["type": "string", "description": description]
            if !options.isEmpty { result["enum"] = options }
            return result
        case let .date(description): return ["type": "string", "description": description + " Format YYYY-MM-DD."]
        case let .number(description, range):
            return ["type": "number", "description": description + " Range \(Self.text(range.lowerBound))-\(Self.text(range.upperBound))."]
        case let .integer(description, range):
            return ["type": "integer", "description": description + " Range \(range.lowerBound)-\(range.upperBound)."]
        case let .boolean(description): return ["type": "boolean", "description": description]
        case let .array(description, item, _): return ["type": "array", "description": description, "items": item.json]
        case let .object(description, fields):
            var result: [String: Any] = ["type": "object", "additionalProperties": false, "required": fields.filter(\.required).map(\.name),
                "properties": Dictionary(uniqueKeysWithValues: fields.map { ($0.name, $0.schema.json) })]
            if !description.isEmpty { result["description"] = description }
            return result
        }
    }

    /// 返回校验后的值。可选字段给出 null 视为没有填写。
    func validated(_ value: Any, path: String = "") throws -> Any {
        let place = path.isEmpty ? "arguments" : path
        switch self {
        case let .string(_, options, limit):
            guard let text = value as? String else { throw AIToolError("\(place) must be a string.") }
            guard text.count <= limit else { throw AIToolError("\(place) must be at most \(limit) characters.") }
            guard options.isEmpty || options.contains(text) else { throw AIToolError("\(place) must be one of: \(options.joined(separator: ", ")).") }
            return text
        case .date:
            guard let text = value as? String, let date = dateFromDay(text), dayString(date) == text else { throw AIToolError("\(place) must be a date formatted YYYY-MM-DD.") }
            return text
        case let .number(_, range):
            guard let number = Self.numeric(value), range.contains(number) else { throw AIToolError("\(place) must be a number from \(Self.text(range.lowerBound)) to \(Self.text(range.upperBound)).") }
            return number
        case let .integer(_, range):
            guard let number = Self.numeric(value), number.rounded() == number, Double(range.lowerBound)...Double(range.upperBound) ~= number else {
                throw AIToolError("\(place) must be a whole number from \(range.lowerBound) to \(range.upperBound).")
            }
            return Int(number)
        case .boolean:
            guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { throw AIToolError("\(place) must be true or false.") }
            return number.boolValue
        case let .array(_, item, limit):
            guard let list = value as? [Any] else { throw AIToolError("\(place) must be an array.") }
            guard list.count <= limit else { throw AIToolError("\(place) must have at most \(limit) items.") }
            return try list.enumerated().map { try item.validated($1, path: "\(place)[\($0)]") }
        case let .object(_, fields):
            guard let map = value as? [String: Any] else { throw AIToolError("\(place) must be an object.") }
            let known = Set(fields.map(\.name))
            if let unknown = map.keys.sorted().first(where: { !known.contains($0) }) {
                throw AIToolError("\(place) has an unknown field \"\(unknown)\". Allowed: \(fields.map(\.name).joined(separator: ", ")).")
            }
            var result: [String: Any] = [:]
            for field in fields {
                guard let raw = map[field.name], !(raw is NSNull) else {
                    if field.required { throw AIToolError("\(place) is missing \"\(field.name)\".") }
                    continue
                }
                result[field.name] = try field.schema.validated(raw, path: path.isEmpty ? field.name : "\(path).\(field.name)")
            }
            return result
        }
    }

    private static func numeric(_ value: Any) -> Double? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite else { return nil }
        return number.doubleValue
    }
    private static func text(_ value: Double) -> String { String(format: "%g", value) }
}

/// 返回给模型的工具错误，用英文说明如何改正。
struct AIToolError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
