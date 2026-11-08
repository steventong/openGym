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
        var payload = store.watchSnapshot().payload
        payload.merge(HealthWorkoutWire.requests(store.workoutHealth.watchRequests)) { _, new in new }
        do { try session.updateApplicationContext(payload) }
        catch { return } // The next mutation or activation retries the latest snapshot.
        if session.isReachable { session.sendMessage(payload, replyHandler: nil, errorHandler: { _ in }) }
    }
    func sendHealthRequests() {
        guard let store, WCSession.isSupported(), WCSession.default.activationState == .activated,
              WCSession.default.isPaired, WCSession.default.isWatchAppInstalled else { return }
        let session = WCSession.default
        // Durable delivery survives disconnects and a later training replacing applicationContext.
        for request in store.workoutHealth.watchRequests where request.phase != .running {
            let queued = session.outstandingUserInfoTransfers.contains {
                HealthWorkoutWire.requests(from: $0.userInfo).contains(request)
            }
            if !queued { session.transferUserInfo(HealthWorkoutWire.requests([request])) }
        }
    }
    private func connectionChanged() {
        // Remote controls must still refresh if a HealthKit retry is already in flight.
        publish()
        sendHealthRequests()
        store?.workoutHealth.retry(wakeWatch: true)
    }
    private func receiveHealth(_ message: [String: Any]) {
        if let report = HealthWorkoutWire.report(from: message) { store?.workoutHealth.receive(report, owner: .watch) }
    }
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        Task { @MainActor [weak self] in self?.receiveHealth(userInfo) }
    }
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor [weak self] in self?.receiveHealth(message) }
    }
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor [weak self] in self?.connectionChanged() }
    }
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) { Task { @MainActor [weak self] in self?.connectionChanged() } }
    nonisolated func sessionWatchStateDidChange(_ session: WCSession) { Task { @MainActor [weak self] in self?.connectionChanged() } }
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        Task { @MainActor [weak self] in
            guard let store = self?.store else { replyHandler(["error": String(localized: "OPEN_OPENGYM_ON_IPHONE", bundle: AppLanguage.bundle, locale: AppLanguage.locale)]); return }
            if let command = WatchTrainingCommand.decode(message) {
                let response = store.performWatchCommand(command)
                await store.restNotifications?.flush()
                replyHandler(response)
            }
            else if message["request"] as? String == "snapshot" {
                store.settleTimer()
                var payload = store.watchSnapshot().payload
                payload.merge(HealthWorkoutWire.requests(store.workoutHealth.watchRequests)) { _, new in new }
                replyHandler(payload)
            } else { replyHandler(["error": String(localized: "UPDATE_OPENGYM_ON_YOUR_PHONE_AND_WATCH", bundle: AppLanguage.bundle, locale: AppLanguage.locale)]); return }
            self?.publish()
        }
    }
}
