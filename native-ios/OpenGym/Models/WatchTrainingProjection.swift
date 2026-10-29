import Foundation
import CryptoKit

extension GymStore {
    func watchSnapshot(now: Date = Date()) -> WatchTrainingSnapshot {
        var snapshot = WatchTrainingSnapshot(generatedAt: now)
        guard let userID else { return snapshot }
        snapshot.account = Self.watchHash(Data("\(serverURL)|\(userID)".utf8))
        guard let draft else { return snapshot }
        snapshot.sessionID = draft.id
        snapshot.revision = Self.watchHash((try? JSONSerialization.data(withJSONObject: draft.activeJSON, options: [.sortedKeys])) ?? Data())
        snapshot.acknowledged = draft.activeJSON["nativeWatchReceipts"] as? [String] ?? []
        let entries = draft.rawEntries
        guard !entries.isEmpty else { snapshot.message = "在 iPhone 添加动作"; return snapshot }
        let e = min(max(0, draft.activeJSON["cur"] as? Int ?? 0), entries.count - 1)
        let entry = entries[e], rows = entry["sets"] as? [[String: Any]] ?? []
        snapshot.exercise = watchExerciseName(entry)
        snapshot.exercisePosition = "动作 \(e + 1) / \(entries.count)"
        if let rest = draft.activeJSON["nativeRest"] as? [String: Any], let end = rest["end"] as? Double {
            snapshot.restEnd = Date(timeIntervalSince1970: end)
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
            var label = "第 \(setNumber) / \(logicalIndexes.count) 组"
            if let sideLabel { label += sideLabel == "L" ? " · 左侧" : " · 右侧" }
            if row["warmup"] as? Bool == true || row["phase"] as? String == "warmup" { label += " · 热身" }
            let unit = TrainingInput.weightUnit(row, fallback: draft.unit)
            let prefix = side ?? "both"
            let weight = TrainingInput.weightDisplay(row, path: "\(prefix).w", value: number(data["w"]), storedUnit: draft.unit)
            var detail = mode == "time" ? "\(decimal(number(data["sec"]))) 秒" : "\(decimal(number(data["r"]))) 次"
            if mode == "cardio" {
                let speedState = state.merging(["unit": draft.unit]) { _, new in new }
                detail = "\(decimal(TrainingInput.speedDisplay(number(data["speed"]), state: speedState))) \(TrainingInput.speedUnit(speedState) == "mph" ? "mph" : "km/h")"
                if let incline = data["incline"] { detail += " · 坡度 \(decimal(number(incline)))%" }
            }
            if let drops = data["drops"] as? [[String: Any]], !drops.isEmpty { detail += " · 递减 \(drops.count) 次" }
            if let clusters = data["clusters"] as? [[String: Any]], !clusters.isEmpty { detail += " · Rest-pause \(clusters.count) 小组" }
            var blocked: String?
            if (try? TrainingInput.validate(row)) == nil { blocked = "请在 iPhone 填完本组数据" }
            if workTimer != nil { blocked = "动作正在计时，请在 iPhone 结束" }
            if syncing { blocked = "iPhone 正在保存" }
            if localSaveError != nil { blocked = "请在 iPhone 处理草稿保存问题" }
            snapshot.nextSet = WatchTrainingSet(entry: e, index: index, side: side, label: label,
                weight: mode == "cardio" ? "\(decimal(number(data["min"]))) 分钟" : "\(weight.isEmpty ? "—" : weight) \(unit)", detail: detail, blockedReason: blocked)
            snapshot.message = ""
        } else {
            snapshot.nextEntry = (1..<entries.count).map { (e + $0) % entries.count }.first { index in
                (entries[index]["sets"] as? [[String: Any]] ?? []).contains { $0["done"] as? Bool != true }
            }
            snapshot.message = snapshot.nextEntry == nil ? "训练已完成，请在 iPhone 保存" : "这个动作已完成"
        }
        return snapshot
    }
    private func watchExerciseName(_ entry: [String: Any]) -> String {
        String((exercise(entry["id"] as? String ?? "")?.name ?? "自定义动作").prefix(80))
    }
    private static func watchHash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    /// Completion is a command, never a toggle. A delayed or duplicated command cannot tick a different set.
    func performWatchCommand(_ command: WatchTrainingCommand) -> [String: Any] {
        var result: String?
        let before = watchSnapshot()
        if command.version != 1 || command.sessionID != before.sessionID || command.account != before.account {
            result = "训练已变更，请按最新数据操作。"
        } else if before.acknowledged.contains(command.id) {
            // Re-send the receipt after a lost reply without starting a second rest timer.
        } else if command.revision != before.revision {
            result = "手机上的记录已更新，请核对当前组后重试。"
        } else if syncing || localSaveError != nil {
            result = "请先在 iPhone 完成保存。"
        } else if command.action == "complete", let row = before.nextSet,
                  row.entry == command.entry, row.index == command.index, row.side == command.side {
            if let reason = row.blockedReason { result = reason }
            else {
                var action: [String: Any] = ["action": "toggle"]; action["side"] = row.side
                let succeeded = liveRowAction(entry: row.entry, set: row.index, action: action)
                if !succeeded || localSaveError != nil { result = "iPhone 草稿保存失败，请在手机检查。" }
                else { acknowledgeWatchCommand(command.id) }
            }
        } else if command.action == "next", before.nextEntry == command.entry {
            selectLiveEntry(command.entry); acknowledgeWatchCommand(command.id)
        } else { result = "当前组已变更，请刷新后重试。" }
        if result == nil, localSaveError != nil { result = "iPhone 草稿保存失败，请在手机检查。" }
        var response = watchSnapshot().payload
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
    }
}

