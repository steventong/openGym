import Foundation
import CryptoKit

extension GymStore {
    func workoutActivityState() -> WorkoutActivityAttributes.ContentState? {
        guard let draft, userID != nil else { return nil }
        let snapshot = watchSnapshot()
        let row = snapshot.nextSet
        let displayedRow = snapshot.displayedSet
        let compactSet: String
        if let row = displayedRow {
            let rows = draft.rawEntries[row.entry]["sets"] as? [[String: Any]] ?? []
            let logical = rows.indices.filter { !(rows[$0]["side"] as? String == "R" && $0 > 0 && rows[$0 - 1]["side"] as? String == "L") }
            compactSet = String(format: String(localized: "SET_COUNT_OF_COUNT", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(describing: logical.filter { $0 <= row.index }.count), String(describing: logical.count))
        } else { compactSet = draft.rawEntries.isEmpty ? "…" : "✓" }
        let available = !syncing && localSaveError == nil
        let command: String?
        if let row, row.blockedReason == nil, available {
            command = activityCommand(snapshot, action: "complete", entry: row.entry, index: row.index, side: row.side)
        } else if let next = snapshot.nextEntry, available {
            command = activityCommand(snapshot, action: "next", entry: next)
        } else { command = nil }
        let commandTitle: String
        if localSaveError != nil { commandTitle = String(localized: "COULD_NOT_SAVE", bundle: AppLanguage.bundle, locale: AppLanguage.locale) }
        else if row?.blockedReason != nil, !syncing { commandTitle = workTimer != nil ? String(localized: "TIMER_RUNNING", bundle: AppLanguage.bundle, locale: AppLanguage.locale) : String(localized: "COMPLETE_SET_DETAILS", bundle: AppLanguage.bundle, locale: AppLanguage.locale) }
        else { commandTitle = row != nil ? String(localized: "COMPLETE", bundle: AppLanguage.bundle, locale: AppLanguage.locale) : (snapshot.nextEntry != nil ? String(localized: "NEXT_EXERCISE", bundle: AppLanguage.bundle, locale: AppLanguage.locale) : String(localized: "OPEN_APP", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) }
        return .init(trainingName: String(draft.name.prefix(80)), exercise: snapshot.exercise,
            position: snapshot.exercisePosition, setLabel: displayedRow?.label ?? (draft.rawEntries.isEmpty ? String(localized: "ADD_AN_EXERCISE_TO_START", bundle: AppLanguage.bundle, locale: AppLanguage.locale) : String(localized: "ALL_SETS_COMPLETE", bundle: AppLanguage.bundle, locale: AppLanguage.locale)), compactSet: compactSet,
            detail: displayedRow.map { "\($0.weight) · \($0.detail)" } ?? "",
            message: row?.blockedReason ?? snapshot.message, restEnd: snapshot.restEnd,
            restExercise: snapshot.restExercise, command: command,
            commandTitle: commandTitle,
            restCommand: snapshot.restEnd != nil && available ? activityCommand(snapshot, action: "skipRest", entry: restEntry ?? 0) : nil,
            setWeight: displayedRow?.weight, setDetail: displayedRow?.detail, setCompletionLabel: snapshot.setCompletionLabel, busyTitle: syncing ? String(localized: "SAVING", bundle: AppLanguage.bundle, locale: AppLanguage.locale) : nil,
            actionReadyAt: snapshot.actionReadyAt, setStartedAt: snapshot.setStartedAt, language: AppLanguage.language)
    }

    private func activityCommand(_ snapshot: WatchTrainingSnapshot, action: String, entry: Int, index: Int? = nil, side: String? = nil) -> String? {
        guard let session = snapshot.sessionID else { return nil }
        let activityRevision = action == "skipRest" ? nil : workoutActionRevision()
        // Stable IDs make duplicate taps idempotent, including across an app relaunch.
        let revision = activityRevision ?? snapshot.revision
        let command = WatchTrainingCommand(id: "activity-\(revision)-\(action)", account: snapshot.account,
            sessionID: session, revision: revision, action: action, entry: entry, index: index, side: side,
            activityRevision: activityRevision)
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        return (try? encoder.encode(command))?.base64EncodedString()
    }

    private func workoutActionRevision() -> String? {
        guard let draft else { return nil }
        var raw = draft.activeJSON
        // A changed rest timer does not change the set being confirmed. Keep every
        // other field, including inputs, order, selection, work timers and receipts.
        // Receipts distinguish a new completion after the user undoes a previous one.
        raw.removeValue(forKey: "nativeRest")
        raw.removeValue(forKey: "nativeActionReadyAt")
        raw.removeValue(forKey: "nativeSetStartedAt")
        guard let data = try? JSONSerialization.data(withJSONObject: raw, options: [.sortedKeys]) else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Returns a user-facing rejection without ever toggling a stale/completed row.
    func performActivityCommand(_ encoded: String, now: Date = Date()) -> String? {
        WorkoutActivityDiagnostics.withTrace { executeActivityCommand(encoded, now: now) }
    }

    private func executeActivityCommand(_ encoded: String, now: Date) -> String? {
        let started = ContinuousClock.now
        WorkoutActivityDiagnostics.record("activity.command.begin", WorkoutActivityDiagnostics.state(self))
        defer { WorkoutActivityDiagnostics.record("activity.command.end", ["elapsed_ms": WorkoutActivityDiagnostics.elapsed(started)]) }
        guard let data = Data(base64Encoded: encoded), var command = try? JSONDecoder().decode(WatchTrainingCommand.self, from: data) else {
            WorkoutActivityDiagnostics.record("activity.command.rejected", ["reason": "invalid_payload"], failure: true)
            return String(localized: "THIS_ACTION_HAS_EXPIRED_OPEN_THE_WORKOUT_SCREEN", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
        }
        let before = watchSnapshot()
        WorkoutActivityDiagnostics.record("activity.command.decoded", WorkoutActivityDiagnostics.command(command, snapshot: before))
        if command.action == "skipRest" {
            let reason: String?
            if command.version != 1 { reason = "unsupported_version" }
            else if command.account != before.account { reason = "account_mismatch" }
            else if command.sessionID != before.sessionID { reason = "session_mismatch" }
            else if command.revision != before.revision { reason = "revision_mismatch" }
            else if restUntil == nil { reason = "rest_missing" }
            else if command.entry != restEntry { reason = "rest_owner_mismatch" }
            else if syncing { reason = "syncing" }
            else if localSaveError != nil { reason = "save_error" }
            else if before.actionTiming.isProtected(at: now) { reason = "action_cooldown" }
            else { reason = nil }
            if let reason {
                WorkoutActivityDiagnostics.record("activity.command.rejected", ["reason": reason], failure: true)
                return String(localized: "YOUR_REST_TIMER_HAS_CHANGED_CHECK_THE_CURRENT_TIMER_BEFORE_CONTINUING", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
            }
            endRestFromTextButton(at: now)
            WorkoutActivityDiagnostics.record("activity.rest.cleared", ["saved": String(localSaveError == nil)], failure: localSaveError != nil)
            return localSaveError
        }
        guard ["complete", "next"].contains(command.action) else {
            WorkoutActivityDiagnostics.record("activity.command.rejected", ["reason": "unsupported_action"], failure: true)
            return String(localized: "THIS_WORKOUT_ACTION_IS_NOT_SUPPORTED", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
        }
        let normalizedMatch = command.activityRevision.map { $0 == workoutActionRevision() } ?? false
        WorkoutActivityDiagnostics.record("activity.revision.checked", ["has_activity_revision": String(command.activityRevision != nil),
            "workout_revision_match": String(normalizedMatch), "full_revision_match": String(command.revision == before.revision)])
        if normalizedMatch {
            // Validate the unchanged workout before translating to the shared executor's
            // full revision. It still checks account, session, target, receipts and saves.
            command.revision = watchSnapshot().revision
        }
        let response = performWatchCommand(command, now: now)
        if let error = response["error"] as? String { return error }
        return localSaveError
    }
}
