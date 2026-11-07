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
                VStack(alignment:.leading,spacing:7) { Text("WORKOUT_STATISTICS").font(.system(size:34,weight:.bold)) }
                HStack(spacing:12) {
                    StatsMetricCard(value: "\(workouts.count)", label: String(localized: "TOTAL_WORKOUTS", bundle: AppLanguage.bundle, locale: AppLanguage.locale), icon: "figure.strengthtraining.traditional")
                    StatsMetricCard(value: "\(completedSets.count)", label: String(localized: "COMPLETED_SETS", bundle: AppLanguage.bundle, locale: AppLanguage.locale), icon: "checkmark.circle")
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
                SectionTitle(text:String(localized: "WORKOUT_HISTORY", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                CommittedSearchField(String(localized: "SEARCH_WORKOUT_NAMES_DATES_AND_EXERCISES", bundle: AppLanguage.bundle, locale: AppLanguage.locale),text:$search).stableInputLine(height: 36).submitLabel(.search).onSubmit { GymKeyboard.dismiss() }.textFieldStyle(.roundedBorder)

                if workouts.isEmpty { EmptyCard(icon:"chart.line.uptrend.xyaxis",title:String(localized: "NO_WORKOUTS_YET", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) }
                LazyVStack(spacing:10) {
                    ForEach(workouts.filter { search.isEmpty || historyMatches($0) }.prefix(historyLimit).map(WorkoutRecord.init),id:\.id) { record in
                        WorkoutHistoryRow(record: record, unsynced: unsyncedIDs.contains(record.id),
                                          syncing: syncingRecordID == record.id,
                                          preview: { previewing = record }, sync: { sync(record.id) }).equatable()
                    }
                }
                if workouts.count > historyLimit { Button("MORE_WORKOUTS") { historyLimit += 30 }.frame(maxWidth:.infinity) }
            }.padding(22)
        }.refreshable { await store.refresh() }.sheet(isPresented:$analytics) { PersonalStatsHub() }.sheet(isPresented:$weightSheet) { WeightEntryView() }.sheet(item:$previewing) { record in WorkoutHistoryPreview(record:record) }
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
    private func historyMatches(_ w:[String:Any])->Bool {
        let text = [w["name"] as? String ?? "",w["d"] as? String ?? "",w["note"] as? String ?? ""] + (w["entries"] as? [[String:Any]] ?? []).map {store.exercise($0["id"] as? String ?? "")?.searchText ?? $0["n"] as? String ?? ""}
        return text.joined(separator:" ").localizedCaseInsensitiveContains(search)
    }
}

private struct StatsWeightSection: View {
    @Environment(GymStore.self) private var store
    @Binding var showEditor: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("WEIGHT_TREND").font(.headline)
                Spacer()
                Button("ADD_RECORD") { showEditor = true }
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
        if points.isEmpty { Text("NO_WEIGHT_RECORDS_YET").font(.subheadline).foregroundStyle(GymTheme.muted) }
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
        let date = dateFromDay(day).map { $0.formatted(.dateTime.month().day().weekday(.abbreviated).locale(AppLanguage.locale)) } ?? day
        let minutes = max(0,Int((number(record.raw["end"]) - number(record.raw["start"])) / 60000))
        let duration = minutes >= 60 ? String(format: String(localized: "COUNT_HR", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(describing: minutes / 60)) + (minutes % 60 > 0 ? String(format: String(localized: "COUNT_MIN_A", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(describing: minutes % 60)) : "") : String(format: String(localized: "COUNT_MIN", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(describing: minutes))
        return [date,duration,String(format: String(localized: "COUNT_SET", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(describing: record.completedSetCount))].joined(separator:" · ")
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
                            Text(record.raw["name"] as? String ?? String(localized: "WORKOUT", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                                .font(.subheadline.weight(.semibold)).foregroundStyle(.white).lineLimit(1)
                            if unsynced {
                                Text("NOT_SYNCED").font(.caption2).foregroundStyle(.orange).fixedSize()
                                    .accessibilityIdentifier("unsynced-history-\(record.id)")
                            }
                            Spacer(minLength: 0)
                            let prs = (record.raw["prs"] as? [Any])?.count ?? 0
                            if prs > 0 {
                                Label("\(prs) PR", systemImage: "trophy.fill").font(.caption2.weight(.semibold))
                                    .foregroundStyle(.yellow).fixedSize(horizontal: true, vertical: false)
                                    .accessibilityLabel(String(format: String(localized: "COUNT_PERSONAL_RECORDS", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(describing: prs)))
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
                Button(syncing ? String(localized: "SYNCING", bundle: AppLanguage.bundle, locale: AppLanguage.locale) : String(localized: "SYNC", bundle: AppLanguage.bundle, locale: AppLanguage.locale), action: sync)
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
                        Text(current.raw["name"] as? String ?? String(localized: "WORKOUT", bundle: AppLanguage.bundle, locale: AppLanguage.locale)).font(.title2.bold())
                        Text(current.raw["d"] as? String ?? "").foregroundStyle(GymTheme.muted)
                        Text(String(format: String(localized: "COUNT_MIN_COUNT_SETS", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(describing: decimal(max(0, number(current.raw["end"]) - number(current.raw["start"])) / 60000)), String(describing: current.completedSetCount)))
                            .font(.subheadline).foregroundStyle(GymTheme.muted)
                        if let note = current.raw["note"] as? String, !note.isEmpty { Text(note).font(.subheadline) }
                    }.frame(maxWidth: .infinity, alignment: .leading).gymCard()
                    let entries = current.raw["entries"] as? [[String: Any]] ?? []
                    ForEach(entries.indices, id: \.self) { index in
                        WorkoutHistoryExerciseCard(entry: entries[index], index: index, unit: unit)
                    }
                    if entries.isEmpty { Text("NO_EXERCISE_HISTORY_YET").foregroundStyle(GymTheme.muted) }
                }.padding(20)
            }.background(GymTheme.background).foregroundStyle(.white)
                .navigationTitle("WORKOUT_HISTORY").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { Button("TURN_OFF") { dismiss() } }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("EDIT_RECORD") { editing = current }
                            .accessibilityIdentifier("edit-history-\(record.id)")
                    }
                }
                .sheet(item: $editing) { record in HistoryEditor(record: record, unit: unit) }
        }.tint(GymTheme.green)
    }
}
