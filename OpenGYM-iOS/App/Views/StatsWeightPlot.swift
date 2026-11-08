import SwiftUI

struct StatsWeightPlot: View, Equatable {
    let points: [[String: Any]]

    static func == (lhs: Self, rhs: Self) -> Bool { RecordPatch.equal(lhs.points, rhs.points) }

    var body: some View {
        if points.isEmpty { Text("NO_WEIGHT_RECORDS_YET").font(.subheadline).foregroundStyle(GymTheme.muted) }
        else { WeightChart(points: points).frame(height: 140) }
    }
}
