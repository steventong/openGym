import Foundation

/// 只读查询。
extension AIToolbox {
    func overview() -> [String: Any] {
        let state = store.state, workouts = store.workouts
        var result: [String: Any] = ["today": dayString(), "weekday": weekday(Date()), "unit": store.unit, "language": AppLanguage.language,
            "routine_count": store.routines.count, "workout_count": workouts.count, "custom_exercise_count": store.customExercises.count,
            "workout_in_progress": store.draft != nil,
            "today_routines": store.scheduledRoutines(on: Date()).map { ["id": $0.id, "name": $0.name] },
            "default_rest_seconds": number(state["restSec"] ?? 90), "effort_scale": state["effort"] as? String ?? "none"]
        if let goal = state["targetW"] { result["goal_weight"] = number(goal) }
        if let latest = store.bodyweights.max(by: { ($0["d"] as? String ?? "") < ($1["d"] as? String ?? "") }) {
            result["latest_body_weight"] = ["date": latest["d"] as? String ?? "", "weight": number(latest["w"])] as [String: Any]
        }
        if let last = workouts.first?["d"] as? String { result["latest_workout_date"] = last }
        if let first = workouts.last?["d"] as? String { result["first_workout_date"] = first }
        return result
    }

    func routineList() -> [String: Any] {
        ["routines": store.routines.map { routine in
            ["id": routine.id, "name": routine.name, "exercises": routine.exercises.map { "\(name($0["id"] as? String ?? "")): \(rowText($0))" }] as [String: Any]
        }]
    }

    func routineDetail(_ arguments: AIArguments) throws -> [String: Any] {
        let routine = try routine(arguments.required("routine_id"))
        let rows = routine.exercises.enumerated().map { slot, row -> [String: Any] in
            let id = row["id"] as? String ?? ""
            var result: [String: Any] = ["slot": slot, "exercise_id": id, "name": name(id), "summary": rowText(row)]
            result["settings"] = RecordPatch.clean(row)
            return result
        }
        return ["id": routine.id, "name": routine.name, "exercises": rows]
    }

