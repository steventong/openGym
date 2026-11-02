import SwiftUI
struct SettingsView: View {
    @Environment(GymStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var server = ""
    @State private var code = ""
    @State private var notice = false
    @State private var loaded = false
    var body: some View {
        NavigationStack {
            Form {
                Section("当前连接") {
                    LabeledContent("服务",value:store.online ? "可用" : "连接失败")
                    LabeledContent("账号",value:store.userName ?? "未配对")
                    if let lastSync = store.lastSync { LabeledContent("上次同步",value:lastSync.formatted(date:.omitted,time:.standard)) }
                    Button("立即同步") { Task { await store.refresh() } }.disabled(store.syncing)
                }
                Section {
                    TextField("http://localhost:8080",text:$server).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("server-url")
                    TextField("输入一次性配对码",text:$code).textInputAutocapitalization(.characters).autocorrectionDisabled().accessibilityIdentifier("pair-code")
                    Button { Task { await store.pair(server:server,code:code) } } label: {
                        HStack { Text(store.syncing ? "正在配对…" : "连接账号"); Spacer(); if store.syncing { ProgressView() } }
                    }.disabled(code.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || store.syncing)
                } header: { Text("配对 openGym") } footer: {
                    Text("在网页「设置 → 账号 → 配对手机 App」获取配对码，5 分钟内有效。")
                }
                Section {
                    Toggle("Apple 健康体重同步",isOn:Binding(get:{store.healthSync.enabled},set:{ value in Task { await store.healthSync.setEnabled(value) } }))
                        .disabled(!store.healthSync.available || (store.healthSync.busy && !store.healthSync.enabled) || store.userID == nil).accessibilityIdentifier("health-weight-enabled")
                    Text(store.healthSync.status).font(.caption).foregroundStyle(.secondary)
                    if let issue = store.healthSync.backgroundIssue { Text(issue).font(.caption).foregroundStyle(.orange) }
                    if let read = store.healthSync.lastRead { LabeledContent("上次读取",value:read.formatted(date:.abbreviated,time:.shortened)) }
                    Button("授权读取体重") { Task { await store.healthSync.setEnabled(true) } }.disabled(store.healthSync.busy || !store.healthSync.available || store.userID == nil)
                    Button("立即同步体重") { Task { await store.healthSync.sync() } }.disabled(!store.healthSync.enabled || store.healthSync.busy || store.syncing)
                } header: { Text("Apple 健康") } footer: {
                    Text("读取 Apple 健康体重并同步到当前账号，不写回健康。权限可在健康 App 中管理。")
                }
                Section {
                    Toggle("同步训练到苹果健身", isOn: Binding(get: { store.workoutHealth.enabled }, set: { value in Task { await store.workoutHealth.setEnabled(value) } }))
                        .disabled(!store.workoutHealth.available || !store.workoutHealth.canChangeSetting)
                        .accessibilityIdentifier("health-workout-enabled")
                    Text(store.workoutHealth.status).font(.caption).foregroundStyle(.secondary)
                    Button("授权训练与运动指标") { Task { await store.workoutHealth.authorize() } }
                        .disabled(store.workoutHealth.busy || !store.workoutHealth.available)
                    Button("重试训练同步") { store.workoutHealth.retry(wakeWatch: true) }.disabled(!store.workoutHealth.available)
                } header: { Text("Apple 健身 · 训练同步") } footer: {
                    Text("开启后，下次训练开始与结束时自动同步为传统力量训练。已连接的 Apple Watch 优先记录心率与活动卡路里；首次使用需在手表授权。无系统数据时留空。运动健康指标仅保留在设备与 Apple 健康中。")
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
                    Text("连接你的 openGym 服务，同步计划和训练记录。").font(.footnote).foregroundStyle(.secondary)
                    Button("开源许可与素材说明") { notice = true }
                }
            }.navigationTitle("设置").toolbar { ToolbarItem(placement:.topBarTrailing) { Button("完成") { dismiss() } } }
                .onAppear { guard !loaded else { return }; loaded = true; server = store.serverURL }
                .sheet(isPresented:$notice) {
                    ScrollView { Text((try? String(contentsOf:Bundle.main.url(forResource:"NOTICE",withExtension:"txt")!)) ?? "openGym · GNU AGPL v3.0").font(.system(size:12)).padding() }
                }
        }.tint(GymTheme.green)
    }
}
