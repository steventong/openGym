import Foundation
import Observation
import WatchConnectivity
import UserNotifications
import WatchKit
import HealthKit

@MainActor @Observable final class WatchRemoteStore: NSObject, WCSessionDelegate, UNUserNotificationCenterDelegate {
    var healthReport: HealthWorkoutReport?
    var healthStatus = ""
    var authorizingHealth = false
    @ObservationIgnored private let healthRecorder = HealthWorkoutRecorder(name: "watch-recorder")
    @ObservationIgnored private let healthStore = HKHealthStore()
    var snapshot = WatchTrainingSnapshot(generatedAt: .distantPast)
    var currentHealthReport: HealthWorkoutReport? {
        guard let sessionID = snapshot.sessionID, healthReport?.id == "\(snapshot.account):\(sessionID)" else { return nil }
        return healthReport
    }
    var reachable = false
    private(set) var reconnecting = false
    var sending = false
    var coolingDown = false
    var error: String?
    var notificationStatus: UNAuthorizationStatus = .notDetermined
    private(set) var pending: WatchTrainingCommand?
    @ObservationIgnored private var reminderKey = ""
    @ObservationIgnored private var timeout: Task<Void, Never>?
    @ObservationIgnored private var reminderTask: Task<Void, Never>?
    @ObservationIgnored private var connectionTask: Task<Void, Never>?
    @ObservationIgnored private var connectionID: UUID?
    @ObservationIgnored private var preview = false

