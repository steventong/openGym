import SwiftUI

/// Training data stays read-only; editing and explicit Health export are separate actions.
struct WorkoutHistoryPreview: View {
    @Environment(GymStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let record: WorkoutRecord
    @State private var editing: WorkoutRecord?
    @State private var detail: Exercise?
    @State private var confirmingHealthSync = false
    @State private var healthMessage: String?
    private var current: WorkoutRecord {
        store.workouts.first { WorkoutRecord.key($0) == record.id }.map(WorkoutRecord.init) ?? record
    }
    private var unit: String { store.historyEdits[record.id]?["unit"] as? String ?? store.unit }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(current.raw["name"] as? String ?? String(localized: "WORKOUT", bundle: AppLanguage.bundle, locale: AppLanguage.locale)).font(.title2.bold())
                        Text(current.raw["d"] as? String ?? "").foregroundStyle(GymTheme.muted)
                        Text(String(format: String(localized: "COUNT_MIN_COUNT_SETS", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(describing: decimal(max(0, number(current.raw["end"]) - number(current.raw["start"])) / 60000)), String(describing: current.completedSetCount)))
                            .font(.subheadline).foregroundStyle(GymTheme.muted)
                        if let note = current.raw["note"] as? String, !note.isEmpty { Text(note).font(.subheadline) }
                    }.frame(maxWidth: .infinity, alignment: .leading).gymCard()
                    let entries = current.raw["entries"] as? [[String: Any]] ?? []
                    ForEach(entries.indices, id: \.self) { index in
                        WorkoutHistoryExerciseCard(entry: entries[index], index: index, unit: unit) {
                            detail = store.exercise(entries[index]["id"] as? String ?? "")
                        }
                    }
                    if entries.isEmpty { Text("NO_EXERCISE_HISTORY_YET").foregroundStyle(GymTheme.muted) }
                }.padding(20)
            }.background(GymTheme.background).foregroundStyle(.white)
                .navigationTitle("WORKOUT_HISTORY").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { Button("TURN_OFF") { dismiss() } }
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button("EDIT_RECORD", systemImage: "pencil") { editing = current }
                                .accessibilityIdentifier("edit-history-\(record.id)")
                            Button("SYNC_TO_APPLE_HEALTH", systemImage: "heart") { confirmingHealthSync = true }
                                .disabled(!store.historyHealth.available || store.userID == nil)
                                .accessibilityIdentifier("sync-history-health-\(record.id)")
                        } label: {
                            Group {
                                if store.historyHealth.busy { ProgressView() }
                                else { Image(systemName: "ellipsis.circle") }
                            }.frame(width: 44, height: 44)
                        }
                        .disabled(store.historyHealth.busy)
                        .accessibilityLabel("RECORD_MENU")
                        .accessibilityIdentifier("history-preview-menu-\(record.id)")
                    }
                }
                .sheet(item: $editing) { record in HistoryEditor(record: record, unit: unit) }
                .sheet(item: $detail) { ExerciseDetail(exercise: $0) }
                .confirmationDialog("SYNC_TO_APPLE_HEALTH", isPresented: $confirmingHealthSync, titleVisibility: .visible) {
                    Button("SYNC_TO_APPLE_HEALTH") { Task { await syncToHealth() } }
                    Button("CANCEL", role: .cancel) {}
                } message: { Text("HEALTH_HISTORY_SYNC_CONFIRMATION") }
                .alert("APPLE_HEALTH", isPresented: Binding(get: { healthMessage != nil }, set: { if !$0 { healthMessage = nil } })) {
                    Button("GOT_IT", role: .cancel) {}
                } message: { Text(healthMessage ?? "") }
        }.tint(GymTheme.green)
    }
    private func syncToHealth() async {
        let snapshot = current
        let account = store.accountFolder?.lastPathComponent ?? ""
        do {
            try await store.historyHealth.sync(snapshot, account: account)
            healthMessage = String(localized: "HEALTH_HISTORY_SYNC_COMPLETE", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
        } catch {
            healthMessage = error.localizedDescription + "\n\n" + String(localized: "HEALTH_HISTORY_CHECK_BEFORE_RETRY", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
        }
    }
}
