import Foundation
import CryptoKit

extension GymStore {
    func watchSnapshot(now: Date = Date()) -> WatchTrainingSnapshot {
        var snapshot = WatchTrainingSnapshot(generatedAt: now)
        snapshot.language = AppLanguage.language
        snapshot.autoEndRestEnabled = autoEndRestEnabled
        guard let userID else { return snapshot }
        snapshot.account = Self.watchHash(Data("\(serverURL)|\(userID)".utf8))
        guard let draft else { return snapshot }
        snapshot.sessionID = draft.id
        snapshot.actionReadyAt = trainingActionReadyAt
        if TrainingSetClock.identity(draft.activeJSON) != nil {
            snapshot.setStartedAt = (draft.activeJSON["nativeSetStartedAt"] as? Double).map(Date.init(timeIntervalSince1970:))
            // Only the untouched first set can safely use the session start in older drafts.
            if snapshot.setStartedAt == nil, (draft.activeJSON["cur"] as? Int ?? 0) == 0,
               !draft.rawEntries.contains(where: { entry in
                   (entry["sets"] as? [[String: Any]] ?? []).contains { row in
                       row["done"] as? Bool == true ||
                       (row["sides"] as? [String: [String: Any]] ?? [:]).values.contains { $0["done"] as? Bool == true }
                   }
               }) { snapshot.setStartedAt = draft.start }
        }
        // Display-only elapsed time must not invalidate an otherwise identical set command.
        var commandState = draft.activeJSON
        commandState.removeValue(forKey: "nativeSetStartedAt")
        snapshot.revision = Self.watchHash((try? JSONSerialization.data(withJSONObject: commandState, options: [.sortedKeys])) ?? Data())
        snapshot.acknowledged = draft.activeJSON["nativeWatchReceipts"] as? [String] ?? []
        let entries = draft.rawEntries
        guard !entries.isEmpty else { snapshot.message = String(localized: "ADD_EXERCISES_ON_IPHONE", bundle: AppLanguage.bundle, locale: AppLanguage.locale); return snapshot }
        let e = min(max(0, draft.activeJSON["cur"] as? Int ?? 0), entries.count - 1)
        let entry = entries[e], rows = entry["sets"] as? [[String: Any]] ?? []
        snapshot.exercise = watchExerciseName(entry)
        snapshot.exercisePosition = String(format: String(localized: "EXERCISE_COUNT_OF_COUNT", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(describing: e + 1), String(describing: entries.count))
        if let rest = draft.activeJSON["nativeRest"] as? [String: Any], let end = rest["end"] as? Double {
            snapshot.restEnd = Date(timeIntervalSince1970: end)
            snapshot.restStartedAt = (rest["start"] as? Double).map(Date.init(timeIntervalSince1970:))
            snapshot.restEntry = rest["entry"] as? Int
            if let owner = rest["entry"] as? Int, entries.indices.contains(owner) { snapshot.restExercise = watchExerciseName(entries[owner]) }
        }
        let target = entry["target"] as? [String: Any] ?? [:]
        func summary(for index: Int) -> WatchTrainingSet {
            let row = rows[index]
            let sides = row["sides"] as? [String: [String: Any]]
            let side = sides.map { $0["L"]?["done"] as? Bool == true ? "R" : "L" }
            let data = side.flatMap { sides?[$0] } ?? row
            let mode = ((try? WebRules.shared.call("rowInfo", payload: ["row": row, "target": target])) as? [String: Any])?["mode"] as? String ?? "reps"
            let logicalIndexes = rows.indices.filter { !(rows[$0]["side"] as? String == "R" && $0 > 0 && rows[$0 - 1]["side"] as? String == "L") }
            let setNumber = logicalIndexes.filter { $0 <= index }.count
            let sideLabel = side ?? row["side"] as? String
            var label = String(format: String(localized: "SET_COUNT_OF_COUNT", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(describing: setNumber), String(describing: logicalIndexes.count))
            if let sideLabel { label += sideLabel == "L" ? String(localized: "LEFT_A", bundle: AppLanguage.bundle, locale: AppLanguage.locale) : String(localized: "RIGHT_A", bundle: AppLanguage.bundle, locale: AppLanguage.locale) }
            if row["warmup"] as? Bool == true || row["phase"] as? String == "warmup" { label += String(localized: "WARM_UP_A", bundle: AppLanguage.bundle, locale: AppLanguage.locale) }
            let unit = TrainingInput.weightUnit(row, fallback: draft.unit)
            let prefix = side ?? "both"
            let weight = TrainingInput.weightDisplay(row, path: "\(prefix).w", value: number(data["w"]), storedUnit: draft.unit)
            var detail = mode == "time" ? String(format: String(localized: "DURATION_SECONDS_SHORT", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(describing: decimal(number(data["sec"])))) : String(format: String(localized: "COUNT_REPS_A", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(describing: decimal(number(data["r"]))))
            if mode == "cardio" {
                let speedState = state.merging(["unit": draft.unit]) { _, new in new }
                detail = "\(decimal(TrainingInput.speedDisplay(number(data["speed"]), state: speedState))) \(TrainingInput.speedUnit(speedState) == "mph" ? "mph" : "km/h")"
                if let incline = data["incline"] { detail += String(format: String(localized: "INCLINE_COUNT", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(describing: decimal(number(incline)))) }
            }
            if let drops = data["drops"] as? [[String: Any]], !drops.isEmpty { detail += String(format: String(localized: "COUNT_DROPS", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(describing: drops.count)) }
            if let clusters = data["clusters"] as? [[String: Any]], !clusters.isEmpty { detail += String(format: String(localized: "COUNT_REST_PAUSE_MINI_SETS", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(describing: clusters.count)) }
            var blocked: String?
            if (try? TrainingInput.validate(row)) == nil { blocked = String(localized: "COMPLETE_THIS_SET_S_DETAILS_ON_IPHONE", bundle: AppLanguage.bundle, locale: AppLanguage.locale) }
            if workTimer != nil { blocked = String(localized: "TIMER_RUNNING_FINISH_IT_ON_IPHONE", bundle: AppLanguage.bundle, locale: AppLanguage.locale) }
            if syncing { blocked = String(localized: "IPHONE_IS_SAVING", bundle: AppLanguage.bundle, locale: AppLanguage.locale) }
            if localSaveError != nil { blocked = String(localized: "RESOLVE_THE_DRAFT_SAVE_ISSUE_ON_IPHONE", bundle: AppLanguage.bundle, locale: AppLanguage.locale) }
            return WatchTrainingSet(entry: e, index: index, side: side, label: label,
                weight: mode == "cardio" ? String(format: String(localized: "COUNT_MIN", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(describing: decimal(number(data["min"])))) : "\(weight.isEmpty ? "—" : weight) \(unit)", detail: detail, blockedReason: blocked)
        }
        // Keep the completed set visible until rest is explicitly ended, including at zero.
        if let rest = draft.activeJSON["nativeRest"] as? [String: Any], snapshot.restEnd != nil,
           rest["entry"] as? Int == e, let index = rest["set"] as? Int,
           rows.indices.contains(index), rows[index]["done"] as? Bool == true {
            snapshot.restSet = summary(for: index)
        }
        if let index = rows.firstIndex(where: { $0["done"] as? Bool != true }) {
            snapshot.nextSet = summary(for: index)
            snapshot.message = ""
        } else {
            snapshot.nextEntry = (1..<entries.count).map { (e + $0) % entries.count }.first { index in
                (entries[index]["sets"] as? [[String: Any]] ?? []).contains { $0["done"] as? Bool != true }
            }
            snapshot.message = snapshot.nextEntry == nil ? String(localized: "WORKOUT_COMPLETE_SAVE_IT_ON_IPHONE", bundle: AppLanguage.bundle, locale: AppLanguage.locale) : String(localized: "EXERCISE_COMPLETE", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
        }
        return snapshot
    }
    private func watchExerciseName(_ entry: [String: Any]) -> String {
        String((exercise(entry["id"] as? String ?? "")?.name ?? String(localized: "CUSTOM_EXERCISE", bundle: AppLanguage.bundle, locale: AppLanguage.locale)).prefix(80))
    }
    private static func watchHash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    /// Completion is a command, never a toggle. A delayed or duplicated command cannot tick a different set.
    func performWatchCommand(_ command: WatchTrainingCommand, now: Date = Date()) -> [String: Any] {
        WorkoutActivityDiagnostics.withTrace { executeRemoteCommand(command, now: now) }
    }

    private func executeRemoteCommand(_ command: WatchTrainingCommand, now: Date) -> [String: Any] {
        let started = ContinuousClock.now
        var result: String?
        var outcome = "applied"
        let before = watchSnapshot()
        WorkoutActivityDiagnostics.record("remote.command.begin", WorkoutActivityDiagnostics.command(command, snapshot: before))
        if command.version != 1 || command.sessionID != before.sessionID || command.account != before.account {
            outcome = command.version != 1 ? "unsupported_version" : (command.account != before.account ? "account_mismatch" : "session_mismatch")
            result = String(localized: "THE_WORKOUT_HAS_CHANGED_CHECK_THE_LATEST_DETAILS_BEFORE_CONTINUING", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
        } else if before.acknowledged.contains(command.id) {
            // Re-send the receipt after a lost reply without starting a second rest timer.
            outcome = "duplicate_acknowledged"
        } else if command.revision != before.revision {
            outcome = "revision_mismatch"
            result = String(localized: "THE_RECORD_ON_YOUR_PHONE_HAS_CHANGED_CHECK_THE_CURRENT_SET_AND", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
        } else if syncing || localSaveError != nil {
            outcome = syncing ? "syncing" : "save_error"
            result = String(localized: "FINISH_SAVING_ON_IPHONE_FIRST", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
        } else if command.action == "resumeFromMotion", !autoEndRestEnabled {
            outcome = "motion_disabled"
            result = String(localized: "AUTO_END_REST_IS_OFF", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
        } else if ["complete", "skipRest", "resumeFromMotion", "next"].contains(command.action), before.actionTiming.isProtected(at: now) {
            outcome = "action_cooldown"
            result = String(format: String(localized: "TRY_AGAIN_IN_COUNT_SECONDS", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(describing: before.actionTiming.protectionSeconds(at: now)))
        } else if command.action == "resumeFromMotion", before.restEnd != nil, before.restEntry == command.entry,
                  let restStart = before.restStartedAt, let startedAt = command.detectedStartedAt,
                  startedAt.timeIntervalSince1970.isFinite, restStart.timeIntervalSince1970.isFinite,
                  startedAt >= restStart, startedAt <= now, !before.actionTiming.isProtected(at: startedAt),
                  let next = before.nextSet, next.blockedReason == nil {
            endRest(startedAt: startedAt, confirmedAt: now)
            if localSaveError == nil { acknowledgeWatchCommand(command.id) }
        } else if command.action == "skipRest", before.restEnd != nil, before.restEntry == command.entry {
            endRestFromTextButton(at: now)
            if localSaveError == nil { acknowledgeWatchCommand(command.id) }
        } else if command.action == "complete", before.restEnd != nil {
            outcome = "rest_not_ended"
            result = String(localized: "END_YOUR_REST_FIRST", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
        } else if command.action == "complete", let row = before.nextSet,
                  row.entry == command.entry, row.index == command.index, row.side == command.side {
            if let reason = row.blockedReason { result = reason; outcome = workTimer != nil ? "work_timer_running" : "invalid_set_input" }
            else {
                WorkoutActivityDiagnostics.record("remote.set.begin", ["entry": String(row.entry), "set": String(row.index)])
                var action: [String: Any] = ["action": "toggle"]; action["side"] = row.side
                let succeeded = liveRowAction(entry: row.entry, set: row.index, action: action)
                WorkoutActivityDiagnostics.record("remote.set.end", ["succeeded": String(succeeded), "saved": String(localSaveError == nil)])
                if !succeeded || localSaveError != nil { result = String(localized: "COULD_NOT_SAVE_THE_DRAFT_ON_IPHONE_CHECK_YOUR_PHONE", bundle: AppLanguage.bundle, locale: AppLanguage.locale); outcome = localSaveError != nil ? "save_failed" : "set_edit_failed" }
                else {
                    // Both remote surfaces advance only on the first accepted completion.
                    if let next = watchSnapshot().nextEntry {
                        WorkoutActivityDiagnostics.record("remote.auto_advance", ["entry": String(next)])
                        selectLiveEntry(next)
                    }
                    if localSaveError == nil {
                        if watchSnapshot().nextSet != nil || restUntil != nil { protectTrainingAction(at: now) }
                        if localSaveError == nil { acknowledgeWatchCommand(command.id) }
                    }
                }
            }
        } else if command.action == "next", before.nextEntry == command.entry {
            selectLiveEntry(command.entry); acknowledgeWatchCommand(command.id)
        } else { result = String(localized: "THE_CURRENT_SET_HAS_CHANGED_REFRESH_AND_TRY_AGAIN", bundle: AppLanguage.bundle, locale: AppLanguage.locale); outcome = "target_mismatch" }
        if result == nil, localSaveError != nil { result = String(localized: "COULD_NOT_SAVE_THE_DRAFT_ON_IPHONE_CHECK_YOUR_PHONE", bundle: AppLanguage.bundle, locale: AppLanguage.locale); outcome = "save_failed" }
        let after = watchSnapshot()
        var fields = WorkoutActivityDiagnostics.state(self, snapshot: after)
        fields["outcome"] = outcome; fields["accepted"] = String(result == nil)
        fields["receipt_present"] = String(after.acknowledged.contains(command.id))
        fields["revision_changed"] = String(before.revision != after.revision)
        fields["elapsed_ms"] = WorkoutActivityDiagnostics.elapsed(started)
        WorkoutActivityDiagnostics.record("remote.command.end", fields, failure: result != nil)
        var response = after.payload
        response["commandID"] = command.id
        response["accepted"] = result == nil
        if let result { response["error"] = result }
        return response
    }
    private func acknowledgeWatchCommand(_ id: String) {
        changeActive { raw in
            var receipts = raw["nativeWatchReceipts"] as? [String] ?? []
            receipts.append(id); raw["nativeWatchReceipts"] = Array(receipts.suffix(32))
        }
        WorkoutActivityDiagnostics.record("remote.receipt.saved", ["command": WorkoutActivityDiagnostics.fingerprint(id),
            "saved": String(localSaveError == nil)], failure: localSaveError != nil)
    }
}
