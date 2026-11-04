import SwiftUI
struct StatsView: View {
    @Environment(GymStore.self) private var store
    var body: some View {
        // Server revision, health samples and unrelated plan updates do not rebuild history.
        StatsContent(workouts: store.workouts, unsyncedIDs: Set(store.historyEdits.keys))
            .equatable()
    }
}

struct StatsContent: View, Equatable {
    @Environment(GymStore.self) private var store
    let workouts: [[String: Any]]
    let unsyncedIDs: Set<String>

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.unsyncedIDs == rhs.unsyncedIDs && RecordPatch.equal(lhs.workouts, rhs.workouts)
    }
    @State private var previewing: WorkoutRecord?
    @State private var syncingRecordID: String?
    @State private var syncError: String?
    @State private var historyLimit = 30
    @State private var analytics = false
    @State private var weightSheet = false
    @State private var search = ""
    private var completedSets: [[String:Any]] {
        workouts.flatMap { $0["entries"] as? [[String:Any]] ?? [] }.flatMap { $0["sets"] as? [[String:Any]] ?? [] }.flatMap { row -> [[String:Any]] in if let sides = row["sides"] as? [String:[String:Any]] {return [sides["L"],sides["R"]].compactMap{$0}};return [row] }.filter { $0["done"] as? Bool == true }
    }
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:24) {
                VStack(alignment:.leading,spacing:7) { Text(L10n.text("WORKOUT_STATISTICS" /* 训练统计 */)).font(.system(size:34,weight:.bold)) }
                HStack(spacing:12) {
                    metric("\(workouts.count)",L10n.text("TOTAL_WORKOUTS" /* 累计训练 */),"figure.strengthtraining.traditional")
                    metric("\(completedSets.count)",L10n.text("COMPLETED_SETS" /* 完成组数 */),"checkmark.circle")
                }
                VStack(alignment:.leading,spacing:16) {
                    HStack { Text(L10n.text("TRAINING_ACTIVITY" /* 训练足迹 */)).font(.headline); Spacer(); Text(L10n.text("LAST_ONETWO_WEEKS" /* 最近 12 周 */)).font(.caption).foregroundStyle(GymTheme.muted) }
                    let trained = Set(workouts.compactMap { $0["d"] as? String })
                    let cells = (0..<84).map { Calendar.current.date(byAdding:.day,value:$0-83,to:Date())! }
                    HStack(spacing:5) {
                        ForEach(0..<12,id:\.self) { week in
                            VStack(spacing:5) { ForEach(0..<7,id:\.self) { day in RoundedRectangle(cornerRadius:3).fill(trained.contains(dayString(cells[week*7+day])) ? GymTheme.green : Color(white:0.20)).aspectRatio(1,contentMode:.fit) } }
                        }
                    }.accessibilityLabel(L10n.text("TRAINING_ACTIVITY_OVER_THE_LAST_TWELVE_WEEKS" /* 最近十二周的训练活动图 */))
                }.gymCard()
                StatsWeightSection(showEditor: $weightSheet)
                Button { analytics = true } label: { Label(L10n.text("EXERCISE_PROGRESS_MUSCLES_AND_BODY_METRICS" /* 动作进步、肌群与身体指标 */),systemImage:"chart.xyaxis.line").frame(maxWidth:.infinity,minHeight:44) }.gymCard().accessibilityIdentifier("open-personal-analytics")
                SectionTitle(text:L10n.text("WORKOUT_HISTORY" /* 训练记录 */))
                CommittedSearchField(L10n.text("SEARCH_WORKOUT_NAMES_DATES_AND_EXERCISES" /* 搜索训练名称、日期、动作 */),text:$search).stableInputLine(height: 36).submitLabel(.search).onSubmit { GymKeyboard.dismiss() }.textFieldStyle(.roundedBorder)

                if workouts.isEmpty { EmptyCard(icon:"chart.line.uptrend.xyaxis",title:L10n.text("NO_WORKOUTS_YET" /* 暂无训练记录 */)) }
                LazyVStack(spacing:10) {
                    ForEach(workouts.filter { search.isEmpty || historyMatches($0) }.prefix(historyLimit).map(WorkoutRecord.init),id:\.id) { record in
                        WorkoutHistoryRow(record: record, unsynced: unsyncedIDs.contains(record.id),
                                          syncing: syncingRecordID == record.id,
                                          preview: { previewing = record }, sync: { sync(record.id) }).equatable()
                    }
                }
                if workouts.count > historyLimit { Button(L10n.text("MORE_WORKOUTS" /* 更多训练记录 */)) { historyLimit += 30 }.frame(maxWidth:.infinity) }
            }.padding(22)
        }.refreshable { await store.refresh() }.sheet(isPresented:$analytics) { PersonalStatsHub() }.sheet(isPresented:$weightSheet) { WeightEntryView() }.sheet(item:$previewing) { record in WorkoutHistoryPreview(record:record) }
            .alert(L10n.text("SYNC_INCOMPLETE" /* 同步未完成 */), isPresented: Binding(get: { syncError != nil }, set: { if !$0 { syncError = nil } })) {
                Button(L10n.text("GOT_IT" /* 知道了 */), role: .cancel) {}
            } message: { Text(syncError ?? "") }
    }
    private func sync(_ id: String) {
        guard syncingRecordID == nil, !store.syncing else { return }
        syncingRecordID = id
        Task {
            defer { syncingRecordID = nil }
            if !(await store.submitHistoryEdit(id)) {
                syncError = store.editError ?? store.localSaveError ?? L10n.text("COULD_NOT_SYNC_YOUR_RECORDS_ARE_SAFE_ON_THIS_DEVICE_TRY_AGAIN" /* 同步失败，记录仍保留在本机，请稍后重试。 */)
            }
        }
    }
    private func historyMatches(_ w:[String:Any])->Bool {
        let text = [w["name"] as? String ?? "",w["d"] as? String ?? "",w["note"] as? String ?? ""] + (w["entries"] as? [[String:Any]] ?? []).map {store.exercise($0["id"] as? String ?? "")?.searchText ?? $0["n"] as? String ?? ""}
        return text.joined(separator:" ").localizedCaseInsensitiveContains(search)
    }
    private func metric(_ value:String,_ label:String,_ icon:String) -> some View {
        VStack(alignment:.leading,spacing:16) {
            Image(systemName:icon).font(.system(size:20)).foregroundStyle(GymTheme.green)
            Text(value).font(.system(size:34,weight:.bold,design:.rounded))
            Text(label).font(.caption).foregroundStyle(GymTheme.muted)
        }.frame(maxWidth:.infinity,alignment:.leading).gymCard()
    }
}

