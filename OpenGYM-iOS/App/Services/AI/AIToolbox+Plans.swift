import Foundation

/// 训练计划与排期的修改。
extension AIToolbox {
    private func cleanName(_ arguments: AIArguments) throws -> String? {
        guard let name = arguments.trimmed("name") else { return nil }
        guard !name.isEmpty else { throw AIToolError("name must not be empty.") }
        return name
    }

    /// 按参数得到完整的动作列表。带 slot 的行从原配置出发，只改写给出的字段。
    private func routineRows(_ arguments: [AIArguments], existing: [[String: Any]], routineID: String) throws -> [[String: Any]] {
        guard !arguments.isEmpty else { throw AIToolError("exercises must not be empty.") }
        var used = Set<Int>()
        var rows = try arguments.map { item -> [String: Any] in
            var base: [String: Any]
            if let slot = item.integer("slot") {
                guard existing.indices.contains(slot) else { throw AIToolError("slot \(slot) does not exist. Use get_routine.") }
                guard used.insert(slot).inserted else { throw AIToolError("slot \(slot) is listed twice.") }
                base = existing[slot]
                if let id = item.string("exercise_id"), id != base["id"] as? String {
                    _ = try exercise(id)
                    base = try WebRules.shared.call("replaceNativeRoutineExercise", payload: ["slot": base, "id": id, "state": store.state, "rid": routineID]) as? [String: Any] ?? base
                }
                // 没有改动的行保持原样，不重新规范化。
                if item.raw.keys.allSatisfy({ ["slot", "exercise_id", "superset"].contains($0) }) { return base }
            } else {
                guard let id = item.string("exercise_id") else { throw AIToolError("A new row needs exercise_id.") }
                _ = try exercise(id)
                base = ["id": id]
            }
            return try configured(base, item)
        }
        try applySupersets(arguments, to: &rows)
        let cleaned = try WebRules.shared.call("planGroup", payload: ["rows": rows, "operation": "cleanup", "index": 0])
        return cleaned as? [[String: Any]] ?? rows
    }

    private func configured(_ base: [String: Any], _ item: AIArguments) throws -> [String: Any] {
        var row = base
        let pyramid = !(row["pyramid"] as? [Any] ?? []).isEmpty
        if pyramid, item.has("sets") || item.has("reps") || item.has("mode") {
            throw AIToolError("This row is a pyramid. Its sets and reps can only be edited by the user; remove the row and add a new one to replace it.")
        }
        if let mode = item.string("mode") { row["mode"] = mode }
        for (key, field) in [("sets", "sets"), ("reps", "reps"), ("seconds", "sec"), ("minutes", "min")] {
            if let value = item.integer(key) { row[field] = value }
        }
        for (key, field) in [("weight", "weight"), ("speed_kmh", "speed")] { if let value = item.number(key) { row[field] = value } }
        // 这些字段以 0 表示移除。
        for (key, field) in [("rest_seconds", "restSec"), ("warmup_sets", "warmupSets"), ("reps_min", "repsMin")] {
            if let value = item.integer(key) { row[field] = value > 0 ? value : nil }
        }
        if let value = item.number("increment") { row["inc"] = value > 0 ? value : nil }
        if let value = item.integer("max_sets") { row["setsMax"] = value }
        if let value = item.boolean("per_side") { row["side"] = value ? true : nil }
        if let note = item.trimmed("note") { row["note"] = note.isEmpty ? nil : note }
        if let policy = item.string("progression") {
            row["prog"] = policy == "default" ? nil : policy
            // 与计划编辑页选择进阶规则时的默认值一致。
            if policy == "greyskull", row["lastToFailure"] == nil { row["lastToFailure"] = true }
            if ["double", "triple"].contains(policy), row["repsMin"] == nil { row["repsMin"] = max(1, Int(number(row["reps"] ?? 10)) - 2) }
            if policy == "triple", row["setsMax"] == nil { row["setsMax"] = min(10, Int(number(row["sets"] ?? 3)) + 2) }
        }
        guard let normal = try WebRules.shared.call("advancedConfig", payload: ["config": row]) as? [String: Any] else { throw APIError.invalidResponse }
        _ = try WebRules.shared.call("validatePersonalConfig", payload: ["config": normal])
        return normal
    }

