import Foundation

extension GymStore {
    var favouriteIDs: Set<String> { Set(state["favEx"] as? [String] ?? []) }
    var customExercises: [[String:Any]] { state["customEx"] as? [[String:Any]] ?? [] }
    func personalInfo(_ action:String, _ extra:[String:Any] = [:]) throws -> [String:Any] {
        var payload = extra; payload["action"] = action; payload["state"] = state
        guard let result = try WebRules.shared.call("personalInfo",payload:payload) as? [String:Any] else { throw APIError.invalidResponse }
        return result
    }
    /// Patch only fields shown by the editor; concurrent, unrelated profile edits survive.
    func savePersonalFields(original:[String:Any],proposed:[String:Any],unit expected:String? = nil) async -> Bool {
        var expectedValues:[String:Any]?
        let keys = Set(original.keys).union(proposed.keys)
        return await mutate(reportError:false,verify:{ source in
            guard let expectedValues else { return false }
            return keys.allSatisfy { RecordPatch.equal(source[$0],expectedValues[$0]) }
        }) { source in
            if let expected, (source["unit"] as? String ?? "kg") != expected { throw APIError.response(409,"重量单位已改变，请重新打开页面。") }
            let next = try PersonalPatch.apply(original:original,proposed:proposed,current:source)
            expectedValues = next; return next
        }
    }
    func setFavourite(_ id:String,enabled:Bool) async -> Bool {
        await mutate(verify:{ (Set($0["favEx"] as? [String] ?? []).contains(id)) == enabled }) { source in
            var s = source; var ids = source["favEx"] as? [String] ?? []
            ids.removeAll { $0 == id }; if enabled { ids.append(id) }; s["favEx"] = ids; return s
        }
    }
    /// Date-keyed measurements and ID-keyed customs update one record, never the entire array.
    func savePersonalRecord(collection:String,key:String,original:[String:Any]?,proposed:[String:Any]?,unit expected:String? = nil) async -> Bool {
        let identity = original?[key] as? String ?? proposed?[key] as? String ?? ""
        let destination = proposed?[key] as? String ?? identity
        var confirmed:[String:Any]?
        return await mutate(reportError:false,verify:{ source in
            let list = source[collection] as? [[String:Any]] ?? []
            if proposed == nil { return !list.contains { $0[key] as? String == identity } }
            return list.contains { $0[key] as? String == destination && RecordPatch.equal($0,confirmed) }
        }) { source in
            if let expected, (source["unit"] as? String ?? "kg") != expected { throw APIError.response(409,"单位已改变，请重新打开编辑器。") }
            var s = source, list = source[collection] as? [[String:Any]] ?? []
            let index = list.firstIndex { $0[key] as? String == identity }
            if let proposed {
                if identity != destination, list.contains(where:{$0[key] as? String == destination}) { throw APIError.response(409,"该日期已有记录，请编辑已有记录。") }
                if let index {
                    if let original { list[index] = try PersonalRecordPatch.apply(original:original,proposed:proposed,current:list[index]) }
                    else if !PersonalRecordPatch.sameValues(list[index],proposed) { throw APIError.response(409,"记录已存在，请重新打开编辑器。") }
                    confirmed = list[index]
                } else {
                    guard original == nil else { throw APIError.response(409,"记录已在其他设备删除。") }
                    list.append(proposed); confirmed = proposed
                }
            } else if let index {
                guard RecordPatch.equal(list[index],original) else { throw APIError.response(409,"记录已在其他设备修改，请刷新后核对。") }
                list.remove(at:index)
            }
            if key == "d" { list.sort { ($0[key] as? String ?? "") < ($1[key] as? String ?? "") } }
            s[collection] = list; return s
        }
    }
    func switchProfileUnit(to:String,convert:Bool) async -> Bool {
        guard draft == nil, historyEdits.isEmpty else { editError = "请先保存训练与历史编辑草稿，再切换账号单位。"; return false }
        let before = unit
        return await mutate(reportError:false,verify:{$0["unit"] as? String == to}) { source in
            let current = source["unit"] as? String ?? "kg"
            if current == to { return source }
            guard current == before, ["kg","lb"].contains(to) else { throw APIError.response(409,"账号单位已改变。") }
            return try WebRules.shared.call("personalChange",payload:["action":"unit","state":source,"unit":to,"convert":convert]) as! [String:Any]
        }
    }
    func copyRoutine(_ routine:Routine,newID:String) async -> Bool {
        await mutate(verify:{ ($0["routines"] as? [[String:Any]] ?? []).contains { $0["id"] as? String == newID } }) { source in
            var s = source; var list = s["routines"] as? [[String:Any]] ?? []
            if list.contains(where:{$0["id"] as? String == newID}) { return s }
            guard var copy = list.first(where:{$0["id"] as? String == routine.id}) else { throw APIError.response(404,"原计划已删除。") }
            copy = RecordPatch.clean(copy) as! [String:Any]; copy["id"] = newID; copy["name"] = (copy["name"] as? String ?? "训练") + " 副本"
            list.append(copy); s["routines"] = list; return s
        }
    }
    func deletePersonalWorkout(_ record:WorkoutRecord) async -> Bool {
        guard historyEdits[record.id] == nil else { editError = "此记录有本机编辑草稿，请先保存或放弃草稿。"; return false }
        return await mutate(reportError:false,verify:{ !($0["workouts"] as? [[String:Any]] ?? []).contains { WorkoutRecord.key($0) == record.id } }) { source in
            if let current = (source["workouts"] as? [[String:Any]] ?? []).first(where:{WorkoutRecord.key($0) == record.id}), !RecordPatch.equal(current,record.raw) { throw APIError.response(409,"训练记录已在其他设备修改，请刷新后核对。") }
            return try WebRules.shared.call("personalChange",payload:["action":"deleteWorkout","state":source,"id":record.id]) as! [String:Any]
        }
    }
    func deleteCustomExercise(_ original:[String:Any]) async -> Bool {
        let id = original["id"] as? String ?? ""
        guard !(draft?.rawEntries.contains { $0["id"] as? String == id } ?? false), historyEdits.isEmpty else { editError = "请先保存训练与历史编辑草稿。"; return false }
        return await mutate(reportError:false,verify:{ !($0["customEx"] as? [[String:Any]] ?? []).contains { $0["id"] as? String == id } }) { source in
            if let current = (source["customEx"] as? [[String:Any]] ?? []).first(where:{$0["id"] as? String == id}), !RecordPatch.equal(current,original) { throw APIError.response(409,"动作已在其他设备修改，请刷新后核对。") }
            return try WebRules.shared.call("personalChange",payload:["action":"deleteCustom","state":source,"id":id]) as! [String:Any]
        }
    }
}

