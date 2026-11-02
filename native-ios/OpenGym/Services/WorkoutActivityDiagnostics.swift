import Foundation
import OSLog
import UIKit
import CryptoKit

/// Structured diagnostics only: never pass payloads, names, credentials, paths or error userInfo.
@MainActor enum WorkoutActivityDiagnostics {
    struct Record {
        let event: String
        let traces: [String]
        let fields: [String: String]
    }

    @TaskLocal static var traceID: String?
    #if DEBUG
    @TaskLocal static var observer: (@MainActor (Record) -> Void)?
    #endif
    private static let logger = Logger(subsystem: "me.itwl.opengym", category: "LiveActivity")
    private static let processRun = UUID().uuidString
    private static var sequence = 0

    static func withTrace<T>(_ operation: () throws -> T) rethrows -> T {
        if traceID != nil { return try operation() }
        return try $traceID.withValue(UUID().uuidString, operation: operation)
    }

    static func record(_ event: String, _ fields: [String: String] = [:], traces: [String]? = nil, failure: Bool = false) {
        sequence += 1
        let ids = traces ?? traceID.map { [$0] } ?? []
        let record = Record(event: event, traces: ids, fields: fields)
        #if DEBUG
        observer?(record)
        #endif
        var payload = fields
        payload["event"] = event
        payload["trace"] = ids.sorted().joined(separator: ",")
        payload["run"] = processRun
        payload["pid"] = String(ProcessInfo.processInfo.processIdentifier)
        payload["seq"] = String(sequence)
        guard let data = try? JSONEncoder().encode(payload), let line = String(data: data, encoding: .utf8) else { return }
        // Notice/error, rather than debug/info, so ordinary device log collection includes these events.
        if failure { logger.error("LA \(line, privacy: .public)") }
        else { logger.notice("LA \(line, privacy: .public)") }
    }

    static func elapsed(_ start: ContinuousClock.Instant) -> String {
        let duration = start.duration(to: .now).components
        return String(format: "%.2f", Double(duration.seconds) * 1_000 + Double(duration.attoseconds) / 1e15)
    }

    static func fingerprint(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    static func errorFields(_ error: Error) -> [String: String] {
        let error = error as NSError
        return ["error_domain": error.domain, "error_code": String(error.code)]
    }

    static func failureIfTracing(_ event: String, error: Error) {
        guard traceID != nil else { return }
        record(event, errorFields(error), failure: true)
    }

    static func publishedCommand(_ encoded: String?) -> String {
        guard let encoded, let data = Data(base64Encoded: encoded),
              let command = try? JSONDecoder().decode(WatchTrainingCommand.self, from: data) else { return "none" }
        return fingerprint(command.id)
    }

    static func environment() -> [String: String] {
        ["app_state": String(UIApplication.shared.applicationState.rawValue),
         "protected_data_available": String(UIApplication.shared.isProtectedDataAvailable),
         "cancelled": String(Task.isCancelled)]
    }

    static func state(_ store: GymStore, snapshot: WatchTrainingSnapshot? = nil) -> [String: String] {
        let snapshot = snapshot ?? store.watchSnapshot()
        return ["has_account": String(store.userID != nil), "has_draft": String(store.draft != nil),
                "syncing": String(store.syncing), "save_error": String(store.localSaveError != nil),
                "work_timer": String(store.workTimer != nil), "completed_sets": String(store.draft?.completedSets ?? 0),
                "current_entry": String(snapshot.nextSet?.entry ?? -1), "current_set": String(snapshot.nextSet?.index ?? -1),
                "rest": snapshot.restEnd == nil ? "none" : (snapshot.isResting() ? "active" : "expired")]
    }

    static func command(_ command: WatchTrainingCommand, snapshot: WatchTrainingSnapshot) -> [String: String] {
        ["command": fingerprint(command.id), "action": ["complete", "next", "skipRest"].contains(command.action) ? command.action : "unsupported",
         "version": String(command.version), "target_entry": String(command.entry), "target_set": String(command.index ?? -1),
         "side": ["L", "R"].contains(command.side ?? "") ? command.side! : (command.side == nil ? "both" : "invalid"),
         "account_match": String(command.account == snapshot.account), "session_match": String(command.sessionID == snapshot.sessionID),
         "revision_match": String(command.revision == snapshot.revision), "duplicate": String(snapshot.acknowledged.contains(command.id)),
         "expected_revision": fingerprint(command.revision), "current_revision": fingerprint(snapshot.revision)]
    }
}