private struct StatsWeightSection: View {
    @Environment(GymStore.self) private var store
    @Binding var showEditor: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(L10n.text("WEIGHT_TREND" /* 体重趋势 */)).font(.headline)
                Spacer()
                Button(L10n.text("ADD_RECORD" /* 添加记录 */)) { showEditor = true }
                    .font(.caption).foregroundStyle(GymTheme.green).frame(minHeight: 44)
                    .accessibilityIdentifier("stats-add-weight")
            }
            StatsWeightPlot(points: store.bodyweights).equatable()
        }.gymCard()
    }
}

private struct StatsWeightPlot: View, Equatable {
    let points: [[String: Any]]
    static func == (lhs: Self, rhs: Self) -> Bool { RecordPatch.equal(lhs.points, rhs.points) }
    var body: some View {
        if points.isEmpty { Text(L10n.text("NO_WEIGHT_RECORDS_YET" /* 暂无体重记录 */)).font(.subheadline).foregroundStyle(GymTheme.muted) }
        else { WeightChart(points: points).frame(height: 140) }
    }
}

private struct WorkoutHistoryRow: View, Equatable {
    let record: WorkoutRecord
    let unsynced: Bool
    let syncing: Bool
    let preview: () -> Void
    let sync: () -> Void
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.unsynced == rhs.unsynced && lhs.syncing == rhs.syncing &&
            lhs.record.id == rhs.record.id && RecordPatch.equal(lhs.record.raw, rhs.record.raw)
    }
    private var subtitle: String {
        let day = record.raw["d"] as? String ?? ""
        let date = dateFromDay(day).map { $0.formatted(.dateTime.month().day().weekday(.abbreviated).locale(L10n.locale)) } ?? day
        let minutes = max(0,Int((number(record.raw["end"]) - number(record.raw["start"])) / 60000))
        let duration = minutes >= 60 ? L10n.text("COUNT_HR" /* {0} 小时 */, minutes / 60) + (minutes % 60 > 0 ? L10n.text("COUNT_MIN_A" /* {0} 分钟 */, minutes % 60) : "") : L10n.text("COUNT_MIN" /* {0} 分钟 */, minutes)
        return [date,duration,L10n.text("COUNT_SET" /* {0} 组 */, record.completedSetCount)].joined(separator:" · ")
    }
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Button(action: preview) {
                HStack(spacing: 12) {
                    Image(systemName: record.raw["routineId"] as? String == nil ? "figure.strengthtraining.traditional" : "dumbbell.fill")
                        .font(.system(size: 19, weight: .medium)).foregroundStyle(.black)
                        .frame(width: 40, height: 40).background(GymTheme.green, in: RoundedRectangle(cornerRadius: 10))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 8) {
                            Text(record.raw["name"] as? String ?? L10n.text("WORKOUT" /* 训练 */))
                                .font(.subheadline.weight(.semibold)).foregroundStyle(.white).lineLimit(1)
                            if unsynced {
                                Text(L10n.text("NOT_SYNCED" /* 未同步 */)).font(.caption2).foregroundStyle(.orange).fixedSize()
                                    .accessibilityIdentifier("unsynced-history-\(record.id)")
                            }
                            Spacer(minLength: 0)
                            let prs = (record.raw["prs"] as? [Any])?.count ?? 0
                            if prs > 0 {
                                Label("\(prs) PR", systemImage: "trophy.fill").font(.caption2.weight(.semibold))
                                    .foregroundStyle(.yellow).fixedSize(horizontal: true, vertical: false)
                                    .accessibilityLabel(L10n.text("COUNT_PERSONAL_RECORDS" /* {0} 项个人纪录 */, prs))
                            }
                        }
                        Text(subtitle).font(.caption).foregroundStyle(GymTheme.muted).fixedSize(horizontal: false, vertical: true)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    if !unsynced {
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                            .foregroundStyle(GymTheme.muted).accessibilityHidden(true)
                    }
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("preview-history-\(record.id)")
            if unsynced {
                Button(syncing ? L10n.text("SYNCING" /* 正在同步… */) : L10n.text("SYNC" /* 同步 */), action: sync)
                    .font(.subheadline).foregroundStyle(GymTheme.green)
                    .frame(minWidth: 44, minHeight: 44).fixedSize()
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("sync-history-\(record.id)")
            }
        }.padding(14).background(GymTheme.card, in: RoundedRectangle(cornerRadius: 16))
    }
}

