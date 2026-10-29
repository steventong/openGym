import Foundation
extension GymStore {
    func changeActive(_ change:(inout [String:Any]) throws -> Void) {
        guard var d = draft else { return }
        do { var raw = d.activeJSON;try change(&raw);if !RecordPatch.equal(raw["entries"],d.activeJSON["entries"]) { raw.removeValue(forKey:"nativeFinishAt") };if let undo = raw["nativeSetUndo"] as? [String: Any], !RecordPatch.equal(undo["expected"], raw["entries"]) { raw.removeValue(forKey: "nativeSetUndo") };try d.setActive(raw);draft = d } catch { self.error = error.localizedDescription }
    }
    func replaceLiveRow(entry:Int,set:Int,row:[String:Any]) {
        changeActive { raw in
            var entries = raw["entries"] as? [[String:Any]] ?? [];guard entries.indices.contains(entry) else { return }
            var sets = entries[entry]["sets"] as? [[String:Any]] ?? [];guard sets.indices.contains(set) else { return }
            sets[set] = row;entries[entry]["sets"] = sets;raw["entries"] = entries
        }
    }
    @discardableResult func liveRowAction(entry:Int,set:Int,action:[String:Any]) -> Bool {
        guard let d = draft,d.rawEntries.indices.contains(entry) else { return false }
        let en = d.rawEntries[entry],rows = en["sets"] as? [[String:Any]] ?? [];guard rows.indices.contains(set) else { return false }
        do {
            var inputState = state; inputState["unit"] = d.unit
            let row = try TrainingInput.edit(row:rows[set],action:action,target:en["target"] as? [String:Any] ?? [:],state:inputState,editing:false)
            let operation = action["operation"] as? [String: Any] ?? action
            let path = action["path"] as? String ?? ""
            let isWeight = operation["action"] as? String == "field" && operation["key"] as? String == "w"
            let validInput = action["action"] as? String != "input" || TrainingInput.valid(action["text"] as? String ?? "", path: path)
            if isWeight && validInput {
                var next = rows; next[set] = row
                var payload: [String: Any] = ["sets": next, "index": set, "target": en["target"] as? [String: Any] ?? [:]]
                payload["side"] = operation["side"]
                let cascaded = try WebRules.shared.call("cascadeNativeWeight", payload: payload) as! [[String: Any]]
                changeActive { raw in
                    var entries = raw["entries"] as! [[String: Any]]
                    entries[entry]["sets"] = cascaded; raw["entries"] = entries
                }
            } else { replaceLiveRow(entry:entry,set:set,row:row) }
            if action["action"] as? String == "toggle",row["done"] as? Bool == true { applyRest(entry:entry,set:set) }
            return localSaveError == nil
        } catch { self.error = error.localizedDescription; return false }
    }
    func applyRest(entry:Int,set:Int) {
        guard let d = draft else { return }
        do {
            let info = try WebRules.shared.call("restForCompleted",payload:["active":d.activeJSON,"entry":entry,"index":set,"state":state,"timerRunning":(restUntil ?? .distantPast) > Date()]) as! [String:Any]
            changeActive { raw in var levels = raw["nativeHighWater"] as? [String:Any] ?? [:];levels[String(entry)] = info["highWater"];raw["nativeHighWater"] = levels }
            if info["preserveRest"] as? Bool == true { return }
            let seconds = number(info["seconds"]); startRest(entry:entry,seconds:seconds,set:set)
            let rows = d.rawEntries[entry]["sets"] as? [[String:Any]] ?? []
            let exerciseDone = !rows.isEmpty && rows.allSatisfy { $0["done"] as? Bool == true }
            // Keep a completed exercise visible until the user taps the next-exercise button.
            changeActive { raw in raw["cur"] = seconds > 0 || exerciseDone ? entry : info["next"] }
        } catch { self.error = error.localizedDescription }
    }
    var restEntry: Int? { (draft?.activeJSON["nativeRest"] as? [String:Any])?["entry"] as? Int }
    func startRest(entry:Int,seconds:Double,set:Int? = nil) {
        changeActive { raw in
            if seconds > 0 {
                var rest: [String: Any] = ["entry":entry,"end":Date().addingTimeInterval(seconds).timeIntervalSince1970]
                rest["set"] = set; raw["nativeRest"] = rest
            }
            else { raw.removeValue(forKey:"nativeRest") }
        }
    }
    func selectLiveEntry(_ index:Int) { changeActive { $0["cur"] = index } }
    func adjustRest(by seconds: Double) {
        changeActive { raw in
            guard var rest = raw["nativeRest"] as? [String: Any] else { return }
            rest["end"] = max(Date().timeIntervalSince1970, number(rest["end"])) + seconds
            if number(rest["end"]) <= Date().timeIntervalSince1970 { raw.removeValue(forKey: "nativeRest") }
            else { raw["nativeRest"] = rest }
        }
    }
    func copyLiveSet(entry: Int, set: Int) {
        guard workTimer == nil else { return }
        changeActive { raw in
            var entries = raw["entries"] as? [[String: Any]] ?? []
            guard entries.indices.contains(entry) else { return }
            let sets = entries[entry]["sets"] as? [[String: Any]] ?? []
            guard sets.indices.contains(set) else { return }
            try TrainingInput.validate(sets[set])
            let result = try WebRules.shared.call("copySelectedSet", payload: ["sets": sets, "index": set]) as! [String: Any]
            let at = Int(number(result["at"])), count = Int(number(result["count"]))
            try TrainingInput.validate(Array(sets[(at - count)..<at]))
            entries[entry]["sets"] = result["sets"]; raw["entries"] = entries
            if var timer = raw["nativeRest"] as? [String: Any], timer["entry"] as? Int == entry,
               let index = timer["set"] as? Int, index >= Int(number(result["at"])) {
                timer["set"] = index + Int(number(result["count"])); raw["nativeRest"] = timer
            }
        }
    }
    func startExerciseRest(entry: Int, seconds: Double) {
        guard workTimer == nil else { return }
        changeActive { raw in
            var entries = raw["entries"] as? [[String: Any]] ?? []
            guard entries.indices.contains(entry) else { return }
            var target = entries[entry]["target"] as? [String: Any] ?? [:]
            target["restSec"] = seconds; entries[entry]["target"] = target; raw["entries"] = entries
            raw["nativeRest"] = ["entry": entry, "end": Date().addingTimeInterval(seconds).timeIntervalSince1970]
        }
    }
    func previousExerciseText(_ entry:[String:Any],before:Double,exclude:String) -> String {
        let payload:[String:Any] = ["state":state,"entry":entry,"before":before,"exclude":exclude]
        let prefix = state["logRef"] as? String == "best" ? "最佳":"上次"
        guard let result = try? WebRules.shared.call("personalReference",payload:payload) as? [String:Any], let date = result["date"] as? String, let label = result["label"] as? String else { return "\(prefix)：暂无同一动作的训练记录" }
        return "\(prefix) \(date) · \(label) · \(unit)"
    }
    func setLiveNote(entry:Int,text:String) {
        changeActive { raw in var entries = raw["entries"] as? [[String:Any]] ?? [];guard entries.indices.contains(entry) else {return};entries[entry]["note"] = text;raw["entries"] = entries }
    }
    func addLiveSet(entry:Int) {
        guard workTimer == nil else { return }
        changeActive { raw in
            var entries = raw["entries"] as? [[String:Any]] ?? [];guard entries.indices.contains(entry) else { return }
            var sets = entries[entry]["sets"] as? [[String:Any]] ?? []
            // The web helper clears completion on a copied set, including both sides.
            if let copied = try WebRules.shared.call("copyAdvancedSet",payload:["sets":sets,"target":entries[entry]["target"] as? [String:Any] ?? [:]]) as? [[String:Any]] { sets = copied }
            entries[entry]["sets"] = sets;raw["entries"] = entries
        }
    }
    func removeLiveSet(entry: Int, set: Int) {
        changeActive { raw in
            let before = raw
            var entries = raw["entries"] as? [[String: Any]] ?? []
            guard entries.indices.contains(entry) else { return }
            let sets = entries[entry]["sets"] as? [[String: Any]] ?? []
            guard sets.indices.contains(set) else { return }
            let result = try WebRules.shared.call("removeAdvancedSet", payload: ["sets": sets, "index": set]) as! [String: Any]
            let start = Int(number(result["start"])), count = Int(number(result["count"]))
            entries[entry]["sets"] = result["sets"]; raw["entries"] = entries
            for key in ["nativeTimer", "nativeRest"] {
                guard var timer = raw[key] as? [String: Any], timer["entry"] as? Int == entry else { continue }
                // Older rest timers lack an owning set; clear them on an edit to their exercise.
                guard let index = timer["set"] as? Int else { raw.removeValue(forKey: key); continue }
                if (start..<(start + count)).contains(index) { raw.removeValue(forKey: key) }
                else if index >= start + count { timer["set"] = index - count; raw[key] = timer }
            }
            var levels = raw["nativeHighWater"] as? [String: Any] ?? [:]
            levels[String(entry)] = result["highWater"]; raw["nativeHighWater"] = levels
            let keys = ["nativeTimer", "nativeRest", "nativeHighWater"]
            raw["nativeSetUndo"] = ["entries": before["entries"] ?? [], "expected": entries,
                "before": before.filter { keys.contains($0.key) }, "after": raw.filter { keys.contains($0.key) }]
        }
    }
    var canUndoSetRemoval: Bool { draft?.activeJSON["nativeSetUndo"] != nil }
    func undoSetRemoval() {
        changeActive { raw in
            guard let undo = raw["nativeSetUndo"] as? [String: Any], RecordPatch.equal(undo["expected"], raw["entries"]) else { return }
            raw["entries"] = undo["entries"]
            let before = undo["before"] as? [String: Any] ?? [:], after = undo["after"] as? [String: Any] ?? [:]
            for key in ["nativeTimer", "nativeRest", "nativeHighWater"] where RecordPatch.equal(raw[key], after[key]) { raw[key] = before[key] }
            raw.removeValue(forKey: "nativeSetUndo")
        }
    }
    var workTimer: [String:Any]? { draft?.activeJSON["nativeTimer"] as? [String:Any] }
    func startWorkTimer(entry:Int,set:Int) {
        guard let d = draft,d.rawEntries.indices.contains(entry),workTimer == nil else { return }
        let rows = d.rawEntries[entry]["sets"] as? [[String:Any]] ?? [];guard rows.indices.contains(set) else { return }
        let seconds = max(1,number(rows[set]["sec"] ?? 45)),now = Date().timeIntervalSince1970
        restUntil = nil
        changeActive { $0["nativeTimer"] = ["entry":entry,"set":set,"start":now,"end":now+seconds,"planned":seconds,"remaining":seconds,"elapsed":0,"paused":false] }
    }
    func pauseWorkTimer() {
        guard var timer = workTimer else { return };let now = Date().timeIntervalSince1970
        if timer["paused"] as? Bool == true { timer["start"] = now;timer["end"] = now+number(timer["remaining"]);timer["paused"] = false }
        else { timer["remaining"] = max(0,number(timer["end"])-now);timer["elapsed"] = number(timer["elapsed"])+max(0,now-number(timer["start"]));timer["paused"] = true }
        changeActive { $0["nativeTimer"] = timer }
    }
    func finishWorkTimer(cancel:Bool = false) {
        guard let timer = workTimer else { return }
        let e = Int(number(timer["entry"])),s = Int(number(timer["set"]))
        let elapsed = number(timer["elapsed"]) + (timer["paused"] as? Bool == true ? 0 : max(0,Date().timeIntervalSince1970-number(timer["start"])))
        changeActive { $0.removeValue(forKey:"nativeTimer") }
        guard !cancel else { return }
        liveRowAction(entry:e,set:s,action:["action":"field","key":"sec","value":max(1,min(number(timer["planned"]),elapsed.rounded()))])
        if let rows = draft?.rawEntries[e]["sets"] as? [[String:Any]],rows.indices.contains(s),rows[s]["done"] as? Bool != true { liveRowAction(entry:e,set:s,action:["action":"toggle"]) }
    }
    func settleTimer() { if let t = workTimer,t["paused"] as? Bool != true,number(t["end"]) <= Date().timeIntervalSince1970 { finishWorkTimer() } }
    func rotationSummary() -> [String:Any] {
        (try? WebRules.shared.call("rotationInfo",payload:["state":state,"today":dayString()])) as? [String:Any] ?? [:]
    }
    func updateRotation(action:String,ids:[String],label:String,baseline:[String:Any]) async -> Bool {
        let active = draft?.activeJSON
        return await mutate(reportError:false) { source in
            // Progress may change while editing; preserve it. Do not adopt another owner's queue silently.
            for key in ["rotation","scheduleMode"] where !RecordPatch.equal(baseline[key],source[key]) { throw APIError.response(409,"循环设置已在另一台设备改变，请重新打开后核对。") }
            let oldQueue = baseline["queue"] as? [String:Any] ?? [:],newQueue = source["queue"] as? [String:Any] ?? [:]
            if !RecordPatch.equal(oldQueue["rotationId"],newQueue["rotationId"]) { throw APIError.response(409,"排期归属已改变，请刷新后重试。") }
            var payload:[String:Any] = ["state":source,"action":action,"ids":ids,"label":label,"today":dayString(),"now":Date().timeIntervalSince1970*1000]
            if let active { payload["active"] = active }
            guard let result = try WebRules.shared.call("rotationChange",payload:payload) as? [String:Any] else { throw APIError.invalidResponse };return result
        }
    }
}
