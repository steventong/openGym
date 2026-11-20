import SwiftUI

/// 保存训练后弹出的 Apple 健康写入进度：从健康同步读取实时状态，并接上重试与关闭。
struct WorkoutHealthReceiptSheet: View {
    @Environment(GymStore.self) private var store

    var body: some View {
        if let receipt = store.workoutHealth.receipt {
            WorkoutHealthReceiptView(receipt: receipt,
                retry: { store.workoutHealth.retry(wakeWatch: true) },
                close: { store.workoutHealth.dismissReceipt() })
        }
    }
}

/// 按写入进度展示等待、已同步或未完成；未同步时可以重试，关闭不影响后台继续同步。
struct WorkoutHealthReceiptView: View {
    let receipt: WorkoutHealthReceipt
    let retry: () -> Void
    let close: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 0)
            VStack(spacing: 12) {
                switch receipt {
                case .waiting:
                    ProgressView()
                        .controlSize(.large)
                        .frame(height: 48)
                    Text("SAVING_WORKOUT_TO_APPLE_HEALTH")
                        .font(.headline)
                    Text("APPLE_WATCH_SAVES_THIS_WORKOUT_KEEP_OPENGYM_OPEN_ON_YOUR_WATCH")
                        .font(.subheadline)
                        .foregroundStyle(GymTheme.muted)
                case .saved(let activeCalories, let message):
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(GymTheme.green)
                    Text("WORKOUT_SYNCED_TO_APPLE_HEALTH_AND_FITNESS")
                        .font(.headline)
                    if let activeCalories {
                        Label(String(format: String(localized: "COUNT_ACTIVE_KCAL", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(format: "%.0f", activeCalories)), systemImage: "flame.fill")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.orange)
                    }
                    if let message {
                        Text(message)
                            .font(.subheadline)
                            .foregroundStyle(GymTheme.muted)
                    }
                case .failed(let message):
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.orange)
                    Text("WORKOUT_SYNC_INCOMPLETE_YOU_CAN_RETRY")
                        .font(.headline)
                    if let message {
                        Text(message)
                            .font(.subheadline)
                            .foregroundStyle(GymTheme.muted)
                    }
                }
            }
            .multilineTextAlignment(.center)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("workout-health-receipt")
            Spacer(minLength: 0)
            VStack(spacing: 10) {
                if case .saved = receipt {
                    GreenButton(title: "DONE", action: close)
                        .accessibilityIdentifier("workout-health-receipt-done")
                } else {
                    Button(action: retry) {
                        Label("RETRY_WORKOUT_SYNC", systemImage: "arrow.clockwise")
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(GymTheme.card, in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("workout-health-receipt-retry")
                    GreenButton(title: "CLOSE", action: close)
                        .accessibilityIdentifier("workout-health-receipt-close")
                }
            }
        }
        .padding(20)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}

#Preview("等待手表") {
    WorkoutHealthReceiptView(receipt: .waiting, retry: {}, close: {})
        .environment(\.locale, AppLanguage.locale(for: "zh"))
        .preferredColorScheme(.dark)
}

#Preview("已同步") {
    WorkoutHealthReceiptView(receipt: .saved(activeCalories: 286, message: nil), retry: {}, close: {})
        .environment(\.locale, AppLanguage.locale(for: "zh"))
        .preferredColorScheme(.dark)
}

#Preview("未完成") {
    WorkoutHealthReceiptView(receipt: .failed(message: "请在 Apple 健康中允许 openGym 写入体能训练"), retry: {}, close: {})
        .environment(\.locale, AppLanguage.locale(for: "zh"))
        .preferredColorScheme(.dark)
}
