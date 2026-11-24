import Foundation

/// 动作、身体数据与偏好的修改。
extension AIToolbox {
    // MARK: - 动作

    private func exerciseChanges(_ arguments: AIArguments, original: [String: Any]?, record: inout [String: Any]) throws -> [AIChange] {
        var changes: [AIChange] = []
        func note(_ label: String, _ before: String?, _ after: String) {
            if before ?? "" != after { changes.append(AIChange(label: label, before: before.flatMap { $0.isEmpty ? nil : $0 }, after: after.isEmpty ? nil : after)) }
        }
        func vocabulary(_ value: String?) -> String? {
            value.map { String(localized: String.LocalizationValue($0), table: "Vocabulary", bundle: AppLanguage.bundle, locale: AppLanguage.locale) }
        }
        func muscleNames(_ list: [String]) -> String {
            list.map { String(localized: String.LocalizationValue($0), table: "Muscles", bundle: AppLanguage.bundle, locale: AppLanguage.locale) }.joined(separator: ", ")
        }
        if let name = arguments.trimmed("name") {
            if let issue = store.customExerciseNameIssue(name, original: original) { throw AIToolError(issue) }
            note(aiText("AI_NAME"), original?["n"] as? String, name)
            record["n"] = name
        }
        if let part = arguments.string("body_part") { note(aiText("BODY_PART"), vocabulary(original?["bp"] as? String), vocabulary(part) ?? part); record["bp"] = part }
        if let equipment = arguments.trimmed("equipment")?.lowercased() {
            guard !equipment.isEmpty else { throw AIToolError("equipment must not be empty.") }
            note(aiText("EQUIPMENT"), vocabulary(original?["eq"] as? String), vocabulary(equipment) ?? equipment)
            record["eq"] = equipment
        }
        if let description = arguments.trimmed("description") { note(aiText("DESCRIPTION_AND_INSTRUCTIONS"), original?["desc"] as? String, description); record["desc"] = description }
        if arguments.has("primary_muscles") || arguments.has("secondary_muscles") || arguments.has("body_part") {
            var groups = (primary: original?["primaries"] as? [String] ?? [], secondary: original?["secondaries"] as? [String] ?? [])
            // 动作库动作没有直接的主次肌群字段，与编辑页一样由规则推导，避免改其他字段时把肌群清空。
            if let original, groups.primary.isEmpty, let inferred = try store.personalInfo("customMetadata", ["exercise": original])["groups"] as? [String] {
                groups = (Array(inferred.prefix(1)), Array(inferred.dropFirst()))
            }
            CustomExerciseMuscles.apply(primary: arguments.strings("primary_muscles") ?? groups.primary, secondary: arguments.strings("secondary_muscles") ?? groups.secondary, to: &record, baseline: original)
            note(aiText("PRIMARY_MUSCLE_GROUPS"), muscleNames(groups.primary), muscleNames(record["primaries"] as? [String] ?? []))
            note(aiText("SECONDARY_MUSCLES"), muscleNames(groups.secondary), muscleNames(record["secondaries"] as? [String] ?? []))
        }
        return changes
    }

    func createExercise(_ arguments: AIArguments) throws -> AIProposal {
        let id = "c" + UUID().uuidString
        var record: [String: Any] = ["id": id, "custom": true, "desc": ""]
        let changes = try exerciseChanges(arguments, original: nil, record: &record), value = record
        return proposal(aiText("AI_CREATE_EXERCISE_COUNT", arguments.trimmed("name") ?? ""), changes) {
            try saved(await store.savePersonalRecord(collection: "customEx", key: "id", original: nil, proposed: value), ["exercise_id": id])
        }
    }

