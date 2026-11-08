import SwiftUI

/// 同一个按钮呈现手动同步的全过程，预览通过动作闭包注入结果，不连接真实服务器。
struct SettingsSyncControls: View {
    var isBusy = false
    let onSync: @MainActor () async -> Result<Void, Error>
    let onPairAgain: () -> Void
    @State private var feedback: Feedback

    enum Feedback: Equatable {
        case idle, syncing, succeeded, failed(String)
        var isSyncing: Bool { self == .syncing }
        var title: LocalizedStringKey {
            switch self {
            case .idle: "SYNC_NOW"
            case .syncing: "SYNCING"
            case .succeeded: "SYNC_SUCCEEDED"
            case .failed: "SYNC_FAILED"
            }
        }
        var symbol: String? {
            switch self {
            case .succeeded: "checkmark.circle.fill"
            case .failed: "exclamationmark.circle.fill"
            default: nil
            }
        }
        var tint: Color {
            if case .failed = self { return .red }
            return GymTheme.green
        }
        var failureMessage: String {
            if case let .failed(message) = self { return message }
            return ""
        }
    }

    init(isBusy: Bool = false, initialFeedback: Feedback = .idle,
         onSync: @escaping @MainActor () async -> Result<Void, Error>, onPairAgain: @escaping () -> Void) {
        self.isBusy = isBusy
        self.onSync = onSync
        self.onPairAgain = onPairAgain
        _feedback = State(initialValue: initialFeedback)
    }

    var body: some View {
        HStack {
            Button {
                guard !isBusy, !feedback.isSyncing else { return }
                feedback = .syncing
                Task {
                    switch await onSync() {
                    case .success: feedback = .succeeded
                    case let .failure(error): feedback = .failed(error.localizedDescription)
                    }
                }
            } label: {
                HStack {
                    if feedback.isSyncing { ProgressView().controlSize(.small) }
                    else if let symbol = feedback.symbol { Image(systemName: symbol) }
                    Text(feedback.title)
                }
            }
            .foregroundStyle(feedback.tint)
            .accessibilityIdentifier("sync-now")
            .accessibilityHint(Text(verbatim: feedback.failureMessage))
            Spacer()
            Button("PAIR_AGAIN", action: onPairAgain).accessibilityIdentifier("pair-again")
        }
        .buttonStyle(.borderless)
        .disabled(isBusy || feedback.isSyncing)
        .task(id: feedback) {
            guard feedback == .succeeded else { return }
            // 状态变化或视图离开时会取消计时，旧的成功提示不能覆盖下一次同步。
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, feedback == .succeeded else { return }
            feedback = .idle
        }
    }
}

#Preview("中文 · 点击同步") {
    Form {
        Section {
            SettingsSyncControls(onSync: {
                try? await Task.sleep(for: .seconds(1))
                return .success(())
            }, onPairAgain: {})
        }
    }
    .environment(\.locale, Locale(identifier: "zh-Hans"))
    .tint(GymTheme.green)
}

#Preview("English · Syncing") {
    Form {
        Section {
            SettingsSyncControls(initialFeedback: .syncing, onSync: { .success(()) }, onPairAgain: {})
        }
    }
    .environment(\.locale, Locale(identifier: "en"))
    .tint(GymTheme.green)
}

#Preview("中文 · 成功后 3 秒恢复") {
    Form {
        Section {
            SettingsSyncControls(initialFeedback: .succeeded, onSync: {
                try? await Task.sleep(for: .seconds(1))
                return .success(())
            }, onPairAgain: {})
        }
    }
    .environment(\.locale, Locale(identifier: "zh-Hans"))
    .tint(GymTheme.green)
}

#Preview("English · Failure and retry · Dark") {
    Form {
        Section {
            SettingsSyncControls(initialFeedback: .failed(URLError(.notConnectedToInternet).localizedDescription), onSync: {
                try? await Task.sleep(for: .seconds(1))
                return .success(())
            }, onPairAgain: {})
        }
    }
    .environment(\.locale, Locale(identifier: "en"))
    .environment(\.dynamicTypeSize, .xxxLarge)
    .preferredColorScheme(.dark)
    .tint(GymTheme.green)
}