    private func applySupersets(_ arguments: [AIArguments], to rows: inout [[String: Any]]) throws {
        for (index, item) in arguments.enumerated() where item.has("superset") {
            for key in ["sg", "sgName", "sgRest"] { rows[index].removeValue(forKey: key) }
        }
        for index in arguments.indices.dropLast() {
            guard let label = arguments[index].trimmed("superset"), !label.isEmpty, arguments[index + 1].trimmed("superset") == label else { continue }
            rows = try WebRules.shared.call("planGroup", payload: ["rows": rows, "operation": "pair", "index": index]) as? [[String: Any]] ?? rows
        }
    }

    func createRoutine(_ arguments: AIArguments) throws -> AIProposal {
        let name = try cleanName(arguments) ?? "", id = UUID().uuidString, unit = store.unit
        let rows = try routineRows(arguments.objects("exercises") ?? [], existing: [], routineID: id)
        let routine: [String: Any] = ["id": id, "name": name, "emoji": "barbell", "ex": rows]
        try EditValidation.routine(routine)
        return proposal(aiText("AI_CREATE_ROUTINE_COUNT", name), rows.map { AIChange(label: self.name($0["id"] as? String ?? ""), after: rowText($0)) }) {
            let ok = await store.mutate(reportError: false) { source in
                guard (source["unit"] as? String ?? "kg") == unit else { throw AIToolError("The weight unit changed.") }
                var next = source
                next["routines"] = (source["routines"] as? [[String: Any]] ?? []) + [routine]
                return next
            }
            return try saved(ok, ["routine_id": id])
        }
    }

    func updateRoutine(_ arguments: AIArguments) throws -> AIProposal {
        let routine = try routine(arguments.required("routine_id")), unit = store.unit, original = routine.raw
        var proposed = original, changes: [AIChange] = []
        if let name = try cleanName(arguments), name != routine.name {
            proposed["name"] = name
            changes.append(AIChange(label: aiText("ROUTINE_NAME"), before: routine.name, after: name))
        }
        if let items = arguments.objects("exercises") {
            let rows = try routineRows(items, existing: routine.exercises, routineID: routine.id)
            if !RecordPatch.equal(rows, routine.exercises) {
                proposed["ex"] = rows
                changes += rowChanges(items, rows: rows, existing: routine.exercises)
            }
        }
        guard !changes.isEmpty else { throw AIToolError("Nothing would change.") }
        try EditValidation.routine(proposed)
        return proposal(aiText("AI_UPDATE_ROUTINE_COUNT", routine.name), changes) {
            try saved(await store.saveRoutine(original: original, proposed: proposed, expectedUnit: unit))
        }
    }

    private func rowChanges(_ items: [AIArguments], rows: [[String: Any]], existing: [[String: Any]]) -> [AIChange] {
        var changes: [AIChange] = []
        for (item, row) in zip(items, rows) {
            let label = name(row["id"] as? String ?? "")
            guard let slot = item.integer("slot") else { changes.append(AIChange(label: label, after: rowText(row))); continue }
            let old = existing[slot], oldName = name(old["id"] as? String ?? "")
            if RecordPatch.equal(old, row) { continue }
            let replaced = old["id"] as? String != row["id"] as? String
            changes.append(AIChange(label: label, before: (replaced ? oldName + " · " : "") + rowText(old), after: rowText(row)))
        }
        let kept = items.compactMap { $0.integer("slot") }
        for (slot, old) in existing.enumerated() where !kept.contains(slot) {
            changes.append(AIChange(label: name(old["id"] as? String ?? ""), before: rowText(old)))
        }
        if kept != kept.sorted() {
            changes.append(AIChange(label: aiText("AI_EXERCISE_ORDER"), after: rows.map { name($0["id"] as? String ?? "") }.joined(separator: " → ")))
        }
        // 只有卡片未细分的字段变化时也要有一行说明，不能出现空白的确认。
        if changes.isEmpty { changes.append(AIChange(label: aiText("AI_EXERCISE_SETTINGS"), after: rows.map { name($0["id"] as? String ?? "") }.joined(separator: ", "))) }
        return changes
    }

