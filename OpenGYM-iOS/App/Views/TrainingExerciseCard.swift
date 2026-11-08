import SwiftUI

struct TrainingExerciseCard<ExerciseActions: View, Accessory: View>: View {
    @Environment(GymStore.self) private var store
    let entry: [String: Any]
    let name: String
    let rows: [TrainingEditorRow]
    let unit: String
    let inputState: [String: Any]
    let previous: String
    let previousNote: String?
    let identifier: String
    let entryIdentity: String
    let timerRunning: Bool
    let restUntil: Date?
    let startTimer: ((Int) -> Void)?
    let startRest: ((Int, Double) -> Void)?
    let showDetails: () -> Void
    let addSet: () -> Void
    let copySet: (Int) -> Void
    let removeSet: (Int) -> Void
    let editSet: (Int, [String: Any]) -> Void
    let undoRemove: (() -> Void)?
    @ViewBuilder let exerciseActions: () -> ExerciseActions
    @ViewBuilder let accessory: () -> Accessory

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            accessory()
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 10) {
                    ExerciseThumbnail(id: entry["id"] as? String ?? "", size: 40)
                    let parts = store.exercise(entry["id"] as? String ?? "")?.titleParts
                    VStack(alignment: .leading, spacing: 4) {
                        Text(parts?.primary ?? name)
                            .font(.headline).lineLimit(1).minimumScaleFactor(0.75)
                        if let subtitle = parts?.secondary, !subtitle.isEmpty {
                            Text(subtitle).font(.caption).foregroundStyle(GymTheme.muted)
                                .lineLimit(2)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("\(identifier)-exercise-title")
                    HStack(spacing: 0) {
                        Button(action: showDetails) {
                            Image(systemName: "info.circle").font(.title2).frame(width: 48, height: 48).contentShape(Rectangle())
                        }.accessibilityLabel("EXERCISE_DETAILS")
                        exerciseActions()
                    }
                }
                if entry["sg"] != nil { Label("SUPERSET", systemImage: "link").font(.caption).foregroundStyle(GymTheme.green) }
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(previous).font(.caption).foregroundStyle(GymTheme.muted).lineLimit(1).fixedSize(horizontal: true, vertical: false)
                }.accessibilityIdentifier("previous-exercise")
                if let previousNote {
                    Text(String(format: String(localized: "PREVIOUS_WORKOUT_NOTE", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(describing: previousNote)))
                        .font(.caption).foregroundStyle(GymTheme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("previous-exercise-note")
                }
            }
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                VStack(alignment: .leading, spacing: 8) {
                    AdvancedSetEditor(row: row.raw, target: (entry["target"] as? [String: Any] ?? [:]).merging(["id": entry["id"] ?? ""]) { _, new in new }, unit: unit, inputState: inputState, identifier: row.accessibilityIdentifier ?? row.id, setLabel: String(format: String(localized: "SET_COUNT", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(describing: setNumber(index))), copySet: { copySet(index) }, removeSet: { removeSet(index) }, timerRunning: timerRunning,
                                      startTimer: startTimer.map { start in { start(index) } },
                                      startRest: startRest.map { start in { start(index, $0) } }) { editSet(index, $0) }
                }
                if index < rows.count - 1 { Divider() }
            // Reset row-local state only when changing exercises, not when inserting
            // or deleting a sibling row. Each row has its own stable identity.
            }.id([entryIdentity, entry["id"] as? String ?? ""])
            if rows.isEmpty { Text("NO_SETS_YET").font(.subheadline).foregroundStyle(GymTheme.muted) }
            HStack(spacing: 12) {
                if let undoRemove {
                    Button(action: undoRemove) { Image(systemName: "arrow.uturn.backward").frame(width: 44, height: 44) }
                        .buttonStyle(.borderless).accessibilityLabel("UNDO_SET_DELETION")
                }
                if startRest != nil {
                    // Keep the same space before, during, and after rest; the overlay cannot resize the card.
                    Color.clear.frame(maxWidth: .infinity)
                        .overlay(alignment: .center) {
                            if let restUntil {
                                ExerciseRestStatus(end: restUntil)
                                    .accessibilityIdentifier("card-rest-timer")
                            }
                        }.allowsHitTesting(false)
                }
                Button(action: addSet) { Label("ADD_SET", systemImage: "plus").frame(maxWidth: .infinity, minHeight: 44) }
                    .buttonStyle(.borderless).disabled(timerRunning).accessibilityIdentifier("add-set")
            }.font(.subheadline).lineLimit(1).minimumScaleFactor(0.6).frame(height: 44)
        }.gymCard()
    }

    private func isRightHalf(_ index: Int) -> Bool {
        index > 0 && rows[index].raw["side"] as? String == "R" && rows[index - 1].raw["side"] as? String == "L"
    }

    private func paired(_ index: Int) -> Bool {
        isRightHalf(index) || (index + 1 < rows.count && isRightHalf(index + 1))
    }

    private func setNumber(_ index: Int) -> Int {
        (0...index).filter { !isRightHalf($0) }.count
    }

}
