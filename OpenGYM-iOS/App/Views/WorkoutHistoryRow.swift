import SwiftUI

struct WorkoutHistoryRow: View, Equatable {
    @Environment(GymStore.self) private var store
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
                                Label(String(format: String(localized: "COUNT_PERSONAL_RECORDS_BADGE", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(prs)), systemImage: "trophy.fill").font(.caption2.weight(.semibold))
                                    .foregroundStyle(.yellow).fixedSize(horizontal: true, vertical: false)
                                    .accessibilityLabel(String(format: String(localized: "COUNT_PERSONAL_RECORDS", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(describing: prs)))
                            }
                        }
                        let exercises = record.exerciseSummary(resolve: store.exercise)
                        if !exercises.isEmpty {
                            Text(exercises)
                                .font(.caption).foregroundStyle(.white.opacity(0.75))
                                .lineLimit(2).truncationMode(.tail)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("history-exercises-\(record.id)")
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
                Button(LocalizedStringKey(syncing ? "SYNCING" : "SYNC"), action: sync)
                    .font(.subheadline).foregroundStyle(GymTheme.green)
                    .frame(minWidth: 44, minHeight: 44).fixedSize()
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("sync-history-\(record.id)")
            }
        }.padding(14).background(GymTheme.card, in: RoundedRectangle(cornerRadius: 16))
    }
}
