import SwiftUI

struct StatsWeightSection: View {
    @Environment(GymStore.self) private var store
    @Binding var showEditor: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("WEIGHT_TREND").font(.headline)
                Spacer()
                Button("ADD_RECORD") { showEditor = true }
                    .font(.caption).foregroundStyle(GymTheme.green).frame(minHeight: 44)
                    .accessibilityIdentifier("stats-add-weight")
            }
            StatsWeightPlot(points: store.bodyweights).equatable()
        }.gymCard()
    }
}