/// Preview has no editable bindings or persistence; corrections use the existing editor.
private struct WorkoutHistoryPreview: View {
    @Environment(GymStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let record: WorkoutRecord
    @State private var editing: WorkoutRecord?
    private var current: WorkoutRecord {
        store.workouts.first { WorkoutRecord.key($0) == record.id }.map(WorkoutRecord.init) ?? record
    }
    private var unit: String { store.historyEdits[record.id]?["unit"] as? String ?? store.unit }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(current.raw["name"] as? String ?? L10n.text("WORKOUT" /* 训练 */)).font(.title2.bold())
                        Text(current.raw["d"] as? String ?? "").foregroundStyle(GymTheme.muted)
                        Text(L10n.text("COUNT_MIN_COUNT_SETS" /* {0} 分钟 · {1} 组 */, decimal(max(0, number(current.raw["end"]) - number(current.raw["start"])) / 60000), current.completedSetCount))
                            .font(.subheadline).foregroundStyle(GymTheme.muted)
                        if let note = current.raw["note"] as? String, !note.isEmpty { Text(note).font(.subheadline) }
                    }.frame(maxWidth: .infinity, alignment: .leading).gymCard()
                    let entries = current.raw["entries"] as? [[String: Any]] ?? []
                    ForEach(entries.indices, id: \.self) { index in
                        exerciseCard(entries[index], index: index)
                    }
                    if entries.isEmpty { Text(L10n.text("NO_EXERCISE_HISTORY_YET" /* 暂无动作记录 */)).foregroundStyle(GymTheme.muted) }
                }.padding(20)
            }.background(GymTheme.background).foregroundStyle(.white)
                .navigationTitle(L10n.text("WORKOUT_HISTORY" /* 训练记录 */)).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { Button(L10n.text("TURN_OFF" /* 关闭 */)) { dismiss() } }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(L10n.text("EDIT_RECORD" /* 编辑记录 */)) { editing = current }
                            .accessibilityIdentifier("edit-history-\(record.id)")
                    }
                }
                .sheet(item: $editing) { record in HistoryEditor(record: record, unit: unit) }
        }.tint(GymTheme.green)
    }
    private func exerciseCard(_ entry: [String: Any], index: Int) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                ExerciseThumbnail(id: entry["id"] as? String ?? "", size: 40)
                let parts = store.exercise(entry["id"] as? String ?? "")?.titleParts
                Text(parts?.primary ?? entry["n"] as? String ?? L10n.text("EXERCISE" /* 动作 */)).font(.headline)
            }
            if entry["sg"] != nil { Label(L10n.text("SUPERSET" /* 超级组 */), systemImage: "link").font(.caption).foregroundStyle(GymTheme.green) }
            let rows = entry["sets"] as? [[String: Any]] ?? []
            ForEach(rows.indices, id: \.self) { i in
                let setNumber = (0...i).filter { !(rows[$0]["side"] as? String == "R" && $0 > 0 && rows[$0 - 1]["side"] as? String == "L") }.count
                AdvancedSetEditor(row: rows[i], target: (entry["target"] as? [String: Any] ?? [:]).merging(["id": entry["id"] ?? ""]) { _, new in new },
                                  unit: unit, inputState: store.state.merging(["unit": unit]) { _, new in new },
                                  identifier: "history-preview-\(index)-\(i)", setLabel: L10n.text("SET_COUNT" /* 第 {0} 组 */, setNumber), readOnly: true) { _ in }
                if i < rows.count - 1 { Divider() }
            }
            if rows.isEmpty { Text(L10n.text("NO_SETS_YET" /* 暂无训练组 */)).font(.caption).foregroundStyle(GymTheme.muted) }
        }.gymCard().accessibilityIdentifier("history-preview-exercise-\(index)")
    }
}
