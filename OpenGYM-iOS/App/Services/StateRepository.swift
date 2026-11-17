import CoreData

/// 资料文档与 Core Data 记录之间的读写，全部在主线程的 viewContext 上完成。
/// 保存时只写发生变化的记录：iCloud 按记录同步，未改动的记录不会被本机旧值覆盖。
@MainActor final class StateRepository {
    private let persistence: PersistenceController
    private var context: NSManagedObjectContext { persistence.container.viewContext }
    /// 上次读出或写入的文档，保存时与它比较得到需要写入的记录。
    private var persisted: [String: Any] = [:]
    private var historyToken: NSPersistentHistoryToken?

    var coordinator: NSPersistentStoreCoordinator { persistence.container.persistentStoreCoordinator }

    init(persistence: PersistenceController) {
        self.persistence = persistence
        historyToken = persistence.container.persistentStoreCoordinator.currentPersistentHistoryToken(fromStores: nil)
    }

    func load() throws -> [String: Any] {
        if let error = persistence.loadError { throw error }
        var duplicates: [NSManagedObject] = []
        var settings: [String: Any] = [:]
        for object in try newest(entity: "StoredSetting", identityAttribute: "key", origin: nil, duplicates: &duplicates) {
            guard let key = object.value(forKey: "key") as? String else { continue }
            settings[key] = try decode(object)
        }
        var records: [String: [[String: Any]]] = [:]
        for set in StateDocument.recordSets {
            var objects = try newest(entity: set.entity, identityAttribute: set.identityAttribute, origin: set.origin, duplicates: &duplicates)
            if set.keepsOrder {
                objects.sort {
                    let a = $0.value(forKey: "position") as? Int64 ?? 0, b = $1.value(forKey: "position") as? Int64 ?? 0
                    return a != b ? a < b : Self.isNewer($1, than: $0)
                }
            }
            records[set.documentKey] = try objects.compactMap { try decode($0) as? [String: Any] }
        }
        // 两台设备各自创建了同一条记录时，iCloud 会把两条都同步过来；只保留较新的一条。
        if !duplicates.isEmpty {
            duplicates.forEach(context.delete)
            try context.save()
        }
        persisted = StateDocument.canonical(StateDocument.assemble(settings: settings, records: records))
        return persisted
    }

    /// `date` 是这批记录的版本时间。导入旧资料时传入很早的时间，任何正常修改都比它新。
    func save(_ document: [String: Any], at date: Date = Date()) throws {
        if let error = persistence.loadError { throw error }
        do {
            try saveSettings(StateDocument.settings(of: document), date: date)
            for set in StateDocument.recordSets { try saveRecords(set, in: document, date: date) }
            if context.hasChanges { try context.save() }
            persisted = document
        } catch {
            context.rollback()
            throw error
        }
    }

    /// 自上次检查以来，数据库里是否出现了不是本 App 写入的事务（iCloud 导入）。
    func consumeForeignChanges() -> Bool {
        let request = NSPersistentHistoryChangeRequest.fetchHistory(after: historyToken)
        request.resultType = .transactionsOnly
        guard let result = try? context.execute(request) as? NSPersistentHistoryResult,
              let transactions = result.result as? [NSPersistentHistoryTransaction] else { return true }
        historyToken = transactions.last?.token ?? historyToken
        return transactions.contains { $0.author != PersistenceController.transactionAuthor }
    }

