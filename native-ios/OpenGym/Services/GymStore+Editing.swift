import Foundation
extension GymStore {
    func deleteRoutine(id:String) async -> Bool {
        await mutate(reportError:false) { source in
            var state = source
            state["routines"] = (source["routines"] as? [[String:Any]] ?? []).filter { $0["id"] as? String != id }
            if var week = source["week"] as? [String:Any] {
                for (day,value) in week {
                    let ids = value as? [String] ?? (value as? String).map { [$0] } ?? []
                    guard ids.contains(id) else { continue }
                    let remaining = ids.filter { $0 != id }
                    if remaining.isEmpty { week.removeValue(forKey:day) } else { week[day] = remaining }
                }
                state["week"] = week
            }
            if let days = source["dayPlan"] as? [String:Any] {
                state["dayPlan"] = days.filter { $0.value as? String != id }
            }
            // Match Web deletion: loop readers skip missing IDs; retain queue identity/progress,
            // history and active training snapshots. The server stamps the removal on write.
            return state
        }
    }
    func saveRoutine(original:[String:Any],proposed:[String:Any],expectedUnit:String) async -> Bool {
        await mutate(reportError:false) { source in
            guard (source["unit"] as? String ?? "kg") == expectedUnit else { throw APIError.response(409,L10n.text("THE_WEIGHT_UNIT_CHANGED_REOPEN_THE_EDITOR" /* 重量单位已改变，请重新打开编辑器。 */)) }
            var state = source; var list = state["routines"] as? [[String:Any]] ?? []
            guard let i = list.firstIndex(where: { $0["id"] as? String == original["id"] as? String }) else { throw APIError.response(404,L10n.text("THIS_ROUTINE_WAS_DELETED_AN_OLD_COPY_CANNOT_BE_SAVED_OVER_IT" /* 计划已被删除，不能保存旧副本。 */)) }
            var merged = try RecordPatch.apply(original:original,proposed:proposed,current:list[i])
            if let rows = merged["ex"] as? [[String:Any]] {
                merged["ex"] = try WebRules.shared.call("planGroup",payload:["rows":rows,"operation":"cleanup","index":0])
            }
            try EditValidation.routine(merged)
            list[i] = merged; state["routines"] = list; return state
        }
    }
    func saveSchedule(original:[String:Any], proposed:[String:Any]) async -> Bool {
        await mutate(reportError:false) { source in
            let next = try RecordPatch.apply(original:original,proposed:proposed,current:source)
            let valid = Set((source["routines"] as? [[String:Any]] ?? []).compactMap { $0["id"] as? String })
            for key in ["week","dayPlan"] {
                let before = original[key] as? [String:Any] ?? [:], after = proposed[key] as? [String:Any] ?? [:]
                for day in Set(before.keys).union(after.keys) where !RecordPatch.equal(before[day],after[day]) {
                    let ids = after[day] as? [String] ?? (after[day] as? String).map { [$0] } ?? []
                    guard ids.allSatisfy({ $0 == "rest" || valid.contains($0) }) else { throw APIError.response(409,L10n.text("A_SCHEDULED_ROUTINE_WAS_DELETED_CHOOSE_ANOTHER_ROUTINE" /* 排期中的计划已被删除，请重新选择。 */)) }
                }
            }
            return next
        }
    }
    func scheduledRoutines(on date:Date) -> [Routine] {
        let result = try? WebRules.shared.call("schedule",payload:["state":state,"dates":[dayString(date)],"today":dayString()])
        let ids = (result as? [[String]])?.first ?? []
        return ids.compactMap { id in routines.first { $0.id == id } }
    }
    func trainingDayMarkers(on dates: [Date]) -> [TrainingDayMarker] {
        let recordedDays = Set(workouts.compactMap { $0["d"] as? String })
        let validRoutineIDs = Set(routines.map(\.id))
        // Resolve the whole visible week once, using the same overrides and rotation rules as the card.
        let schedule = (try? WebRules.shared.call("schedule", payload: ["state": state,
            "dates": dates.map { dayString($0) }, "today": dayString()])) as? [[String]] ?? []
        return dates.enumerated().map { index, date in
            if recordedDays.contains(dayString(date)) { return .completed }
            if schedule.indices.contains(index), schedule[index].contains(where: { validRoutineIDs.contains($0) }) { return .planned }
            return .none
        }
    }
    func saveWorkout(original:[String:Any],proposed:[String:Any],expectedUnit:String) async -> Bool {
        guard keepHistoryEdit(original:original,proposed:proposed,unit:expectedUnit,submit:true) else { editError = localSaveError; return false }
        return await submitHistoryEdit(WorkoutRecord.key(original))
    }
    func submitHistoryEdit(_ key:String) async -> Bool {
        guard let item = historyEdits[key], let original = item["original"] as? [String:Any],
              let proposed = item["proposed"] as? [String:Any], let generation = item["generation"] as? String else { return false }
        if let fields = item["form"] as? [String:Any], let minutes = fields["minutes"] as? String, TrainingInput.value(minutes) == nil {
            editError = L10n.text("THE_DURATION_IS_INCOMPLETE_YOUR_LOCAL_INPUT_HAS_BEEN_KEPT" /* 时长还未填完，本机输入已保留。 */); return false
        }
        do { try TrainingInput.validate(proposed) } catch { editError = error.localizedDescription; return false }
        guard persistHistoryEdits() else { editError = localSaveError; return false }
        var expected = item["expected"] as? [String:Any]
        let ok = await mutate(reportError:false,verify:{ source in
            guard let expected else { return false }
            return (source["workouts"] as? [[String:Any]] ?? []).contains { WorkoutRecord.key($0) == key && RecordPatch.equal($0,expected) }
        }) { source in
            if let expected, let current = (source["workouts"] as? [[String:Any]] ?? []).first(where:{WorkoutRecord.key($0) == key}), RecordPatch.equal(current,expected) { return source }
            let current = (source["workouts"] as? [[String:Any]] ?? []).first { WorkoutRecord.key($0) == key }
            let prior = item["priorExpected"] as? [String:Any]
            let baseline = prior != nil && RecordPatch.equal(prior,current) ? prior! : original
            let next = try self.patchedWorkoutState(source:source,original:baseline,proposed:TrainingInput.clean(proposed) as! [String:Any],expectedUnit:item["unit"] as? String ?? "kg")
            expected = (next["workouts"] as? [[String:Any]])?.first { WorkoutRecord.key($0) == key }
            guard self.historyEdits[key]?["generation"] as? String == generation else { throw APIError.response(0,L10n.text("YOUR_LOCAL_EDITS_HAVE_CHANGED_SUBMIT_THE_LATEST_VERSION" /* 本机编辑已更新，请提交最新内容。 */)) }
            self.historyEdits[key]?["expected"] = expected
            self.historyEdits[key]?["submitted"] = true
            guard self.persistHistoryEdits() else { throw APIError.response(0,self.localSaveError ?? L10n.text("COULD_NOT_SAVE_ON_THIS_DEVICE" /* 本机保存失败 */)) }
            return next
        }
        if ok {
            let archived = archiveHistoryEdit(key,generation:generation)
            if !archived { editError = localSaveError ?? L10n.text("NEW_INPUT_WAS_ENTERED_AFTER_SUBMITTING_IT_HAS_BEEN_KEPT_FOR_YOU" /* 提交后有更新的本机输入，已保留，请继续核对。 */) }
            return archived
        }
        return false
    }
    func patchedWorkoutState(source:[String:Any],original:[String:Any],proposed:[String:Any],expectedUnit:String) throws -> [String:Any] {
            guard (source["unit"] as? String ?? "kg") == expectedUnit else { throw APIError.response(409,L10n.text("THE_WEIGHT_UNIT_CHANGED_REOPEN_THE_EDITOR" /* 重量单位已改变，请重新打开编辑器。 */)) }
            var state = source; var list = state["workouts"] as? [[String:Any]] ?? []
            let key = WorkoutRecord.key(original)
            guard let i = list.firstIndex(where:{WorkoutRecord.key($0) == key}) else { throw APIError.response(404,L10n.text("THIS_WORKOUT_WAS_DELETED_SAVING_YOUR_EDITS_WILL_NOT_RECREATE_IT" /* 这条训练已被删除，你的修改不会重新创建它。 */)) }
            var next = try RecordPatch.apply(original:original,proposed:proposed,current:list[i])
            guard !(next["name"] as? String ?? "").trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else { throw APIError.response(0,L10n.text("ENTER_A_WORKOUT_NAME" /* 请输入训练名称。 */)) }
            let timeChanged = !RecordPatch.equal(original["start"],proposed["start"]) || !RecordPatch.equal(original["end"],proposed["end"])
            if timeChanged {
                let start = number(next["start"]), end = number(next["end"])
                guard start.isFinite, end.isFinite, end >= start, end-start <= 86_400_000, end <= Date().timeIntervalSince1970*1000 else { throw APIError.response(0,L10n.text("THE_END_TIME_CANNOT_BE_IN_THE_FUTURE_DURATION_MUST_BE_BETWEEN" /* 结束时间不能在未来，时长需要在 0–1440 分钟内。 */)) }
            }
            let entriesChanged = !RecordPatch.equal(original["entries"],proposed["entries"])
            if entriesChanged {
                let entries = next["entries"] as? [[String:Any]] ?? []
                guard entries.contains(where: { ($0["sets"] as? [[String:Any]] ?? []).contains(where:rawCompleted) }) else { throw APIError.response(0,L10n.text("KEEP_AT_LEAST_ONE_COMPLETED_SET" /* 请至少保留一组已完成的训练。 */)) }
                for entry in entries {
                    for set in entry["sets"] as? [[String:Any]] ?? [] where EditValidation.ordinarySet(set,entry:entry) {
                        guard EditValidation.validNumber(set["w"] ?? 0,0...2000), EditValidation.validNumber(set["r"] ?? 0,0...1000) else { throw APIError.response(0,L10n.text("CHECK_THE_WEIGHT_AND_REPS_FOR_EACH_SET" /* 请检查每组的重量和次数。 */)) }
                    }
                }
            }
            next["id"] = key // Freeze the legacy date/start identity before moving it.
            let previous = list[i]; list[i] = next; state["workouts"] = list
            if entriesChanged || !RecordPatch.equal(original["start"],proposed["start"]) {
                let touched = Set(((previous["entries"] as? [[String:Any]] ?? []) + (next["entries"] as? [[String:Any]] ?? [])).compactMap { $0["id"] as? String })
                guard let repaired = try WebRules.shared.call("repairHistory",payload:["state":state,"changedID":key,"touched":Array(touched),"recomputeEntries":entriesChanged,"previous":previous]) as? [String:Any] else { throw APIError.invalidResponse }
                state = repaired
            }
            return state
    }
}

enum TrainingDayMarker: Equatable {
    case none, planned, completed
}
