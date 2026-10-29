import Foundation
import WatchConnectivity

@MainActor final class PhoneWatchBridge: NSObject, WCSessionDelegate {
    private weak var store: GymStore?
    private var publication: Task<Void, Never>?
    init(store: GymStore) {
        self.store = store
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }
    func publish() {
        publication?.cancel()
        publication = Task { [weak self] in
            // Coalesce the row edit, rest calculation and command receipt into one snapshot.
            await Task.yield()
            guard !Task.isCancelled else { return }
            self?.publishNow()
        }
    }
    private func publishNow() {
        guard let store, WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
        let payload = store.watchSnapshot().payload
        do { try session.updateApplicationContext(payload) }
        catch { return } // The next mutation or activation retries the latest snapshot.
        if session.isReachable { session.sendMessage(payload, replyHandler: nil, errorHandler: { _ in }) }
    }
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor [weak self] in self?.publish() }
    }
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) { Task { @MainActor [weak self] in self?.publish() } }
    nonisolated func sessionWatchStateDidChange(_ session: WCSession) { Task { @MainActor [weak self] in self?.publish() } }
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        Task { @MainActor [weak self] in
            guard let store = self?.store else { replyHandler(["error": "请打开 iPhone 上的 openGym"]); return }
            if let command = WatchTrainingCommand.decode(message) { replyHandler(store.performWatchCommand(command)) }
            else if message["request"] as? String == "snapshot" {
                store.settleTimer()
                replyHandler(store.watchSnapshot().payload)
            } else { replyHandler(["error": "请更新手机和手表上的 openGym"]); return }
            self?.publish()
        }
    }
}
