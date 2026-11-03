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
                  Section("当前连接") {
                    LabeledContent("服务",value:store.online ? "可用" : "连接失败")
                    LabeledContent("服务器") {
                        Text(store.serverURL).multilineTextAlignment(.trailing).textSelection(.enabled)
                    }
                    LabeledContent("账号",value:store.userName ?? "需要重新配对")
                    LabeledContent("上次同步", value: store.lastSync?.formatted(date: .omitted, time: .standard) ?? "—")
                    HStack {
                        Button("立即同步") { Task { await store.refresh() } }
                        Spacer()
                        Button("重新配对") { confirmPairing = true }.accessibilityIdentifier("pair-again")
                    }.buttonStyle(.borderless).disabled(store.syncing)
                  }
                } else {
                  Section {
                    TextField("http://localhost:8080",text:$server).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("server-url")
                    TextField("输入一次性配对码",text:$code).textInputAutocapitalization(.characters).autocorrectionDisabled().accessibilityIdentifier("pair-code")
                    Button { Task { await store.pair(server:server,code:code) } } label: {
                        HStack { Text(store.syncing ? "正在配对" : "连接账号"); Spacer(); if store.syncing { ProgressView() } }
                    }.disabled(code.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || store.syncing)
                    if pairingAgain {
                        Button("取消重新配对", role: .cancel) { pairingAgain = false; code = "" }
                            .disabled(store.syncing)
                    }
                } header: { Text("配对 openGym") } footer: {
                    Text("配对码在网页「账号」中获取，5 分钟有效。")
                  }
                }
                Section {
                    Toggle("Apple 健康体重同步",isOn:Binding(get:{store.healthSync.enabled},set:{ value in Task { await store.healthSync.setEnabled(value) } }))
                        .disabled(!store.healthSync.available || (store.healthSync.busy && !store.healthSync.enabled) || store.userID == nil).accessibilityIdentifier("health-weight-enabled")
                    LabeledContent("同步状态") {
                        StatusDetailButton(title: weightStatus, message: [store.healthSync.status, store.healthSync.backgroundIssue,
                            "读取体重并同步到当前账号，不写回 Apple 健康。读取权限可在健康 App 管理。"].compactMap { $0 }.joined(separator: "\n\n"),
                            warning: store.healthSync.backgroundIssue != nil || store.healthSync.pending)
                    }
                    LabeledContent("上次读取", value: store.healthSync.lastRead?.formatted(date: .abbreviated, time: .shortened) ?? "—")
                    Button("授权读取体重") { Task { await store.healthSync.setEnabled(true) } }.disabled(store.healthSync.busy || !store.healthSync.available || store.userID == nil)
                    Button("立即同步体重") { Task { await store.healthSync.sync() } }.disabled(!store.healthSync.enabled || store.healthSync.busy || store.syncing)
                } header: { Text("Apple 健康") }
                Section {
                    Toggle("同步训练到苹果健身", isOn: Binding(get: { store.workoutHealth.enabled }, set: { value in Task { await store.workoutHealth.setEnabled(value) } }))
                        .disabled(!store.workoutHealth.available || !store.workoutHealth.canChangeSetting)
                        .accessibilityIdentifier("health-workout-enabled")
                    LabeledContent("同步状态") {
                        StatusDetailButton(title: workoutStatus,
                            message: store.workoutHealth.status + "\n\n只同步开启后开始的新训练，不补传或更新历史训练。已连接的 Apple Watch 优先记录心率和热量，首次使用需在手表授权。运动健康指标仅保留在设备与 Apple 健康中。",
                            warning: store.workoutHealth.current?.state == .failed)
                    }
                    Button("授权训练与运动指标") { Task { await store.workoutHealth.authorize() } }
                        .disabled(store.workoutHealth.busy || !store.workoutHealth.available)
                    Button("重试训练同步") { store.workoutHealth.retry(wakeWatch: true) }.disabled(!store.workoutHealth.available)
                } header: { Text("Apple 健身 · 训练同步") }
                if let notifications = store.restNotifications {
                    Section {
                        Toggle("休息结束通知", isOn: Binding(get: { notifications.enabled }, set: { value in
                            Task { await notifications.setEnabled(value) }
                        }))
                        .disabled(notifications.busy)
                        .accessibilityIdentifier("rest-notifications-enabled")
                        LabeledContent("通知状态") {
                            StatusDetailButton(title: !notifications.enabled ? "已关闭" : notifications.issue != nil ? "需处理" : notifications.permission.canDeliver ? "已允许" : "未授权",
                                message: notifications.status, warning: notifications.enabled && (!notifications.permission.canDeliver || notifications.issue != nil))
                        }
                        Button(notifications.permission.authorization == .notDetermined ? "允许系统通知" : "系统通知设置") {
                            if notifications.permission.authorization == .notDetermined { Task { await notifications.authorize() } }
                            else if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                        }.disabled(notifications.busy)
                    } header: { Text("系统通知") }
                }
                Section("个人设置") {
                    NavigationLink("健身房器械筛选") { EquipmentProfilesView() }
                    NavigationLink("训练偏好与单位") { PersonalSettingsView() }
                    NavigationLink("体重记录与目标") { BodyRecordsView(measurements:false) }
                    NavigationLink("身体围度") { BodyRecordsView(measurements:true) }
                }
                Section("关于") {
                    LabeledContent("客户端",value:"SwiftUI 原生预览 · 0.1")
                    LabeledContent("动作库",value:"\(store.exercises.count) 个动作")
                    Button("开源许可与素材说明") { notice = true }
                }
            }.navigationTitle("设置").toolbar { ToolbarItem(placement:.topBarTrailing) { Button("完成") { dismiss() } } }
                .onAppear { guard !loaded else { return }; loaded = true; server = store.serverURL }
                .task { await store.restNotifications?.flush() }
                .confirmationDialog("重新配对 openGym？", isPresented: $confirmPairing, titleVisibility: .visible) {
                    Button("重新配对") { server = store.serverURL; code = ""; pairingAgain = true }
                    Button("取消", role: .cancel) {}
                }
                .sheet(isPresented:$notice) {
                    ScrollView { Text((try? String(contentsOf:Bundle.main.url(forResource:"NOTICE",withExtension:"txt")!,encoding:.utf8)) ?? "openGym · GNU AGPL v3.0").font(.system(size:12)).padding() }
                }
        }.tint(GymTheme.green)
    }
    private var weightStatus: String {
        if !store.healthSync.available { return "不可用" }
        if store.healthSync.busy { return "正在同步" }
        if !store.healthSync.enabled { return "未开启" }
        if store.healthSync.backgroundIssue != nil { return "需处理" }
        if store.healthSync.pending { return "待同步" }
        return store.healthSync.status == "体重已同步" ? "已同步" : "查看状态"
    }
    private var workoutStatus: String {
        if !store.workoutHealth.available { return "不可用" }
        if store.workoutHealth.busy { return "处理中" }
        if !store.workoutHealth.enabled { return "未开启" }
        switch store.workoutHealth.current?.state {
        case .running: return "记录中"
        case .saved: return "已同步"
        case .failed: return "需处理"
        case .discarded: return "已结束"
        case nil: return "查看状态"
        }
    }
}
