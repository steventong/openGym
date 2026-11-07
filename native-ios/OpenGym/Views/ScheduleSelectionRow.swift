import SwiftUI

struct ScheduleSelectionRow: View {
    let title: String
    let selected: Bool
    let icon: String

    var body: some View {
        HStack {
            Label(title, systemImage: icon).foregroundStyle(.primary)
            Spacer()
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(selected ? GymTheme.green : .gray)
        }
    }
}

#Preview {
    ScheduleSelectionRow(title: String(localized: "REST_ON_THIS_DAY", bundle: AppLanguage.bundle, locale: AppLanguage.locale),
        selected: true, icon: "moon")
}
