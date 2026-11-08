import SwiftUI

struct StatsMetricCard: View {
    let value: String
    let label: LocalizedStringKey
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: icon).font(.system(size: 20)).foregroundStyle(GymTheme.green)
            Text(value).font(.system(size: 34, weight: .bold, design: .rounded))
            Text(label).font(.caption).foregroundStyle(GymTheme.muted)
        }.frame(maxWidth: .infinity, alignment: .leading).gymCard()
    }
}

#Preview {
    StatsMetricCard(value: "24", label: "TOTAL_WORKOUTS",
        icon: "figure.strengthtraining.traditional")
}
