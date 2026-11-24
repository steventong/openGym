import Foundation

/// 等待用户确认的一次修改：`summary` 是卡片内容，确认后才执行 `apply`。
struct AIProposal {
    let summary: AIProposalSummary
    let apply: @MainActor () async throws -> Any
}

enum AIToolWork {
    case answer(Any)
    case proposal(AIProposal)
}

/// 把模型的工具调用落到本机资料上。查询直接给出结果；修改只生成提案，全部经 GymStore 现有的校验与保存流程写入。
@MainActor struct AIToolbox {
    let store: GymStore

    /// 单个结果的长度上限，避免一次查询占满上下文。
    static let resultLimit = 60_000

    func prepare(_ call: AIToolCall) throws -> AIToolWork {
        guard let tool = AITool.all.first(where: { $0.name == call.name }) else { throw AIToolError("Unknown tool \(call.name).") }
        guard let raw = try? JSONSerialization.jsonObject(with: Data(call.arguments.utf8)) else { throw AIToolError("The arguments are not valid JSON.") }
        let arguments = AIArguments(try tool.schema.validated(raw) as? [String: Any] ?? [:])
        switch call.name {
        case "get_overview": return .answer(overview())
        case "list_routines": return .answer(routineList())
        case "get_routine": return .answer(try routineDetail(arguments))
        case "get_schedule": return .answer(try schedule(arguments))
        case "list_workouts": return .answer(workoutList(arguments))
        case "get_workout": return .answer(try workoutDetail(arguments))
        case "search_exercises": return .answer(try searchExercises(arguments))
        case "get_exercise": return .answer(try exerciseDetail(arguments))
        case "get_exercise_history": return .answer(try exerciseHistory(arguments))
        case "get_body_records": return .answer(bodyRecords(arguments))
        case "get_training_stats": return .answer(try trainingStats(arguments))
        case "create_routine": return .proposal(try createRoutine(arguments))
        case "update_routine": return .proposal(try updateRoutine(arguments))
        case "delete_routine": return .proposal(try deleteRoutine(arguments))
        case "set_weekly_schedule": return .proposal(try setWeeklySchedule(arguments))
        case "set_date_plan": return .proposal(try setDatePlan(arguments))
        case "add_workout": return .proposal(try addWorkout(arguments))
        case "update_workout": return .proposal(try updateWorkout(arguments))
        case "delete_workout": return .proposal(try deleteWorkout(arguments))
        case "create_exercise": return .proposal(try createExercise(arguments))
        case "update_exercise": return .proposal(try updateExercise(arguments))
        case "delete_exercise": return .proposal(try deleteExercise(arguments))
        case "set_exercise_note": return .proposal(try setExerciseNote(arguments))
        case "set_favourite": return .proposal(try setFavourite(arguments))
        case "log_body_weight": return .proposal(try logBodyWeight(arguments))
        case "log_measurements": return .proposal(try logMeasurements(arguments))
        case "delete_body_record": return .proposal(try deleteBodyRecord(arguments))
        case "update_preferences": return .proposal(try updatePreferences(arguments))
        default: throw AIToolError("Unknown tool \(call.name).")
        }
    }

    static func encode(_ value: Any) throws -> String {
        guard JSONSerialization.isValidJSONObject(value) else { throw AIToolError("The result could not be encoded.") }
        let text = String(decoding: try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes]), as: UTF8.self)
        guard text.count <= resultLimit else { throw AIToolError("The result is too large. Narrow the request with a shorter date range or a smaller limit.") }
        return text
    }

    // MARK: - 共用

    /// 保存动作的统一收尾：失败时把 Store 给出的原因交还给模型。
    func saved(_ ok: Bool, _ result: [String: Any] = [:]) throws -> Any {
        guard ok else { throw AIToolError(store.editError ?? store.error ?? "The change could not be saved.") }
        return result.merging(["saved": true]) { $1 }
    }
    func proposal(_ title: String, _ changes: [AIChange], destructive: Bool = false, apply: @escaping @MainActor () async throws -> Any) -> AIProposal {
        AIProposal(summary: AIProposalSummary(title: title, changes: changes, destructive: destructive), apply: apply)
    }
    func routine(_ id: String) throws -> Routine {
        guard let routine = store.routines.first(where: { $0.id == id }) else { throw AIToolError("No routine has the id \(id). Use list_routines.") }
        return routine
    }
    func exercise(_ id: String) throws -> Exercise {
        guard let exercise = store.exercise(id) else { throw AIToolError("No exercise has the id \(id). Use search_exercises.") }
        return exercise
    }
    func name(_ id: String) -> String { store.exercise(id)?.titleParts.primary ?? id }
    /// 只取已保存的记录；界面里还有未提交修改的记录不允许 AI 同时改动。
    func savedWorkout(_ id: String) throws -> [String: Any] {
        guard store.historyEdits[id] == nil else { throw AIToolError("The user has unsaved edits on this workout in History. Ask them to save or discard those first.") }
        guard let raw = (store.state["workouts"] as? [[String: Any]] ?? []).first(where: { WorkoutRecord.key($0) == id }) else { throw AIToolError("No workout has the id \(id). Use list_workouts.") }
        return raw
    }
    func text(_ value: Double) -> String { String(format: "%.8g", value) }
    func weekday(_ date: Date) -> Int { Calendar.current.component(.weekday, from: date) - 1 }
    static func ids(_ value: Any?) -> [String] { value as? [String] ?? (value as? String).map { [$0] } ?? [] }
}

/// 已通过 schema 校验的参数。
struct AIArguments {
    let raw: [String: Any]
    init(_ raw: [String: Any]) { self.raw = raw }
    func has(_ key: String) -> Bool { raw[key] != nil }
    func string(_ key: String) -> String? { raw[key] as? String }
    func trimmed(_ key: String) -> String? { string(key)?.trimmingCharacters(in: .whitespacesAndNewlines) }
    func number(_ key: String) -> Double? { (raw[key] as? Double) ?? (raw[key] as? Int).map(Double.init) }
    func integer(_ key: String) -> Int? { raw[key] as? Int }
    func boolean(_ key: String) -> Bool? { raw[key] as? Bool }
    func strings(_ key: String) -> [String]? { raw[key] as? [String] }
    func objects(_ key: String) -> [AIArguments]? { (raw[key] as? [[String: Any]])?.map(AIArguments.init) }
    /// 必填字段由 schema 保证存在。
    func required(_ key: String) -> String { string(key) ?? "" }
}
