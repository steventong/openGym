import SwiftUI

/// Shared exercise page for an active session and a saved workout.
/// Owners provide persistence and the live-only timer controls.
struct TrainingExerciseEditor<Accessory: View>: View {
    @Environment(GymStore.self) private var store
    @Binding var showingOptions: Bool
    let entries: [[String: Any]]
    let names: [String]
    @Binding var selected: Int
    let rows: [TrainingEditorRow]
    let unit: String
    var inputState: [String: Any] = [:]
    let previous: String
    @Binding var note: String
    let identifier: String
    var timerRunning = false
    var restUntil: Date? = nil
    var startTimer: ((Int) -> Void)? = nil
    var startRest: ((Int, Double) -> Void)? = nil
    let showDetails: () -> Void
    let addSet: () -> Void
    let copySet: (Int) -> Void
    let removeSet: (Int) -> Void
    let editSet: (Int, [String: Any]) -> Void
    var undoRemove: (() -> Void)? = nil
    @ViewBuilder let accessory: () -> Accessory
    @State private var unitError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if entries.indices.contains(selected) {
                exerciseCard(entries[selected])
                HStack {
                    Button { selected -= 1 } label: {
                        Label("上一个动作", systemImage: "chevron.left")
                            .foregroundStyle(selected == 0 ? GymTheme.muted : .white)
                            .frame(minHeight: 44)
                    }
                        .disabled(selected == 0).accessibilityIdentifier("\(identifier)-previous-entry")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("\(selected + 1)/\(entries.count)")
                        .font(.caption.monospacedDigit()).foregroundStyle(GymTheme.muted)
                        .fixedSize().accessibilityLabel("第 \(selected + 1) 个动作，共 \(entries.count) 个")
                        .accessibilityIdentifier("\(identifier)-entry-position")
                    Button { selected += 1 } label: {
                        HStack(spacing: 8) {
                            Text("下一个动作")
                            Image(systemName: "chevron.right")
                        }.foregroundStyle(selected + 1 >= entries.count ? GymTheme.muted : .white)
                            .frame(minHeight: 44)
                    }
                        .disabled(selected + 1 >= entries.count).accessibilityIdentifier("\(identifier)-next-entry")
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }.font(.subheadline)
            }
        }.sheet(isPresented: $showingOptions) {
            optionsSheet
        }.onChange(of: selected) { _, _ in showingOptions = false; unitError = nil }
    }

    private func exerciseCard(_ entry: [String: Any]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            accessory()
            HStack(alignment: .center, spacing: 10) {
                ExerciseThumbnail(id: entry["id"] as? String ?? "", size: 40)
                let parts = store.exercise(entry["id"] as? String ?? "")?.titleParts
                VStack(alignment: .leading, spacing: 4) {
                    Text(parts?.primary ?? names[selected])
                        .font(.headline).lineLimit(1).minimumScaleFactor(0.75)
                    if let subtitle = parts?.secondary, !subtitle.isEmpty {
                        Text(subtitle).font(.caption).foregroundStyle(GymTheme.muted)
                            .lineLimit(2)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("\(identifier)-exercise-title")
                Button(action: showDetails) { Image(systemName: "info.circle").frame(width: 44, height: 44) }.accessibilityLabel("动作详情")
            }
            if let targetNote = (entry["target"] as? [String: Any])?["note"] as? String, !targetNote.isEmpty {
                Text(targetNote).font(.caption).foregroundStyle(GymTheme.muted)
            }
            if entry["sg"] != nil { Label("超级组", systemImage: "link").font(.caption).foregroundStyle(GymTheme.green) }
            ScrollView(.horizontal, showsIndicators: false) {
                Text(previous).font(.caption).foregroundStyle(GymTheme.muted).lineLimit(1).fixedSize(horizontal: true, vertical: false)
            }.accessibilityIdentifier("previous-exercise")
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                VStack(alignment: .leading, spacing: 8) {
                    AdvancedSetEditor(row: row.raw, target: (entry["target"] as? [String: Any] ?? [:]).merging(["id": entry["id"] ?? ""]) { _, new in new }, unit: unit, inputState: inputState, identifier: row.id, setLabel: "第 \(setNumber(index)) 组", copySet: { copySet(index) }, removeSet: { removeSet(index) }, timerRunning: timerRunning,
                                      startTimer: startTimer.map { start in { start(index) } },
                                      startRest: startRest.map { start in { start(index, $0) } }) { editSet(index, $0) }
                }
                if index < rows.count - 1 { Divider() }
            // Reset input focus and row-local controls without recreating the title and thumbnail.
            }.id([String(selected),entry["id"] as? String ?? ""] + rows.map(\.id))
            if let undoRemove {
                HStack { Text("已删除训练组").foregroundStyle(GymTheme.muted); Spacer(); Button("撤销", action: undoRemove).frame(minHeight: 44) }.font(.caption)
            }
            if rows.isEmpty { Text("暂无训练组，点击下方添加。").font(.subheadline).foregroundStyle(GymTheme.muted) }
            HStack(spacing: 12) {
                if startRest != nil {
                    // Keep the same space before, during, and after rest; the overlay cannot resize the card.
                    Color.clear.frame(maxWidth: .infinity)
                        .overlay(alignment: .center) {
                            if let restUntil {
                                TimelineView(.periodic(from: .now, by: 1)) { context in
                                    let seconds = max(0, Int(ceil(restUntil.timeIntervalSince(context.date))))
                                    Label(String(format: "%02d:%02d", seconds / 60, seconds % 60), systemImage: "timer")
                                        .monospacedDigit().foregroundStyle(GymTheme.green)
                                        .accessibilityLabel(seconds > 0 ? "组间休息剩余 \(seconds) 秒" : "休息结束")
                                }.accessibilityIdentifier("card-rest-timer")
                            }
                        }.allowsHitTesting(false)
                }
                Button(action: addSet) { Label("添加一组", systemImage: "plus").frame(maxWidth: .infinity, minHeight: 44) }
                    .buttonStyle(.borderless).disabled(timerRunning).accessibilityIdentifier("add-set")
            }.font(.subheadline).lineLimit(1).minimumScaleFactor(0.6).frame(height: 44)
        }.gymCard()
    }

    private var optionsSheet: some View {
        NavigationStack {
            Form {
                Section("本次动作备注") {
                    TextField("填写备注", text: $note, axis: .vertical)
                        .lineLimit(3...6).accessibilityIdentifier("\(identifier)-exercise-note")
                }
                if entries.indices.contains(selected), !rows.isEmpty,
                   (entries[selected]["target"] as? [String: Any])?["mode"] as? String != "cardio",
                   rows.contains(where: { $0.raw["mode"] as? String != "cardio" }) {
                    Section {
                        Picker("本次重量单位", selection: Binding(get: {
                            TrainingInput.weightUnit(rows.first?.raw ?? [:], fallback: unit)
                        }, set: { next in
                            do {
                                // Validate every row first so a switch cannot discard unfinished input.
                                for row in rows { try TrainingInput.validateWeightSwitch(row.raw) }
                                for index in rows.indices { editSet(index, ["action": "weightUnit", "unit": next]) }
                            } catch { unitError = error.localizedDescription }
                        })) {
                            Text("kg 公斤").tag("kg")
                            Text("lb 磅").tag("lb")
                        }.pickerStyle(.segmented).disabled(timerRunning)
                            .accessibilityIdentifier("\(identifier)-weight-unit")
                    } header: {
                        Text("本次重量单位")
                    } footer: {
                        Text("按当前器械选择；已有重量自动换算，仅影响本次动作。")
                    }
                }
            }.navigationTitle("备注与单位").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { showingOptions = false } } }
                .alert("重量输入已保留", isPresented: Binding(get: { unitError != nil }, set: { if !$0 { unitError = nil } })) {
                    Button("知道了", role: .cancel) {}
                } message: { Text(unitError ?? "") }
        }.presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
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

struct TrainingEditorRow: Identifiable {
    let id: String
    let raw: [String: Any]
}
