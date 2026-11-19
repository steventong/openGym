import SwiftUI

struct SettingsView: View {
    @Environment(GymStore.self) private var store
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @State private var notice = false
    /// 本机留有的服务器版地址；打开设置时读取一次，没有则不显示迁移入口。
    @State private var legacyServer: String?

    var body: some View {
        let weightDetails = [store.healthSync.status, store.healthSync.backgroundIssue,
            String(localized: "READS_BODY_WEIGHT_AND_SYNCS_IT_TO_THIS_ACCOUNT_WITHOUT_WRITING_TO", bundle: AppLanguage.bundle, locale: AppLanguage.locale)].compactMap { $0 }.joined(separator: "\n\n")
        let workoutDetails = store.workoutHealth.status + String(localized: "AUTOMATIC_WORKOUT_SYNC_INFO", bundle: AppLanguage.bundle, locale: AppLanguage.locale)

        NavigationStack {
            Form {
                if let cloudSync = store.cloudSync {
                    CloudSyncSection(status: cloudSync.status)
                }

                MediaServerSection(current: store.mediaServerURL, save: store.saveMediaServer)

                if let legacyServer {
                    LegacyImportSection(server: legacyServer, busy: store.syncing, run: store.importLegacyServerData)
                }

                Section("PERSONAL_SETTINGS") {
                    NavigationLink("FILTER_BY_GYM_EQUIPMENT") { EquipmentProfilesView() }
                    NavigationLink("WORKOUT_PREFERENCES_AND_UNITS") { PersonalSettingsView() }
                    NavigationLink("BODY_WEIGHT_AND_GOAL") { BodyRecordsView(measurements: false) }
                    NavigationLink("BODY_MEASUREMENTS") { BodyRecordsView(measurements: true) }
                }

                Section {
                    Toggle("AUTO_END_REST", isOn: Binding(get: { store.autoEndRestEnabled }, set: { store.autoEndRestEnabled = $0 }))
                        .accessibilityIdentifier("auto-end-rest-enabled")
                } header: {
                    Text("APPLE_WATCH")
                } footer: {
                    Text("AUTO_END_REST_INFO")
                }

                Section("APPLE_HEALTH") {
                    Toggle("SYNC_WEIGHT_FROM_APPLE_HEALTH", isOn: Binding(get: { store.healthSync.enabled }, set: { value in
                        Task { await store.healthSync.setEnabled(value) }
                    }))
                    .disabled(!store.healthSync.available || (store.healthSync.busy && !store.healthSync.enabled) || store.userID == nil)
                    .accessibilityIdentifier("health-weight-enabled")
                    LabeledContent("SYNC_STATUS") {
                        StatusDetailButton(title: weightStatus, message: "\(weightDetails)",
                            warning: store.healthSync.backgroundIssue != nil || store.healthSync.pending)
                    }
                    LabeledContent("LAST_READ", value: store.healthSync.lastRead?.formatted(date: .abbreviated, time: .shortened) ?? "—")
                    Button("ALLOW_WEIGHT_ACCESS") { Task { await store.healthSync.setEnabled(true) } }
                        .disabled(store.healthSync.busy || !store.healthSync.available || store.userID == nil)
                    Button("SYNC_WEIGHT_NOW") { Task { await store.healthSync.sync() } }
                        .disabled(!store.healthSync.enabled || store.healthSync.busy || store.syncing)
                }

                Section {
                    Toggle("SYNC_WORKOUTS_TO_APPLE_FITNESS", isOn: Binding(get: { store.workoutHealth.enabled }, set: { value in
                        Task { await store.workoutHealth.setEnabled(value) }
                    }))
                    .disabled(!store.workoutHealth.available || !store.workoutHealth.canChangeSetting)
                    .accessibilityIdentifier("health-workout-enabled")
                    Toggle("ADD_LOCATION_AND_WEATHER", isOn: Binding(get: { store.workoutHealth.placeEnabled }, set: { value in
                        Task { await store.workoutHealth.setPlaceEnabled(value) }
                    }))
                    .disabled(!store.workoutHealth.enabled || store.workoutHealth.busy)
                    .accessibilityIdentifier("health-workout-place-enabled")
                    LabeledContent("SYNC_STATUS") {
                        StatusDetailButton(title: workoutStatus, message: "\(workoutDetails)",
                            warning: store.workoutHealth.current?.state == .failed)
                    }
                    Button("ALLOW_WORKOUT_AND_ACTIVITY_ACCESS") { Task { await store.workoutHealth.authorize() } }
                        .disabled(store.workoutHealth.busy || !store.workoutHealth.available)
                    Button("RETRY_WORKOUT_SYNC") { store.workoutHealth.retry(wakeWatch: true) }
                        .disabled(!store.workoutHealth.available)
                } header: {
                    Text("APPLE_FITNESS_WORKOUT_SYNC")
                } footer: {
                    Text("ADD_LOCATION_AND_WEATHER_INFO")
                }

                if let notifications = store.restNotifications {
                    Section("SYSTEM_NOTIFICATIONS") {
                        Toggle("REST_END_NOTIFICATIONS", isOn: Binding(get: { notifications.enabled }, set: { value in
                            Task { await notifications.setEnabled(value) }
                        }))
                        .disabled(notifications.busy)
                        .accessibilityIdentifier("rest-notifications-enabled")
                        LabeledContent("NOTIFICATION_STATUS") {
                            StatusDetailButton(title: !notifications.enabled ? "STATUS_OFF" : notifications.issue != nil ? "NEEDS_ATTENTION" : notifications.permission.canDeliver ? "ALLOWED" : "NOT_AUTHORIZED",
                                message: "\(notifications.status)", warning: notifications.enabled && (!notifications.permission.canDeliver || notifications.issue != nil))
                        }
                        Button(LocalizedStringKey(notifications.permission.authorization == .notDetermined ? "ALLOW_NOTIFICATIONS" : "SYSTEM_NOTIFICATION_SETTINGS")) {
                            if notifications.permission.authorization == .notDetermined { Task { await notifications.authorize() } }
                            else if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                        }
                        .disabled(notifications.busy)
                    }
                }

                Section("ABOUT") {
                    LabeledContent("EXERCISES", value: String(format: String(localized: "COUNT_EXERCISES", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(describing: store.exercises.count)))
                    Button("LICENSES_AND_CREDITS") { notice = true }
                }
            }
            .navigationTitle("SETTINGS")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("DONE") { dismiss() } } }
            .task {
                legacyServer = LegacyAccount.find(in: store.localStorage)?.server
                await store.restNotifications?.flush()
            }
            .sheet(isPresented: $notice) {
                ScrollView { Text((try? String(contentsOf: Bundle.main.url(forResource: "NOTICE", withExtension: "txt")!, encoding: .utf8)) ?? "openGym · GNU AGPL v3.0").font(.system(size: 12)).padding() }
            }
        }.tint(GymTheme.green)
    }

    private var weightStatus: LocalizedStringKey {
        if !store.healthSync.available { return "UNAVAILABLE" }
        if store.healthSync.busy { return "SYNCING" }
        if !store.healthSync.enabled { return "NOT_ENABLED" }
        if store.healthSync.backgroundIssue != nil { return "NEEDS_ATTENTION" }
        if store.healthSync.pending { return "SYNC_PENDING" }
        return store.healthSync.status == String(localized: "WEIGHT_SYNCED", bundle: AppLanguage.bundle, locale: AppLanguage.locale) ? "SYNCED" : "VIEW_STATUS"
    }
    private var workoutStatus: LocalizedStringKey {
        if !store.workoutHealth.available { return "UNAVAILABLE" }
        if store.workoutHealth.busy { return "PROCESSING" }
        if !store.workoutHealth.enabled { return "NOT_ENABLED" }
        switch store.workoutHealth.current?.state {
        case .running: return "RECORDING"
        case .saved: return "SYNCED"
        case .failed: return "NEEDS_ATTENTION"
        case .discarded: return "ENDED"
        case nil: return "VIEW_STATUS"
        }
    }
}

#Preview("中文") {
    let store = GymStore(userID: "preview")
    store.mediaServerURL = "https://gym.example.com"
    if let url = Bundle.main.url(forResource: "catalogue", withExtension: "json"),
       let data = try? Data(contentsOf: url), let exercises = try? JSONDecoder().decode([Exercise].self, from: data) {
        store.registerCatalogue(exercises)
    }
    return SettingsView().environment(store).environment(\.locale, Locale(identifier: "zh-Hans"))
}

#Preview("English · Dark") {
    let store = GymStore(userID: "preview")
    store.mediaServerURL = "https://gym.example.com"
    return SettingsView().environment(store).environment(\.locale, Locale(identifier: "en")).preferredColorScheme(.dark)
}
