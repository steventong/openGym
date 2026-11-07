import SwiftUI

struct CoachWeeklyScheduleView: View {
    let bundle: [String: Any]

    var body: some View {
        let week = bundle.coachObject("week")
        let routines = bundle.coachObjects("routines")
        VStack(alignment: .leading, spacing: 7) {
            ForEach([1, 2, 3, 4, 5, 6, 0], id: \.self) { day in
                let ids = (week[String(day)] as? [String]) ?? (week[String(day)] as? String).map { [$0] } ?? []
                if !ids.isEmpty {
                    Text("\(CoachCadenceView.days[day]) · \(ids.map { id in routines.first { $0.coachText("id") == id }?.coachText("name") ?? id }.joined(separator: " + "))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