extension GymStore {
    func repeatPersonalWorkout(_ record:WorkoutRecord) -> Bool {
        guard draft == nil else { error = "请先完成当前训练。";return false }
        guard userID != nil else {showSettings = true;return false}
        do {
            let result = try WebRules.shared.call("personalRepeat",payload:["state":state,"workout":record.raw,"id":UUID().uuidString,"day":dayString(),"now":Date().timeIntervalSince1970*1000]) as! [String:Any]
            draft = try TrainingDraft.fromWeb(result["active"] as! [String:Any],unit:unit)
            guard persistDraft() else {error = localSaveError;return false}
            selectedTab = 2
            if number(result["skipped"])>0 {error = "已开始训练；\(Int(number(result["skipped"]))) 个已删除动作无法重复。"}
            return true
        } catch {self.error = error.localizedDescription;return false}
    }
}

/// Personal preference maps use their own per-choice timestamps in web sync.
enum PersonalPatch {
    static func apply(original:[String:Any],proposed:[String:Any],current:[String:Any]) throws -> [String:Any] {
        var result = try RecordPatch.apply(original:original,proposed:proposed,current:current)
        for (key,value) in proposed {
            guard !RecordPatch.equal(original[key],value),let desired = value as? [String:Any],let merged = result[key] as? [String:Any] else {continue}
            result[key] = try apply(original:original[key] as? [String:Any] ?? [:],proposed:desired,current:merged)
        }
        if !RecordPatch.equal(original,proposed),let stamp = proposed["_ts"] { result["_ts"] = stamp }
        return result
    }
}

/// `t` records save time, not a user-editable measurement. Retrying a lost response must
/// compare the measurement itself, while still refusing a changed remote value.
enum PersonalRecordPatch {
    static func sameValues(_ a:[String:Any],_ b:[String:Any])->Bool {
        RecordPatch.equal(a.filter {$0.key != "t"},b.filter {$0.key != "t"})
    }
    static func apply(original:[String:Any],proposed:[String:Any],current:[String:Any]) throws -> [String:Any] {
        if sameValues(proposed,current) {return current}
        var next = try RecordPatch.apply(original:original.filter {$0.key != "t"},proposed:proposed.filter {$0.key != "t"},current:current)
        if let t = proposed["t"] {next["t"] = t}
        return next
    }
}