    func updateExercise(_ arguments: AIArguments) throws -> AIProposal {
        let exercise = try exercise(arguments.required("exercise_id"))
        let original = store.customExercises.first { $0["id"] as? String == exercise.id }
        let baseline = try original ?? store.editableRecord(for: exercise)
        var record = baseline
        let changes = try exerciseChanges(arguments, original: baseline, record: &record), value = record
        guard !changes.isEmpty else { throw AIToolError("Nothing would change.") }
        return proposal(aiText("AI_UPDATE_EXERCISE_COUNT", exercise.name), changes) {
            try saved(await store.savePersonalRecord(collection: "customEx", key: "id", original: original, proposed: value))
        }
    }

    func deleteExercise(_ arguments: AIArguments) throws -> AIProposal {
        let id = arguments.required("exercise_id")
        guard let original = store.customExercises.first(where: { $0["id"] as? String == id }) else { throw AIToolError("Only custom exercises can be deleted.") }
        if let issue = store.customExerciseDeletionIssue(id) { throw AIToolError(issue) }
        return proposal(aiText("AI_DELETE_EXERCISE_COUNT", name(id)), [], destructive: true) {
            try saved(await store.deleteCustomExercise(original))
        }
    }

    func setExerciseNote(_ arguments: AIArguments) throws -> AIProposal {
        let exercise = try exercise(arguments.required("exercise_id")), note = arguments.trimmed("note") ?? "", before = store.standingExerciseNote(exercise.id)
        guard note != before ?? "" else { throw AIToolError("Nothing would change.") }
        return proposal(aiText("AI_UPDATE_EXERCISE_NOTE_COUNT", exercise.name), [AIChange(label: aiText("AI_NOTE"), before: before, after: note.isEmpty ? nil : note)]) {
            guard store.standingExerciseNote(exercise.id) == before else { throw AIToolError("The note changed in the meantime. Read it again.") }
            return try saved(await store.setStandingExerciseNote(exercise.id, text: note))
        }
    }

    func setFavourite(_ arguments: AIArguments) throws -> AIProposal {
        let exercise = try exercise(arguments.required("exercise_id")), enabled = arguments.boolean("favourite") ?? true
        guard store.favouriteIDs.contains(exercise.id) != enabled else { throw AIToolError("Nothing would change.") }
        return proposal(enabled ? aiText("AI_ADD_FAVOURITE") : aiText("AI_REMOVE_FAVOURITE"), [AIChange(label: exercise.name)]) {
            try saved(await store.setFavourite(exercise.id, enabled: enabled))
        }
    }

    // MARK: - 身体数据

    private func rejectFuture(_ day: String) throws {
        guard day <= dayString() else { throw AIToolError("The date is in the future.") }
    }
    private func record(_ collection: String, _ day: String) -> [String: Any]? {
        (store.state[collection] as? [[String: Any]] ?? []).first { $0["d"] as? String == day }
    }

    func logBodyWeight(_ arguments: AIArguments) throws -> AIProposal {
        let day = arguments.required("date"), weight = arguments.number("weight") ?? 0, unit = store.unit
        try rejectFuture(day)
        let original = record("bodyweight", day)
        guard original.map({ number($0["w"]) }) != weight else { throw AIToolError("Nothing would change.") }
        var row = original ?? ["d": day]
        row["w"] = weight
        row["t"] = Date().timeIntervalSince1970 * 1000
        // 与手动修改一致：改过的值不再视为 Apple 健康读入的值。
        row.removeValue(forKey: "healthKit")
        let value = row
        return proposal(aiText("AI_LOG_BODY_WEIGHT"), [AIChange(label: day, before: original.map { "\(text(number($0["w"]))) \(unit)" }, after: "\(text(weight)) \(unit)")]) {
            try saved(await store.savePersonalRecord(collection: "bodyweight", key: "d", original: original, proposed: value, unit: unit))
        }
    }

