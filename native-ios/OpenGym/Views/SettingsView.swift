import SwiftUI
struct SettingsView: View {
    @Environment(GymStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var server = ""
    @State private var code = ""
    @State private var notice = false
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
                Section("关于") {
                    LabeledContent("客户端",value:"SwiftUI 原生预览 · 0.1")
                    LabeledContent("动作库",value:"\(store.exercises.count) 个动作")
                    Text("连接你的 openGym 服务，同步计划和训练记录。").font(.footnote).foregroundStyle(.secondary)
                    Button("开源许可与素材说明") { notice = true }
                }
            }.navigationTitle("设置").toolbar { ToolbarItem(placement:.topBarTrailing) { Button("完成") { dismiss() } } }
                .onAppear { server = store.serverURL }
                .sheet(isPresented:$notice) {
                    ScrollView { Text((try? String(contentsOf:Bundle.main.url(forResource:"NOTICE",withExtension:"txt")!)) ?? "openGym · GNU AGPL v3.0").font(.system(size:12)).padding() }
                }
        }.tint(GymTheme.green)
    }
}
