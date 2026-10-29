import SwiftUI
import WatchKit

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
    private let green = Color(red: 0.38, green: 0.86, blue: 0.34)
    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                if store.snapshot.sessionID == nil {
                    Image(systemName: "iphone.and.arrow.forward").font(.largeTitle).foregroundStyle(green)
                    Text("在 iPhone 开始训练").font(.headline).multilineTextAlignment(.center)
                    Text("这里会显示当前动作和训练组").font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
                } else {
                    Text(store.snapshot.exercise).font(.headline).multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.85)
                    if let row = store.snapshot.nextSet {
                        Text(row.label).font(.caption).foregroundStyle(green)
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(row.weight).font(.system(.title3, design: .rounded).bold()).minimumScaleFactor(0.7).lineLimit(1)
                            Text(row.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2).minimumScaleFactor(0.8)
                        }.frame(maxWidth: .infinity)
                        if let reason = row.blockedReason { Text(reason).font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center) }
                    } else { Text(store.snapshot.message).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center) }
                    if let end = store.snapshot.restEnd {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            let remaining = max(0, Int(ceil(end.timeIntervalSince(context.date))))
                            HStack {
                                Image(systemName: "timer")
                                Text(remaining > 0 ? "休息" : "休息结束")
                                Spacer(minLength: 2)
                                Text(String(format: "%02d:%02d", remaining / 60, remaining % 60)).monospacedDigit()
                            }.font(.subheadline).foregroundStyle(green)
                        }.padding(6).background(green.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                    }
                    if store.pending != nil {
                        Button(store.sending ? "正在确认…" : "重试确认") { store.retry() }.disabled(store.sending || !store.reachable)
                    } else if let row = store.snapshot.nextSet {
                        Button { store.complete() } label: { Label("完成本组", systemImage: "checkmark").font(.body.bold()).frame(maxWidth: .infinity) }
                            .tint(green).buttonStyle(.borderedProminent).controlSize(.small).disabled(!store.reachable || store.coolingDown || row.blockedReason != nil)
                            .accessibilityIdentifier("watch-complete")
                    } else if store.snapshot.nextEntry != nil {
                        Button("下一个动作") { store.nextExercise() }.tint(green).disabled(!store.reachable)
                    }
                }
                if let error = store.error { Text(error).font(.caption2).foregroundStyle(.orange).multilineTextAlignment(.center) }
                if !store.reachable {
                    Button("连接 iPhone") { store.refresh() }.font(.caption)
                    if store.snapshot.sessionID != nil { Text("当前为上次同步的数据").font(.caption2).foregroundStyle(.secondary) }
                }
                if store.notificationStatus == .notDetermined { Button("开启休息提醒") { store.enableReminder() }.font(.caption2) }
            }.padding(.horizontal, 4)
        }.navigationTitle("openGym").task { store.refresh() }
    }
}