    func schedule(_ arguments: AIArguments) throws -> [String: Any] {
        let start = arguments.string("from").flatMap(dateFromDay) ?? Date()
        let dates = (0..<(arguments.integer("days") ?? 14)).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: start) }
        let days = dates.map { dayString($0) }
        let resolved = try WebRules.shared.call("schedule", payload: ["state": store.state, "dates": days, "today": dayString()]) as? [[String]] ?? []
        let names = Dictionary(store.routines.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        func named(_ ids: [String]) -> [[String: Any]] { ids.map { ["id": $0, "name": names[$0] ?? $0] } }
        let week = store.state["week"] as? [String: Any] ?? [:]
        var result: [String: Any] = [
            "weekly": week.mapValues { named(Self.ids($0)) },
            "date_overrides": store.state["dayPlan"] as? [String: Any] ?? [:],
            "days": zip(dates, resolved).map { ["date": dayString($0), "weekday": weekday($0), "routines": named($1)] as [String: Any] }]
        let mode = store.rotationSummary()["mode"] as? String ?? "week"
        result["mode"] = mode
        if mode == "rotation" {
            result["rotation"] = named((store.state["rotation"] as? [String: Any])?["sequence"] as? [String] ?? [])
            result["note"] = "A rotation is active, so the weekly schedule is not in effect. Rotations can only be edited by the user on the Plan tab."
        }
        return result
    }

    private func matches(_ day: String, _ arguments: AIArguments) -> Bool {
        (arguments.string("from").map { day >= $0 } ?? true) && (arguments.string("to").map { day <= $0 } ?? true)
    }

    func workoutList(_ arguments: AIArguments) -> [String: Any] {
        let exercise = arguments.string("exercise_id")
        let found = store.workouts.filter { workout in
            matches(workout["d"] as? String ?? "", arguments)
                && (exercise == nil || (workout["entries"] as? [[String: Any]] ?? []).contains { $0["id"] as? String == exercise })
        }
        let shown = found.prefix(arguments.integer("limit") ?? 15).map { workout -> [String: Any] in
            var result = workoutHeader(workout)
            result["exercises"] = (workout["entries"] as? [[String: Any]] ?? []).map { "\(name($0["id"] as? String ?? "")): \(setsText($0))" }
            return result
        }
        return ["total": found.count, "workouts": shown]
    }

    func workoutDetail(_ arguments: AIArguments) throws -> [String: Any] {
        let id = arguments.required("workout_id")
        guard let workout = store.workouts.first(where: { WorkoutRecord.key($0) == id }) else { throw AIToolError("No workout has the id \(id). Use list_workouts.") }
        var result = workoutHeader(workout)
        result["exercises"] = (workout["entries"] as? [[String: Any]] ?? []).enumerated().map { index, entry -> [String: Any] in
            let id = entry["id"] as? String ?? ""
            var item: [String: Any] = ["entry": index, "exercise_id": id, "name": name(id)]
            if let note = entry["note"] as? String, !note.isEmpty { item["note"] = note }
            item["sets"] = (entry["sets"] as? [[String: Any]] ?? []).enumerated().map { number, row in setDetail(row, number: number) }
            return item
        }
        return result
    }

    private func workoutHeader(_ workout: [String: Any]) -> [String: Any] {
        var result: [String: Any] = ["id": WorkoutRecord.key(workout), "date": workout["d"] as? String ?? "", "name": workout["name"] as? String ?? "",
            "duration_minutes": ((number(workout["end"]) - number(workout["start"])) / 60_000).rounded(),
            "personal_records": (workout["prs"] as? [String] ?? []).map(name)]
        if let start = workout["start"] { result["start_time"] = Self.time(Date(timeIntervalSince1970: number(start) / 1000)) }
        if let volume = workout["vol"] { result["volume"] = number(volume) }
        if let note = workout["note"] as? String, !note.isEmpty { result["note"] = note }
        return result
    }

    private func setDetail(_ row: [String: Any], number index: Int) -> [String: Any] {
        var result: [String: Any] = ["set": index, "done": rawCompleted(row)]
        for (key, label) in [("w", "weight"), ("r", "reps"), ("sec", "seconds"), ("min", "minutes"), ("speed", "speed_kmh"), ("incline", "incline"), ("rir", "rir"), ("rpe", "rpe")] {
            if let value = row[key], !(value is NSNull) { result[label] = number(value) }
        }
        if Self.isWarmup(row) { result["warmup"] = true }
        for key in ["sides", "drops", "clusters"] { if let value = row[key] { result[key] = RecordPatch.clean(value) } }
        return result
    }

    func searchExercises(_ arguments: AIArguments) throws -> [String: Any] {
        let words = (arguments.string("query") ?? "").split(whereSeparator: \.isWhitespace).map(String.init)
        let favourites = store.favouriteIDs, trained = store.trainedExerciseIDs
        let customs = Set(store.customExercises.compactMap { $0["id"] as? String })
        let allowed: Set<String>?
        switch arguments.string("only") {
        case "custom": allowed = customs
        case "favourites": allowed = favourites
        case "trained": allowed = trained
        case "available": allowed = Set(try store.personalInfo("equipment")["available"] as? [String] ?? [])
        default: allowed = nil
        }
        let found = store.exercises.filter { exercise in
            (allowed?.contains(exercise.id) ?? true)
                && (arguments.string("body_part").map { exercise.bodyPart == $0 } ?? true)
                && (arguments.string("equipment").map { exercise.equipment.localizedCaseInsensitiveCompare($0) == .orderedSame } ?? true)
                && words.allSatisfy { exercise.searchText.localizedCaseInsensitiveContains($0) }
        }
        // 用户练过或收藏的动作优先，其次是名称更短、更接近关键词的动作。
        func rank(_ exercise: Exercise) -> Int { trained.contains(exercise.id) ? 0 : favourites.contains(exercise.id) || customs.contains(exercise.id) ? 1 : 2 }
        let shown = found.sorted { (rank($0), $0.english.count, $0.id) < (rank($1), $1.english.count, $1.id) }.prefix(arguments.integer("limit") ?? 15)
        var result: [String: Any] = ["total": found.count, "exercises": shown.map { exercise in
            ["id": exercise.id, "name": exercise.name, "english": exercise.english, "body_part": exercise.bodyPart, "equipment": exercise.equipment,
             "target": exercise.target, "custom": customs.contains(exercise.id), "favourite": favourites.contains(exercise.id), "trained": trained.contains(exercise.id)] as [String: Any]
        }]
        if found.isEmpty { result["hint"] = "Nothing matched. Try fewer or different keywords, in English as well." }
        return result
    }

    func exerciseDetail(_ arguments: AIArguments) throws -> [String: Any] {
        let exercise = try exercise(arguments.required("exercise_id"))
        let custom = store.customExercises.first { $0["id"] as? String == exercise.id }
        var result: [String: Any] = ["id": exercise.id, "name": exercise.name, "english": exercise.english, "body_part": exercise.bodyPart,
            "equipment": exercise.equipment, "target": exercise.target, "description": exercise.description, "instructions": exercise.instructions,
            "custom": custom != nil, "favourite": store.favouriteIDs.contains(exercise.id)]
        if let primary = custom?["primaries"] { result["primary_muscles"] = primary }
        if let secondary = custom?["secondaries"] { result["secondary_muscles"] = secondary }
        if let note = store.standingExerciseNote(exercise.id) { result["standing_note"] = note }
        return result
    }

    func exerciseHistory(_ arguments: AIArguments) throws -> [String: Any] {
        let id = try exercise(arguments.required("exercise_id")).id
        let sessions = store.workouts.compactMap { workout -> [String: Any]? in
            let entries = (workout["entries"] as? [[String: Any]] ?? []).filter { $0["id"] as? String == id }
            guard !entries.isEmpty else { return nil }
            var result: [String: Any] = ["workout_id": WorkoutRecord.key(workout), "date": workout["d"] as? String ?? "", "sets": entries.map(setsText).joined(separator: "; ")]
            let notes = entries.compactMap { $0["note"] as? String }.filter { !$0.isEmpty }
            if !notes.isEmpty { result["note"] = notes.joined(separator: "; ") }
            return result
        }
        var result: [String: Any] = ["exercise_id": id, "name": name(id), "unit": store.unit, "total_sessions": sessions.count,
            "sessions": Array(sessions.prefix(arguments.integer("limit") ?? 10))]
        let progress = try store.personalInfo("progress", ["id": id])
        if let best = progress["best"], !(best is NSNull) { result["best_estimated_1rm"] = best }
        return result
    }

    func bodyRecords(_ arguments: AIArguments) -> [String: Any] {
        let measurements = arguments.required("kind") == "measurements"
        let rows = (measurements ? store.state["measurements"] as? [[String: Any]] ?? [] : store.bodyweights)
            .filter { matches($0["d"] as? String ?? "", arguments) }
            .sorted { ($0["d"] as? String ?? "") > ($1["d"] as? String ?? "") }
        let shown = rows.prefix(arguments.integer("limit") ?? 30)
        guard measurements else {
            return ["total": rows.count, "unit": store.unit, "records": shown.map { ["date": $0["d"] as? String ?? "", "weight": number($0["w"])] as [String: Any] }]
        }
        let fields = MeasureField.all(store.state)
        return ["total": rows.count,
            "fields": fields.map { ["id": $0.id, "name": $0.name, "unit": Self.measureUnit($0.id)] },
            "records": shown.map { row in
                ["date": row["d"] as? String ?? "",
                 "values": Dictionary(fields.map { ($0.id, MeasureField.value(row, $0.id)) }, uniquingKeysWith: { first, _ in first }).filter { $0.value > 0 }] as [String: Any]
            }]
    }

    func trainingStats(_ arguments: AIArguments) throws -> [String: Any] {
        let days = arguments.integer("days") ?? 28, now = Date()
        let muscles = try store.personalInfo("muscles", ["days": days, "now": now.timeIntervalSince1970 * 1000])
        var weeks: [String: [Double]] = [:]
        for workout in store.workouts where now.timeIntervalSince1970 - number(workout["start"]) / 1000 <= Double(days) * 86_400 {
            guard let date = dateFromDay(workout["d"] as? String ?? ""), let week = Calendar(identifier: .iso8601).dateInterval(of: .weekOfYear, for: date)?.start else { continue }
            let record = WorkoutRecord(raw: workout), previous = weeks[dayString(week)] ?? [0, 0, 0]
            weeks[dayString(week)] = [previous[0] + 1, previous[1] + Double(record.completedSetCount), previous[2] + number(workout["vol"])]
        }
        var result: [String: Any] = ["days": days, "unit": store.unit, "weekly_streak": muscles["streak"] ?? 0,
            "weeks": weeks.keys.sorted().map { ["week_starting": $0, "workouts": weeks[$0]![0], "sets": weeks[$0]![1], "volume": weeks[$0]![2]] as [String: Any] }]
        result["sets_per_muscle"] = muscles["load"]
        result["planned_weekly_sets_per_muscle"] = muscles["plan"]
        result["muscle_fatigue"] = muscles["fatigue"]
        return result
    }

    // MARK: - 文字摘要

    static func time(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }
    static func isWarmup(_ row: [String: Any]) -> Bool { row["phase"] as? String == "warmup" || row["warmup"] as? Bool == true }
    static func progressionName(_ policy: String) -> String {
        switch policy {
        case "off": aiText("NO_AUTOMATIC_PROGRESSION")
        case "linear": aiText("LINEAR_PROGRESSION")
        case "greyskull": aiText("GREYSKULL_LP")
        case "double": aiText("DOUBLE_PROGRESSION")
        case "triple": aiText("TRIPLE_PROGRESSION")
        case "time": aiText("INCREASE_DURATION")
        default: policy
        }
    }
    static func measureUnit(_ id: String) -> String { id == "bodyFat" ? "%" : id.hasPrefix("other:") ? "as entered" : "cm" }

    /// 一行计划配置的可读摘要，也用于确认卡片的前后对比，覆盖 AI 能修改的全部字段。
    func rowText(_ row: [String: Any]) -> String {
        var parts: [String] = []
        let sets = Int(number(row["sets"] ?? 3)), weight = number(row["weight"])
        let mode = row["mode"] as? String ?? (row["min"] != nil ? "cardio" : row["sec"] != nil ? "time" : "reps")
        switch mode {
        case "cardio":
            parts.append("\(sets)× " + aiText("AI_COUNT_MINUTES", text(number(row["min"]))))
            if number(row["speed"]) > 0 { parts.append(text(number(row["speed"])) + " km/h") }
        case "time": parts.append("\(sets)× " + aiText("AI_COUNT_SECONDS", text(number(row["sec"]))))
        default:
            let top = text(number(row["reps"] ?? 10)), low = number(row["repsMin"])
            parts.append("\(sets)×" + (low > 0 && low < number(row["reps"] ?? 10) ? "\(text(low))-\(top)" : top))
        }
        if mode != "cardio", weight > 0 { parts.append("\(text(weight)) \(store.unit)") }
        if row["side"] as? Bool == true { parts.append(aiText("AI_PER_SIDE")) }
        if number(row["warmupSets"]) > 0 { parts.append(aiText("AI_COUNT_WARMUP_SETS", text(number(row["warmupSets"])))) }
        if number(row["restSec"]) > 0 { parts.append(aiText("AI_COUNT_REST", text(number(row["restSec"])))) }
        if let policy = row["prog"] as? String { parts.append(Self.progressionName(policy)) }
        if number(row["inc"]) > 0 { parts.append("+" + text(number(row["inc"]))) }
        if number(row["setsMax"]) > 0 { parts.append(aiText("AI_COUNT_MAX_SETS", text(number(row["setsMax"])))) }
        if !(row["pyramid"] as? [Any] ?? []).isEmpty || row["intensifier"] != nil { parts.append(aiText("ADVANCED_SET_TYPES")) }
        if row["sg"] != nil { parts.append(aiText("SUPERSET")) }
        if let note = row["note"] as? String, !note.isEmpty { parts.append("“\(note)”") }
        return parts.joined(separator: " · ")
    }

    func setText(_ row: [String: Any]) -> String {
        var result: String
        if let sides = row["sides"] as? [String: [String: Any]] {
            result = ["L", "R"].compactMap { side in sides[side].map { "\(side) " + setText($0.filter { $0.key != "done" }) } }.joined(separator: " / ")
        } else if number(row["min"]) > 0 || number(row["speed"]) > 0 {
            result = aiText("AI_COUNT_MINUTES", text(number(row["min"]))) + (number(row["speed"]) > 0 ? " @ \(text(number(row["speed"]))) km/h" : "")
        } else if number(row["sec"]) > 0 {
            result = aiText("AI_COUNT_SECONDS", text(number(row["sec"]))) + (number(row["w"]) > 0 ? " · \(text(number(row["w"])))" : "")
        } else {
            result = "\(text(number(row["w"])))×\(text(number(row["r"])))"
        }
        for item in row["drops"] as? [[String: Any]] ?? [] { result += "→\(text(number(item["w"])))×\(text(number(item["r"])))" }
        if let rir = row["rir"], !(rir is NSNull) { result += " RIR \(text(number(rir)))" }
        if let rpe = row["rpe"], !(rpe is NSNull) { result += " RPE \(text(number(rpe)))" }
        if Self.isWarmup(row) { result += " (\(aiText("AI_WARMUP")))" }
        if row["sides"] == nil, row["done"] as? Bool == false { result += " (\(aiText("AI_NOT_DONE")))" }
        return result
    }
    func setsText(_ entry: [String: Any]) -> String {
        (entry["sets"] as? [[String: Any]] ?? []).map(setText).joined(separator: ", ")
    }
}
