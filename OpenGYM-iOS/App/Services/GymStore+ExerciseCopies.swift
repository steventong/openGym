import Foundation

/// 动作库只是动作的提供方：计划或训练记录一旦用到某个动作，就把它复制进用户自己的资料。
/// 副本随资料保存和同步，之后显示以副本为准；用户编辑后它成为同 ID 的自定义动作。
enum ExerciseCopies {
    static func referencedIDs(in document: [String: Any]) -> [String] {
        let routines = (document["routines"] as? [[String: Any]] ?? []).flatMap { $0["ex"] as? [[String: Any]] ?? [] }
        let workouts = (document["workouts"] as? [[String: Any]] ?? []).flatMap { $0["entries"] as? [[String: Any]] ?? [] }
        var seen: Set<String> = []
        return (routines + workouts).compactMap { $0["id"] as? String }.filter { seen.insert($0).inserted }
    }
}

extension Exercise {
    /// 副本沿用内置动作库的字段格式。
    var copyRecord: [String: Any]? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func catalogueCopy(_ raw: [String: Any]) -> Exercise? {
        guard let data = try? JSONSerialization.data(withJSONObject: raw) else { return nil }
        return try? JSONDecoder().decode(Exercise.self, from: data)
    }
}

extension GymStore {
    /// 为文档中被引用、但尚无本地版本的动作库动作补上副本；已有同 ID 自定义动作的不再保留副本。
    /// 动作库尚未加载时不补，下一次保存会补齐。
    func addingExerciseCopies(to document: [String: Any]) -> [String: Any] {
        let custom = Set((document[StateDocument.customExercises] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String })
        var copies = (document[StateDocument.exerciseCopies] as? [[String: Any]] ?? []).filter { copy in
            (copy["id"] as? String).map { !custom.contains($0) } ?? false
        }
        var known = Set(copies.compactMap { $0["id"] as? String })
        for id in ExerciseCopies.referencedIDs(in: document) where !custom.contains(id) && !known.contains(id) {
            guard let record = catalogueExercise(id)?.copyRecord else { continue }
            copies.append(record)
            known.insert(id)
        }
        var result = document
        result[StateDocument.exerciseCopies] = copies.isEmpty ? nil : copies
        return result
    }

    /// 把动作库动作转成可编辑的自定义动作记录，保留原 ID，计划和历史继续指向它。
    func editableRecord(for exercise: Exercise) throws -> [String: Any] {
        try exerciseCopyRecord(exercise, id: exercise.id, name: exercise.name)
    }
}
