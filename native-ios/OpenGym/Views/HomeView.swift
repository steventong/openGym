import SwiftUI
import Charts
struct HomeView: View {
    @Environment(GymStore.self) private var store
    @State private var weekOffset = 0
    @State private var selectedDay = Calendar.current.startOfDay(for:Date())
    private var days: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for:Date())
        let offset = (calendar.component(.weekday,from:today) + 5) % 7
        let monday = calendar.date(byAdding:.day,value:-offset + 7 * weekOffset,to:today)!
        return (0..<7).map { calendar.date(byAdding:.day,value:$0,to:monday)! }
    }
    var body: some View {
        let calendarDays = days
        let markers = store.trainingDayMarkers(on: calendarDays)
        let scheduled = store.scheduledRoutines(on: selectedDay)
        ScrollView {
            VStack(alignment:.leading,spacing:24) {
                HStack(alignment:.center) {
                    VStack(alignment:.leading,spacing:7) {
                        Text("START_WORKOUT").font(.system(size:35,weight:.bold))
                        Text(Date().formatted(.dateTime.month().day().weekday(.wide).locale(AppLanguage.locale))).font(.system(size:13)).foregroundStyle(GymTheme.muted)
                    }
                    Spacer()
                    Button { store.showSettings = true } label: { Image(systemName:"gearshape").font(.system(size:22)).foregroundStyle(.white).padding(12).background(GymTheme.card,in:Circle()) }.accessibilityLabel("SETTINGS")
                }
                VStack(spacing:18) {
                    HStack {
                        Button { weekOffset -= 1 } label: { Image(systemName:"chevron.left").padding(6) }.accessibilityLabel("PREVIOUS_WEEK")
                        Spacer(); Text(weekOffset == 0 ? String(localized: "THIS_WEEK", bundle: AppLanguage.bundle, locale: AppLanguage.locale) : calendarDays[0].formatted(.dateTime.month().day())).font(.system(size:13,weight:.medium)); Spacer()
                        Button { weekOffset += 1 } label: { Image(systemName:"chevron.right").padding(6) }.accessibilityLabel("NEXT_WEEK")
                    }.foregroundStyle(GymTheme.muted)
                    HStack(spacing:7) {
                        ForEach(Array(calendarDays.enumerated()),id:\.offset) { i, day in
                            Button { selectedDay = day } label: {
                                VStack(spacing:11) {
                                    Text([String(localized: "MO", bundle: AppLanguage.bundle, locale: AppLanguage.locale),String(localized: "TU", bundle: AppLanguage.bundle, locale: AppLanguage.locale),String(localized: "WE", bundle: AppLanguage.bundle, locale: AppLanguage.locale),String(localized: "TH", bundle: AppLanguage.bundle, locale: AppLanguage.locale),String(localized: "FR", bundle: AppLanguage.bundle, locale: AppLanguage.locale),String(localized: "SA", bundle: AppLanguage.bundle, locale: AppLanguage.locale),String(localized: "SU", bundle: AppLanguage.bundle, locale: AppLanguage.locale)][i]).font(.system(size:11))
                                    Text(day.formatted(.dateTime.day())).font(.system(size:18,weight:.semibold))
                                    Circle().fill(markers[i] == .completed ? GymTheme.green : markers[i] == .planned ? GymTheme.muted : .clear)
                                        .frame(width:4,height:4).accessibilityHidden(true)
                                }.foregroundStyle(day == selectedDay ? .black : GymTheme.muted).frame(maxWidth:.infinity).padding(.vertical,12)
                                    .background(day == selectedDay ? GymTheme.green : GymTheme.card,in:Capsule())
                            }.buttonStyle(.plain)
                                .accessibilityValue(markers[i] == .completed ? String(localized: "WORKOUT_LOGGED", bundle: AppLanguage.bundle, locale: AppLanguage.locale) : markers[i] == .planned ? String(localized: "WORKOUT_SCHEDULED", bundle: AppLanguage.bundle, locale: AppLanguage.locale) : String(localized: "NO_WORKOUT_SCHEDULED", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                        }
                    }
                }
                VStack(alignment:.leading,spacing:18) {
                    HStack { Text(Calendar.current.isDateInToday(selectedDay) ? String(localized: "TODAY", bundle: AppLanguage.bundle, locale: AppLanguage.locale) : selectedDay.formatted(.dateTime.month().day())).font(.system(size:12)).foregroundStyle(GymTheme.muted); Spacer(); Image(systemName:"figure.strengthtraining.traditional").foregroundStyle(GymTheme.green) }
                        .lineLimit(1).frame(height:20)
                    HStack(alignment:.bottom,spacing:12) {
                        Text(store.draft?.name ?? (scheduled.isEmpty ? String(localized: "REST_DAY", bundle: AppLanguage.bundle, locale: AppLanguage.locale) : scheduled.map(\.name).joined(separator:" + ")))
                            .font(.system(size:29,weight:.bold)).lineLimit(1)
                            .frame(maxWidth:.infinity, alignment:.leading)
                        if store.draft == nil && !scheduled.isEmpty {
                            Text(String(format: String(localized: "COUNT_EXERCISES", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(describing: scheduled.flatMap(\.exercises).count)))
                                .font(.system(size:13)).foregroundStyle(GymTheme.muted)
                                .lineLimit(1).fixedSize()
                        }
                    }.frame(height:36, alignment:.leading)
                    GlassEffectContainer {
                        VStack(spacing: 18) {
                            HomeTrainingButton(title:
                                store.draft != nil ? String(localized: "CONTINUE_WORKOUT", bundle: AppLanguage.bundle, locale: AppLanguage.locale) : scheduled.isEmpty ? String(localized: "FREESTYLE", bundle: AppLanguage.bundle, locale: AppLanguage.locale) : String(localized: "START_WORKOUT", bundle: AppLanguage.bundle, locale: AppLanguage.locale),
                                icon: store.draft == nil && scheduled.isEmpty ? "figure.strengthtraining.traditional" : "play.fill",
                                primary: true,
                                identifier: store.draft == nil && scheduled.isEmpty ? "start-freestyle-workout" : "home-start-workout",
                                startedAt: store.draft?.start
                            ) {
                                if store.draft != nil {
                                    store.selectedTab = 2
                                } else if scheduled.isEmpty {
                                    store.startFreestyle()
                                } else {
                                    store.start(scheduled)
                                }
                            }
                            HomeTrainingButton(title:
                                scheduled.isEmpty ? String(localized: "CHOOSE_A_ROUTINE", bundle: AppLanguage.bundle, locale: AppLanguage.locale) : String(localized: "FREESTYLE", bundle: AppLanguage.bundle, locale: AppLanguage.locale),
                                icon: scheduled.isEmpty ? "list.bullet" : "figure.strengthtraining.traditional",
                                primary: false,
                                identifier: scheduled.isEmpty ? "home-select-plan" : "start-freestyle-workout",
                                enabled: store.draft == nil
                            ) {
                                if scheduled.isEmpty {
                                    store.selectedTab = 2
                                } else {
                                    store.startFreestyle()
                                }
                            }
                        }
                    }
                }.gymCard()
                if store.rotationSummary()["view"] as? [String:Any] != nil {RotationProgressCard()}
            }.padding(22)
        }.refreshable { await store.refresh() }
    }
}
struct WeightChart: View {
    let points: [[String:Any]]
    var body: some View {
        Chart {
            ForEach(Array(points.suffix(30).enumerated()),id:\.offset) { i, p in
                LineMark(x:.value(String(localized: "DATE", bundle: AppLanguage.bundle, locale: AppLanguage.locale),i),y:.value(String(localized: "BODY_WEIGHT", bundle: AppLanguage.bundle, locale: AppLanguage.locale),number(p["w"]))).foregroundStyle(GymTheme.green).interpolationMethod(.catmullRom)
                PointMark(x:.value(String(localized: "DATE", bundle: AppLanguage.bundle, locale: AppLanguage.locale),i),y:.value(String(localized: "BODY_WEIGHT", bundle: AppLanguage.bundle, locale: AppLanguage.locale),number(p["w"]))).foregroundStyle(GymTheme.green).symbolSize(20)
            }
        }.chartYScale(domain:.automatic(includesZero:false)).chartXAxis(.hidden)
    }
}
struct WeightEntryView: View {
    @Environment(GymStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var value = ""
    var body: some View {
        NavigationStack {
            Form {
                Section(String(format: String(localized: "TODAY_S_WEIGHT_COUNT", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(describing: store.unit))) { TextField("ENTER_BODY_WEIGHT",text:$value).textFieldStyle(.plain).stableInputLine().submitLabel(.done).onSubmit { GymKeyboard.dismiss() }.keyboardType(.decimalPad) }
                Section { Button(store.syncing ? String(localized: "SAVING", bundle: AppLanguage.bundle, locale: AppLanguage.locale) : String(localized: "SAVE_TO_SERVER", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) {
                    if let number = Double(value.replacingOccurrences(of:",",with:".")), number > 0 { Task { if await store.recordWeight(number) { dismiss() } } }
                }.disabled(store.syncing || (Double(value.replacingOccurrences(of:",",with:".")) ?? 0) <= 0) }
            }.navigationTitle("LOG_BODY_WEIGHT").toolbar { ToolbarItem(placement:.topBarTrailing) { Button("CANCEL") { dismiss() } } }
                .keyboardDismissToolbar()
        }.presentationDetents([.medium]).tint(GymTheme.green)
    }
}
