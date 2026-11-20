import SwiftUI

/// 设置页里进入 iCloud 同步页面的一行，只显示概况。
struct CloudSyncRow: View {
    let status: CloudSyncStatus

    var body: some View {
        NavigationLink {
            CloudSyncView(status: status)
        } label: {
            LabeledContent("ICLOUD_SYNC") {
                CloudSyncStatusText(status: status)
            }
        }
        .accessibilityIdentifier("icloud-sync")
    }
}

/// iCloud 同步页面。同步由系统自动完成，这里说明账号、结果，以及失败时的具体原因。
struct CloudSyncView: View {
    let status: CloudSyncStatus

    var body: some View {
        Form {
            Section {
                LabeledContent("ICLOUD_ACCOUNT") {
                    Text(LocalizedStringKey(status.accountAvailable ? "ICLOUD_SIGNED_IN" : "ICLOUD_SIGNED_OUT"))
                        .foregroundStyle(status.accountAvailable ? Color.secondary : Color.orange)
                }
                LabeledContent("LAST_SYNC", value: status.lastSync?.formatted(date: .abbreviated, time: .shortened) ?? "—")
                LabeledContent("SYNC_STATUS") {
                    CloudSyncStatusText(status: status)
                }
            } footer: {
                Text("ICLOUD_SYNC_INFO")
            }

            // 未登录时系统只会反复报告“没有账号”，账号一行已经说明。
            if status.accountAvailable, let issue = status.issue {
                Section {
                    ForEach(Array(issue.causes.enumerated()), id: \.offset) { _, cause in
                        CloudSyncCauseRow(cause: cause)
                    }
                } header: {
                    Text(LocalizedStringKey(issue.phaseTitle))
                }
                Section {
                    ForEach(issue.details, id: \.self) { detail in
                        Text(verbatim: detail).font(.footnote).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                } header: {
                    Text("ERROR_DETAILS")
                }
            }
        }
        .navigationTitle("ICLOUD_SYNC")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// 同步概况：未登录、需处理、等待自动重试、已同步。
struct CloudSyncStatusText: View {
    let status: CloudSyncStatus

    var body: some View {
        Text(LocalizedStringKey(title)).foregroundStyle(warning ? Color.orange : Color.secondary)
    }

    private var warning: Bool {
        !status.accountAvailable || status.issue?.needsAction == true
    }

    private var title: String {
        guard status.accountAvailable else { return "ICLOUD_SIGNED_OUT" }
        if let issue = status.issue { return issue.needsAction ? "NEEDS_ATTENTION" : "SYNC_PENDING" }
        return status.lastSync == nil ? "SYNC_PENDING" : "SYNCED"
    }
}

/// 一种失败原因：说明发生了什么、要不要处理，以及涉及多少条记录。
struct CloudSyncCauseRow: View {
    let cause: CloudSyncIssue.Cause

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(LocalizedStringKey(explanation))
                .foregroundStyle(cause.reason.needsAction ? Color.orange : Color.primary)
            if let records = cause.records {
                Text("CLOUD_SYNC_AFFECTED_RECORDS \(records)").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var explanation: String {
        switch cause.reason {
        case .schemaNotDeployed: "CLOUD_SYNC_REASON_SCHEMA"
        case .conflict: "CLOUD_SYNC_REASON_CONFLICT"
        case .quotaExceeded: "CLOUD_SYNC_REASON_QUOTA"
        case .notSignedIn: "CLOUD_SYNC_REASON_SIGNED_OUT"
        case .network: "CLOUD_SYNC_REASON_NETWORK"
        case .busy: "CLOUD_SYNC_REASON_BUSY"
        case .dataDeleted: "CLOUD_SYNC_REASON_DELETED"
        case .configuration: "CLOUD_SYNC_REASON_CONFIGURATION"
        case .other: "CLOUD_SYNC_REASON_OTHER"
        }
    }
}

private extension CloudSyncIssue {
    var phaseTitle: String {
        switch phase {
        case .setup: "CLOUD_SYNC_SETUP_FAILED"
        case .download: "CLOUD_SYNC_DOWNLOAD_FAILED"
        case .upload: "CLOUD_SYNC_UPLOAD_FAILED"
        }
    }
}

#Preview("中文 · 已同步") {
    NavigationStack {
        CloudSyncView(status: CloudSyncStatus(accountAvailable: true, lastSync: Date()))
    }
    .environment(\.locale, Locale(identifier: "zh-Hans"))
    .tint(GymTheme.green)
}

#Preview("English · Signed out · Dark") {
    NavigationStack {
        CloudSyncView(status: CloudSyncStatus())
    }
    .environment(\.locale, Locale(identifier: "en"))
    .preferredColorScheme(.dark)
    .tint(GymTheme.green)
}

#Preview("中文 · 上传失败") {
    NavigationStack {
        CloudSyncView(status: CloudSyncStatus(accountAvailable: true, lastSync: Date().addingTimeInterval(-3600),
            issue: CloudSyncIssue(phase: .upload, causes: [
                CloudSyncIssue.Cause(reason: .schemaNotDeployed, records: 12),
                CloudSyncIssue.Cause(reason: .conflict, records: 1),
            ], details: ["CKError 12: Cannot create new type CD_StoredWorkout in production schema"])))
    }
    .environment(\.locale, Locale(identifier: "zh-Hans"))
    .tint(GymTheme.green)
}

#Preview("设置行 · 需处理") {
    NavigationStack {
        Form {
            CloudSyncRow(status: CloudSyncStatus(accountAvailable: true, lastSync: Date(),
                issue: CloudSyncIssue(phase: .upload, causes: [CloudSyncIssue.Cause(reason: .schemaNotDeployed, records: 3)], details: [])))
        }
    }
    .environment(\.locale, Locale(identifier: "zh-Hans"))
    .tint(GymTheme.green)
}
