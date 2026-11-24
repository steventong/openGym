import XCTest
@testable import OpenGYM

@MainActor final class AIToolTests: XCTestCase {
    private var root: URL!
    private var defaults: UserDefaults!
    private var suite: String!
    private var store: GymStore!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        suite = "ai-tools-" + UUID().uuidString
        defaults = UserDefaults(suiteName: suite)
        store = GymStore(userID: "local", storage: LocalTrainingStorage(root: root), defaults: defaults)
        store.registerCatalogue([exercise("0025", "杠铃卧推", "barbell bench press"), exercise("0047", "上斜卧推", "barbell incline bench press")])
        let seeded = await store.mutate { _ in
            ["unit": "kg", "week": ["1": ["r1"]], "bodyweight": [["d": "2026-11-01", "w": 80, "t": 1]],
             "routines": [["id": "r1", "name": "推", "ex": [
                ["id": "0025", "mode": "reps", "sets": 3, "reps": 10, "weight": 60, "restSec": 90, "future": "keep"],
                ["id": "0047", "mode": "reps", "sets": 3, "reps": 12, "weight": 40]] as [[String: Any]]] as [String: Any]],
             "workouts": [self.workout("w1", "2026-11-01", 60), self.workout("w2", "2026-11-08", 65)]]
        }
        XCTAssertTrue(seeded)
    }
    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
        defaults.removePersistentDomain(forName: suite)
    }

    private func exercise(_ id: String, _ name: String, _ english: String) -> Exercise {
        Exercise(id: id, name: name, english: english, bodyPart: "chest", equipment: "barbell", target: "pectorals", category: "strength", instructions: [], description: "")
    }
    private func workout(_ id: String, _ day: String, _ weight: Double) -> [String: Any] {
        let start = dateFromDay(day)!.timeIntervalSince1970 * 1000 + 36_000_000
        return ["id": id, "d": day, "start": start, "end": start + 3_600_000, "name": "推", "prs": ["0025"],
                "entries": [["id": "0025", "target": ["mode": "reps"], "sets": [["w": weight, "r": 8, "done": true, "at": start], ["w": weight, "r": 7, "done": true, "at": start]]] as [String: Any]]]
    }
    private func prepare(_ name: String, _ arguments: [String: Any] = [:]) throws -> AIToolWork {
        let data = try JSONSerialization.data(withJSONObject: arguments)
        return try AIToolbox(store: store).prepare(AIToolCall(id: "c", name: name, arguments: String(decoding: data, as: UTF8.self)))
    }
    private func answer(_ name: String, _ arguments: [String: Any] = [:]) throws -> [String: Any] {
        guard case let .answer(value) = try prepare(name, arguments) else { throw AIToolError("expected an answer") }
        _ = try AIToolbox.encode(value)
        return try XCTUnwrap(value as? [String: Any])
    }
    private func proposal(_ name: String, _ arguments: [String: Any]) throws -> AIProposal {
        guard case let .proposal(value) = try prepare(name, arguments) else { throw AIToolError("expected a proposal") }
        return value
    }
    private func stored(_ id: String) -> [String: Any] { (store.state["workouts"] as? [[String: Any]] ?? []).first { $0["id"] as? String == id } ?? [:] }
    private func sets(_ id: String) -> [[String: Any]] { ((stored(id)["entries"] as? [[String: Any]])?.first?["sets"] as? [[String: Any]]) ?? [] }

    // MARK: - 清单

    func testEveryToolIsHandledAndTitledInBothLanguages() throws {
        XCTAssertEqual(Set(AITool.all.map(\.name)).count, AITool.all.count)
        for tool in AITool.all {
            XCTAssertTrue(JSONSerialization.isValidJSONObject(tool.schema.json), tool.name)
            for language in ["en", "zh"] {
                let key = "AI_TOOL_" + tool.name.uppercased()
                XCTAssertNotEqual(String(localized: String.LocalizationValue(key), bundle: AppLanguage.bundle(for: language), locale: AppLanguage.locale(for: language)), key)
            }
            do { _ = try prepare(tool.name) } catch { XCTAssertFalse(error.localizedDescription.contains("Unknown tool"), tool.name) }
        }
        XCTAssertThrowsError(try prepare("drop_everything"))
    }

    func testSchemaRejectsBadArguments() {
        let bad: [(String, [String: Any])] = [
            ("get_routine", [:]), ("get_routine", ["routine_id": "r1", "extra": 1]), ("get_routine", ["routine_id": 3]),
            ("get_schedule", ["from": "2026-02-30"]), ("get_schedule", ["days": 61]), ("get_schedule", ["days": 1.5]), ("get_schedule", ["days": true]),
            ("set_favourite", ["exercise_id": "0025", "favourite": 1]), ("get_body_records", ["kind": "height"]),
            ("log_body_weight", ["date": "2026-11-01", "weight": -1]),
        ]
        for (name, arguments) in bad { XCTAssertThrowsError(try prepare(name, arguments), "\(name) \(arguments)") }
        XCTAssertThrowsError(try AIToolbox(store: store).prepare(AIToolCall(id: "c", name: "get_overview", arguments: "{oops")))
        XCTAssertNoThrow(try prepare("get_schedule", ["from": NSNull()]), "null 视为未填写")
    }

    func testQueriesDescribeStoredData() throws {
        XCTAssertEqual(try answer("get_overview")["workout_count"] as? Int, 2)
        XCTAssertEqual((try answer("get_routine", ["routine_id": "r1"])["exercises"] as? [[String: Any]])?.map { $0["slot"] as? Int }, [0, 1])
        let list = try answer("list_workouts", ["from": "2026-11-05", "exercise_id": "0025"])
        XCTAssertEqual((list["workouts"] as? [[String: Any]])?.map { $0["id"] as? String }, ["w2"])
        XCTAssertEqual((try answer("search_exercises", ["query": "incline bench"])["exercises"] as? [[String: Any]])?.first?["id"] as? String, "0047")
        XCTAssertEqual((try answer("search_exercises", ["query": "卧推"])["exercises"] as? [[String: Any]])?.first?["id"] as? String, "0025", "练过的动作排在前面")
        XCTAssertEqual(try answer("get_exercise_history", ["exercise_id": "0025"])["total_sessions"] as? Int, 2)
        XCTAssertEqual(try answer("get_body_records", ["kind": "weight"])["total"] as? Int, 1)
        _ = try answer("get_schedule"); _ = try answer("get_training_stats"); _ = try answer("get_body_records", ["kind": "measurements"]); _ = try answer("search_exercises", ["only": "available"])
    }

    // MARK: - 修改

    func testPreparingChangesNeverWrites() throws {
        let before = store.state
        _ = try proposal("delete_routine", ["routine_id": "r1"])
        _ = try proposal("delete_workout", ["workout_id": "w1"])
        _ = try proposal("log_body_weight", ["date": "2026-11-01", "weight": 79])
        _ = try proposal("set_weekly_schedule", ["days": [["weekday": 1, "routine_ids": [String]()]]])
        XCTAssertTrue(StateDocument.same(before, store.state))
    }

    func testRoutineEditKeepsUntouchedFieldsAndShowsChanges() async throws {
        let change = try proposal("update_routine", ["routine_id": "r1", "exercises": [["slot": 0, "sets": 4, "weight": 62.5], ["exercise_id": "0047", "sets": 2, "reps": 15]]])
        XCTAssertEqual(change.summary.changes.count, 3, "修改、新增、删除各一行")
        XCTAssertEqual(change.summary.changes[0].before?.contains("3×10"), true)
        XCTAssertEqual(change.summary.changes[0].after?.contains("4×10"), true)
        _ = try await change.apply()
        let rows = try XCTUnwrap(store.routines.first?.exercises)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0]["future"] as? String, "keep")
        XCTAssertEqual(number(rows[0]["sets"]), 4); XCTAssertEqual(number(rows[0]["weight"]), 62.5); XCTAssertEqual(number(rows[0]["restSec"]), 90)
        XCTAssertEqual(number(rows[1]["reps"]), 15)
        for bad in [[["slot": 9]], [["slot": 0], ["slot": 0]], [["exercise_id": "nope"]], [["sets": 3]]] as [[[String: Any]]] {
            XCTAssertThrowsError(try proposal("update_routine", ["routine_id": "r1", "exercises": bad]))
        }
        XCTAssertThrowsError(try proposal("update_routine", ["routine_id": "r1", "name": "推"]), "没有变化不打扰用户")
        XCTAssertThrowsError(try proposal("update_routine", ["routine_id": "r1", "exercises": [["slot": 0, "progression": "time"]]]), "进阶规则要与记录方式匹配")
    }

    func testCreateRoutineSupportsSupersetsAndProgression() async throws {
        let change = try proposal("create_routine", ["name": "拉", "exercises": [
            ["exercise_id": "0025", "reps": 12, "reps_min": 8, "progression": "double", "superset": "A"], ["exercise_id": "0047", "superset": "A"]]])
        let result = try await change.apply() as? [String: Any]
        let routine = try XCTUnwrap(store.routines.first { $0.id == result?["routine_id"] as? String })
        XCTAssertEqual(number(routine.exercises[0]["repsMin"]), 8)
        XCTAssertNotNil(routine.exercises[0]["sg"])
        XCTAssertEqual(routine.exercises[0]["sg"] as? String, routine.exercises[1]["sg"] as? String)
    }

    func testStaleRoutineDeletionIsRefused() async throws {
        let change = try proposal("delete_routine", ["routine_id": "r1"])
        XCTAssertTrue(change.summary.destructive)
        _ = try await proposal("update_routine", ["routine_id": "r1", "name": "新推"]).apply()
        do { _ = try await change.apply(); XCTFail("内容变化后不应删除") } catch {}
        XCTAssertEqual(store.routines.count, 1)
        _ = try await proposal("delete_routine", ["routine_id": "r1"]).apply()
        XCTAssertTrue(store.routines.isEmpty)
        XCTAssertNil((store.state["week"] as? [String: Any])?["1"])
    }

    func testScheduleChangesOnlyListedDays() async throws {
        _ = try await proposal("set_weekly_schedule", ["days": [["weekday": 3, "routine_ids": ["r1"]]]]).apply()
        XCTAssertEqual((store.state["week"] as? [String: [String]]), ["1": ["r1"], "3": ["r1"]])
        _ = try await proposal("set_date_plan", ["date": "2026-11-30", "plan": "rest"]).apply()
        XCTAssertEqual((store.state["dayPlan"] as? [String: String]), ["2026-11-30": "rest"])
        _ = try await proposal("set_date_plan", ["date": "2026-11-30", "plan": "follow_schedule"]).apply()
        XCTAssertNil((store.state["dayPlan"] as? [String: Any])?["2026-11-30"])
        XCTAssertThrowsError(try proposal("set_weekly_schedule", ["days": [["weekday": 2, "routine_ids": ["gone"]]]]))
    }

    func testWorkoutCorrectionKeepsOtherValuesAndRebuildsRecords() async throws {
        let change = try proposal("update_workout", ["workout_id": "w2", "exercises": [["entry": 0, "sets": [["set": 0, "weight": 50], ["set": 1, "weight": 50]]]]])
        XCTAssertEqual(change.summary.changes.first?.before, "65×8, 65×7")
        XCTAssertEqual(change.summary.changes.first?.after, "50×8, 50×7")
        _ = try await change.apply()
        XCTAssertEqual(sets("w2").map { number($0["w"]) }, [50, 50])
        XCTAssertNotNil(sets("w2")[0]["at"])
        XCTAssertEqual(number(stored("w2")["vol"]), 750)
        XCTAssertEqual(stored("w2")["prs"] as? [String], [], "更正后不再是个人纪录")
        XCTAssertTrue(store.historyEdits.isEmpty, "不留下历史草稿")
    }

    func testWorkoutTimeChangeAndInvalidEditsLeaveDataAlone() async throws {
        _ = try await proposal("update_workout", ["workout_id": "w1", "date": "2026-11-02", "start_time": "18:30", "duration_minutes": 45]).apply()
        XCTAssertEqual(stored("w1")["d"] as? String, "2026-11-02")
        XCTAssertEqual(number(stored("w1")["end"]) - number(stored("w1")["start"]), 45 * 60_000)
        let before = store.state
        XCTAssertThrowsError(try proposal("update_workout", ["workout_id": "w1", "start_time": "25:00"]))
        XCTAssertThrowsError(try proposal("update_workout", ["workout_id": "w1", "date": "2099-01-01"]))
        XCTAssertThrowsError(try proposal("update_workout", ["workout_id": "w1", "exercises": [["entry": 0, "sets": [["set": 0, "done": false]]]]]), "至少保留一组完成")
        store.historyEdits = ["w1": ["proposed": stored("w1")]]
        XCTAssertThrowsError(try proposal("update_workout", ["workout_id": "w1", "name": "x"]), "用户有未提交编辑时不能修改")
        XCTAssertTrue(StateDocument.same(before, store.state))
    }

    func testBackfilledWorkoutIsSavedOnceAndFixesLaterRecords() async throws {
        let arguments: [String: Any] = ["name": "补录", "date": "2026-11-05", "start_time": "09:00", "duration_minutes": 50,
            "exercises": [["exercise_id": "0025", "sets": [["weight": 40, "reps": 10, "warmup": true], ["weight": 90, "reps": 5, "rir": 1]]]]]
        let result = try await proposal("add_workout", arguments).apply() as? [String: Any]
        let id = try XCTUnwrap(result?["workout_id"] as? String)
        XCTAssertEqual((store.state["workouts"] as? [[String: Any]])?.map { $0["id"] as? String }, ["w1", id, "w2"])
        XCTAssertEqual(number(stored(id)["end"]) - number(stored(id)["start"]), 50 * 60_000)
        XCTAssertEqual(stored(id)["prs"] as? [String], ["0025"])
        XCTAssertEqual(stored("w2")["prs"] as? [String], [], "之后较轻的训练不再是纪录")
        XCTAssertEqual(sets(id).first?["phase"] as? String, "warmup")
        XCTAssertThrowsError(try proposal("add_workout", arguments.merging(["date": "2099-01-01"]) { $1 }))
        XCTAssertThrowsError(try proposal("add_workout", arguments.merging(["exercises": [["exercise_id": "0025", "sets": [["weight": 40]]]]]) { $1 }))
    }

    func testDeleteWorkout() async throws {
        _ = try await proposal("delete_workout", ["workout_id": "w2"]).apply()
        XCTAssertTrue(stored("w2").isEmpty)
        XCTAssertFalse(stored("w1").isEmpty)
    }

    func testExercisesNotesAndFavourites() async throws {
        let created = try await proposal("create_exercise", ["name": "弹力带卧推", "body_part": "chest", "equipment": "band", "primary_muscles": ["chest"], "secondary_muscles": ["triceps"]]).apply() as? [String: Any]
        let id = try XCTUnwrap(created?["exercise_id"] as? String)
        XCTAssertEqual(store.exercise(id)?.name, "弹力带卧推")
        XCTAssertEqual(store.customExercises.first?["muscleGroups"] as? [String], ["chest", "triceps"])
        XCTAssertThrowsError(try proposal("create_exercise", ["name": "杠铃卧推", "body_part": "chest", "equipment": "barbell"]), "重名")
        _ = try await proposal("update_exercise", ["exercise_id": id, "name": "弹力带推胸"]).apply()
        XCTAssertEqual(store.exercise(id)?.name, "弹力带推胸")
        _ = try await proposal("set_exercise_note", ["exercise_id": "0025", "note": "肩胛收紧"]).apply()
        XCTAssertEqual(store.standingExerciseNote("0025"), "肩胛收紧")
        _ = try await proposal("set_favourite", ["exercise_id": "0025", "favourite": true]).apply()
        XCTAssertTrue(store.favouriteIDs.contains("0025"))
        XCTAssertThrowsError(try proposal("delete_exercise", ["exercise_id": "0025"]), "动作库动作不能删除")
        _ = try await proposal("delete_exercise", ["exercise_id": id]).apply()
        XCTAssertNil(store.exercise(id))
    }

    func testEditingCatalogueExerciseKeepsIDAndMuscles() async throws {
        let full = try XCTUnwrap(Bundle.main.url(forResource: "catalogue", withExtension: "json"))
        store.registerCatalogue(try JSONDecoder().decode([Exercise].self, from: Data(contentsOf: full)))
        _ = try await proposal("update_exercise", ["exercise_id": "0025", "name": "平板卧推", "body_part": "chest"]).apply()
        let record = try XCTUnwrap(store.customExercises.first)
        XCTAssertEqual(record["id"] as? String, "0025")
        XCTAssertEqual(record["n"] as? String, "平板卧推")
        XCTAssertFalse((record["primaries"] as? [String] ?? []).isEmpty, "未提到的肌群不会被清空")
    }

    func testBodyRecordsAndPreferences() async throws {
        _ = try await proposal("log_body_weight", ["date": "2026-11-01", "weight": 79.5]).apply()
        _ = try await proposal("log_measurements", ["date": "2026-11-01", "values": [["field": "waist", "value": 82.5], ["field": "bodyFat", "value": 18]]]).apply()
        XCTAssertEqual(number((store.state["bodyweight"] as? [[String: Any]])?.first?["w"]), 79.5)
        let row = try XCTUnwrap((store.state["measurements"] as? [[String: Any]])?.first)
        XCTAssertEqual(number(row["waist"]), 82.5); XCTAssertEqual(number(row["bodyFat"]), 18)
        XCTAssertThrowsError(try proposal("log_measurements", ["date": "2026-11-01", "values": [["field": "nose", "value": 3]]]))
        XCTAssertThrowsError(try proposal("log_body_weight", ["date": "2099-01-01", "weight": 80]))
        _ = try await proposal("delete_body_record", ["kind": "measurements", "date": "2026-11-01"]).apply()
        XCTAssertTrue((store.state["measurements"] as? [Any] ?? []).isEmpty)
        _ = try await proposal("update_preferences", ["goal_weight": 75, "default_rest_seconds": 120]).apply()
        XCTAssertEqual(number(store.state["targetW"]), 75); XCTAssertEqual(number(store.state["restSec"]), 120)
        _ = try await proposal("update_preferences", ["goal_weight": 0]).apply()
        XCTAssertNil(store.state["targetW"])
    }
}
