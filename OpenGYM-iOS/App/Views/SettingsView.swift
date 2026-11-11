import SwiftUI

struct SettingsView: View {
    @Environment(GymStore.self) private var store
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @State private var server = ""
    @State private var code = ""
    @State private var notice = false
    @State private var loaded = false
    @State private var pairingAgain = false
    @State private var confirmPairing = false

    var body: some View {
        let weightDetails = [store.healthSync.status, store.healthSync.backgroundIssue,
            String(localized: "READS_BODY_WEIGHT_AND_SYNCS_IT_TO_THIS_ACCOUNT_WITHOUT_WRITING_TO", bundle: AppLanguage.bundle, locale: AppLanguage.locale)].compactMap { $0 }.joined(separator: "\n\n")
        let workoutDetails = store.workoutHealth.status + String(localized: "AUTOMATIC_WORKOUT_SYNC_INFO", bundle: AppLanguage.bundle, locale: AppLanguage.locale)

        NavigationStack {
            Form {
                if store.userID != nil && !pairingAgain {
                    Section("CURRENT_CONNECTION") {
                        LabeledContent("SERVER") {
                            Text(store.serverURL)
                                .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                        }
                        LabeledContent("ACCOUNT", value: store.userName ?? String(localized: "PAIR_AGAIN_TO_RECONNECT", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                        LabeledContent("SERVICE", value: store.online ? String(localized: "AVAILABLE", bundle: AppLanguage.bundle, locale: AppLanguage.locale) : String(localized: "CONNECTION_FAILED", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                        LabeledContent("LAST_SYNC", value: store.lastSync?.formatted(date: .omitted, time: .standard) ?? "—")
                        SettingsSyncControls(isBusy: store.syncing, onSync: store.refresh) { confirmPairing = true }
                    }
                } else {
                    Section("PAIR_OPENGYM") {
                        TextField("LOCAL_SERVER_EXAMPLE", text: $server)
                            .textFieldStyle(.plain).stableInputLine().submitLabel(.done)
                            .onSubmit { GymKeyboard.dismiss() }.keyboardType(.URL)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .accessibilityIdentifier("server-url")
                        TextField("ENTER_A_ONE_TIME_PAIRING_CODE", text: $code)
                            .textFieldStyle(.plain).stableInputLine().submitLabel(.done)
                            .onSubmit { GymKeyboard.dismiss() }.textInputAutocapitalization(.characters)
                            .autocorrectionDisabled().accessibilityIdentifier("pair-code")
                        Button { Task { await store.pair(server: server, code: code) } } label: {
                            HStack {
                                Text(LocalizedStringKey(store.syncing ? "PAIRING" : "CONNECT_ACCOUNT"))
                                Spacer()
                                if store.syncing { ProgressView() }
                            }
                        }
                        .disabled(code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.syncing)
                        if pairingAgain {
                            Button("CANCEL_PAIRING", role: .cancel) { pairingAgain = false; code = "" }
                                .disabled(store.syncing)
                        }
                    }
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

                Section("APPLE_FITNESS_WORKOUT_SYNC") {
                    Toggle("SYNC_WORKOUTS_TO_APPLE_FITNESS", isOn: Binding(get: { store.workoutHealth.enabled }, set: { value in
                        Task { await store.workoutHealth.setEnabled(value) }
                    }))
                    .disabled(!store.workoutHealth.available || !store.workoutHealth.canChangeSetting)
                    .accessibilityIdentifier("health-workout-enabled")
                    LabeledContent("SYNC_STATUS") {
                        StatusDetailButton(title: workoutStatus, message: "\(workoutDetails)",
                            warning: store.workoutHealth.current?.state == .failed)
                    }
                    Button("ALLOW_WORKOUT_AND_ACTIVITY_ACCESS") { Task { await store.workoutHealth.authorize() } }
                        .disabled(store.workoutHealth.busy || !store.workoutHealth.available)
                    Button("RETRY_WORKOUT_SYNC") { store.workoutHealth.retry(wakeWatch: true) }
                        .disabled(!store.workoutHealth.available)
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
            .onAppear { guard !loaded else { return }; loaded = true; server = store.serverURL }
            .task { await store.restNotifications?.flush() }
            .confirmationDialog("PAIR_OPENGYM_AGAIN", isPresented: $confirmPairing, titleVisibility: .visible) {
                Button("PAIR_AGAIN") { server = store.serverURL; code = ""; pairingAgain = true }
                Button("CANCEL", role: .cancel) {}
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

#Preview("Connected") {
    let store = GymStore(userID: "preview")
    store.serverURL = "https://gym.example.com"
    store.userName = "Alex"
    store.online = true
    store.lastSync = Date()
    if let url = Bundle.main.url(forResource: "catalogue", withExtension: "json"),
       let data = try? Data(contentsOf: url), let exercises = try? JSONDecoder().decode([Exercise].self, from: data) {
        store.registerCatalogue(exercises)
    }
    return SettingsView().environment(store).environment(\.locale, AppLanguage.locale)
}

#Preview("Pair account · Dark") {
    let store = GymStore()
    store.serverURL = "https://gym.example.com"
    return SettingsView().environment(store).environment(\.locale, AppLanguage.locale).preferredColorScheme(.dark)
}