    func logMeasurements(_ arguments: AIArguments) throws -> AIProposal {
        let day = arguments.required("date"), fields = MeasureField.all(store.state), unit = store.unit
        try rejectFuture(day)
        let original = record("measurements", day)
        var row = original ?? ["d": day], others = row["other"] as? [[String: Any]] ?? [], changes: [AIChange] = []
        for item in arguments.objects("values") ?? [] {
            let id = item.required("field"), value = item.number("value") ?? 0
            guard let field = fields.first(where: { $0.id == id }) else { throw AIToolError("Unknown measurement field \(id). Use get_body_records.") }
            if id == "bodyFat", value > 100 { throw AIToolError("bodyFat is a percentage.") }
            let before = MeasureField.value(original ?? [:], id)
            guard before != value else { continue }
            let stored: Any = value > 0 ? value : NSNull()
            if id.hasPrefix("other:") {
                let key = String(id.dropFirst(6))
                if let index = others.firstIndex(where: { $0["id"] as? String == key }) { others[index]["value"] = stored }
                else { others.append(["id": key, "name": field.name, "value": stored]) }
            } else { row[id] = stored }
            let suffix = id == "bodyFat" ? " %" : id.hasPrefix("other:") ? "" : " cm"
            changes.append(AIChange(label: field.name, before: before > 0 ? text(before) + suffix : nil, after: value > 0 ? text(value) + suffix : nil))
        }
        guard !changes.isEmpty else { throw AIToolError("Nothing would change.") }
        if !others.isEmpty { row["other"] = others }
        guard fields.contains(where: { MeasureField.value(row, $0.id) > 0 }) else { throw AIToolError("Every value would be empty. Use delete_body_record instead.") }
        row["t"] = Date().timeIntervalSince1970 * 1000
        let value = row
        return proposal(aiText("AI_LOG_MEASUREMENTS_COUNT", day), changes) {
            try saved(await store.savePersonalRecord(collection: "measurements", key: "d", original: original, proposed: value, unit: unit))
        }
    }

    func deleteBodyRecord(_ arguments: AIArguments) throws -> AIProposal {
        let day = arguments.required("date"), weight = arguments.required("kind") == "weight", collection = weight ? "bodyweight" : "measurements"
        guard let original = record(collection, day) else { throw AIToolError("There is no record for \(day).") }
        let before = weight ? "\(text(number(original["w"]))) \(store.unit)"
            : MeasureField.all(store.state).filter { MeasureField.value(original, $0.id) > 0 }.map { "\($0.name) \(text(MeasureField.value(original, $0.id)))" }.joined(separator: " · ")
        return proposal(weight ? aiText("AI_DELETE_BODY_WEIGHT") : aiText("AI_DELETE_MEASUREMENTS"), [AIChange(label: day, before: before)], destructive: true) {
            try saved(await store.savePersonalRecord(collection: collection, key: "d", original: original, proposed: nil))
        }
    }

    // MARK: - 偏好

    func updatePreferences(_ arguments: AIArguments) throws -> AIProposal {
        let original = store.state.filter { ["targetW", "restSec"].contains($0.key) }, unit = store.unit
        var next = original, changes: [AIChange] = []
        if let goal = arguments.number("goal_weight"), goal != number(original["targetW"]) {
            next["targetW"] = goal > 0 ? goal : nil
            changes.append(AIChange(label: aiText("AI_GOAL_WEIGHT"), before: original["targetW"].map { "\(text(number($0))) \(unit)" }, after: goal > 0 ? "\(text(goal)) \(unit)" : nil))
        }
        if let rest = arguments.integer("default_rest_seconds"), Double(rest) != number(original["restSec"] ?? 90) {
            next["restSec"] = rest
            changes.append(AIChange(label: aiText("AI_DEFAULT_REST"), before: aiText("AI_COUNT_SECONDS", text(number(original["restSec"] ?? 90))), after: aiText("AI_COUNT_SECONDS", String(rest))))
        }
        guard !changes.isEmpty else { throw AIToolError("Nothing would change.") }
        let proposed = next
        return proposal(aiText("AI_UPDATE_PREFERENCES"), changes) {
            try saved(await store.savePersonalFields(original: original, proposed: proposed, unit: unit))
        }
    }
}
