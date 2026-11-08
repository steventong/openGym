import Foundation
import Observation
import HealthKit

/// Explicit, foreground-only export. Never joins the live workout retry queue.
@MainActor @Observable final class HistoryHealthSync {
    typealias Authorize = @MainActor () async throws -> Void
    typealias Delete = @MainActor (String) async throws -> Void
    typealias Save = @MainActor (HealthWorkoutRequest) async throws -> Void
    let available: Bool
    private(set) var busy = false
    private let authorize: Authorize
    private let deletePrevious: Delete
    private let save: Save

    init(available: Bool = HKHealthStore.isHealthDataAvailable(), authorize: Authorize? = nil,
         deletePrevious: Delete? = nil, save: Save? = nil) {
        self.available = available
        let health = HKHealthStore()
        self.authorize = authorize ?? {
            try await health.requestAuthorization(toShare: [HealthWorkoutAccess.workout], read: [])
            guard health.authorizationStatus(for: HealthWorkoutAccess.workout) == .sharingAuthorized else {
                throw APIError.response(0, String(localized: "ALLOW_OPENGYM_TO_WRITE_WORKOUTS_IN_THE_HEALTH_APP", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
            }
        }
        self.deletePrevious = deletePrevious ?? { try await Self.deletePreviousWorkouts(syncIdentifier: $0, health: health) }
        self.save = save ?? { try await HealthWorkoutAccess.saveDuration($0, health: health) }
    }

    private static func deletePreviousWorkouts(syncIdentifier: String, health: HKHealthStore) async throws {
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForObjects(from: HKSource.default()),
            HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeySyncIdentifier, allowedValues: [syncIdentifier])
        ])
        let matches: [HKSample] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: HealthWorkoutAccess.workout, predicate: predicate,
                                      limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: samples ?? []) }
            }
            health.execute(query)
        }
        guard !matches.isEmpty else { return }
        try await health.delete(matches)
    }

    func sync(_ record: WorkoutRecord, account: String) async throws {
        guard !busy else {
            throw APIError.response(0, String(localized: "HEALTH_HISTORY_SYNC_IN_PROGRESS", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
        }
        guard available else {
            throw APIError.response(0, String(localized: "HEALTH_DATA_IS_UNAVAILABLE_ON_THIS_DEVICE", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
        }
        let request = try HistoryHealthRequest.make(record, account: account)
        busy = true
        defer { busy = false }
        try await authorize()
        try await deletePrevious(request.syncIdentifier)
        try await save(request)
    }
}
