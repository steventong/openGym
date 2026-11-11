import SwiftUI

struct WatchRootView: View {
    let store: WatchRemoteStore

    @Environment(\.scenePhase) private var scenePhase
    @State private var trainingViewModel: TrainingViewModel

    init(store: WatchRemoteStore) {
        self.store = store
        _trainingViewModel = State(initialValue: TrainingViewModel(source: WatchTrainingContentSource(store: store)))
    }

    var body: some View {
        Group {
            // snapshot 是手机通过 WatchConnectivity 同步给手表的训练状态快照；
            // 它代表最近收到的状态，断线时不一定是手机当前的最新状态。
            // sessionID 标识一次训练（不是登录会话）；完成后用独立结束页替换训练仪表盘。
            // 训练中与休息中属于同一次训练，sessionID 相同，由 restEnd 等字段区分状态。
            if store.snapshot.sessionID == nil {
                WatchWaitingView()
            } else if store.snapshot.isFinished {
                WatchWorkoutFinishedView()
            } else {
                WatchTrainingView(viewModel: trainingViewModel, healthReport: store.currentHealthReport,
                    onPrimaryAction: store.performPrimaryAction)
            }
        }
        .task { store.refresh() }
        .task(id: scenePhase == .active && (store.snapshot.sessionID == nil || !store.reachable)) {
            // Connection recovery is automatic on both waiting and training screens.
            guard scenePhase == .active, store.snapshot.sessionID == nil || !store.reachable else { return }
            while !Task.isCancelled {
                store.refresh()
                do { try await Task.sleep(for: .seconds(8)) }
                catch { return }
            }
        }
    }
}
