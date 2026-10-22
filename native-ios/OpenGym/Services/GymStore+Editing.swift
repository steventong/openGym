import Foundation
extension GymStore {
    func saveRoutine(original:[String:Any],proposed:[String:Any],expectedUnit:String) async -> Bool {
        await mutate(reportError:false) { source in
            guard (source["unit"] as? String ?? "kg") == expectedUnit else { throw APIError.response(409,"重量单位已改变，请重新打开编辑器。") }
            var state = source; var list = state["routines"] as? [[String:Any]] ?? []
            guard let i = list.firstIndex(where: { $0["id"] as? String == original["id"] as? String }) else { throw APIError.response(404,"计划已被删除，不能保存旧副本。") }
            let merged = try RecordPatch.apply(original:original,proposed:proposed,current:list[i])
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
                    guard ids.allSatisfy({ $0 == "rest" || valid.contains($0) }) else { throw APIError.response(409,"排期中的计划已被删除，请重新选择。") }
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
    func saveWorkout(original:[String:Any],proposed:[String:Any],expectedUnit:String) async -> Bool {
        await mutate(reportError:false) { source in
            guard (source["unit"] as? String ?? "kg") == expectedUnit else { throw APIError.response(409,"重量单位已改变，请重新打开编辑器。") }
            var state = source; var list = state["workouts"] as? [[String:Any]] ?? []
            let key = WorkoutRecord.key(original)
            guard let i = list.firstIndex(where:{WorkoutRecord.key($0) == key}) else { throw APIError.response(404,"这条训练已被删除，你的修改不会重新创建它。") }
            var next = try RecordPatch.apply(original:original,proposed:proposed,current:list[i])
            guard !(next["name"] as? String ?? "").trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else { throw APIError.response(0,"请输入训练名称。") }
            let timeChanged = !RecordPatch.equal(original["start"],proposed["start"]) || !RecordPatch.equal(original["end"],proposed["end"])
            if timeChanged {
                let start = number(next["start"]), end = number(next["end"])
                guard start.isFinite, end.isFinite, end >= start, end-start <= 86_400_000, end <= Date().timeIntervalSince1970*1000 else { throw APIError.response(0,"结束时间不能在未来，时长需要在 0–1440 分钟内。") }
            }
            let entriesChanged = !RecordPatch.equal(original["entries"],proposed["entries"])
            if entriesChanged {
                let entries = next["entries"] as? [[String:Any]] ?? []
                guard entries.contains(where: { ($0["sets"] as? [[String:Any]] ?? []).contains { $0["done"] as? Bool == true } }) else { throw APIError.response(0,"请至少保留一组已完成的训练。") }
                for entry in entries {
                    for set in entry["sets"] as? [[String:Any]] ?? [] where EditValidation.ordinarySet(set,entry:entry) {
                        guard EditValidation.validNumber(set["w"] ?? 0,0...2000), EditValidation.validNumber(set["r"] ?? 0,0...1000) else { throw APIError.response(0,"请检查每组的重量和次数。") }
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
}
