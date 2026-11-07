import SwiftUI

struct CoachChangeRow: View {
    let change: [String: Any]
    let historical: Bool
    let locked: Bool
    @Binding var selected: Bool

    var body: some View {
        let stale = change.coachText("status") == "stale"
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text(change.coachText("title")).font(.headline)
                    Spacer()
                    if stale {
                        StatusDetailButton(title: String(localized: "OUTDATED", bundle: AppLanguage.bundle, locale: AppLanguage.locale),
                            message: String(localized: "YOUR_ROUTINES_CHANGED_ON_ANOTHER_DEVICE_REQUEST_A_NEW_REVIEW", bundle: AppLanguage.bundle, locale: AppLanguage.locale), warning: true)
                    }
                }
                if !change.coachText("routineName").isEmpty { Text(change.coachText("routineName")).font(.caption).foregroundStyle(.secondary) }
                let values = change.coachObject("values")
                if !values.isEmpty { Text(values.coachText("before") + " → " + values.coachText("after")).font(.subheadline).foregroundStyle(GymTheme.green) }
                Text(change.coachText("why")).font(.subheadline).foregroundStyle(.secondary)
                if historical {
                    Text(change.coachText("status") == "accepted" ? String(localized: "ACCEPTED", bundle: AppLanguage.bundle, locale: AppLanguage.locale) : String(localized: "NOT_APPLIED", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 2)
            if !historical {
                Toggle("CHOOSE_SUGGESTIONS", isOn: $selected).labelsHidden().toggleStyle(.switch).disabled(stale || locked)
            }
        }.padding(.vertical, 9).opacity(stale ? 0.6 : 1)
    }
}
