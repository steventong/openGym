import SwiftUI

/// 设置页的 iCloud 同步状态。同步由系统自动完成，这里只展示结果。
struct CloudSyncSection: View {
    let status: CloudSyncStatus

    var body: some View {
        Section {
            LabeledContent("ICLOUD_ACCOUNT") {
                Text(LocalizedStringKey(status.accountAvailable ? "ICLOUD_SIGNED_IN" : "ICLOUD_SIGNED_OUT"))
                    .foregroundStyle(status.accountAvailable ? Color.secondary : Color.orange)
            }
            LabeledContent("LAST_SYNC", value: status.lastSync?.formatted(date: .abbreviated, time: .shortened) ?? "—")
            // 未登录时系统只会反复报告“没有账号”，上面一行已经说明。
            if status.accountAvailable, let issue = status.issue {
                StatusDetailRow(label: "SYNC_STATUS", title: "NEEDS_ATTENTION", message: "\(issue)", warning: true)
            }
        } header: {
            Text("ICLOUD_SYNC")
        } footer: {
            Text("ICLOUD_SYNC_INFO")
        }
    }
}

#Preview("中文 · 已同步") {
    Form {
        CloudSyncSection(status: CloudSyncStatus(accountAvailable: true, lastSync: Date()))
    }
    .environment(\.locale, Locale(identifier: "zh-Hans"))
    .tint(GymTheme.green)
}

#Preview("English · Signed out · Dark") {
    Form {
        CloudSyncSection(status: CloudSyncStatus())
    }
    .environment(\.locale, Locale(identifier: "en"))
    .preferredColorScheme(.dark)
    .tint(GymTheme.green)
}

#Preview("中文 · 同步出错") {
    Form {
        CloudSyncSection(status: CloudSyncStatus(accountAvailable: true, lastSync: Date().addingTimeInterval(-3600),
                                                 issue: URLError(.notConnectedToInternet).localizedDescription))
    }
    .environment(\.locale, Locale(identifier: "zh-Hans"))
    .tint(GymTheme.green)
}
