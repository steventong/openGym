import XCTest
@testable import OpenGYM

@MainActor final class WatchRestMotionServiceTests: XCTestCase {
    private final class Source: RestMotionSource {
        var handlers: [(Result<RepeatedMotionDetector.Sample, Error>) -> Void] = []
        var receiving: ((Result<RepeatedMotionDetector.Sample, Error>) -> Void)?
        var starts = 0
        var stops = 0
        func start(_ receive: @escaping (Result<RepeatedMotionDetector.Sample, Error>) -> Void) {
            starts += 1
            handlers.append(receive)
            receiving = receive
        }
        func stop() { stops += 1; receiving = nil }
    }

    private var source: Source!
    private var service: WatchRestMotionService!
    private var clock: Date!
    private var commands: [WatchTrainingCommand]!

    override func setUp() async throws {
        clock = Date(timeIntervalSince1970: 1000)
        source = Source()
        commands = []
        service = WatchRestMotionService(source: source, now: { [unowned self] in clock })
        service.onResume = { [unowned self] in commands.append($0) }
    }

    override func tearDown() async throws {
        service.update(WatchTrainingSnapshot(), canSend: false, runtimeAvailable: false)
        service = nil
        source = nil
    }

    private func snapshot() -> WatchTrainingSnapshot {
        WatchTrainingSnapshot(account: "account", sessionID: "session", revision: "revision",
            nextSet: .init(entry: 0, index: 1, label: "2", weight: "40 kg", detail: "10"),
            restEnd: Date(timeIntervalSince1970: 1090), restEntry: 0, restStartedAt: Date(timeIntervalSince1970: 999), autoEndRestEnabled: true)
    }

    private func feed(from start: Date, duration: Double = 8,
                      handler: ((Result<RepeatedMotionDetector.Sample, Error>) -> Void)? = nil) {
        for index in 0...Int(duration * 25) {
            let elapsed = Double(index) / 25
            clock = start.addingTimeInterval(elapsed)
            let sample = RepeatedMotionDetector.Sample(timestamp: clock.timeIntervalSince1970 - 900,
                recordedAt: clock, acceleration: .init(x: 0.4 * sin(2 * .pi * elapsed / 2), y: 0, z: 0))
            (handler ?? source.receiving)?(.success(sample))
        }
    }

    func testOnlyRestWithNextSetReachableIdleAndRuntimeCanSample() {
        let valid = snapshot()
        var noRest = valid; noRest.restEnd = nil
        var noStart = valid; noStart.restStartedAt = nil
        var noNext = valid; noNext.nextSet = nil
        var blocked = valid; blocked.nextSet?.blockedReason = "Saving"
        var noSession = valid; noSession.sessionID = nil
        for invalid in [noRest, noStart, noNext, blocked, noSession] {
            service.update(invalid, canSend: true, runtimeAvailable: true)
            XCTAssertEqual(source.starts, 0)
        }
        service.update(valid, canSend: false, runtimeAvailable: true)
        service.update(valid, canSend: true, runtimeAvailable: false)
        XCTAssertEqual(source.starts, 0)
        service.update(valid, canSend: true, runtimeAvailable: true)
        XCTAssertEqual(source.starts, 1)
    }

    func testDefaultOffDoesNotSampleAndEnablingStartsDetection() {
        var state = snapshot()
        state.autoEndRestEnabled = WatchTrainingSnapshot().autoEndRestEnabled
        service.update(state, canSend: true, runtimeAvailable: true)
        XCTAssertEqual(source.starts, 0)
        state.autoEndRestEnabled = true
        service.update(state, canSend: true, runtimeAvailable: true)
        feed(from: clock)
        XCTAssertEqual(source.starts, 1)
        XCTAssertEqual(commands.count, 1)
    }

