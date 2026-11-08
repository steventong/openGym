import SwiftUI

struct CoachInsightMetric: View {
    let name: LocalizedStringKey
    let value: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value, format: .number.precision(.fractionLength(0...1))).font(.headline)
            Text(name).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

#Preview {
    CoachInsightMetric(name: "SETS", value: 12)
}