    func deleteRoutine(_ arguments: AIArguments) throws -> AIProposal {
        let routine = try routine(arguments.required("routine_id"))
        return proposal(aiText("AI_DELETE_ROUTINE_COUNT", routine.name), routine.exercises.map { AIChange(label: name($0["id"] as? String ?? ""), before: rowText($0)) }, destructive: true) {
            // 确认期间计划被改动过时不删除，避免删掉用户没有看到的内容。
            guard RecordPatch.equal(store.routines.first { $0.id == routine.id }?.raw, routine.raw) else { throw AIToolError("The routine changed in the meantime. Read it again.") }
            return try saved(await store.deleteRoutine(id: routine.id))
        }
    }

    private func planNames(_ ids: [String]) -> String {
        ids.isEmpty ? aiText("REST_DAY") : ids.map { id in store.routines.first { $0.id == id }?.name ?? aiText("UNKNOWN_ROUTINE") }.joined(separator: " + ")
    }
    private func scheduleResult(_ ok: Bool) throws -> Any {
        let rotation = store.rotationSummary()["mode"] as? String == "rotation"
        return try saved(ok, rotation ? ["note": "A rotation is active, so the weekly schedule takes effect only after the user switches back to it on the Plan tab."] : [:])
    }

    func setWeeklySchedule(_ arguments: AIArguments) throws -> AIProposal {
        let original = store.state.filter { $0.key == "week" }, labels = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"] as [String.LocalizationValue]
        let before = original["week"] as? [String: Any] ?? [:]
        var week = before, changes: [AIChange] = []
        for item in arguments.objects("days") ?? [] {
            let day = item.integer("weekday") ?? 0, ids = item.strings("routine_ids") ?? []
            for id in ids { _ = try routine(id) }
            guard Self.ids(week[String(day)]) != ids else { continue }
            changes.append(AIChange(label: aiText(labels[day]), before: planNames(Self.ids(before[String(day)])), after: planNames(ids)))
            week[String(day)] = ids.isEmpty ? nil : ids
        }
        guard !changes.isEmpty else { throw AIToolError("Nothing would change.") }
        let proposed: [String: Any] = ["week": week]
        return proposal(aiText("AI_UPDATE_WEEKLY_SCHEDULE"), changes) {
            try scheduleResult(await store.saveSchedule(original: original, proposed: proposed))
        }
    }

    func setDatePlan(_ arguments: AIArguments) throws -> AIProposal {
        let original = store.state.filter { $0.key == "dayPlan" }, day = arguments.required("date"), plan = arguments.required("plan")
        var days = original["dayPlan"] as? [String: Any] ?? [:]
        func label(_ value: Any?) -> String {
            guard let id = value as? String else { return aiText("BACK_TO_WEEKLY_PLAN") }
            return planNames(id == "rest" ? [] : [id])
        }
        if plan != "rest", plan != "follow_schedule" { _ = try routine(plan) }
        let before = days[day]
        days[day] = plan == "follow_schedule" ? nil : plan
        guard !RecordPatch.equal(before, days[day]) else { throw AIToolError("Nothing would change.") }
        let proposed: [String: Any] = ["dayPlan": days]
        return proposal(aiText("AI_UPDATE_DATE_PLAN"), [AIChange(label: day, before: label(before), after: label(days[day]))]) {
            try scheduleResult(await store.saveSchedule(original: original, proposed: proposed))
        }
    }
}