    private func saveSettings(_ settings: [String: Any], date: Date) throws {
        let before = StateDocument.settings(of: persisted)
        let removed = before.keys.filter { settings[$0] == nil }
        let changed = settings.filter { !StateDocument.same(before[$0.key], $0.value) }
        guard !removed.isEmpty || !changed.isEmpty else { return }
        let existing = try objects(entity: "StoredSetting", identityAttribute: "key", origin: nil, ids: removed + changed.keys)
        for key in removed { existing[key]?.forEach(context.delete) }
        for (key, value) in changed {
            let object = try reusable(existing[key], entity: "StoredSetting")
            object.setValue(key, forKey: "key")
            object.setValue(try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .fragmentsAllowed]), forKey: "payload")
            object.setValue(date, forKey: "updatedAt")
        }
    }

    private func saveRecords(_ set: StateDocument.RecordSet, in document: [String: Any], date: Date) throws {
        let before = Dictionary(StateDocument.records(of: set, in: persisted).map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        let after = StateDocument.records(of: set, in: document)
        let kept = Set(after.map(\.id))
        let removed = before.keys.filter { !kept.contains($0) }
        let changed = after.filter { record in
            guard let old = before[record.id] else { return true }
            return !StateDocument.same(old.payload, record.payload) || (set.keepsOrder && old.position != record.position)
        }
        guard !removed.isEmpty || !changed.isEmpty else { return }
        let existing = try objects(entity: set.entity, identityAttribute: set.identityAttribute, origin: set.origin, ids: removed + changed.map(\.id))
        for id in removed { existing[id]?.forEach(context.delete) }
        for record in changed {
            let object = try reusable(existing[record.id], entity: set.entity)
            object.setValue(record.id, forKey: set.identityAttribute)
            object.setValue(try JSONSerialization.data(withJSONObject: record.payload, options: [.sortedKeys]), forKey: "payload")
            object.setValue(date, forKey: "updatedAt")
            // 以下属性是 payload 的冗余副本，方便在数据库和 CloudKit 控制台里辨认与查询。
            let attributes = object.entity.attributesByName
            if attributes["origin"] != nil { object.setValue(set.origin, forKey: "origin") }
            if attributes["position"] != nil { object.setValue(Int64(record.position), forKey: "position") }
            if attributes["name"] != nil, let field = set.nameField { object.setValue(record.payload[field] as? String, forKey: "name") }
            if set.entity == "StoredWorkout" {
                object.setValue(record.payload["d"] as? String, forKey: "day")
                object.setValue(number(record.payload["start"]), forKey: "start")
            }
        }
    }

    /// 复用已有记录并清掉同标识的多余记录；没有时新建。
    private func reusable(_ matches: [NSManagedObject]?, entity: String) throws -> NSManagedObject {
        guard let first = matches?.first else { return NSEntityDescription.insertNewObject(forEntityName: entity, into: context) }
        matches?.dropFirst().forEach(context.delete)
        return first
    }

    private func objects(entity: String, identityAttribute: String, origin: String?, ids: [String]) throws -> [String: [NSManagedObject]] {
        let request = NSFetchRequest<NSManagedObject>(entityName: entity)
        var predicates = [NSPredicate(format: "%K IN %@", identityAttribute, ids)]
        if let origin { predicates.append(NSPredicate(format: "origin == %@", origin)) }
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        return Dictionary(grouping: try context.fetch(request)) { $0.value(forKey: identityAttribute) as? String ?? "" }
    }

    /// 每个标识最新的一条记录；其余放进 duplicates 等待删除。
    private func newest(entity: String, identityAttribute: String, origin: String?, duplicates: inout [NSManagedObject]) throws -> [NSManagedObject] {
        let request = NSFetchRequest<NSManagedObject>(entityName: entity)
        if let origin { request.predicate = NSPredicate(format: "origin == %@", origin) }
        var latest: [String: NSManagedObject] = [:]
        for object in try context.fetch(request) {
            guard let id = object.value(forKey: identityAttribute) as? String, !id.isEmpty, object.value(forKey: "payload") is Data else {
                duplicates.append(object); continue
            }
            guard let current = latest[id] else { latest[id] = object; continue }
            if Self.isNewer(object, than: current) { duplicates.append(current); latest[id] = object }
            else { duplicates.append(object) }
        }
        return Array(latest.values)
    }

    /// 时间相同时比较内容，保证各设备选出同一条。
    private static func isNewer(_ a: NSManagedObject, than b: NSManagedObject) -> Bool {
        let dateA = a.value(forKey: "updatedAt") as? Date ?? .distantPast, dateB = b.value(forKey: "updatedAt") as? Date ?? .distantPast
        if dateA != dateB { return dateA > dateB }
        let dataA = a.value(forKey: "payload") as? Data ?? Data(), dataB = b.value(forKey: "payload") as? Data ?? Data()
        return dataA.lexicographicallyPrecedes(dataB) == false && dataA != dataB
    }

    private func decode(_ object: NSManagedObject) throws -> Any {
        guard let data = object.value(forKey: "payload") as? Data else { throw CocoaError(.coderValueNotFound) }
        return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }
}
