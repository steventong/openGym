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
        NavigationStack {
            Form {
                if store.userID != nil && !pairingAgain {
                  Section("CURRENT_CONNECTION") {
                    LabeledContent("SERVICE",value:store.online ? String(localized: "AVAILABLE", bundle: AppLanguage.bundle, locale: AppLanguage.locale) : String(localized: "CONNECTION_FAILED", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                    LabeledContent("SERVER") {
                        Text(store.serverURL).multilineTextAlignment(.trailing).textSelection(.enabled)
                    }
                    LabeledContent("ACCOUNT",value:store.userName ?? String(localized: "PAIR_AGAIN_TO_RECONNECT", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                    LabeledContent("LAST_SYNC", value: store.lastSync?.formatted(date: .omitted, time: .standard) ?? "—")
                    HStack {
                        Button("SYNC_NOW") { Task { await store.refresh() } }
                        Spacer()
                        Button("PAIR_AGAIN") { confirmPairing = true }.accessibilityIdentifier("pair-again")
                    }.buttonStyle(.borderless).disabled(store.syncing)
                    Text("SYNC_BACKUP_LOCATION")
                        .font(.footnote).foregroundStyle(.secondary)
                  }
                } else {
                  Section {
                    TextField("LOCAL_SERVER_EXAMPLE",text:$server).textFieldStyle(.plain).stableInputLine().submitLabel(.done).onSubmit { GymKeyboard.dismiss() }.keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("server-url")
                    TextField("ENTER_A_ONE_TIME_PAIRING_CODE",text:$code).textFieldStyle(.plain).stableInputLine().submitLabel(.done).onSubmit { GymKeyboard.dismiss() }.textInputAutocapitalization(.characters).autocorrectionDisabled().accessibilityIdentifier("pair-code")
                    Button { Task { await store.pair(server:server,code:code) } } label: {
                        HStack { Text(store.syncing ? String(localized: "PAIRING", bundle: AppLanguage.bundle, locale: AppLanguage.locale) : String(localized: "CONNECT_ACCOUNT", bundle: AppLanguage.bundle, locale: AppLanguage.locale)); Spacer(); if store.syncing { ProgressView() } }
                    }.disabled(code.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || store.syncing)
                    if pairingAgain {
                        Button("CANCEL_PAIRING", role: .cancel) { pairingAgain = false; code = "" }
                            .disabled(store.syncing)
                    }
                } header: { Text("PAIR_OPENGYM") } footer: {
                    Text("GET_A_PAIRING_CODE_FROM_ACCOUNT_IN_THE_WEB_APP_IT_EXPIRES")
                  }
                }
                Section {
                    Toggle("SYNC_WEIGHT_FROM_APPLE_HEALTH",isOn:Binding(get:{store.healthSync.enabled},set:{ value in Task { await store.healthSync.setEnabled(value) } }))
                        .disabled(!store.healthSync.available || (store.healthSync.busy && !store.healthSync.enabled) || store.userID == nil).accessibilityIdentifier("health-weight-enabled")
                    LabeledContent("SYNC_STATUS") {
                        StatusDetailButton(title: weightStatus, message: [store.healthSync.status, store.healthSync.backgroundIssue,
                            String(localized: "READS_BODY_WEIGHT_AND_SYNCS_IT_TO_THIS_ACCOUNT_WITHOUT_WRITING_TO", bundle: AppLanguage.bundle, locale: AppLanguage.locale)].compactMap { $0 }.joined(separator: "\n\n"),
                            warning: store.healthSync.backgroundIssue != nil || store.healthSync.pending)
                    }
                    LabeledContent("LAST_READ", value: store.healthSync.lastRead?.formatted(date: .abbreviated, time: .shortened) ?? "—")
                    Button("ALLOW_WEIGHT_ACCESS") { Task { await store.healthSync.setEnabled(true) } }.disabled(store.healthSync.busy || !store.healthSync.available || store.userID == nil)
                    Button("SYNC_WEIGHT_NOW") { Task { await store.healthSync.sync() } }.disabled(!store.healthSync.enabled || store.healthSync.busy || store.syncing)
                } header: { Text("APPLE_HEALTH") }
                Section {
                    Toggle("SYNC_WORKOUTS_TO_APPLE_FITNESS", isOn: Binding(get: { store.workoutHealth.enabled }, set: { value in Task { await store.workoutHealth.setEnabled(value) } }))
                        .disabled(!store.workoutHealth.available || !store.workoutHealth.canChangeSetting)
                        .accessibilityIdentifier("health-workout-enabled")
                    LabeledContent("SYNC_STATUS") {
                        StatusDetailButton(title: workoutStatus,
                            message: store.workoutHealth.status + String(localized: "ONLY_NEW_WORKOUTS_STARTED_AFTER_ENABLING_SYNC_ARE_INCLUDED_PAST_WORKOUTS_ARE", bundle: AppLanguage.bundle, locale: AppLanguage.locale),
                            warning: store.workoutHealth.current?.state == .failed)
                    }
                    Button("ALLOW_WORKOUT_AND_ACTIVITY_ACCESS") { Task { await store.workoutHealth.authorize() } }
                        .disabled(store.workoutHealth.busy || !store.workoutHealth.available)
                    Button("RETRY_WORKOUT_SYNC") { store.workoutHealth.retry(wakeWatch: true) }.disabled(!store.workoutHealth.available)
                } header: { Text("APPLE_FITNESS_WORKOUT_SYNC") }
                if let notifications = store.restNotifications {
                    Section {
                        Toggle("REST_END_NOTIFICATIONS", isOn: Binding(get: { notifications.enabled }, set: { value in
                            Task { await notifications.setEnabled(value) }
                        }))
                        .disabled(notifications.busy)
                        .accessibilityIdentifier("rest-notifications-enabled")
                        LabeledContent("NOTIFICATION_STATUS") {
                            StatusDetailButton(title: !notifications.enabled ? String(localized: "STATUS_OFF", bundle: AppLanguage.bundle, locale: AppLanguage.locale) : notifications.issue != nil ? String(localized: "NEEDS_ATTENTION", bundle: AppLanguage.bundle, locale: AppLanguage.locale) : notifications.permission.canDeliver ? String(localized: "ALLOWED", bundle: AppLanguage.bundle, locale: AppLanguage.locale) : String(localized: "NOT_AUTHORIZED", bundle: AppLanguage.bundle, locale: AppLanguage.locale),
                                message: notifications.status, warning: notifications.enabled && (!notifications.permission.canDeliver || notifications.issue != nil))
                        }
                        Button(notifications.permission.authorization == .notDetermined ? String(localized: "ALLOW_NOTIFICATIONS", bundle: AppLanguage.bundle, locale: AppLanguage.locale) : String(localized: "SYSTEM_NOTIFICATION_SETTINGS", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) {
                            if notifications.permission.authorization == .notDetermined { Task { await notifications.authorize() } }
                            else if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                        }.disabled(notifications.busy)
                    } header: { Text("SYSTEM_NOTIFICATIONS") }
                }
                Section("PERSONAL_SETTINGS") {
                    NavigationLink("FILTER_BY_GYM_EQUIPMENT") { EquipmentProfilesView() }
                    NavigationLink("WORKOUT_PREFERENCES_AND_UNITS") { PersonalSettingsView() }
                    NavigationLink("BODY_WEIGHT_AND_GOAL") { BodyRecordsView(measurements:false) }
                    NavigationLink("BODY_MEASUREMENTS") { BodyRecordsView(measurements:true) }
                }
                Section("ABOUT") {
                    LabeledContent("CLIENT",value:String(localized: "SWIFTUI_NATIVE_PREVIEW_ZERO_ONE", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                    LabeledContent("EXERCISES",value:String(format: String(localized: "COUNT_EXERCISES", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(describing: store.exercises.count)))
                    Button("LICENSES_AND_CREDITS") { notice = true }
                }
            }.navigationTitle("SETTINGS").toolbar { ToolbarItem(placement:.topBarTrailing) { Button("DONE") { dismiss() } } }
                .onAppear { guard !loaded else { return }; loaded = true; server = store.serverURL }
                .task { await store.restNotifications?.flush() }
                .confirmationDialog("PAIR_OPENGYM_AGAIN", isPresented: $confirmPairing, titleVisibility: .visible) {
                    Button("PAIR_AGAIN") { server = store.serverURL; code = ""; pairingAgain = true }
                    Button("CANCEL", role: .cancel) {}
                }
                .sheet(isPresented:$notice) {
                    ScrollView { Text((try? String(contentsOf:Bundle.main.url(forResource:"NOTICE",withExtension:"txt")!,encoding:.utf8)) ?? "openGym · GNU AGPL v3.0").font(.system(size:12)).padding() }
                }
        }.tint(GymTheme.green)
    }
    private var weightStatus: String {
        if !store.healthSync.available { return String(localized: "UNAVAILABLE", bundle: AppLanguage.bundle, locale: AppLanguage.locale) }
        if store.healthSync.busy { return String(localized: "SYNCING", bundle: AppLanguage.bundle, locale: AppLanguage.locale) }
        if !store.healthSync.enabled { return String(localized: "NOT_ENABLED", bundle: AppLanguage.bundle, locale: AppLanguage.locale) }
        if store.healthSync.backgroundIssue != nil { return String(localized: "NEEDS_ATTENTION", bundle: AppLanguage.bundle, locale: AppLanguage.locale) }
        if store.healthSync.pending { return String(localized: "SYNC_PENDING", bundle: AppLanguage.bundle, locale: AppLanguage.locale) }
        return store.healthSync.status == String(localized: "WEIGHT_SYNCED", bundle: AppLanguage.bundle, locale: AppLanguage.locale) ? String(localized: "SYNCED", bundle: AppLanguage.bundle, locale: AppLanguage.locale) : String(localized: "VIEW_STATUS", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
    }
    private var workoutStatus: String {
        if !store.workoutHealth.available { return String(localized: "UNAVAILABLE", bundle: AppLanguage.bundle, locale: AppLanguage.locale) }
        if store.workoutHealth.busy { return String(localized: "PROCESSING", bundle: AppLanguage.bundle, locale: AppLanguage.locale) }
        if !store.workoutHealth.enabled { return String(localized: "NOT_ENABLED", bundle: AppLanguage.bundle, locale: AppLanguage.locale) }
        switch store.workoutHealth.current?.state {
        case .running: return String(localized: "RECORDING", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
        case .saved: return String(localized: "SYNCED", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
        case .failed: return String(localized: "NEEDS_ATTENTION", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
        case .discarded: return String(localized: "ENDED", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
        case nil: return String(localized: "VIEW_STATUS", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
        }
    }
}
