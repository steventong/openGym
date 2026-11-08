import SwiftUI

struct WorkoutHistoryList: View, Equatable {
    @Environment(GymStore.self) private var store
    let workouts: [[String: Any]]
    let unsyncedIDs: Set<String>
    @State private var previewing: WorkoutRecord?
    @State private var syncingRecordID: String?
    @State private var syncError: String?
    @State private var historyLimit = 30
    @State private var search = ""

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.unsyncedIDs == rhs.unsyncedIDs && RecordPatch.equal(lhs.workouts, rhs.workouts)
    }

    var body: some View {
        let matchingWorkouts = workouts.filter { search.isEmpty || historyMatches($0) }
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                TextField("SEARCH_WORKOUT_NAMES_DATES_AND_EXERCISES", text: $search)
                    .stableInputLine(height: 36)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit { GymKeyboard.dismiss() }
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("history-search")

                if workouts.isEmpty {
                    EmptyCard(icon: "clock.arrow.circlepath", title: "NO_WORKOUTS_YET")
                }
                LazyVStack(spacing: 10) {
                    ForEach(matchingWorkouts.prefix(historyLimit).map(WorkoutRecord.init), id: \.id) { record in
                        WorkoutHistoryRow(record: record, unsynced: unsyncedIDs.contains(record.id),
                                          syncing: syncingRecordID == record.id,
                                          preview: { previewing = record }, sync: { sync(record.id) }).equatable()
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 8)
            .padding(.bottom, 22)
        }
        .accessibilityIdentifier("history-list")
        .onScrollGeometryChange(for: Int?.self) { geometry in
            guard historyLimit < matchingWorkouts.count,
                  geometry.visibleRect.height > 0, geometry.contentSize.height > 0,
                  geometry.visibleRect.maxY >= geometry.contentSize.height - 44 else { return nil }
            // Keep loading if a large viewport still fits the newly appended page.
            return historyLimit
        } action: { _, visiblePageEnd in
            guard let visiblePageEnd, visiblePageEnd == historyLimit else { return }
            historyLimit = min(visiblePageEnd + 30, matchingWorkouts.count)
        }
        .refreshable { await store.refresh() }
        .sheet(item: $previewing) { record in WorkoutHistoryPreview(record: record) }
        .alert("SYNC_INCOMPLETE", isPresented: Binding(get: { syncError != nil }, set: { if !$0 { syncError = nil } })) {
            Button("GOT_IT", role: .cancel) {}
        } message: { Text(syncError ?? "") }
    }

    private func sync(_ id: String) {
        guard syncingRecordID == nil, !store.syncing else { return }
        syncingRecordID = id
        Task {
            defer { syncingRecordID = nil }
            if !(await store.submitHistoryEdit(id)) {
                syncError = store.editError ?? store.localSaveError ?? String(localized: "COULD_NOT_SYNC_YOUR_RECORDS_ARE_SAFE_ON_THIS_DEVICE_TRY_AGAIN", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
            }
        }
    }

    private func historyMatches(_ w: [String: Any]) -> Bool {
        let text = [w["name"] as? String ?? "", w["d"] as? String ?? "", w["note"] as? String ?? ""] + (w["entries"] as? [[String: Any]] ?? []).map { store.exercise($0["id"] as? String ?? "")?.searchText ?? $0["n"] as? String ?? "" }
        return text.joined(separator: " ").localizedCaseInsensitiveContains(search)
    }
}
