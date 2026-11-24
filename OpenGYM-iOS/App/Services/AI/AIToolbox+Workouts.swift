import Foundation

/// 训练记录的补录、修正与删除。
extension AIToolbox {
    private func startDate(day: String, time: String) throws -> Date {
        let parts = time.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2, time.count == 5, (0..<24).contains(parts[0]), (0..<60).contains(parts[1]), let date = dateFromDay(day),
              let start = Calendar.current.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: date) else {
            throw AIToolError("start_time must be HH:MM, 24-hour.")
        }
        return start
    }

    private func mode(_ id: String, _ sets: [AIArguments]) -> String {
        if sets.contains(where: { $0.has("minutes") || $0.has("speed_kmh") }) { return "cardio" }
        if sets.contains(where: { $0.has("seconds") }) { return "time" }
        return sets.contains { $0.has("reps") } ? "reps" : store.exercise(id)?.bodyPart == "cardio" ? "cardio" : "reps"
    }

    private func setRow(_ item: AIArguments, base: [String: Any]?, mode: String) throws -> [String: Any] {
        var row = base ?? ["done": true, "type": "work"]
        let values: [(String, String)] = [("weight", "w"), ("reps", "r"), ("seconds", "sec"), ("minutes", "min"), ("speed_kmh", "speed")]
        if row["sides"] != nil, values.contains(where: { item.has($0.0) }) || item.has("done") {
            throw AIToolError("Sets logged per side can only be edited by the user in History. Keep the set unchanged.")
        }
        if row["drops"] != nil || row["clusters"] != nil, item.has("weight") || item.has("reps") {
            throw AIToolError("Drop sets and rest-pause sets can only be edited by the user in History. Keep the set unchanged.")
        }
        for (key, field) in values { if let value = item.number(key) { row[field] = value } }
        // RIR 与 RPE 只保留一种，与训练页输入规则一致。
        if let rir = item.number("rir") { row["rir"] = rir; row.removeValue(forKey: "rpe") }
        if let rpe = item.number("rpe") { row["rpe"] = rpe; row.removeValue(forKey: "rir") }
        if let warmup = item.boolean("warmup") { row["phase"] = warmup ? "warmup" : "work"; row["warmup"] = warmup }
        if let done = item.boolean("done") { row["done"] = done }
        if base == nil {
            switch mode {
            case "cardio": guard number(row["min"]) > 0 else { throw AIToolError("A cardio set needs minutes.") }
            case "time": guard number(row["sec"]) > 0 else { throw AIToolError("A timed set needs seconds.") }
            default:
                guard number(row["r"]) > 0 else { throw AIToolError("A set needs reps.") }
                row["w"] = row["w"] ?? 0
            }
        }
        return row
    }

    private func newEntry(_ item: AIArguments) throws -> [String: Any] {
        guard let id = item.string("exercise_id") else { throw AIToolError("A new exercise needs exercise_id.") }
        _ = try exercise(id)
        guard let sets = item.objects("sets"), !sets.isEmpty else { throw AIToolError("A new exercise needs sets.") }
        guard !sets.contains(where: { $0.has("set") }) else { throw AIToolError("A new exercise has no existing sets to refer to; omit set.") }
        let mode = mode(id, sets), rows = try sets.map { try setRow($0, base: nil, mode: mode) }
        let first = rows.first { !Self.isWarmup($0) } ?? rows[0]
        var config: [String: Any] = ["id": id, "mode": mode, "sets": rows.count]
        for (field, key) in [("w", "weight"), ("r", "reps"), ("sec", "sec"), ("min", "min"), ("speed", "speed")] { config[key] = first[field] }
        guard let target = try WebRules.shared.call("advancedConfig", payload: ["config": config]) as? [String: Any] else { throw APIError.invalidResponse }
        var entry: [String: Any] = ["id": id, "target": target, "sets": rows]
        if let note = item.trimmed("note"), !note.isEmpty { entry["note"] = note }
        return entry
    }

    private func entries(_ items: [AIArguments], existing: [[String: Any]]) throws -> [[String: Any]] {
        guard !items.isEmpty else { throw AIToolError("exercises must not be empty.") }
        var used = Set<Int>()
        return try items.map { item in
            guard let index = item.integer("entry") else { return try newEntry(item) }
            guard existing.indices.contains(index) else { throw AIToolError("entry \(index) does not exist. Use get_workout.") }
            guard used.insert(index).inserted else { throw AIToolError("entry \(index) is listed twice.") }
            var entry = existing[index]
            if let id = item.string("exercise_id"), id != entry["id"] as? String {
                _ = try exercise(id)
                // 与历史编辑页更换动作相同：保留记录的组，只修正归属。
                entry["target"] = try WebRules.shared.call("replaceNativeRoutineExercise", payload: ["slot": entry["target"] as? [String: Any] ?? [:], "id": id, "state": store.state, "rid": entry["rid"] as? String ?? ""])
                entry["id"] = id
                for key in ["plan", "planned", "topW"] { entry.removeValue(forKey: key) }
            }
            if let note = item.trimmed("note") { entry["note"] = note.isEmpty ? nil : note }
            if let sets = item.objects("sets") {
                let old = entry["sets"] as? [[String: Any]] ?? []
                let current = (entry["target"] as? [String: Any])?["mode"] as? String ?? mode(entry["id"] as? String ?? "", sets)
                var usedSets = Set<Int>()
                entry["sets"] = try sets.map { set in
                    guard let number = set.integer("set") else { return try setRow(set, base: nil, mode: current) }
                    guard old.indices.contains(number) else { throw AIToolError("set \(number) does not exist in entry \(index). Use get_workout.") }
                    guard usedSets.insert(number).inserted else { throw AIToolError("set \(number) is listed twice in entry \(index).") }
                    return try setRow(set, base: old[number], mode: current)
                }
            }
            return entry
        }
    }

    private func entryText(_ entry: [String: Any]) -> String {
        let note = entry["note"] as? String ?? ""
        return setsText(entry) + (note.isEmpty ? "" : " · “\(note)”")
    }

    func addWorkout(_ arguments: AIArguments) throws -> AIProposal {
        let day = arguments.required("date"), unit = store.unit, id = UUID().uuidString
        guard let name = arguments.trimmed("name"), !name.isEmpty else { throw AIToolError("name must not be empty.") }
        let start = try startDate(day: day, time: arguments.required("start_time")), minutes = arguments.number("duration_minutes") ?? 0
        let end = start.addingTimeInterval(minutes * 60)
        guard end <= Date() else { throw AIToolError("The workout would end in the future.") }
        let entries = try entries(arguments.objects("exercises") ?? [], existing: [])
        guard entries.contains(where: { ($0["sets"] as? [[String: Any]] ?? []).contains(where: rawCompleted) }) else { throw AIToolError("At least one set must be completed.") }
        var active: [String: Any] = ["id": id, "d": day, "start": start.timeIntervalSince1970 * 1000, "name": name, "routineIds": [String](), "entries": entries]
        if let note = arguments.trimmed("note"), !note.isEmpty { active["note"] = note }
        let snapshot = active
        var changes = [AIChange(label: aiText("DATE"), after: "\(day) \(Self.time(start)) · " + aiText("AI_COUNT_MINUTES", text(minutes)))]
        changes += entries.map { AIChange(label: self.name($0["id"] as? String ?? ""), after: entryText($0)) }
        if let note = active["note"] as? String { changes.append(AIChange(label: aiText("AI_NOTE"), after: note)) }
        return proposal(aiText("AI_ADD_WORKOUT_COUNT", name), changes) {
            let ok = await store.mutate(reportError: false) { source in
                guard (source["unit"] as? String ?? "kg") == unit else { throw AIToolError("The weight unit changed.") }
                // 先按完成训练的规则写入，再重建这次之后的个人纪录：补录的日期可能早于已有训练。
                guard let finished = try WebRules.shared.call("finishAdvanced", payload: ["state": source, "active": snapshot, "now": end.timeIntervalSince1970 * 1000, "today": dayString()]) as? [String: Any],
                      let repaired = try WebRules.shared.call("repairHistory", payload: ["state": finished, "changedID": id, "touched": entries.compactMap { $0["id"] as? String }, "recomputeEntries": false]) as? [String: Any] else { throw APIError.invalidResponse }
                return repaired
            }
            return try saved(ok, ["workout_id": id])
        }
    }

    func updateWorkout(_ arguments: AIArguments) throws -> AIProposal {
        let id = arguments.required("workout_id"), original = try savedWorkout(id), unit = store.unit
        var proposed = original, changes: [AIChange] = []
        let oldName = original["name"] as? String ?? ""
        if let name = arguments.trimmed("name"), name != oldName {
            guard !name.isEmpty else { throw AIToolError("name must not be empty.") }
            proposed["name"] = name
            changes.append(AIChange(label: aiText("AI_NAME"), before: oldName, after: name))
        }
        if let note = arguments.trimmed("note"), note != original["note"] as? String ?? "" {
            proposed["note"] = note
            changes.append(AIChange(label: aiText("AI_NOTE"), before: original["note"] as? String, after: note.isEmpty ? nil : note))
        }
        let oldStart = Date(timeIntervalSince1970: number(original["start"]) / 1000), oldMinutes = (number(original["end"]) - number(original["start"])) / 60_000
        if arguments.has("date") || arguments.has("start_time") || arguments.has("duration_minutes") {
            let day = arguments.string("date") ?? original["d"] as? String ?? dayString(oldStart)
            let start = arguments.has("date") || arguments.has("start_time") ? try startDate(day: day, time: arguments.string("start_time") ?? Self.time(oldStart)) : oldStart
            let minutes = arguments.number("duration_minutes") ?? oldMinutes
            func label(_ day: String, _ start: Date, _ minutes: Double) -> String { "\(day) \(Self.time(start)) · " + aiText("AI_COUNT_MINUTES", text(minutes.rounded())) }
            let before = label(original["d"] as? String ?? "", oldStart, oldMinutes), after = label(day, start, minutes)
            if before != after {
                proposed["d"] = day
                if start != oldStart { proposed["start"] = start.timeIntervalSince1970 * 1000 }
                proposed["end"] = number(proposed["start"]) + minutes * 60_000
                changes.append(AIChange(label: aiText("DATE"), before: before, after: after))
            }
        }
        if let items = arguments.objects("exercises") {
            let old = original["entries"] as? [[String: Any]] ?? [], next = try entries(items, existing: old)
            if !RecordPatch.equal(old, next) {
                proposed["entries"] = next
                changes += entryChanges(items, next: next, old: old)
            }
        }
        guard !changes.isEmpty else { throw AIToolError("Nothing would change.") }
        // 先在当前资料上试算一遍，不合法的修改不会出现在确认卡片里。
        _ = try store.patchedWorkoutState(source: store.state, original: original, proposed: proposed, expectedUnit: unit)
        let change = proposed
        return proposal(aiText("AI_UPDATE_WORKOUT_COUNT", "\(oldName) · \(original["d"] as? String ?? "")"), changes) {
            _ = try savedWorkout(id)
            let ok = await store.mutate(reportError: false) { source in
                try store.patchedWorkoutState(source: source, original: original, proposed: change, expectedUnit: unit)
            }
            return try saved(ok)
        }
    }

    private func entryChanges(_ items: [AIArguments], next: [[String: Any]], old: [[String: Any]]) -> [AIChange] {
        var changes: [AIChange] = []
        for (item, entry) in zip(items, next) {
            let label = name(entry["id"] as? String ?? "")
            guard let index = item.integer("entry") else { changes.append(AIChange(label: label, after: entryText(entry))); continue }
            guard !RecordPatch.equal(old[index], entry) else { continue }
            let replaced = old[index]["id"] as? String != entry["id"] as? String
            changes.append(AIChange(label: label, before: (replaced ? name(old[index]["id"] as? String ?? "") + " · " : "") + entryText(old[index]), after: entryText(entry)))
        }
        let kept = items.compactMap { $0.integer("entry") }
        for (index, entry) in old.enumerated() where !kept.contains(index) {
            changes.append(AIChange(label: name(entry["id"] as? String ?? ""), before: entryText(entry)))
        }
        if kept != kept.sorted() {
            changes.append(AIChange(label: aiText("AI_EXERCISE_ORDER"), after: next.map { name($0["id"] as? String ?? "") }.joined(separator: " → ")))
        }
        return changes
    }

    func deleteWorkout(_ arguments: AIArguments) throws -> AIProposal {
        let raw = try savedWorkout(arguments.required("workout_id"))
        let changes = (raw["entries"] as? [[String: Any]] ?? []).map { AIChange(label: name($0["id"] as? String ?? ""), before: entryText($0)) }
        return proposal(aiText("AI_DELETE_WORKOUT_COUNT", "\(raw["name"] as? String ?? "") · \(raw["d"] as? String ?? "")"), changes, destructive: true) {
            try saved(await store.deletePersonalWorkout(WorkoutRecord(raw: raw)))
        }
    }
}
