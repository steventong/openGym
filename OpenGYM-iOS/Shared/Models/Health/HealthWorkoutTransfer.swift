import Foundation

/// Phone-issued sensor commands. `owner` identifies the HealthKit writer, not the training controller.
/// Automatic collection uses Watch; explicit history exports use the phone. Terminal commands never regress.
struct HealthWorkoutRequest: Codable, Equatable, Identifiable {
    enum Owner: String, Codable { case phone, watch }
    enum Phase: String, Codable { case running, finished, discarded }
    var id: String
    var start: Date
    var end: Date?
    var owner: Owner
    var phase: Phase = .running
    // Optional so queued requests from earlier app versions remain readable.
    var title: String?
    var isValid: Bool {
        !id.isEmpty && start.timeIntervalSince1970.isFinite &&
        (phase == .running ? end == nil : end.map { $0 >= start && $0.timeIntervalSince1970.isFinite } == true)
    }
    /// Late Watch connections collect from now, without claiming sensor coverage before joining.
    func collectionStart(at now: Date) -> Date? {
        guard owner == .watch, phase == .running, isValid else { return nil }
        return max(start, now)
    }
    var syncIdentifier: String { "me.itwl.opengym.workout.\(id)" }
}

struct HealthWorkoutReport: Codable, Equatable {
    enum State: String, Codable { case running, saved, discarded, failed }
    var id: String
    var state: State
    var activeCalories: Double?
    var totalCalories: Double?
    var heartRate: Double?
    var message: String?
    var updatedAt = Date()
    var terminal: Bool { state == .saved || state == .discarded }
    static func metric(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        return value
    }
    static func totalCalories(active: Double?, resting: Double?) -> Double? {
        guard let active = metric(active), let resting = metric(resting) else { return nil }
        return metric(active + resting)
    }
}

struct HealthWorkoutLedger: Codable {
    var requests: [String: HealthWorkoutRequest] = [:]
    var reports: [String: HealthWorkoutReport] = [:]
    var activeID: String?
    var interruptedIDs: Set<String>?
    @discardableResult mutating func merge(_ request: HealthWorkoutRequest) -> Bool {
        guard request.isValid else { return false }
        if let old = requests[request.id] {
            guard old.owner == request.owner, old.start == request.start, old.phase == .running,
                  request.phase != .running, reports[request.id]?.terminal != true else { return false }
        }
        requests[request.id] = request
        return true
    }
    mutating func receive(_ report: HealthWorkoutReport) {
        guard requests[report.id] != nil, reports[report.id]?.terminal != true,
              report.updatedAt >= (reports[report.id]?.updatedAt ?? .distantPast) else { return }
        var clean = report
        clean.activeCalories = HealthWorkoutReport.metric(report.activeCalories)
        clean.totalCalories = HealthWorkoutReport.metric(report.totalCalories)
        clean.heartRate = HealthWorkoutReport.metric(report.heartRate)
        reports[report.id] = clean
    }
    var pending: [HealthWorkoutRequest] {
        requests.values.filter { reports[$0.id]?.terminal != true }.sorted {
            if ($0.phase == .running) != ($1.phase == .running) { return $0.phase != .running }
            return $0.start < $1.start
        }
    }
}

/// Device-only journal; no heart rate or calories are sent to the openGym server or cloud backup.
final class HealthWorkoutJournal {
    let url: URL
    init(name: String, root: URL? = nil) {
        let base = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OpenGymHealth", isDirectory: true)
        url = base.appendingPathComponent(name + ".json")
    }
    func read() throws -> HealthWorkoutLedger {
        guard FileManager.default.fileExists(atPath: url.path) else { return HealthWorkoutLedger() }
        return try JSONDecoder().decode(HealthWorkoutLedger.self, from: Data(contentsOf: url))
    }
    func write(_ ledger: HealthWorkoutLedger) throws {
        var folder = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try folder.setResourceValues(values)
        try JSONEncoder().encode(ledger).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}

enum HealthWorkoutWire {
    static func requests(_ values: [HealthWorkoutRequest]) -> [String: Any] {
        ["healthWorkouts": (try? JSONEncoder().encode(values)) ?? Data()]
    }
    static func requests(from payload: [String: Any]) -> [HealthWorkoutRequest] {
        guard let data = payload["healthWorkouts"] as? Data else { return [] }
        return (try? JSONDecoder().decode([HealthWorkoutRequest].self, from: data))?.filter(\.isValid) ?? []
    }
    static func report(_ value: HealthWorkoutReport) -> [String: Any] {
        ["healthReport": (try? JSONEncoder().encode(value)) ?? Data()]
    }
    static func report(from payload: [String: Any]) -> HealthWorkoutReport? {
        guard let data = payload["healthReport"] as? Data else { return nil }
        return try? JSONDecoder().decode(HealthWorkoutReport.self, from: data)
    }
}
