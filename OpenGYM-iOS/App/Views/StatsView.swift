import SwiftUI

struct StatsView: View, Equatable {
    @Environment(GymStore.self) private var store
    let workouts: [[String: Any]]
    @State private var analytics = false
    @State private var weightSheet = false

    static func == (lhs: Self, rhs: Self) -> Bool {
        RecordPatch.equal(lhs.workouts, rhs.workouts)
    }

    private var completedSets: [[String:Any]] {
        workouts.flatMap { $0["entries"] as? [[String:Any]] ?? [] }.flatMap { $0["sets"] as? [[String:Any]] ?? [] }.flatMap { row -> [[String:Any]] in if let sides = row["sides"] as? [String:[String:Any]] {return [sides["L"],sides["R"]].compactMap{$0}};return [row] }.filter { $0["done"] as? Bool == true }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing:12) {
                    StatsMetricCard(value: "\(workouts.count)", label: "TOTAL_WORKOUTS", icon: "figure.strengthtraining.traditional")
                    StatsMetricCard(value: "\(completedSets.count)", label: "COMPLETED_SETS", icon: "checkmark.circle")
                }
                VStack(alignment:.leading,spacing:16) {
                    HStack { Text("TRAINING_ACTIVITY").font(.headline); Spacer(); Text("LAST_ONETWO_WEEKS").font(.caption).foregroundStyle(GymTheme.muted) }
                    let trained = Set(workouts.compactMap { $0["d"] as? String })
                    let cells = (0..<84).map { Calendar.current.date(byAdding:.day,value:$0-83,to:Date())! }
                    HStack(spacing:5) {
                        ForEach(0..<12,id:\.self) { week in
                            VStack(spacing:5) { ForEach(0..<7,id:\.self) { day in RoundedRectangle(cornerRadius:3).fill(trained.contains(dayString(cells[week*7+day])) ? GymTheme.green : Color(white:0.20)).aspectRatio(1,contentMode:.fit) } }
                        }
                    }.accessibilityLabel("TRAINING_ACTIVITY_OVER_THE_LAST_TWELVE_WEEKS")
                }.gymCard()
                StatsWeightSection(showEditor: $weightSheet)
                Button { analytics = true } label: { Label("EXERCISE_PROGRESS_MUSCLES_AND_BODY_METRICS",systemImage:"chart.xyaxis.line").frame(maxWidth:.infinity,minHeight:44) }.gymCard().accessibilityIdentifier("open-personal-analytics")
            }
            .padding(.horizontal, 22)
            .padding(.top, 8)
            .padding(.bottom, 22)
        }
        .accessibilityIdentifier("history-stats")
        .refreshable { await store.refresh() }
        .sheet(isPresented: $analytics) { PersonalStatsHub() }
        .sheet(isPresented: $weightSheet) { WeightEntryView() }
    }
}
