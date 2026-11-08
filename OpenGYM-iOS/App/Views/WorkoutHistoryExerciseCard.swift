import SwiftUI

struct WorkoutHistoryExerciseCard: View {
    @Environment(GymStore.self) private var store
    let entry: [String: Any]
    let index: Int
    let unit: String
    let showDetails: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                ExerciseThumbnail(id: entry["id"] as? String ?? "", size: 40)
                let parts = store.exercise(entry["id"] as? String ?? "")?.titleParts
                Text(parts?.primary ?? entry["n"] as? String ?? String(localized: "EXERCISE", bundle: AppLanguage.bundle, locale: AppLanguage.locale)).font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(action: showDetails) {
                    Image(systemName: "info.circle").font(.title2).frame(width: 48, height: 48).contentShape(Rectangle())
                }.buttonStyle(.plain).foregroundStyle(GymTheme.green)
                    .accessibilityLabel("EXERCISE_DETAILS")
                    .accessibilityIdentifier("history-exercise-info-\(index)")
                    .disabled(store.exercise(entry["id"] as? String ?? "") == nil)
            }
            if entry["sg"] != nil { Label("SUPERSET", systemImage: "link").font(.caption).foregroundStyle(GymTheme.green) }
            let rows = entry["sets"] as? [[String: Any]] ?? []
            ForEach(rows.indices, id: \.self) { i in
                let setNumber = (0...i).filter { !(rows[$0]["side"] as? String == "R" && $0 > 0 && rows[$0 - 1]["side"] as? String == "L") }.count
                AdvancedSetEditor(row: rows[i], target: (entry["target"] as? [String: Any] ?? [:]).merging(["id": entry["id"] ?? ""]) { _, new in new },
                    unit: unit, inputState: store.state.merging(["unit": unit]) { _, new in new },
                    identifier: "history-preview-\(index)-\(i)", setLabel: String(format: String(localized: "SET_COUNT", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(describing: setNumber)), readOnly: true) { _ in }
                if i < rows.count - 1 { Divider() }
            }
            if rows.isEmpty { Text("NO_SETS_YET").font(.caption).foregroundStyle(GymTheme.muted) }
        }.gymCard().accessibilityIdentifier("history-preview-exercise-\(index)")
    }
}
