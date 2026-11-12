import Foundation

extension GymStore {
    var favouriteIDs: Set<String> { Set(state["favEx"] as? [String] ?? []) }
    /// Only logged, completed work counts; planned or unfinished sets do not.
    var trainedExerciseIDs: Set<String> {
        Set(workouts.flatMap { $0["entries"] as? [[String: Any]] ?? [] }.compactMap { entry in
            guard let id = entry["id"] as? String, !id.isEmpty,
                  (entry["sets"] as? [[String: Any]] ?? []).contains(where: rawCompleted) else { return nil }
            return id
        })
    }
    var customExercises: [[String:Any]] { state["customEx"] as? [[String:Any]] ?? [] }
    func personalInfo(_ action:String, _ extra:[String:Any] = [:]) throws -> [String:Any] {
        var payload = extra; payload["action"] = action; payload["state"] = state
        guard let result = try WebRules.shared.call("personalInfo",payload:payload) as? [String:Any] else { throw APIError.invalidResponse }
        return result
    }
    func customExerciseNameIssue(_ name: String, original: [String: Any]? = nil) -> String? {
        guard !name.isEmpty, name.count <= 80 else {
            return String(localized: "USE_A_NAME_BETWEEN_ONE_AND_EIGHTZERO_CHARACTERS", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
        }
        if name.lowercased() != (original?["n"] as? String ?? "").lowercased(),
           exercises.contains(where: { exercise in
               exercise.id != original?["id"] as? String
                   && (exercise.name.localizedCaseInsensitiveCompare(name) == .orderedSame
                       || exercise.english.localizedCaseInsensitiveCompare(name) == .orderedSame)
           }) {
            return String(localized: "AN_EXERCISE_WITH_THIS_NAME_ALREADY_EXISTS", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
        }
        return nil
    }
    func exerciseCopyRecord(_ exercise: Exercise, id: String, name: String) throws -> [String: Any] {
        let custom = customExercises.first { $0["id"] as? String == exercise.id }
        let result = try WebRules.shared.call("personalInfo", payload: [
            "action": "exerciseDefinition", "state": ["customEx": custom.map { [$0] } ?? []], "id": exercise.id
        ]) as? [String: Any]
        guard let definition = result?["exercise"] as? [String: Any] else { throw APIError.invalidResponse }
        var copy = definition.filter { !RecordPatch.metadata.contains($0.key) }
        if custom == nil {
            copy["english"] = exercise.english
            copy["desc"] = exercise.description
            copy["instructions"] = exercise.instructions
            copy["englishInstructions"] = exercise.englishInstructions
            copy["st"] = exercise.englishInstructions ?? exercise.instructions
            copy["img"] = imageMediaID(exercise.id).map { "\($0).webp" }
            copy["gif"] = videoMediaID(exercise.id).map { "\($0).mp4" }
        }
        if let assisted = result?["assisted"] as? Bool { copy["assisted"] = assisted }
        copy["id"] = id
        copy["n"] = name
        copy["custom"] = true
        return copy
    }
    /// Patch only fields shown by the editor; concurrent, unrelated profile edits survive.
    func savePersonalFields(original:[String:Any],proposed:[String:Any],unit expected:String? = nil) async -> Bool {
        var expectedValues:[String:Any]?
        let keys = Set(original.keys).union(proposed.keys)
        return await mutate(reportError:false,verify:{ source in
            guard let expectedValues else { return false }
            return keys.allSatisfy { RecordPatch.equal(source[$0],expectedValues[$0]) }
        }) { source in
            if let expected, (source["unit"] as? String ?? "kg") != expected { throw APIError.response(409,String(localized: "THE_WEIGHT_UNIT_CHANGED_REOPEN_THIS_SCREEN", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) }
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
            if let expected, (source["unit"] as? String ?? "kg") != expected { throw APIError.response(409,String(localized: "THE_UNIT_CHANGED_REOPEN_THE_EDITOR", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) }
            var s = source, list = source[collection] as? [[String:Any]] ?? []
            let index = list.firstIndex { $0[key] as? String == identity }
            if let proposed {
                if identity != destination, list.contains(where:{$0[key] as? String == destination}) { throw APIError.response(409,String(localized: "A_RECORD_ALREADY_EXISTS_FOR_THIS_DATE_EDIT_THAT_RECORD_INSTEAD", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) }
                if let index {
                    if let original { list[index] = try PersonalRecordPatch.apply(original:original,proposed:proposed,current:list[index]) }
                    else if !PersonalRecordPatch.sameValues(list[index],proposed) { throw APIError.response(409,String(localized: "THIS_RECORD_ALREADY_EXISTS_REOPEN_THE_EDITOR", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) }
                    confirmed = list[index]
                } else {
                    guard original == nil else { throw APIError.response(409,String(localized: "THIS_RECORD_WAS_DELETED_ON_ANOTHER_DEVICE", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) }
                    list.append(proposed); confirmed = proposed
                }
            } else if let index {
                guard RecordPatch.equal(list[index],original) else { throw APIError.response(409,String(localized: "THIS_RECORD_CHANGED_ON_ANOTHER_DEVICE_REFRESH_TO_REVIEW_IT", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) }
                list.remove(at:index)
            }
            if key == "d" { list.sort { ($0[key] as? String ?? "") < ($1[key] as? String ?? "") } }
            s[collection] = list; return s
        }
    }
    func switchProfileUnit(to:String,convert:Bool) async -> Bool {
        guard draft == nil, historyEdits.isEmpty else { editError = String(localized: "SAVE_WORKOUT_AND_HISTORY_DRAFTS_BEFORE_CHANGING_YOUR_ACCOUNT_S_UNIT", bundle: AppLanguage.bundle, locale: AppLanguage.locale); return false }
        let before = unit
        return await mutate(reportError:false,verify:{$0["unit"] as? String == to}) { source in
            let current = source["unit"] as? String ?? "kg"
            if current == to { return source }
            guard current == before, ["kg","lb"].contains(to) else { throw APIError.response(409,String(localized: "YOUR_ACCOUNT_S_UNIT_HAS_CHANGED", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) }
            return try WebRules.shared.call("personalChange",payload:["action":"unit","state":source,"unit":to,"convert":convert]) as! [String:Any]
        }
    }
    func copyRoutine(_ routine:Routine,newID:String) async -> Bool {
        await mutate(verify:{ ($0["routines"] as? [[String:Any]] ?? []).contains { $0["id"] as? String == newID } }) { source in
            var s = source; var list = s["routines"] as? [[String:Any]] ?? []
            if list.contains(where:{$0["id"] as? String == newID}) { return s }
            guard var copy = list.first(where:{$0["id"] as? String == routine.id}) else { throw APIError.response(404,String(localized: "THE_ORIGINAL_ROUTINE_WAS_DELETED", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) }
            copy = RecordPatch.clean(copy) as! [String:Any]; copy["id"] = newID; copy["name"] = (copy["name"] as? String ?? String(localized: "WORKOUT", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) + String(localized: "COPY_A", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
            list.append(copy); s["routines"] = list; return s
        }
    }
    func deletePersonalWorkout(_ record:WorkoutRecord) async -> Bool {
        guard historyEdits[record.id] == nil else { editError = String(localized: "THIS_RECORD_HAS_A_LOCAL_DRAFT_SAVE_OR_DISCARD_IT_FIRST", bundle: AppLanguage.bundle, locale: AppLanguage.locale); return false }
        return await mutate(reportError:false,verify:{ !($0["workouts"] as? [[String:Any]] ?? []).contains { WorkoutRecord.key($0) == record.id } }) { source in
            if let current = (source["workouts"] as? [[String:Any]] ?? []).first(where:{WorkoutRecord.key($0) == record.id}), !RecordPatch.equal(current,record.raw) { throw APIError.response(409,String(localized: "THIS_WORKOUT_CHANGED_ON_ANOTHER_DEVICE_REFRESH_TO_REVIEW_IT", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) }
            return try WebRules.shared.call("personalChange",payload:["action":"deleteWorkout","state":source,"id":record.id]) as! [String:Any]
        }
    }
    private var localExerciseEntries: [[String: Any]] {
        (draft?.rawEntries ?? []) + historyEdits.values.flatMap { edit in
            (edit["proposed"] as? [String: Any])?["entries"] as? [[String: Any]] ?? []
        }
    }
    private var customExerciseInUseMessage: String {
        String(localized: "CUSTOM_EXERCISE_STILL_IN_USE", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
    }
    func customExerciseDeletionIssue(_ id: String) -> String? {
        do {
            let usage = try personalInfo("customExerciseInUse", ["id": id, "localEntries": localExerciseEntries])
            guard let inUse = usage["inUse"] as? Bool else { throw APIError.invalidResponse }
            return inUse ? customExerciseInUseMessage : nil
        } catch {
            return error.localizedDescription
        }
    }
    func deleteCustomExercise(_ original:[String:Any]) async -> Bool {
        guard let id = original["id"] as? String, !id.isEmpty else { editError = APIError.invalidResponse.localizedDescription; return false }
        return await mutate(reportError:false,verify:{ !($0["customEx"] as? [[String:Any]] ?? []).contains { $0["id"] as? String == id } }) { source in
            if let current = (source["customEx"] as? [[String:Any]] ?? []).first(where:{$0["id"] as? String == id}), !RecordPatch.equal(current,original) { throw APIError.response(409,String(localized: "THIS_EXERCISE_CHANGED_ON_ANOTHER_DEVICE_REFRESH_TO_REVIEW_IT", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) }
            let result = try WebRules.shared.call("personalChange", payload: [
                "action": "deleteCustom", "state": source, "id": id, "localEntries": self.localExerciseEntries
            ]) as? [String: Any]
            if result?["inUse"] as? Bool == true { throw APIError.response(409, self.customExerciseInUseMessage) }
            guard let next = result?["state"] as? [String: Any] else { throw APIError.invalidResponse }
            return next
        }
    }
}

extension GymStore {
    func repeatPersonalWorkout(_ record:WorkoutRecord) -> Bool {
        guard draft == nil else { error = String(localized: "FINISH_YOUR_CURRENT_WORKOUT_FIRST", bundle: AppLanguage.bundle, locale: AppLanguage.locale);return false }
        guard userID != nil else {showSettings = true;return false}
        do {
            let result = try WebRules.shared.call("personalRepeat",payload:["state":state,"workout":record.raw,"id":UUID().uuidString,"day":dayString(),"now":Date().timeIntervalSince1970*1000]) as! [String:Any]
            draft = try TrainingDraft.fromWeb(result["active"] as! [String:Any],unit:unit)
            guard persistDraft() else {error = localSaveError;return false}
            selectedTab = 2
            if number(result["skipped"])>0 {error = String(format: String(localized: "WORKOUT_STARTED_COUNT_DELETED_EXERCISES_COULD_NOT_BE_REPEATED", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(describing: Int(number(result["skipped"]))))}
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
