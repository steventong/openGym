import SwiftUI

struct CoachWeeklyScheduleView: View {
    let bundle: [String: Any]

    var body: some View {
        let days = CoachCadenceView.days.map { String(localized: $0, bundle: AppLanguage.bundle, locale: AppLanguage.locale) }
        let week = bundle.coachObject("week")
        let routines = bundle.coachObjects("routines")
        VStack(alignment: .leading, spacing: 7) {
            ForEach([1, 2, 3, 4, 5, 6, 0], id: \.self) { day in
                let ids = (week[String(day)] as? [String]) ?? (week[String(day)] as? String).map { [$0] } ?? []
                if !ids.isEmpty {
                    let routineNames = ids.map { id in routines.first { $0.coachText("id") == id }?.coachText("name") ?? id }.joined(separator: " + ")
                    Text(String(format: String(localized: "COACH_SCHEDULE_ENTRY", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, days[day], routineNames))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
