import SwiftUI

struct ScheduleSelectionRow: View {
    let title: LocalizedStringKey
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
    ScheduleSelectionRow(title: "REST_ON_THIS_DAY",
        selected: true, icon: "moon")
}
