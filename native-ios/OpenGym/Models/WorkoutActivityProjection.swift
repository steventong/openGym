import Foundation

extension GymStore {
    func workoutActivityState() -> WorkoutActivityAttributes.ContentState? {
        guard let draft, userID != nil else { return nil }
        let snapshot = watchSnapshot()
        let row = snapshot.nextSet
        let compactSet: String
        if let row {
            let rows = draft.rawEntries[row.entry]["sets"] as? [[String: Any]] ?? []
            let logical = rows.indices.filter { !(rows[$0]["side"] as? String == "R" && $0 > 0 && rows[$0 - 1]["side"] as? String == "L") }
            compactSet = "\(logical.filter { $0 <= row.index }.count)/\(logical.count)"
        } else { compactSet = draft.rawEntries.isEmpty ? "…" : "✓" }
        let available = !syncing && localSaveError == nil
        let command: String?
        if let row, row.blockedReason == nil, available {
            command = activityCommand(snapshot, action: "complete", entry: row.entry, index: row.index, side: row.side)
        } else if let next = snapshot.nextEntry, available {
            command = activityCommand(snapshot, action: "next", entry: next)
        } else { command = nil }
        return .init(trainingName: String(draft.name.prefix(80)), exercise: snapshot.exercise,
            position: snapshot.exercisePosition, setLabel: row?.label ?? (draft.rawEntries.isEmpty ? "添加动作后开始" : "全部组已完成"), compactSet: compactSet,
            detail: row.map { "\($0.weight) · \($0.detail)" } ?? "",
            message: row?.blockedReason ?? snapshot.message, restEnd: snapshot.restEnd,
            restExercise: snapshot.restExercise, command: command,
            commandTitle: row == nil ? "下一个动作" : "完成本组",
            restCommand: snapshot.restEnd != nil && available ? activityCommand(snapshot, action: "skipRest", entry: restEntry ?? 0) : nil)
    }

    private func activityCommand(_ snapshot: WatchTrainingSnapshot, action: String, entry: Int, index: Int? = nil, side: String? = nil) -> String? {
        guard let session = snapshot.sessionID else { return nil }
        // Stable IDs make duplicate taps idempotent, including across an app relaunch.
        let command = WatchTrainingCommand(id: "activity-\(snapshot.revision)-\(action)", account: snapshot.account,
            sessionID: session, revision: snapshot.revision, action: action, entry: entry, index: index, side: side)
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        return (try? encoder.encode(command))?.base64EncodedString()
    }

    /// Returns a user-facing rejection without ever toggling a stale/completed row.
    func performActivityCommand(_ encoded: String) -> String? {
        guard let data = Data(base64Encoded: encoded), let command = try? JSONDecoder().decode(WatchTrainingCommand.self, from: data) else {
            return "操作已失效，请打开训练页面。"
        }
        if command.action == "skipRest" {
            let snapshot = watchSnapshot()
            guard command.version == 1, command.account == snapshot.account, command.sessionID == snapshot.sessionID,
                  command.revision == snapshot.revision, restUntil != nil, command.entry == restEntry,
                  !syncing, localSaveError == nil else { return "休息已更新，请按最新状态操作。" }
            restUntil = nil
            return localSaveError
        }
        guard ["complete", "next"].contains(command.action) else { return "不支持的训练操作。" }
        return performWatchCommand(command)["error"] as? String
    }
}
