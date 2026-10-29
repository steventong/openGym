import SwiftUI

/// Shared exercise page for an active session and a saved workout.
/// Owners provide persistence and the live-only timer controls.
struct TrainingExerciseEditor<Accessory: View>: View {
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
    @State private var options: OptionsRoute?
    private enum OptionsRoute: String, Identifiable {
        case metadata
        var id: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if entries.indices.contains(selected) {
                exerciseCard(entries[selected]).id(selected)
                HStack {
                    Button { selected -= 1 } label: { Label("上一个动作", systemImage: "chevron.left").frame(minHeight: 44) }
                        .disabled(selected == 0).accessibilityIdentifier("\(identifier)-previous-entry")
                    Spacer()
                    Button { selected += 1 } label: { Label("下一个动作", systemImage: "chevron.right").frame(minHeight: 44) }
                        .disabled(selected + 1 >= entries.count).accessibilityIdentifier("\(identifier)-next-entry")
                }.font(.subheadline)
            }
        }.sheet(item: $options) { _ in
            optionsSheet
        }.onChange(of: selected) { _, _ in options = nil; unitError = nil }
    }

    private func exerciseCard(_ entry: [String: Any]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            accessory()
            HStack(spacing: 10) {
                ExerciseThumbnail(id: entry["id"] as? String ?? "", size: 40)
                Menu {
                    Button("备注与单位", systemImage: "square.and.pencil") { options = .metadata }
                        .accessibilityIdentifier("\(identifier)-exercise-options")
                    Divider()
                    ForEach(entries.indices, id: \.self) { index in
                        Button("\(index + 1).\(names[index]) · \(status(entries[index]))") { selected = index }
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(selected + 1).\(names[selected])").font(.headline).multilineTextAlignment(.leading)
                        HStack(spacing: 5) {
                            Text("\(status(entry)) · \(selected + 1) / \(entries.count)")
                            Image(systemName: "chevron.down")
                        }.font(.caption).foregroundStyle(GymTheme.green)
                    }.frame(maxWidth: .infinity, alignment: .leading).frame(minHeight: 44)
                }.buttonStyle(.plain).accessibilityIdentifier("\(identifier)-exercise-selector")
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
            }.id(rows.map(\.id))
            if let undoRemove {
                HStack { Text("已删除训练组").foregroundStyle(GymTheme.muted); Spacer(); Button("撤销", action: undoRemove).frame(minHeight: 44) }.font(.caption)
            }
            if rows.isEmpty { Text("暂无训练组，点击下方添加。").font(.subheadline).foregroundStyle(GymTheme.muted) }
            Button(action: addSet) { Label("添加一组", systemImage: "plus").font(.subheadline).frame(maxWidth: .infinity, minHeight: 44) }
                .buttonStyle(.borderless).disabled(timerRunning).accessibilityIdentifier("add-set")
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
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { options = nil } } }
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

    private func status(_ entry: [String: Any]) -> String {
        let sets = entry["sets"] as? [[String: Any]] ?? []
        if !sets.isEmpty && sets.allSatisfy({ $0["done"] as? Bool == true }) { return "已练" }
        return sets.contains(where: rawCompleted) ? "进行中" : "待练"
    }
}

struct TrainingEditorRow: Identifiable {
    let id: String
    let raw: [String: Any]
}
