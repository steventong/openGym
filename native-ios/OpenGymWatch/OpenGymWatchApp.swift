import SwiftUI
import WatchKit
import HealthKit

@main struct OpenGymWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchRemoteDelegate.self) private var delegate
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            WatchRemoteView(store: delegate.store)
                .onChange(of: scenePhase, initial: true) { _, phase in
                    delegate.store.setForegroundActive(phase == .active)
                }
        }
    }
}
@MainActor final class WatchRemoteDelegate: NSObject, WKApplicationDelegate {
    let store = WatchRemoteStore()
    func applicationDidFinishLaunching() { store.start() }
    func handle(_ workoutConfiguration: HKWorkoutConfiguration) { store.start(); store.authorizeWorkout(); store.refresh() }
    func handleActiveWorkoutRecovery() { store.start(); store.refresh() }
    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        for task in backgroundTasks {
            if task is WKWatchConnectivityRefreshBackgroundTask {
                store.start()
                Task {
                    // Give WatchConnectivity its background delivery window, then release the task.
                    await store.finishBackgroundDelivery()
                    task.setTaskCompletedWithSnapshot(false)
                }
            } else { task.setTaskCompletedWithSnapshot(false) }
        }
    }
}
struct WatchRemoteView: View {
    let store: WatchRemoteStore
    private let green = Color(red: 0.47, green: 0.89, blue: 0.42)

    var body: some View {
        Group {
            if store.snapshot.sessionID == nil {
                VStack(spacing: 8) {
                    Image(systemName: "iphone.and.arrow.forward").font(.largeTitle).foregroundStyle(green)
                    Text(L10n.text("START_A_WORKOUT_ON_IPHONE" /* 在 iPhone 开始训练 */)).font(.headline).multilineTextAlignment(.center)
                    Button(L10n.text("CONNECT_IPHONE" /* 连接 iPhone */)) { store.refresh() }.font(.caption).disabled(store.reconnecting)
                }
            } else {
                GeometryReader { geometry in
                    dashboard(scale: min(1, geometry.size.height / 191, geometry.size.width / 184))
                }
            }
        }
        .task { store.refresh() }
    }

    private func dashboard(scale: CGFloat) -> some View {
        return VStack(spacing: 4 * scale) {
            Text(store.snapshot.exercise).font(.system(size: 15 * scale, weight: .semibold))
                .lineLimit(1, reservesSpace: true).minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 22 * scale)
            setSummary(scale: scale).frame(height: 52 * scale)
            metrics(scale: scale).frame(height: 43 * scale)
            WatchPrimaryActionButton(store: store, scale: scale, tint: green)
                .frame(height: 62 * scale)
        }
        .padding(.horizontal, 5)
        .frame(maxWidth: .infinity, maxHeight: .infinity)

    }

    private func setSummary(scale: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 4 * scale) {
            HStack(alignment: .firstTextBaseline, spacing: 4 * scale) {
                Text(store.snapshot.nextSet?.label ?? L10n.text("ALL_SETS_COMPLETE" /* 全部组已完成 */))
                    .font(.system(size: 10 * scale, weight: .medium)).foregroundStyle(green)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(store.snapshot.exercisePosition)
                    .font(.system(size: 9 * scale)).foregroundStyle(.secondary)
            }.lineLimit(1).minimumScaleFactor(0.65)
            HStack(alignment: .firstTextBaseline, spacing: 5 * scale) {
                Text(store.snapshot.nextSet?.weight ?? L10n.text("SAVE_ON_IPHONE" /* 请在 iPhone 保存 */))
                    .font(.system(size: 23 * scale, weight: .semibold, design: .rounded))
                Text(store.snapshot.nextSet?.detail ?? "")
                    .font(.system(size: 11 * scale)).foregroundStyle(.secondary)
            }.lineLimit(1).minimumScaleFactor(0.65)
        }
        .padding(.horizontal, 9 * scale)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 12 * scale))
    }

    private func metrics(scale: CGFloat) -> some View {
        let report = store.currentHealthReport
        return HStack(spacing: 2) {
            metric(L10n.text("HEART_RATE" /* 心率 */), value: report?.state == .running ? report?.heartRate : nil, unit: L10n.text("BPM" /* 次/分 */), color: .red, scale: scale)
            metric(L10n.text("ACTIVE_CALORIES" /* 活动热量 */), value: report?.activeCalories, unit: "kcal", color: .orange, scale: scale)
            metric(L10n.text("TOTAL_CALORIES" /* 总热量 */), value: report?.totalCalories, unit: "kcal", color: .orange, scale: scale)
        }.frame(height: 43 * scale)
    }

    private func metric(_ title: String, value: Double?, unit: String, color: Color, scale: CGFloat) -> some View {
        VStack(spacing: 0) {
            Text(title).font(.system(size: 9 * scale)).foregroundStyle(.secondary).frame(height: 11 * scale)
            Text(value.map { String(format: "%.0f", $0) } ?? "—")
                .font(.system(size: 18 * scale, weight: .semibold, design: .rounded)).foregroundStyle(color)
                .monospacedDigit().frame(height: 21 * scale)
            Text(unit).font(.system(size: 8 * scale)).foregroundStyle(.secondary).frame(height: 10 * scale)
        }.lineLimit(1, reservesSpace: true).minimumScaleFactor(0.7).frame(maxWidth: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(title)，\(value.map { String(format: "%.0f", $0) + unit } ?? L10n.text("NO_DATA_YET" /* 暂无数据 */))")
    }
}

private struct WatchPrimaryActionButton: View {
    let store: WatchRemoteStore
    let scale: CGFloat
    let tint: Color

    var body: some View {
        let action = store.primaryAction()
        TrainingActionControl(title: action.title, symbol: action.symbol, timing: store.snapshot.actionTiming,
            disabled: store.isDisabled(action, includeProtection: false), tint: tint,
            scale: scale,
            readyHint: action == .complete ? L10n.text("READY_FOR_YOUR_NEXT_SET" /* 准备好后开始下一组 */) : nil) { label in
                Button { store.performPrimaryAction() } label: { label }
            }.accessibilityIdentifier("watch-primary-action")
    }
}
