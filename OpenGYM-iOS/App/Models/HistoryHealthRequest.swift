import Foundation
import CoreFoundation

enum HistoryHealthRequest {
    static func make(_ record: WorkoutRecord, account: String, now: Date = Date()) throws -> HealthWorkoutRequest {
        guard !account.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw APIError.signIn }
        guard !record.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw APIError.response(0, String(localized: "HEALTH_HISTORY_INVALID_RECORD", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
        }
        guard let name = record.raw["name"] as? String, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw APIError.response(0, String(localized: "ENTER_A_WORKOUT_NAME", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
        }
        guard let start = record.raw["start"] as? NSNumber, let end = record.raw["end"] as? NSNumber,
              CFGetTypeID(start) != CFBooleanGetTypeID(), CFGetTypeID(end) != CFBooleanGetTypeID(),
              start.doubleValue.isFinite, end.doubleValue.isFinite,
              start.doubleValue > 0, end.doubleValue > start.doubleValue,
              end.doubleValue - start.doubleValue <= 86_400_000,
              end.doubleValue <= now.timeIntervalSince1970 * 1000 else {
            throw APIError.response(0, String(localized: "HEALTH_HISTORY_INVALID_TIME", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
        }
        return HealthWorkoutRequest(id: "\(account):history:\(record.id)",
            start: Date(timeIntervalSince1970: start.doubleValue / 1000),
            end: Date(timeIntervalSince1970: end.doubleValue / 1000), owner: .phone, phase: .finished, title: name)
    }
}
