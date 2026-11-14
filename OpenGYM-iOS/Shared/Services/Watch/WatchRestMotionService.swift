import Foundation
import OSLog

/// 休息检测的唯一入口：外部只更新可用状态，并把产出的命令交给既有通信通道。
@MainActor final class WatchRestMotionService {
    var onResume: ((WatchTrainingCommand) -> Void)?

    private struct Rest: Equatable {
        var account: String
        var sessionID: String
        var entry: Int
        var startedAt: Date
    }

    private struct Context: Equatable {
        var rest: Rest
        var revision: String
        var end: Date
        var readyAt: Date?
        var nextSetID: String

        init?(_ snapshot: WatchTrainingSnapshot) {
            guard snapshot.autoEndRestEnabled, !snapshot.account.isEmpty, let sessionID = snapshot.sessionID,
                  let entry = snapshot.restEntry, let start = snapshot.restStartedAt, let end = snapshot.restEnd,
                  start.timeIntervalSince1970.isFinite, end.timeIntervalSince1970.isFinite,
                  let next = snapshot.nextSet, next.blockedReason == nil else { return nil }
            rest = Rest(account: snapshot.account, sessionID: sessionID, entry: entry, startedAt: start)
            revision = snapshot.revision
            self.end = end
            readyAt = snapshot.actionReadyAt
            nextSetID = next.id
        }
    }

    private enum State {
        case idle
        case waiting(Context, UUID, Task<Void, Never>)
        case listening(Context, UUID, Date, RepeatedMotionDetector)

        var context: Context? {
            switch self {
            case .idle: nil
            case .waiting(let context, _, _), .listening(let context, _, _, _): context
            }
        }
    }

    private let source: any RestMotionSource
    private let now: () -> Date
    private var state = State.idle
    /// 只在状态变化时写日志；快照每次刷新都会调用 update，不能逐次记录。
    private var lastStatus: String?
    static let logger = Logger(subsystem: "me.itwl.opengym.watchkitapp", category: "RestMotion")
    /// 一次休息至多尝试一次；通信待确认或断连不能让同一休息重新触发。
    private var consumedRest: Rest?

    init(source: any RestMotionSource, now: @escaping () -> Date = Date.init) {
        self.source = source
        self.now = now
    }

    func update(_ snapshot: WatchTrainingSnapshot, canSend: Bool, runtimeAvailable: Bool) {
        guard let context = Context(snapshot) else {
            log(status: Self.inactiveReason(snapshot))
            stop()
            // 保留已消费身份：暂时缺少下一组／输入被阻塞，不应重放同一休息。
            if snapshot.restEnd == nil || snapshot.sessionID != consumedRest?.sessionID || snapshot.account != consumedRest?.account {
                consumedRest = nil
            }
            return
        }
        guard canSend, runtimeAvailable, consumedRest != context.rest else {
            log(status: !runtimeAvailable ? "blocked_runtime" : !canSend ? "blocked_send" : "consumed")
            stop()
            return
        }
        guard context != state.context else { return }
        if let previous = state.context {
            // 同一休息内重启会丢弃已累计的周期，单独记录便于对照中断。
            Self.logger.notice("Rest motion restarted, same_rest=\(previous.rest == context.rest, privacy: .public) revision_changed=\(previous.revision != context.revision, privacy: .public)")
            lastStatus = nil
        }
        stop()
        let token = UUID()
        let delay = context.readyAt?.timeIntervalSince(now()) ?? 0
        log(status: delay > 0 ? "waiting" : "listening", detail: "entry=\(context.rest.entry) delay=\(String(format: "%.1f", max(0, delay)))")
        if delay > 0 {
            let task = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(delay)) }
                catch { return }
                guard let self, case .waiting(let current, let currentToken, _) = state,
                      current == context, currentToken == token else { return }
                log(status: "listening", detail: "entry=\(context.rest.entry) after_protection")
                listen(context, token: token)
            }
            state = .waiting(context, token, task)
        } else { listen(context, token: token) }
    }

    private func listen(_ context: Context, token: UUID) {
        state = .listening(context, token, now(), RepeatedMotionDetector())
        source.start { [weak self] result in self?.receive(result, token: token) }
    }

    private func receive(_ result: Result<RepeatedMotionDetector.Sample, Error>, token: UUID) {
        guard case .listening(let context, let current, let listeningSince, var detector) = state, token == current else { return }
        guard case .success(let sample) = result else {
            log(status: "source_failed")
            consumedRest = context.rest
            stop()
            return
        }
        guard sample.recordedAt >= max(listeningSince, context.rest.startedAt), sample.recordedAt <= now() else { return }
        let onset = detector.consume(sample)
        if let note = detector.takeNote() { Self.log(note) }
        guard let onset else {
            state = .listening(context, token, listeningSince, detector)
            return
        }
        let startedAt = sample.recordedAt.addingTimeInterval(onset - sample.timestamp)
        guard startedAt >= max(listeningSince, context.rest.startedAt), startedAt <= now() else {
            // 检测器此后不再产出结果，本次休息实际已停止识别，必须留下记录。
            Self.logger.notice("Rest motion onset outside rest window, onset_before_listen_s=\(listeningSince.timeIntervalSince(startedAt), privacy: .public)")
            return
        }
        Self.logger.notice("Rest motion detected, entry=\(context.rest.entry, privacy: .public) onset_lag_s=\(self.now().timeIntervalSince(startedAt), privacy: .public) rest_elapsed_s=\(startedAt.timeIntervalSince(context.rest.startedAt), privacy: .public) countdown_left_s=\(context.end.timeIntervalSince(startedAt), privacy: .public)")
        lastStatus = "detected"
        consumedRest = context.rest
        stop()
        onResume?(WatchTrainingCommand(account: context.rest.account, sessionID: context.rest.sessionID,
            revision: context.revision, action: "resumeFromMotion", entry: context.rest.entry, detectedStartedAt: startedAt))
    }

    private func log(status: String, detail: String = "") {
        guard status != lastStatus else { return }
        lastStatus = status
        Self.logger.notice("Rest motion \(status, privacy: .public) \(detail, privacy: .public)")
    }

    private static func log(_ note: RepeatedMotionDetector.Note) {
        func format(_ value: Double?) -> String { value.map { String(format: "%.3f", $0) } ?? "-" }
        logger.info("Rest motion \(note.kind.rawValue, privacy: .public) cycles=\(note.cycles, privacy: .public) reason=\(note.reason?.rawValue ?? "-", privacy: .public) period_s=\(format(note.period), privacy: .public) peak_pos_g=\(format(note.positivePeak), privacy: .public) peak_neg_g=\(format(note.negativePeak), privacy: .public)")
    }

    /// 与 Context 的条件顺序一致，说明为何当前不需要采样。
    private static func inactiveReason(_ snapshot: WatchTrainingSnapshot) -> String {
        if snapshot.restEnd == nil { return "idle_no_rest" }
        if !snapshot.autoEndRestEnabled { return "idle_disabled" }
        if snapshot.nextSet == nil { return "idle_no_next_set" }
        if snapshot.nextSet?.blockedReason != nil { return "idle_next_set_blocked" }
        return "idle_incomplete_rest"
    }

    private func stop() {
        let previous = state
        state = .idle
        switch previous {
        case .waiting(_, _, let task): task.cancel()
        case .listening: source.stop()
        case .idle: break
        }
    }
}