    override init() {
        super.init()
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-remote-preview") {
            preview = true
            snapshot = WatchTrainingSnapshot(sessionID: "preview", exercise: "杠铃卧推", exercisePosition: "动作 1 / 5",
                nextSet: WatchTrainingSet(entry: 0, index: 1, label: "第 2 / 4 组", weight: "40 kg", detail: "10 次"),
                restEnd: Date().addingTimeInterval(75), restEntry: 0, restExercise: "杠铃卧推", message: "预览")
            reachable = true
            notificationStatus = .authorized
            healthReport = HealthWorkoutReport(id: ":preview", state: .running, activeCalories: 128, totalCalories: 156, heartRate: 124)
            if ProcessInfo.processInfo.arguments.contains("-preview-training") { snapshot.restEnd = nil }
            if ProcessInfo.processInfo.arguments.contains("-preview-disconnected") { reachable = false }
            if ProcessInfo.processInfo.arguments.contains("-preview-long-text") {
                snapshot.exercise = "坐姿单臂哑铃肩上推举（交替训练）"
                snapshot.nextSet?.label = "第 12 / 12 组 · 右侧 · 热身"
                snapshot.nextSet?.detail = "12 次 · Rest-pause 3 小组"
            }
            return
        }
        #endif
        if let data = UserDefaults.standard.data(forKey: "remote.snapshot"), let cached = try? JSONDecoder().decode(WatchTrainingSnapshot.self, from: data) { snapshot = cached }
        if let data = UserDefaults.standard.data(forKey: "remote.pending") { pending = try? JSONDecoder().decode(WatchTrainingCommand.self, from: data) }
    }
    func start() {
        guard !preview else { return }
        healthRecorder.onReport = { [weak self] report in self?.publishHealth(report) }
        healthRecorder.accept([])
        UNUserNotificationCenter.current().delegate = self
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }
    func refresh() {
        guard !preview, connectionTask == nil else { return }
        Task {
            let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
            if status != notificationStatus { notificationStatus = status; reminderKey = ""; scheduleReminder() }
        }
        let session = WCSession.default
        if session.activationState == .notActivated { start() }
        if !session.isReachable { reachable = false }
        reconnecting = true
        let id = UUID(); connectionID = id
        connectionTask = Task { [weak self] in
            // Give activation/transient reachability a short automatic recovery window.
            // Only a fresh phone reply re-enables training; never replay a completion here.
            for _ in 0..<3 {
                guard !Task.isCancelled, self?.connectionID == id else { return }
                if session.activationState == .activated && session.isReachable {
                    session.sendMessage(["request": "snapshot"], replyHandler: { [weak self] message in
                        Task { @MainActor in
                            guard let self, self.connectionID == id, WatchTrainingSnapshot.decode(message) != nil else { return }
                            self.receive(message)
                            self.reachable = true
                            self.finishConnection()
                        }
                    }, errorHandler: { _ in })
                }
                try? await Task.sleep(for: .seconds(2))
            }
            guard !Task.isCancelled, let self, self.connectionID == id else { return }
            self.reachable = false
            self.finishConnection()
        }
    }
    private func finishConnection() {
        connectionTask?.cancel(); connectionTask = nil; connectionID = nil; reconnecting = false
    }
    func primaryAction(at date: Date = Date()) -> WatchTrainingAction {
        snapshot.primaryAction(reachable: reachable, reconnecting: reconnecting,
            hasPending: pending != nil, sending: sending, at: date)
    }
    func isDisabled(_ action: WatchTrainingAction) -> Bool {
        if action == .connect { return reconnecting }
        if !reachable || reconnecting { return true }
        switch action {
        case .sending, .finished: return true
        case .retry: return sending
        case .endRest: return coolingDown || snapshot.restEntry == nil
        case .complete: return coolingDown || snapshot.nextSet?.blockedReason != nil
        case .next: return coolingDown
        case .connect: return false
        }
    }
    func performPrimaryAction() {
        let action = primaryAction()
        guard !isDisabled(action) else { return }
        switch action {
        case .connect: refresh()
        case .retry: retry()
        case .endRest: endRest()
        case .complete: complete()
        case .next: nextExercise()
        case .sending, .finished: break
        }
    }
    func finishBackgroundDelivery() async {
        for _ in 0..<40 {
            if WCSession.default.activationState == .activated && !WCSession.default.hasContentPending { break }
            try? await Task.sleep(for: .milliseconds(250))
        }
        await reminderTask?.value
    }
    func complete() {
        guard pending == nil, !coolingDown, !snapshot.isResting(), let sessionID = snapshot.sessionID, let row = snapshot.nextSet, row.blockedReason == nil else { return }
        send(WatchTrainingCommand(account: snapshot.account, sessionID: sessionID, revision: snapshot.revision, action: "complete", entry: row.entry, index: row.index, side: row.side))
    }
    func endRest() {
        guard pending == nil, !coolingDown, snapshot.isResting(),
              let sessionID = snapshot.sessionID, let entry = snapshot.restEntry else { return }
        send(WatchTrainingCommand(account: snapshot.account, sessionID: sessionID, revision: snapshot.revision, action: "skipRest", entry: entry))
    }
    func nextExercise() {
        guard pending == nil, let sessionID = snapshot.sessionID, let entry = snapshot.nextEntry else { return }
        send(WatchTrainingCommand(account: snapshot.account, sessionID: sessionID, revision: snapshot.revision, action: "next", entry: entry))
    }
    func retry() { if let pending { send(pending) } }
    private func send(_ command: WatchTrainingCommand) {
        guard !preview, !sending, WCSession.default.activationState == .activated else { return }
        reachable = WCSession.default.isReachable
        guard reachable else { refresh(); return }
        pending = command
        UserDefaults.standard.set(try? JSONEncoder().encode(command), forKey: "remote.pending")
        sending = true; error = nil
        timeout?.cancel()
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(12))
            guard !Task.isCancelled, self?.pending?.id == command.id else { return }
            self?.sending = false; self?.error = "尚未收到手机确认，可重试确认。"
            self?.reachable = false; self?.refresh()
        }
        WCSession.default.sendMessage(command.payload, replyHandler: { [weak self] message in
            Task { @MainActor in self?.receive(message) }
        }, errorHandler: { [weak self] _ in
            Task { @MainActor in
                guard self?.pending?.id == command.id else { return }
                self?.sending = false; self?.error = "尚未收到手机确认，可重试确认。"
                self?.reachable = false; self?.refresh()
            }
        })
    }
    private func receive(_ message: [String: Any]) {
        let requests = HealthWorkoutWire.requests(from: message).filter { $0.owner == .watch }
        if !requests.isEmpty {
            healthRecorder.accept(requests)
            if requests.contains(where: { $0.phase == .running }),
               healthStore.authorizationStatus(for: HealthWorkoutAccess.workout) == .notDetermined,
               WKApplication.shared().applicationState == .active {
                authorizeWorkout()
            }
        }
        if let incoming = WatchTrainingSnapshot.decode(message), incoming.generatedAt >= snapshot.generatedAt {
            snapshot = incoming
            UserDefaults.standard.set(try? JSONEncoder().encode(incoming), forKey: "remote.snapshot")
            if let pending, incoming.acknowledged.contains(pending.id) { clearPending(); error = nil; acknowledge() }
            else if let pending, incoming.sessionID != pending.sessionID || incoming.account != pending.account {
                clearPending(); error = "训练已变更，已更新为手机上的记录。"
            }
            scheduleReminder()
        }
        if let id = message["commandID"] as? String, id == pending?.id {
            let accepted = message["accepted"] as? Bool == true
            clearPending()
            error = accepted ? nil : message["error"] as? String ?? "请核对手机上的训练。"
            if accepted { acknowledge() }
        }
    }
    func authorizeWorkout() {
        guard !authorizingHealth, HKHealthStore.isHealthDataAvailable() else { return }
        authorizingHealth = true
        Task {
            defer { authorizingHealth = false }
            do {
                try await HealthWorkoutAccess.authorize(healthStore)
                healthStatus = "已授权，等待手机训练同步"
                healthRecorder.accept([]); refresh()
            } catch { healthStatus = error.localizedDescription }
        }
    }
    func stopHealthWorkout() { healthRecorder.stopFromWatch() }
    private func publishHealth(_ report: HealthWorkoutReport) {
        // Receipts for a previous workout must not replace the current workout's live display.
        let expected = "\(snapshot.account):\(snapshot.sessionID ?? "")"
        if report.id == expected || healthReport == nil || healthReport?.id == report.id {
            healthReport = report
            switch report.state {
            case .running: healthStatus = "正在记录运动"
            case .saved: healthStatus = "运动已保存；训练组请在手机提交"
            case .discarded: healthStatus = "运动记录已取消"
            case .failed: healthStatus = report.message ?? "运动同步失败，请重试"
            }
        }
        guard WCSession.default.activationState == .activated else { return }
        let payload = HealthWorkoutWire.report(report)
        if WCSession.default.isReachable { WCSession.default.sendMessage(payload, replyHandler: nil, errorHandler: { _ in }) }
        if report.terminal || report.state == .failed {
            let queued = WCSession.default.outstandingUserInfoTransfers.contains {
                HealthWorkoutWire.report(from: $0.userInfo) == report
            }
            if !queued { WCSession.default.transferUserInfo(payload) }
        }
    }
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        Task { @MainActor [weak self] in self?.receive(userInfo) }
    }
    private func acknowledge() {
        WKInterfaceDevice.current().play(.success)
        coolingDown = true
        Task { try? await Task.sleep(for: .milliseconds(750)); coolingDown = false }
    }
    private func clearPending() {
        pending = nil; sending = false; timeout?.cancel()
        UserDefaults.standard.removeObject(forKey: "remote.pending")
    }
    func enableReminder() {
        Task {
            do { _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) }
            catch { self.error = "无法开启提醒，请稍后重试。" }
            notificationStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
            reminderKey = ""; scheduleReminder()
        }
    }
    private func scheduleReminder() {
        let key = "\(snapshot.sessionID ?? "")|\(snapshot.restEnd?.timeIntervalSince1970 ?? 0)"
        guard key != reminderKey else { return }
        reminderKey = key
        let previous = reminderTask, current = snapshot
        previous?.cancel()
        reminderTask = Task {
            // Finish an in-flight add before replacing it, so an old rest cannot win a race.
            await previous?.value
            guard !Task.isCancelled else { return }
            let center = UNUserNotificationCenter.current()
            center.removePendingNotificationRequests(withIdentifiers: ["opengym.rest"])
            center.removeDeliveredNotifications(withIdentifiers: ["opengym.rest"])
            guard let end = current.restEnd, end.timeIntervalSinceNow > 0, current.sessionID != nil else { return }
            let content = UNMutableNotificationContent()
            content.title = "休息结束"
            content.body = current.restExercise.isEmpty ? "准备开始下一组" : "\(current.restExercise) · 准备开始下一组"
            content.sound = .default
            let request = UNNotificationRequest(identifier: "opengym.rest", content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, end.timeIntervalSinceNow), repeats: false))
            do { try await center.add(request) }
            catch { self.error = "休息提醒未能设置，请留意倒计时。" }
        }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        Task { @MainActor in
            WKInterfaceDevice.current().play(.notification)
            completionHandler([.banner])
        }
    }
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor [weak self] in self?.receive(session.receivedApplicationContext); self?.refresh() }
    }
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) { Task { @MainActor [weak self] in self?.refresh() } }
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) { Task { @MainActor [weak self] in self?.receive(applicationContext) } }
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) { Task { @MainActor [weak self] in self?.receive(message) } }
}