    func testDisablingStopsSamplingDiscardsPartialMotionAndIgnoresOldCallbacks() throws {
        var state = snapshot()
        service.update(state, canSend: true, runtimeAvailable: true)
        let oldHandler = try XCTUnwrap(source.receiving)
        feed(from: clock, duration: 3)
        state.autoEndRestEnabled = false
        service.update(state, canSend: true, runtimeAvailable: true)
        XCTAssertEqual(source.stops, 1)
        XCTAssertNil(source.receiving)
        feed(from: clock, handler: oldHandler)
        XCTAssertTrue(commands.isEmpty)
        state.autoEndRestEnabled = true
        service.update(state, canSend: true, runtimeAvailable: true)
        XCTAssertEqual(source.starts, 2)
        feed(from: clock, duration: 3)
        XCTAssertTrue(commands.isEmpty)
        feed(from: clock)
        XCTAssertEqual(commands.count, 1)
    }

    func testDisablingWhileWaitingCancelsScheduledSampling() async throws {
        let liveSource = Source()
        let liveService = WatchRestMotionService(source: liveSource)
        var state = snapshot()
        state.actionReadyAt = Date().addingTimeInterval(0.05)
        liveService.update(state, canSend: true, runtimeAvailable: true)
        state.autoEndRestEnabled = false
        liveService.update(state, canSend: true, runtimeAvailable: true)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(liveSource.starts, 0)
        state.autoEndRestEnabled = true
        liveService.update(state, canSend: true, runtimeAvailable: true)
        XCTAssertEqual(liveSource.starts, 1)
        state.autoEndRestEnabled = false
        liveService.update(state, canSend: true, runtimeAvailable: true)
        XCTAssertEqual(liveSource.stops, 1)
    }

    func testRefreshDoesNotRestartAndExpiredCountdownStillDetectsFirstMovementOnce() throws {
        var state = snapshot()
        state.restEnd = clock.addingTimeInterval(-0.1)
        service.update(state, canSend: true, runtimeAvailable: true)
        state.generatedAt = clock.addingTimeInterval(1)
        service.update(state, canSend: true, runtimeAvailable: true)
        XCTAssertEqual(source.starts, 1)
        feed(from: clock)
        let command = try XCTUnwrap(commands.first)
        XCTAssertEqual(commands.count, 1)
        XCTAssertEqual(command.action, "resumeFromMotion")
        XCTAssertEqual(command.account, state.account)
        XCTAssertEqual(command.sessionID, state.sessionID)
        XCTAssertEqual(command.revision, state.revision)
        XCTAssertEqual(command.entry, state.restEntry)
        XCTAssertEqual(try XCTUnwrap(command.detectedStartedAt).timeIntervalSince1970, 1000.12, accuracy: 0.001)
        XCTAssertEqual(source.stops, 1)
        service.update(state, canSend: false, runtimeAvailable: true)
        service.update(state, canSend: true, runtimeAvailable: true)
        state.revision = "another-revision"
        service.update(state, canSend: true, runtimeAvailable: true)
        XCTAssertEqual(source.starts, 1, "An unconfirmed or rejected command must not auto-replay the same rest")
    }

    func testDisconnectAndLosingForegroundOrWorkoutRuntimeClearPartialSequence() {
        for losesConnection in [true, false] {
            let state = snapshot()
            service.update(state, canSend: true, runtimeAvailable: true)
            feed(from: clock, duration: 3)
            service.update(state, canSend: !losesConnection, runtimeAvailable: losesConnection)
            XCTAssertNil(source.receiving)
            clock = clock.addingTimeInterval(1)
            service.update(state, canSend: true, runtimeAvailable: true)
            feed(from: clock, duration: 5.8)
            XCTAssertTrue(commands.isEmpty)
            service.update(WatchTrainingSnapshot(), canSend: false, runtimeAvailable: false)
        }
    }

    func testStaleCallbackCannotResumeAfterRevisionAccountSessionOrRestChange() throws {
        for change in 0..<4 {
            var state = snapshot()
            service.update(state, canSend: true, runtimeAvailable: true)
            let oldHandler = try XCTUnwrap(source.receiving)
            switch change {
            case 0: state.revision = "edited"
            case 1: state.account = "other"
            case 2: state.sessionID = "other"
            default: state.restStartedAt = clock
            }
            service.update(state, canSend: true, runtimeAvailable: true)
            feed(from: clock, handler: oldHandler)
            XCTAssertTrue(commands.isEmpty)
            feed(from: clock)
            XCTAssertEqual(commands.count, 1)
            commands.removeAll()
            service.update(WatchTrainingSnapshot(), canSend: false, runtimeAvailable: false)
        }
    }

