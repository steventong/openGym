import Foundation

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
    /// 一次休息至多尝试一次；通信待确认或断连不能让同一休息重新触发。
    private var consumedRest: Rest?

    init(source: any RestMotionSource, now: @escaping () -> Date = Date.init) {
        self.source = source
        self.now = now
    }

    func update(_ snapshot: WatchTrainingSnapshot, canSend: Bool, runtimeAvailable: Bool) {
        guard let context = Context(snapshot) else {
            stop()
            // 保留已消费身份：暂时缺少下一组／输入被阻塞，不应重放同一休息。
            if snapshot.restEnd == nil || snapshot.sessionID != consumedRest?.sessionID || snapshot.account != consumedRest?.account {
                consumedRest = nil
            }
            return
        }
        guard canSend, runtimeAvailable, consumedRest != context.rest else { stop(); return }
        guard context != state.context else { return }
        stop()
        let token = UUID()
        let delay = context.readyAt?.timeIntervalSince(now()) ?? 0
        if delay > 0 {
            let task = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(delay)) }
                catch { return }
                guard let self, case .waiting(let current, let currentToken, _) = state,
                      current == context, currentToken == token else { return }
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
            consumedRest = context.rest
            stop()
            return
        }
        guard sample.recordedAt >= max(listeningSince, context.rest.startedAt), sample.recordedAt <= now() else { return }
        guard let onset = detector.consume(sample) else {
            state = .listening(context, token, listeningSince, detector)
            return
        }
        let startedAt = sample.recordedAt.addingTimeInterval(onset - sample.timestamp)
        guard startedAt >= max(listeningSince, context.rest.startedAt), startedAt <= now() else { return }
        consumedRest = context.rest
        stop()
        onResume?(WatchTrainingCommand(account: context.rest.account, sessionID: context.rest.sessionID,
            revision: context.revision, action: "resumeFromMotion", entry: context.rest.entry, detectedStartedAt: startedAt))
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
