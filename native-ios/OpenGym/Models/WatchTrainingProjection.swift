import Foundation
import CryptoKit

extension GymStore {
    func watchSnapshot(now: Date = Date()) -> WatchTrainingSnapshot {
        var snapshot = WatchTrainingSnapshot(generatedAt: now)
        snapshot.language = L10n.language
        guard let userID else { return snapshot }
        snapshot.account = Self.watchHash(Data("\(serverURL)|\(userID)".utf8))
        guard let draft else { return snapshot }
        snapshot.sessionID = draft.id
        snapshot.actionReadyAt = trainingActionReadyAt
        snapshot.revision = Self.watchHash((try? JSONSerialization.data(withJSONObject: draft.activeJSON, options: [.sortedKeys])) ?? Data())
        snapshot.acknowledged = draft.activeJSON["nativeWatchReceipts"] as? [String] ?? []
        let entries = draft.rawEntries
        guard !entries.isEmpty else { snapshot.message = L10n.text("ADD_EXERCISES_ON_IPHONE" /* 在 iPhone 添加动作 */); return snapshot }
        let e = min(max(0, draft.activeJSON["cur"] as? Int ?? 0), entries.count - 1)
        let entry = entries[e], rows = entry["sets"] as? [[String: Any]] ?? []
        snapshot.exercise = watchExerciseName(entry)
        snapshot.exercisePosition = L10n.text("EXERCISE_COUNT_OF_COUNT" /* 第 {0}/{1} 个动作 */, e + 1, entries.count)
        if let rest = draft.activeJSON["nativeRest"] as? [String: Any], let end = rest["end"] as? Double {
            snapshot.restEnd = Date(timeIntervalSince1970: end)
            snapshot.restEntry = rest["entry"] as? Int
            if let owner = rest["entry"] as? Int, entries.indices.contains(owner) { snapshot.restExercise = watchExerciseName(entries[owner]) }
        }
        let target = entry["target"] as? [String: Any] ?? [:]
        if let index = rows.firstIndex(where: { $0["done"] as? Bool != true }) {
            let row = rows[index]
            let sides = row["sides"] as? [String: [String: Any]]
            let side = sides.map { $0["L"]?["done"] as? Bool == true ? "R" : "L" }
            let data = side.flatMap { sides?[$0] } ?? row
            let mode = ((try? WebRules.shared.call("rowInfo", payload: ["row": row, "target": target])) as? [String: Any])?["mode"] as? String ?? "reps"
            let logicalIndexes = rows.indices.filter { !(rows[$0]["side"] as? String == "R" && $0 > 0 && rows[$0 - 1]["side"] as? String == "L") }
            let setNumber = logicalIndexes.filter { $0 <= index }.count
            let sideLabel = side ?? row["side"] as? String
            var label = L10n.text("SET_COUNT_OF_COUNT" /* 第 {0}/{1} 组 */, setNumber, logicalIndexes.count)
            if let sideLabel { label += sideLabel == "L" ? L10n.text("LEFT_A" /* · 左侧 */) : L10n.text("RIGHT_A" /* · 右侧 */) }
            if row["warmup"] as? Bool == true || row["phase"] as? String == "warmup" { label += L10n.text("WARM_UP_A" /* · 热身 */) }
            let unit = TrainingInput.weightUnit(row, fallback: draft.unit)
            let prefix = side ?? "both"
            let weight = TrainingInput.weightDisplay(row, path: "\(prefix).w", value: number(data["w"]), storedUnit: draft.unit)
            var detail = mode == "time" ? L10n.text("DURATION_SECONDS_SHORT" /* {0} 秒 */, decimal(number(data["sec"]))) : L10n.text("COUNT_REPS_A" /* {0} 次 */, decimal(number(data["r"])))
            if mode == "cardio" {
                let speedState = state.merging(["unit": draft.unit]) { _, new in new }
                detail = "\(decimal(TrainingInput.speedDisplay(number(data["speed"]), state: speedState))) \(TrainingInput.speedUnit(speedState) == "mph" ? "mph" : "km/h")"
                if let incline = data["incline"] { detail += L10n.text("INCLINE_COUNT" /* · 坡度 {0}% */, decimal(number(incline))) }
            }
            if let drops = data["drops"] as? [[String: Any]], !drops.isEmpty { detail += L10n.text("COUNT_DROPS" /* · 递减 {0} 次 */, drops.count) }
            if let clusters = data["clusters"] as? [[String: Any]], !clusters.isEmpty { detail += L10n.text("COUNT_REST_PAUSE_MINI_SETS" /* · {0} 个休息暂停小组 */, clusters.count) }
            var blocked: String?
            if (try? TrainingInput.validate(row)) == nil { blocked = L10n.text("COMPLETE_THIS_SET_S_DETAILS_ON_IPHONE" /* 请在 iPhone 填完本组数据 */) }
            if workTimer != nil { blocked = L10n.text("TIMER_RUNNING_FINISH_IT_ON_IPHONE" /* 动作正在计时，请在 iPhone 结束 */) }
            if syncing { blocked = L10n.text("IPHONE_IS_SAVING" /* iPhone 正在保存 */) }
            if localSaveError != nil { blocked = L10n.text("RESOLVE_THE_DRAFT_SAVE_ISSUE_ON_IPHONE" /* 请在 iPhone 处理草稿保存问题 */) }
            snapshot.nextSet = WatchTrainingSet(entry: e, index: index, side: side, label: label,
                weight: mode == "cardio" ? L10n.text("COUNT_MIN" /* {0} 分钟 */, decimal(number(data["min"]))) : "\(weight.isEmpty ? "—" : weight) \(unit)", detail: detail, blockedReason: blocked)
            snapshot.message = ""
        } else {
            snapshot.nextEntry = (1..<entries.count).map { (e + $0) % entries.count }.first { index in
                (entries[index]["sets"] as? [[String: Any]] ?? []).contains { $0["done"] as? Bool != true }
            }
            snapshot.message = snapshot.nextEntry == nil ? L10n.text("WORKOUT_COMPLETE_SAVE_IT_ON_IPHONE" /* 训练已完成，请在 iPhone 保存 */) : L10n.text("EXERCISE_COMPLETE" /* 这个动作已完成 */)
        }
        return snapshot
    }
    private func watchExerciseName(_ entry: [String: Any]) -> String {
        String((exercise(entry["id"] as? String ?? "")?.name ?? L10n.text("CUSTOM_EXERCISE" /* 自定义动作 */)).prefix(80))
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
            result = L10n.text("THE_WORKOUT_HAS_CHANGED_CHECK_THE_LATEST_DETAILS_BEFORE_CONTINUING" /* 训练已变更，请按最新数据操作。 */)
        } else if before.acknowledged.contains(command.id) {
            // Re-send the receipt after a lost reply without starting a second rest timer.
            outcome = "duplicate_acknowledged"
        } else if command.revision != before.revision {
            outcome = "revision_mismatch"
            result = L10n.text("THE_RECORD_ON_YOUR_PHONE_HAS_CHANGED_CHECK_THE_CURRENT_SET_AND" /* 手机上的记录已更新，请核对当前组后重试。 */)
        } else if syncing || localSaveError != nil {
            outcome = syncing ? "syncing" : "save_error"
            result = L10n.text("FINISH_SAVING_ON_IPHONE_FIRST" /* 请先在 iPhone 完成保存。 */)
        } else if ["complete", "skipRest", "next"].contains(command.action), before.actionTiming.isProtected(at: now) {
            outcome = "action_cooldown"
            result = L10n.text("TRY_AGAIN_IN_COUNT_SECONDS" /* 请等待 {0} 秒后再操作。 */, before.actionTiming.protectionSeconds(at: now))
        } else if command.action == "skipRest", before.restEnd != nil, before.restEntry == command.entry {
            endRestFromTextButton(at: now)
            if localSaveError == nil { acknowledgeWatchCommand(command.id) }
        } else if command.action == "complete", before.restEnd != nil {
            outcome = "rest_not_ended"
            result = L10n.text("END_YOUR_REST_FIRST" /* 请先结束休息。 */)
        } else if command.action == "complete", let row = before.nextSet,
                  row.entry == command.entry, row.index == command.index, row.side == command.side {
            if let reason = row.blockedReason { result = reason; outcome = workTimer != nil ? "work_timer_running" : "invalid_set_input" }
            else {
                WorkoutActivityDiagnostics.record("remote.set.begin", ["entry": String(row.entry), "set": String(row.index)])
                var action: [String: Any] = ["action": "toggle"]; action["side"] = row.side
                let succeeded = liveRowAction(entry: row.entry, set: row.index, action: action)
                WorkoutActivityDiagnostics.record("remote.set.end", ["succeeded": String(succeeded), "saved": String(localSaveError == nil)])
                if !succeeded || localSaveError != nil { result = L10n.text("COULD_NOT_SAVE_THE_DRAFT_ON_IPHONE_CHECK_YOUR_PHONE" /* iPhone 草稿保存失败，请在手机检查。 */); outcome = localSaveError != nil ? "save_failed" : "set_edit_failed" }
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
        } else { result = L10n.text("THE_CURRENT_SET_HAS_CHANGED_REFRESH_AND_TRY_AGAIN" /* 当前组已变更，请刷新后重试。 */); outcome = "target_mismatch" }
        if result == nil, localSaveError != nil { result = L10n.text("COULD_NOT_SAVE_THE_DRAFT_ON_IPHONE_CHECK_YOUR_PHONE" /* iPhone 草稿保存失败，请在手机检查。 */); outcome = "save_failed" }
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
