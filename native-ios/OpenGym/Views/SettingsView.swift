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
                    Text("在网页中登录，打开「设置 → 账号 → 配对手机 App」，输入生成的代码。配对码有效期为 5 分钟。模拟器可直接连接本机 localhost 服务。")
                }
                Section {
                    Toggle("Apple 健康体重同步",isOn:Binding(get:{store.healthSync.enabled},set:{ value in Task { await store.healthSync.setEnabled(value) } }))
                        .disabled(!store.healthSync.available || (store.healthSync.busy && !store.healthSync.enabled) || store.userID == nil).accessibilityIdentifier("health-weight-enabled")
                    Text(store.healthSync.status).font(.caption).foregroundStyle(.secondary)
                    if let issue = store.healthSync.backgroundIssue { Text(issue).font(.caption).foregroundStyle(.orange) }
                    if let read = store.healthSync.lastRead { LabeledContent("上次读取",value:read.formatted(date:.abbreviated,time:.shortened)) }
                    Button("授权读取体重 / 重新请求授权") { Task { await store.healthSync.setEnabled(true) } }.disabled(store.healthSync.busy || !store.healthSync.available || store.userID == nil)
                    Button("立即同步体重") { Task { await store.healthSync.sync() } }.disabled(!store.healthSync.enabled || store.healthSync.busy || store.syncing)
                } header: { Text("Apple 健康") } footer: {
                    Text("只读取体重，不向 Apple 健康写入。每天采用最后一次测量，先保存在本机，再同步到当前 openGym 账号；已有手动记录优先。关闭开关会停止后续同步。读取权限请到「健康 → 个人头像 → App → openGym」管理；iOS 不向 App 显示是否拒绝了读取权限。后台同步由系统调度。")
                }
                Section("关于") {
                    LabeledContent("客户端",value:"SwiftUI 原生预览 · 0.1")
                    LabeledContent("动作库",value:"\(store.exercises.count) 个动作")
                    Text("这是 openGym 的非商业原生客户端开发版本，使用现有服务端协议。普通训练组可记录和同步；复杂进阶规则仍由网页版提供。").font(.footnote).foregroundStyle(.secondary)
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
