import SwiftUI

struct HistoryView: View {
    @Environment(GymStore.self) private var store
    @State private var selectedTab = HistoryTab.stats

    private enum HistoryTab: Hashable {
        case stats
        case list
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 20) {
                Text("HISTORY").font(.system(size: 34, weight: .bold))
                Picker("HISTORY", selection: $selectedTab) {
                    Text("STATS").tag(HistoryTab.stats)
                    Text("LIST").tag(HistoryTab.list)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("history-tabs")
            }
            .padding(.horizontal, 22)
            .padding(.top, 22)
            .padding(.bottom, 16)

            TabView(selection: $selectedTab) {
                // Ignore unrelated server revisions, health samples and plan updates.
                StatsView(workouts: store.workouts)
                    .equatable()
                    .tag(HistoryTab.stats)
                WorkoutHistoryList(workouts: store.workouts, unsyncedIDs: Set(store.historyEdits.keys))
                    .equatable()
                    .tag(HistoryTab.list)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
    }
}

#Preview {
    HistoryView()
        .environment(GymStore())
        .environment(\.locale, AppLanguage.locale)
        .background(GymTheme.background)
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .tint(GymTheme.green)
}