    func testEndingRestStopsAndNextRestCanDetectAgain() {
        var state = snapshot()
        service.update(state, canSend: true, runtimeAvailable: true)
        feed(from: clock)
        XCTAssertEqual(commands.count, 1)
        state.restEnd = nil
        service.update(state, canSend: true, runtimeAvailable: true)
        XCTAssertNil(source.receiving)
        state.restStartedAt = clock
        state.restEnd = clock.addingTimeInterval(90)
        state.revision = "new-rest"
        service.update(state, canSend: true, runtimeAvailable: true)
        feed(from: clock)
        XCTAssertEqual(commands.count, 2)
    }

    func testDetectedMotionFlowsThroughPhoneAuthorityWithoutCompletingNextSet() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "WatchRestMotionServiceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let phone = GymStore(userID: "motion-flow", storage: LocalTrainingStorage(root: root), defaults: defaults)
        phone.autoEndRestEnabled = true
        phone.state = ["unit": "kg", "restSec": 90]
        phone.draft = try TrainingDraft.fromWeb(["id": "session", "start": 1000, "cur": 0,
            "entries": [["id": "bench", "sets": [["w": 40, "r": 10], ["w": 40, "r": 10]]]]], unit: "kg")
        XCTAssertTrue(phone.liveRowAction(entry: 0, set: 0, action: ["action": "toggle"]))
        let before = phone.watchSnapshot()
        let samplingStart = try XCTUnwrap(before.restStartedAt).addingTimeInterval(4)
        clock = samplingStart
        var response: [String: Any]?
        service.onResume = { [unowned self] command in
            response = phone.performWatchCommand(command, now: clock)
            service.update(phone.watchSnapshot(), canSend: true, runtimeAvailable: true)
        }
        service.update(before, canSend: true, runtimeAvailable: true)
        feed(from: samplingStart)
        let reply = try XCTUnwrap(response)
        XCTAssertEqual(reply["accepted"] as? Bool, true)
        let after = try XCTUnwrap(WatchTrainingSnapshot.decode(reply))
        XCTAssertNil(after.restEnd)
        XCTAssertEqual(after.nextSet, before.nextSet)
        XCTAssertEqual(phone.draft?.completedSets, 1)
        XCTAssertEqual(try XCTUnwrap(after.setStartedAt).timeIntervalSince(samplingStart), 0.12, accuracy: 0.001)
        XCTAssertEqual(phone.workoutActivityState()?.setStartedAt, after.setStartedAt)
        XCTAssertEqual(source.stops, 1)
        XCTAssertNil(source.receiving)
    }

    func testSourceFailureStopsWithoutChangingTrainingOrRetryingEveryRefresh() {
        let state = snapshot()
        service.update(state, canSend: true, runtimeAvailable: true)
        source.receiving?(.failure(NSError(domain: "test", code: 1)))
        XCTAssertNil(source.receiving)
        service.update(state, canSend: true, runtimeAvailable: true)
        XCTAssertEqual(source.starts, 1)
        XCTAssertTrue(commands.isEmpty)
    }

    func testProtectionDeadlineStartsWithoutAnotherSnapshotAndCancellationDisarmsIt() async throws {
        let liveSource = Source()
        let liveService = WatchRestMotionService(source: liveSource)
        var state = snapshot()
        state.actionReadyAt = Date().addingTimeInterval(0.05)
        liveService.update(state, canSend: true, runtimeAvailable: true)
        XCTAssertEqual(liveSource.starts, 0)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(liveSource.starts, 1)
        liveService.update(state, canSend: false, runtimeAvailable: true)
        XCTAssertEqual(liveSource.stops, 1)
        state.actionReadyAt = Date().addingTimeInterval(0.05)
        liveService.update(state, canSend: true, runtimeAvailable: true)
        liveService.update(state, canSend: false, runtimeAvailable: true)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(liveSource.starts, 1)
    }
}
