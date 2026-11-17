import Foundation

/// 规则引擎和页面使用的是一整份资料文档；存储时拆成逐条记录，iCloud 才能按记录合并。
/// 这里只做纯数据的拆分与拼回，不接触 Core Data。
enum StateDocument {
    /// 文档中一个按记录保存的数组。
    struct RecordSet {
        let documentKey: String
        let entity: String
        let identityAttribute: String
        /// 同一实体内的分区，目前只有本地动作区分“自建／已编辑”与“动作库副本”。
        var origin: String? = nil
        /// 数组顺序有意义时按 position 保存；否则按内容排序。
        var keepsOrder = false
        /// 没有记录时文档里是否仍保留空数组。
        var alwaysPresent = true
        let identity: ([String: Any]) -> String?
        var nameField: String? = nil
    }

    struct Record {
        let id: String
        let payload: [String: Any]
        let position: Int
    }

    static let customExercises = "customEx"
    static let exerciseCopies = "exerciseCopies"

    static let recordSets: [RecordSet] = [
        RecordSet(documentKey: "workouts", entity: "StoredWorkout", identityAttribute: "id",
                  identity: { WorkoutRecord.key($0) }),
        RecordSet(documentKey: "routines", entity: "StoredRoutine", identityAttribute: "id", keepsOrder: true,
                  identity: { $0["id"] as? String }, nameField: "name"),
        RecordSet(documentKey: "bodyweight", entity: "StoredBodyWeight", identityAttribute: "day",
                  identity: { $0["d"] as? String }),
        RecordSet(documentKey: "measurements", entity: "StoredMeasurement", identityAttribute: "day", alwaysPresent: false,
                  identity: { $0["d"] as? String }),
        RecordSet(documentKey: customExercises, entity: "StoredExercise", identityAttribute: "id", origin: "custom", keepsOrder: true,
                  identity: { $0["id"] as? String }, nameField: "n"),
        RecordSet(documentKey: exerciseCopies, entity: "StoredExercise", identityAttribute: "id", origin: "catalogue", alwaysPresent: false,
                  identity: { $0["id"] as? String }, nameField: "name"),
    ]
    private static let recordKeys = Set(recordSets.map(\.documentKey))

    /// 其余顶层字段各存一条设置记录。
    static func settings(of document: [String: Any]) -> [String: Any] {
        document.filter { !recordKeys.contains($0.key) }
    }

    /// 取出一个数组里可识别的记录。缺少标识的条目 App 本来就读不到，不保存；标识重复时保留后出现的一条。
    static func records(of set: RecordSet, in document: [String: Any]) -> [Record] {
        var result: [Record] = [], positions: [String: Int] = [:]
        for case let payload as [String: Any] in document[set.documentKey] as? [Any] ?? [] {
            guard let id = set.identity(payload), !id.isEmpty else { continue }
            if let existing = positions[id] { result[existing] = Record(id: id, payload: payload, position: existing) }
            else { positions[id] = result.count; result.append(Record(id: id, payload: payload, position: result.count)) }
        }
        return set.keepsOrder ? result : sorted(result, in: set)
    }

    /// 无固定顺序的数组沿用原有约定：训练按日期和开始时间，体重与围度按日期，其余按标识。
    private static func sorted(_ records: [Record], in set: RecordSet) -> [Record] {
        let ordered: [Record]
        if set.documentKey == "workouts" {
            ordered = records.sorted { a, b in
                let dayA = a.payload["d"] as? String ?? "", dayB = b.payload["d"] as? String ?? ""
                if dayA != dayB { return dayA < dayB }
                let startA = number(a.payload["start"]), startB = number(b.payload["start"])
                return startA != startB ? startA < startB : a.id < b.id
            }
        } else {
            ordered = records.sorted { $0.id < $1.id }
        }
        return ordered.enumerated().map { Record(id: $1.id, payload: $1.payload, position: $0) }
    }

    static func assemble(settings: [String: Any], records: [String: [[String: Any]]]) -> [String: Any] {
        var document = settings
        for set in recordSets {
            let payloads = records[set.documentKey] ?? []
            if set.alwaysPresent || !payloads.isEmpty { document[set.documentKey] = payloads }
        }
        return document
    }

    /// 文档写入后再读出的样子。内存中的文档保持这个形态，重新读取时才不会出现无意义的差异。
    static func canonical(_ document: [String: Any]) -> [String: Any] {
        var records: [String: [[String: Any]]] = [:]
        for set in recordSets { records[set.documentKey] = self.records(of: set, in: document).map(\.payload) }
        return assemble(settings: settings(of: document), records: records)
    }

    /// 与 `RecordPatch.equal` 不同，同步元数据的变化也算差异，需要落盘。
    static func same(_ a: Any?, _ b: Any?) -> Bool {
        guard let a else { return b == nil }
        guard let b else { return false }
        return NSDictionary(dictionary: ["v": a]).isEqual(to: ["v": b])
    }
}
