import Foundation
import WatchConnectivity
import WatchKit
import HealthKit

// 手机是训练状态的唯一来源：手表发送操作，手机执行后返回最新快照。
// 本文件只处理连接、收发和结果协调，不在手表上另算一份训练进度。
extension WatchRemoteStore {
    // MARK: - 连接与生命周期

    /// 接管手机通信，并把健康采集、休息提醒的结果接回 Store。
    /// 初始化只恢复本地数据；由应用生命周期显式调用 start() 才开始通信。
    func start() {
        guard !isPreview else { return }
        restReminder.onError = { [weak self] message in self?.error = message }
        restReminder.start()
        restMotion.onResume = { [weak self] command in
            guard let self, case .idle = commandState,
                  command.account == snapshot.account, command.sessionID == snapshot.sessionID,
                  command.revision == snapshot.revision, snapshot.restEnd != nil else { return }
            send(command)
        }
        healthRecorder.onSessionStateChange = { [weak self] in self?.updateCompanionServices() }
        healthRecorder.onReport = { [weak self] report in self?.publishHealth(report) }
        healthRecorder.accept([])
        updateCompanionServices()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// 向手机索取最新快照。同一时间只保留一轮刷新，不自动重发训练命令。
    func refresh() {
        guard !isPreview else { return }
        let session = WCSession.default
        if session.activationState == .notActivated { start() }
        // 刷新未结束时也接收连接变化，通信恢复即可操作，不必等待快照回复。
        updateReachability()
        guard connectionTask == nil else { return }
        restReminder.refreshAuthorization()

        // 快照同步独立于按钮可用性，手机仍会校验命令对应的训练和版本。
        let id = UUID()
        connectionID = id
        connectionTask = Task { [weak self] in
            // 给系统激活和短暂断线留出恢复窗口：最多三次，每次间隔两秒。
            // connectionID 防止旧刷新回调结束新一轮刷新。
            for _ in 0..<3 {
                guard !Task.isCancelled, self?.connectionID == id else { return }
                self?.updateReachability()
                if session.activationState == .activated && session.isReachable {
                    session.sendMessage(["request": "snapshot"], replyHandler: { [weak self] message in
                        Task { @MainActor in
                            guard let self, self.connectionID == id, WatchTrainingSnapshot.decode(message) != nil else { return }
                            self.receive(message)
                            self.updateReachability()
                            self.finishConnection()
                        }
                    }, errorHandler: { _ in })
                }
                try? await Task.sleep(for: .seconds(2))
            }
            guard !Task.isCancelled, let self, self.connectionID == id else { return }
            self.updateReachability()
            self.finishConnection()
        }
    }

    /// 只以系统通信状态判断可达性，刷新超时或旧回复不覆盖当前连接状态。
    private func updateReachability() {
        let session = WCSession.default
        reachable = session.activationState == .activated && session.isReachable
        updateCompanionServices()
    }

    private func finishConnection() {
        connectionTask?.cancel()
        connectionTask = nil
        connectionID = nil
    }

    /// 抬腕进入前台时刷新手机状态；具体震动和通知调度交给提醒对象。
    func setForegroundActive(_ active: Bool) {
        guard !isPreview else { return }
        foregroundActive = active
        restReminder.setForegroundActive(active)
        updateCompanionServices()
        if active { refresh() }
    }

    /// 系统后台交付结束前，给通信最多十秒处理消息，并等待本地通知写入完成。
    func finishBackgroundDelivery() async {
        guard !isPreview else { return }
        for _ in 0..<40 {
            if WCSession.default.activationState == .activated && !WCSession.default.hasContentPending { break }
            try? await Task.sleep(for: .milliseconds(250))
        }
        await restReminder.flush()
    }

    // MARK: - 界面操作

    /// 根据手机快照和命令确认状态决定按钮含义，不在本地推进训练。
    func primaryAction() -> WatchTrainingAction {
        snapshot.primaryAction(commandState: commandState)
    }

    /// 视图可自行计算按钮保护期；真正执行前仍会完整检查一次。
    func isDisabled(_ action: WatchTrainingAction, includeProtection: Bool = true) -> Bool {
        if !reachable { return true }
        if includeProtection && snapshot.actionTiming.isProtected(at: Date()) { return true }
        switch action {
        case .sending, .finished: return true
        case .retry: return commandState.isSending
        case .endRest: return snapshot.restEntry == nil
        case .complete: return snapshot.nextSet?.blockedReason != nil
        case .next: return false
        }
    }

    /// 将按钮点击转成手机命令。预览只展示注入的数据，不模拟真实操作。
    func performPrimaryAction() {
        guard !isPreview else { return }
        let action = primaryAction()
        guard !isDisabled(action) else { return }
        switch action {
        case .retry: if let command = commandState.command { send(command) }
        case .endRest: endRest()
        case .complete: complete()
        case .next: nextExercise()
        case .sending, .finished: break
        }
    }

    private func complete() {
        guard case .idle = commandState, !snapshot.actionTiming.isProtected(at: Date()), snapshot.restEnd == nil,
              let sessionID = snapshot.sessionID, let row = snapshot.nextSet, row.blockedReason == nil else { return }
        send(WatchTrainingCommand(account: snapshot.account, sessionID: sessionID, revision: snapshot.revision,
            action: "complete", entry: row.entry, index: row.index, side: row.side))
    }

    private func endRest() {
        guard case .idle = commandState, !snapshot.actionTiming.isProtected(at: Date()), snapshot.restEnd != nil,
              let sessionID = snapshot.sessionID, let entry = snapshot.restEntry else { return }
        send(WatchTrainingCommand(account: snapshot.account, sessionID: sessionID, revision: snapshot.revision,
            action: "skipRest", entry: entry))
    }

    private func nextExercise() {
        guard case .idle = commandState, let sessionID = snapshot.sessionID, let entry = snapshot.nextEntry else { return }
        send(WatchTrainingCommand(account: snapshot.account, sessionID: sessionID, revision: snapshot.revision,
            action: "next", entry: entry))
    }

    // MARK: - 命令发送与确认

    /// 先保存待确认命令，再发给手机；失败时保留原命令，重试继续使用同一个 ID。
    /// 手机按 ID 去重，避免“已经执行、但回复丢失”时重复记录一组。
    private func send(_ command: WatchTrainingCommand) {
        guard !isPreview, !commandState.isSending, WCSession.default.activationState == .activated else { return }
        updateReachability()
        guard reachable else { refresh(); return }
        commandState = .sending(command)
        updateCompanionServices()
        UserDefaults.standard.set(try? JSONEncoder().encode(command), forKey: "remote.pending")
        error = nil
        timeout?.cancel()
        timeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(12)) }
            catch { return }
            guard !Task.isCancelled else { return }
            self?.commandUnconfirmed(id: command.id)
        }
        WCSession.default.sendMessage(command.payload, replyHandler: { [weak self] message in
            Task { @MainActor in self?.receive(message) }
        }, errorHandler: { [weak self] _ in
            Task { @MainActor in self?.commandUnconfirmed(id: command.id) }
        })
    }

    /// 超时或发送失败都进入“等待确认”；不把通信失败当作手机没有执行。
    private func commandUnconfirmed(id: String) {
        guard commandState.markUnconfirmed(commandID: id) else { return }
        updateCompanionServices()
        timeout?.cancel()
        timeout = nil
        error = String(localized: "YOUR_PHONE_HAS_NOT_CONFIRMED_YET_YOU_CAN_RETRY_CONFIRMATION", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
        refresh()
    }

    /// 手机已给出结果，或账号／训练已切换时，清除内存和磁盘中的待确认命令。
    private func clearCommand() {
        commandState = .idle
        updateCompanionServices()
        timeout?.cancel()
        timeout = nil
        UserDefaults.standard.removeObject(forKey: "remote.pending")
    }

    private func acknowledge() {
        WKInterfaceDevice.current().play(.success)
    }

    // MARK: - 接收手机消息

    /// 同一条消息可能同时包含健康请求、训练快照和命令回执，分别处理而不是互斥分支。
    private func receive(_ message: [String: Any]) {
        guard !isPreview else { return }
        let requests = HealthWorkoutWire.requests(from: message).filter { $0.owner == .watch }
        if !requests.isEmpty {
            healthRecorder.accept(requests)
            if requests.contains(where: { $0.phase == .running }),
               healthStore.authorizationStatus(for: HealthWorkoutAccess.workout) == .notDetermined,
               WKApplication.shared().applicationState == .active {
                authorizeWorkout()
            }
        }

        // 实时消息和后台快照可能乱序到达，只接受不早于当前快照的数据。
        if let incoming = WatchTrainingSnapshot.decode(message), incoming.generatedAt >= snapshot.generatedAt {
            if let language = incoming.language { AppLanguage.setLanguage(language) }
            snapshot = incoming
            UserDefaults.standard.set(try? JSONEncoder().encode(incoming), forKey: "remote.snapshot")

            // 快照也携带已处理命令的 ID，可在实时回复丢失后补上确认。
            if let pending = commandState.command, incoming.acknowledged.contains(pending.id) {
                clearCommand()
                error = nil
                acknowledge()
            } else if let pending = commandState.command, incoming.sessionID != pending.sessionID || incoming.account != pending.account {
                clearCommand()
                error = String(localized: "THE_WORKOUT_CHANGED_UPDATED_TO_MATCH_YOUR_PHONE", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
            }
            updateCompanionServices()
        }

        // 若前面的快照已经确认此命令，这里不会再次震动。
        if let id = message["commandID"] as? String, id == commandState.command?.id {
            let accepted = message["accepted"] as? Bool == true
            clearCommand()
            error = accepted ? nil : message["error"] as? String ?? String(localized: "CHECK_THE_WORKOUT_ON_YOUR_PHONE", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
            if accepted { acknowledge() }
        }
    }

    // MARK: - 健康采集与提醒协调

    /// 健康授权由系统处理；成功后让采集器继续处理已经收到的训练请求。
    func authorizeWorkout() {
        guard !isPreview, !authorizingHealth, HKHealthStore.isHealthDataAvailable() else { return }
        authorizingHealth = true
        Task {
            defer { authorizingHealth = false }
            do {
                try await HealthWorkoutAccess.authorize(healthStore)
                healthRecorder.accept([])
                refresh()
            } catch { self.error = error.localizedDescription }
        }
    }

    /// 更新手表健康指标，并把采集结果发回手机。
    private func publishHealth(_ report: HealthWorkoutReport) {
        // 上一场训练迟到的报告仍需回传，但不能替换当前训练的实时指标。
        let expected = "\(snapshot.account):\(snapshot.sessionID ?? "")"
        if report.id == expected || healthReport == nil || healthReport?.id == report.id { healthReport = report }
        updateCompanionServices()
        guard WCSession.default.activationState == .activated else { return }
        let payload = HealthWorkoutWire.report(report)
        if WCSession.default.isReachable { WCSession.default.sendMessage(payload, replyHandler: nil, errorHandler: { _ in }) }

        // 保存、取消、失败等重要回执进入系统后台队列，不只依赖一次实时发送。
        if report.terminal || report.state == .failed {
            let queued = WCSession.default.outstandingUserInfoTransfers.contains {
                HealthWorkoutWire.report(from: $0.userInfo) == report
            }
            if !queued { WCSession.default.transferUserInfo(payload) }
        }
    }

    /// Store 只协调状态；提醒与动作采样的规则分别由各自服务负责。
    private func updateCompanionServices() {
        let workoutRunning = snapshot.sessionID.map { healthRecorder.runningSessionID == "\(snapshot.account):\($0)" } ?? false
        restReminder.update(snapshot, workoutRunning: workoutRunning)
        restMotion.update(snapshot, canSend: reachable && commandState == .idle,
            runtimeAvailable: foregroundActive || workoutRunning)
    }

    // MARK: - 本地恢复

    /// 缓存用于启动时先显示界面；待确认命令恢复成可重试状态，不会自动再次执行。
    func restoreState() {
        guard !isPreview else { return }
        if let data = UserDefaults.standard.data(forKey: "remote.snapshot"),
           let cached = try? JSONDecoder().decode(WatchTrainingSnapshot.self, from: data) {
            snapshot = cached
            if let language = cached.language { AppLanguage.setLanguage(language) }
        }
        if let data = UserDefaults.standard.data(forKey: "remote.pending"),
           let command = try? JSONDecoder().decode(WatchTrainingCommand.self, from: data) {
            commandState = .awaitingConfirmation(command)
        }
    }
}

// MARK: - WatchConnectivity 系统回调

// 系统可能在后台线程调用代理，统一切回 MainActor 后更新 Store。
extension WatchRemoteStore: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor [weak self] in
            self?.receive(session.receivedApplicationContext)
            self?.refresh()
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor [weak self] in self?.refresh() }
    }

    /// applicationContext 只保留手机最新一次发布的快照。
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor [weak self] in self?.receive(applicationContext) }
    }

    /// 手机在线时主动推送的实时消息。
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor [weak self] in self?.receive(message) }
    }

    /// 系统后台队列交付的消息，例如离线期间手机发出的健康训练结束请求。
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        Task { @MainActor [weak self] in self?.receive(userInfo) }
    }
}
