import SwiftUI
import WatchKit
import HealthKit

@main struct OpenGymWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchRemoteDelegate.self) private var delegate
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            WatchRemoteView(store: delegate.store)
                .onChange(of: scenePhase) { _, phase in if phase == .active { delegate.store.refresh() } }
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
    @State private var showDetails = false
    @State private var confirmHealthEnd = false
    private let green = Color(red: 0.38, green: 0.86, blue: 0.34)

    var body: some View {
        Group {
            if store.snapshot.sessionID == nil {
                VStack(spacing: 8) {
                    Image(systemName: "iphone.and.arrow.forward").font(.largeTitle).foregroundStyle(green)
                    Text("在 iPhone 开始训练").font(.headline).multilineTextAlignment(.center)
                    Button("连接 iPhone") { store.refresh() }.font(.caption).disabled(store.reconnecting)
                }
            } else {
                GeometryReader { geometry in
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        dashboard(at: context.date, scale: min(1, geometry.size.height / 190))
                    }
                }
            }
        }
        .task { store.refresh() }
        .sheet(isPresented: $showDetails) { details }
    }

    private func dashboard(at date: Date, scale: CGFloat) -> some View {
        let resting = store.snapshot.isResting(at: date)
        return VStack(spacing: 4 * scale) {
            HStack(spacing: 3) {
                Text(store.snapshot.exercise).font(.system(size: 15 * scale, weight: .semibold))
                    .lineLimit(1, reservesSpace: true).minimumScaleFactor(0.75)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button { showDetails = true } label: {
                    Image(systemName: "ellipsis.circle").font(.system(size: 18 * scale))
                        .frame(width: 28 * scale, height: 28 * scale)
                }.buttonStyle(.plain).accessibilityLabel("训练详情与设置")
            }.frame(height: 28 * scale)
            setSummary(scale: scale).frame(height: 40 * scale)
            metrics(scale: scale).frame(height: 48 * scale)
            HStack(spacing: 4) {
                Image(systemName: "timer")
                Text("休息")
                Spacer(minLength: 2)
                // Keep this row, including its height, even when no rest is active.
                Text(resting ? remainingRest(at: date) : "00:00").monospacedDigit()
            }.font(.system(size: 12 * scale, weight: .medium)).foregroundStyle(green)
                .lineLimit(1, reservesSpace: true).minimumScaleFactor(0.8)
                .frame(height: 18 * scale).opacity(resting ? 1 : 0)
                .accessibilityHidden(!resting)
            trainingButton(at: date, scale: scale).frame(height: 40 * scale)
        }
        .padding(.horizontal, 5)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transaction { transaction in
            transaction.animation = nil
            transaction.disablesAnimations = true
        }
    }

    private func remainingRest(at date: Date) -> String {
        let remaining = max(0, Int(ceil(store.snapshot.restEnd?.timeIntervalSince(date) ?? 0)))
        return String(format: "%02d:%02d", remaining / 60, remaining % 60)
    }

    private func setSummary(scale: CGFloat) -> some View {
        VStack(spacing: 0) {
            Text(store.snapshot.nextSet?.label ?? "全部组已完成")
                .font(.system(size: 12 * scale, weight: .medium)).foregroundStyle(green)
                .lineLimit(1, reservesSpace: true).minimumScaleFactor(0.75).frame(height: 16 * scale)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(store.snapshot.nextSet?.weight ?? "请在 iPhone 保存")
                    .font(.system(size: 20 * scale, weight: .bold, design: .rounded))
                Text(store.snapshot.nextSet?.detail ?? "")
                    .font(.system(size: 12 * scale)).foregroundStyle(.secondary)
            }.lineLimit(1).minimumScaleFactor(0.7).frame(height: 24 * scale)
        }
    }

    private func metrics(scale: CGFloat) -> some View {
        let report = store.currentHealthReport
        return HStack(spacing: 2) {
            metric("心率", value: report?.state == .running ? report?.heartRate : nil, unit: "次/分", color: .red, scale: scale)
            metric("活动热量", value: report?.activeCalories, unit: "kcal", color: .orange, scale: scale)
            metric("总热量", value: report?.totalCalories, unit: "kcal", color: .orange, scale: scale)
        }.frame(height: 48 * scale)
            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
    }

    private func metric(_ title: String, value: Double?, unit: String, color: Color, scale: CGFloat) -> some View {
        VStack(spacing: 0) {
            Text(title).font(.system(size: 10 * scale)).foregroundStyle(.secondary).frame(height: 12 * scale)
            Text(value.map { String(format: "%.0f", $0) } ?? "—")
                .font(.system(size: 19 * scale, weight: .semibold, design: .rounded)).foregroundStyle(color)
                .monospacedDigit().frame(height: 23 * scale)
            Text(unit).font(.system(size: 9 * scale)).foregroundStyle(.secondary).frame(height: 11 * scale)
        }.lineLimit(1, reservesSpace: true).minimumScaleFactor(0.7).frame(maxWidth: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(title)，\(value.map { String(format: "%.0f", $0) + unit } ?? "暂无数据")")
    }

    private func trainingButton(at date: Date, scale: CGFloat) -> some View {
        let action = store.primaryAction(at: date)
        let disabled = store.isDisabled(action)
        // One stable Button identity for connection, rest, completion and pending replies.
        return Button { store.performPrimaryAction() } label: {
            Label(action.title, systemImage: action.symbol).font(.system(size: 15 * scale, weight: .bold))
                .lineLimit(1, reservesSpace: true).minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity).frame(height: 40 * scale)
                .foregroundStyle(disabled ? Color.secondary : .black)
                .background(disabled ? Color.gray.opacity(0.25) : green, in: RoundedRectangle(cornerRadius: 14))
        }.buttonStyle(.plain).disabled(disabled).accessibilityIdentifier("watch-primary-action")
    }

    private var details: some View {
        ScrollView {
            VStack(spacing: 10) {
                Text("训练详情").font(.headline)
                if !store.snapshot.exercise.isEmpty { Text(store.snapshot.exercise).font(.caption) }
                if let reason = store.snapshot.nextSet?.blockedReason { Text(reason).foregroundStyle(.orange) }
                if let error = store.error { Text(error).foregroundStyle(.orange) }
                if !store.reachable {
                    Text("当前为上次同步的数据，请靠近 iPhone 并打开 openGym。")
                }
                Text(store.healthStatus.isEmpty ? "开启 iPhone 的 Apple 健身训练同步并授权，即可显示心率和热量。" : store.healthStatus)
                Text("总热量包含活动与静息消耗；无可用数据时显示 —。")
                Button("授权并刷新健康数据") { store.authorizeWorkout() }.disabled(store.authorizingHealth)
                if store.currentHealthReport?.state == .running {
                    Button("结束运动记录", role: .destructive) { confirmHealthEnd = true }
                }
                if store.notificationStatus == .notDetermined { Button("开启休息提醒") { store.enableReminder() } }
                Button("返回训练") { showDetails = false }
            }.font(.caption2).multilineTextAlignment(.center).padding(.horizontal, 4)
        }
        .confirmationDialog("结束运动记录？", isPresented: $confirmHealthEnd, titleVisibility: .visible) {
            Button("结束并保存运动") { store.stopHealthWorkout() }
        } message: { Text("停止心率与卡路里采集并保存到健康。训练组仍保留在手机，请在手机提交。") }
    }
}
