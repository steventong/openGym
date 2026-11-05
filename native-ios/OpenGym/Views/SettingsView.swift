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
                  Section(L10n.text("CURRENT_CONNECTION" /* 当前连接 */)) {
                    LabeledContent(L10n.text("SERVICE" /* 服务 */),value:store.online ? L10n.text("AVAILABLE" /* 可用 */) : L10n.text("CONNECTION_FAILED" /* 连接失败 */))
                    LabeledContent(L10n.text("SERVER" /* 服务器 */)) {
                        Text(store.serverURL).multilineTextAlignment(.trailing).textSelection(.enabled)
                    }
                    LabeledContent(L10n.text("ACCOUNT" /* 账号 */),value:store.userName ?? L10n.text("PAIR_AGAIN_TO_RECONNECT" /* 需要重新配对 */))
                    LabeledContent(L10n.text("LAST_SYNC" /* 上次同步 */), value: store.lastSync?.formatted(date: .omitted, time: .standard) ?? "—")
                    HStack {
                        Button(L10n.text("SYNC_NOW" /* 立即同步 */)) { Task { await store.refresh() } }
                        Spacer()
                        Button(L10n.text("PAIR_AGAIN" /* 重新配对 */)) { confirmPairing = true }.accessibilityIdentifier("pair-again")
                    }.buttonStyle(.borderless).disabled(store.syncing)
                    Text(L10n.text("SYNC_BACKUP_LOCATION" /* 每次同步前自动保存服务器快照，可在“文件”App → OpenGYM → backup 中查看。 */))
                        .font(.footnote).foregroundStyle(.secondary)
                  }
                } else {
                  Section {
                    TextField(L10n.text("LOCAL_SERVER_EXAMPLE" /* 术语：http://localhost:8080 */),text:$server).textFieldStyle(.plain).stableInputLine().submitLabel(.done).onSubmit { GymKeyboard.dismiss() }.keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("server-url")
                    TextField(L10n.text("ENTER_A_ONE_TIME_PAIRING_CODE" /* 输入一次性配对码 */),text:$code).textFieldStyle(.plain).stableInputLine().submitLabel(.done).onSubmit { GymKeyboard.dismiss() }.textInputAutocapitalization(.characters).autocorrectionDisabled().accessibilityIdentifier("pair-code")
                    Button { Task { await store.pair(server:server,code:code) } } label: {
                        HStack { Text(store.syncing ? L10n.text("PAIRING" /* 正在配对 */) : L10n.text("CONNECT_ACCOUNT" /* 连接账号 */)); Spacer(); if store.syncing { ProgressView() } }
                    }.disabled(code.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || store.syncing)
                    if pairingAgain {
                        Button(L10n.text("CANCEL_PAIRING" /* 取消重新配对 */), role: .cancel) { pairingAgain = false; code = "" }
                            .disabled(store.syncing)
                    }
                } header: { Text(L10n.text("PAIR_OPENGYM" /* 配对 openGym */)) } footer: {
                    Text(L10n.text("GET_A_PAIRING_CODE_FROM_ACCOUNT_IN_THE_WEB_APP_IT_EXPIRES" /* 配对码在网页「账号」中获取，5 分钟有效。 */))
                  }
                }
                Section {
                    Toggle(L10n.text("SYNC_WEIGHT_FROM_APPLE_HEALTH" /* Apple 健康体重同步 */),isOn:Binding(get:{store.healthSync.enabled},set:{ value in Task { await store.healthSync.setEnabled(value) } }))
                        .disabled(!store.healthSync.available || (store.healthSync.busy && !store.healthSync.enabled) || store.userID == nil).accessibilityIdentifier("health-weight-enabled")
                    LabeledContent(L10n.text("SYNC_STATUS" /* 同步状态 */)) {
                        StatusDetailButton(title: weightStatus, message: [store.healthSync.status, store.healthSync.backgroundIssue,
                            L10n.text("READS_BODY_WEIGHT_AND_SYNCS_IT_TO_THIS_ACCOUNT_WITHOUT_WRITING_TO" /* 读取体重并同步到当前账号，不写回 Apple 健康。读取权限可在健康 App 管理。 */)].compactMap { $0 }.joined(separator: "\n\n"),
                            warning: store.healthSync.backgroundIssue != nil || store.healthSync.pending)
                    }
                    LabeledContent(L10n.text("LAST_READ" /* 上次读取 */), value: store.healthSync.lastRead?.formatted(date: .abbreviated, time: .shortened) ?? "—")
                    Button(L10n.text("ALLOW_WEIGHT_ACCESS" /* 授权读取体重 */)) { Task { await store.healthSync.setEnabled(true) } }.disabled(store.healthSync.busy || !store.healthSync.available || store.userID == nil)
                    Button(L10n.text("SYNC_WEIGHT_NOW" /* 立即同步体重 */)) { Task { await store.healthSync.sync() } }.disabled(!store.healthSync.enabled || store.healthSync.busy || store.syncing)
                } header: { Text(L10n.text("APPLE_HEALTH" /* Apple 健康 */)) }
                Section {
                    Toggle(L10n.text("SYNC_WORKOUTS_TO_APPLE_FITNESS" /* 同步训练到苹果健身 */), isOn: Binding(get: { store.workoutHealth.enabled }, set: { value in Task { await store.workoutHealth.setEnabled(value) } }))
                        .disabled(!store.workoutHealth.available || !store.workoutHealth.canChangeSetting)
                        .accessibilityIdentifier("health-workout-enabled")
                    LabeledContent(L10n.text("SYNC_STATUS" /* 同步状态 */)) {
                        StatusDetailButton(title: workoutStatus,
                            message: store.workoutHealth.status + L10n.text("ONLY_NEW_WORKOUTS_STARTED_AFTER_ENABLING_SYNC_ARE_INCLUDED_PAST_WORKOUTS_ARE" /* 只同步开启后开始的新训练，不补传或更新历史训练。已连接的 Apple Watch 优先记录心率和热量，首次使用需在手表授权。运动健康指标仅保留在设备与 Apple 健康中。 */),
                            warning: store.workoutHealth.current?.state == .failed)
                    }
                    Button(L10n.text("ALLOW_WORKOUT_AND_ACTIVITY_ACCESS" /* 授权训练与运动指标 */)) { Task { await store.workoutHealth.authorize() } }
                        .disabled(store.workoutHealth.busy || !store.workoutHealth.available)
                    Button(L10n.text("RETRY_WORKOUT_SYNC" /* 重试训练同步 */)) { store.workoutHealth.retry(wakeWatch: true) }.disabled(!store.workoutHealth.available)
                } header: { Text(L10n.text("APPLE_FITNESS_WORKOUT_SYNC" /* Apple 健身 · 训练同步 */)) }
                if let notifications = store.restNotifications {
                    Section {
                        Toggle(L10n.text("REST_END_NOTIFICATIONS" /* 休息结束通知 */), isOn: Binding(get: { notifications.enabled }, set: { value in
                            Task { await notifications.setEnabled(value) }
                        }))
                        .disabled(notifications.busy)
                        .accessibilityIdentifier("rest-notifications-enabled")
                        LabeledContent(L10n.text("NOTIFICATION_STATUS" /* 通知状态 */)) {
                            StatusDetailButton(title: !notifications.enabled ? L10n.text("STATUS_OFF" /* 已关闭 */) : notifications.issue != nil ? L10n.text("NEEDS_ATTENTION" /* 需处理 */) : notifications.permission.canDeliver ? L10n.text("ALLOWED" /* 已允许 */) : L10n.text("NOT_AUTHORIZED" /* 未授权 */),
                                message: notifications.status, warning: notifications.enabled && (!notifications.permission.canDeliver || notifications.issue != nil))
                        }
                        Button(notifications.permission.authorization == .notDetermined ? L10n.text("ALLOW_NOTIFICATIONS" /* 允许系统通知 */) : L10n.text("SYSTEM_NOTIFICATION_SETTINGS" /* 系统通知设置 */)) {
                            if notifications.permission.authorization == .notDetermined { Task { await notifications.authorize() } }
                            else if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                        }.disabled(notifications.busy)
                    } header: { Text(L10n.text("SYSTEM_NOTIFICATIONS" /* 系统通知 */)) }
                }
                Section(L10n.text("PERSONAL_SETTINGS" /* 个人设置 */)) {
                    NavigationLink(L10n.text("FILTER_BY_GYM_EQUIPMENT" /* 健身房器械筛选 */)) { EquipmentProfilesView() }
                    NavigationLink(L10n.text("WORKOUT_PREFERENCES_AND_UNITS" /* 训练偏好与单位 */)) { PersonalSettingsView() }
                    NavigationLink(L10n.text("BODY_WEIGHT_AND_GOAL" /* 体重记录与目标 */)) { BodyRecordsView(measurements:false) }
                    NavigationLink(L10n.text("BODY_MEASUREMENTS" /* 身体围度 */)) { BodyRecordsView(measurements:true) }
                }
                Section(L10n.text("ABOUT" /* 关于 */)) {
                    LabeledContent(L10n.text("CLIENT" /* 客户端 */),value:L10n.text("SWIFTUI_NATIVE_PREVIEW_ZERO_ONE" /* SwiftUI 原生预览 · 0.1 */))
                    LabeledContent(L10n.text("EXERCISES" /* 动作库 */),value:L10n.text("COUNT_EXERCISES" /* {0} 个动作 */, store.exercises.count))
                    Button(L10n.text("LICENSES_AND_CREDITS" /* 开源许可与素材说明 */)) { notice = true }
                }
            }.navigationTitle(L10n.text("SETTINGS" /* 设置 */)).toolbar { ToolbarItem(placement:.topBarTrailing) { Button(L10n.text("DONE" /* 完成 */)) { dismiss() } } }
                .onAppear { guard !loaded else { return }; loaded = true; server = store.serverURL }
                .task { await store.restNotifications?.flush() }
                .confirmationDialog(L10n.text("PAIR_OPENGYM_AGAIN" /* 重新配对 openGym？ */), isPresented: $confirmPairing, titleVisibility: .visible) {
                    Button(L10n.text("PAIR_AGAIN" /* 重新配对 */)) { server = store.serverURL; code = ""; pairingAgain = true }
                    Button(L10n.text("CANCEL" /* 取消 */), role: .cancel) {}
                }
                .sheet(isPresented:$notice) {
                    ScrollView { Text((try? String(contentsOf:Bundle.main.url(forResource:"NOTICE",withExtension:"txt")!,encoding:.utf8)) ?? "openGym · GNU AGPL v3.0").font(.system(size:12)).padding() }
                }
        }.tint(GymTheme.green)
    }
    private var weightStatus: String {
        if !store.healthSync.available { return L10n.text("UNAVAILABLE" /* 不可用 */) }
        if store.healthSync.busy { return L10n.text("SYNCING" /* 正在同步… */) }
        if !store.healthSync.enabled { return L10n.text("NOT_ENABLED" /* 未开启 */) }
        if store.healthSync.backgroundIssue != nil { return L10n.text("NEEDS_ATTENTION" /* 需处理 */) }
        if store.healthSync.pending { return L10n.text("SYNC_PENDING" /* 待同步 */) }
        return store.healthSync.status == L10n.text("WEIGHT_SYNCED" /* 体重已同步 */) ? L10n.text("SYNCED" /* 已同步 */) : L10n.text("VIEW_STATUS" /* 查看状态 */)
    }
    private var workoutStatus: String {
        if !store.workoutHealth.available { return L10n.text("UNAVAILABLE" /* 不可用 */) }
        if store.workoutHealth.busy { return L10n.text("PROCESSING" /* 处理中 */) }
        if !store.workoutHealth.enabled { return L10n.text("NOT_ENABLED" /* 未开启 */) }
        switch store.workoutHealth.current?.state {
        case .running: return L10n.text("RECORDING" /* 记录中 */)
        case .saved: return L10n.text("SYNCED" /* 已同步 */)
        case .failed: return L10n.text("NEEDS_ATTENTION" /* 需处理 */)
        case .discarded: return L10n.text("ENDED" /* 已结束 */)
        case nil: return L10n.text("VIEW_STATUS" /* 查看状态 */)
        }
    }
}
