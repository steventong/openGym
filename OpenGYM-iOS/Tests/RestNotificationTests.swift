import XCTest
import UserNotifications
@testable import OpenGYM

@MainActor final class RestNotificationTests: XCTestCase {
    private var store: GymStore!
    private var center: FakeRestNotificationCenter!
    private var notifications: RestNotifications!
    private var defaults: UserDefaults!
    private var suite: String!
    private var root: URL!
    private var foreground = false

    override func setUp() async throws {
        foreground = false
        suite = UUID().uuidString
        defaults = UserDefaults(suiteName: suite)
        root = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        store = GymStore(userID: "notification-test", storage: LocalTrainingStorage(root: root))
        store.state = ["restSec": 90]
        store.draft = try TrainingDraft.fromWeb(["id": "session", "name": "训练", "start": 1000, "cur": 0,
            "entries": [["id": "bench", "sets": [["w": 40, "r": 10, "done": false], ["w": 40, "r": 10, "done": false]]]]], unit: "kg")
        center = FakeRestNotificationCenter()
        notifications = RestNotifications(store: store, center: center, defaults: defaults, foreground: { [weak self] in self?.foreground ?? false })
        store.restNotifications = notifications
    }

    override func tearDown() async throws {
        await notifications.flush()
        store.restNotifications = nil
        notifications = nil; store = nil; center = nil
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: root)
    }

    func testEveryRestSchedulesOnceWithoutLiveActivityAndAdjustmentReplacesIt() async throws {
        XCTAssertNil(store.liveActivity)
        store.startRest(entry: 0, seconds: 90)
        await notifications.flush()
        let first = try XCTUnwrap(center.request)
        XCTAssertEqual(first.content.title, "OpenGYM 组间休息完成")
        XCTAssertEqual(first.content.userInfo["openGymWorkout"] as? Bool, true)
        XCTAssertNotNil(first.content.sound)
        XCTAssertFalse(try XCTUnwrap(first.trigger).repeats)
        await notifications.flush()
        XCTAssertEqual(center.addCount, 1)
        store.adjustRest(by: 30)
        await notifications.flush()
        XCTAssertEqual(center.addCount, 2)
        XCTAssertEqual(center.request?.identifier, first.identifier)
        XCTAssertEqual(try XCTUnwrap(center.request?.trigger as? UNTimeIntervalNotificationTrigger).timeInterval, 120, accuracy: 2)
        store.restUntil = nil
        await notifications.flush()
        XCTAssertNil(center.request)
        store.startRest(entry: 0, seconds: 15)
        await notifications.flush()
        XCTAssertEqual(center.addCount, 3)
    }

    func testCompletedSetNotificationNamesUpcomingSetWhileSummaryKeepsCompletedSet() async throws {
        store.state["customEx"] = [["id": "bench", "n": "杠铃臀腿", "bp": "legs", "eq": "barbell", "tg": "glutes"]]
        XCTAssertTrue(store.liveRowAction(entry: 0, set: 0, action: ["action": "toggle"]))
        await notifications.flush()
        let content = try XCTUnwrap(center.request?.content)
        XCTAssertEqual(content.title, "OpenGYM 组间休息完成")
        XCTAssertEqual(content.body, "杠铃臀腿 开始第 2/2 组")
        let snapshot = store.watchSnapshot()
        XCTAssertEqual(snapshot.displayedSet?.label, "第 1/2 组")
        XCTAssertEqual(snapshot.setCompletionLabel, "已完成")
        XCTAssertEqual(snapshot.restNotificationTitle, content.title)
        XCTAssertEqual(snapshot.restNotificationBody, content.body)
    }

    func testDisableCancelsAndPersistsThenEnableSchedulesCurrentRest() async {
        store.startRest(entry: 0, seconds: 90)
        await notifications.flush()
        await notifications.setEnabled(false)
        XCTAssertNil(center.request)
        let restored = RestNotifications(store: store, center: center, defaults: defaults, foreground: { false })
        XCTAssertFalse(restored.enabled)
        store.adjustRest(by: 15)
        await notifications.flush()
        XCTAssertNil(center.request)
        await notifications.setEnabled(true)
        XCTAssertNotNil(center.request)
    }

    func testDeniedPermissionAndSystemSettingsReturn() async {
        center.authorization = .denied
        store.startRest(entry: 0, seconds: 90)
        await notifications.setEnabled(true)
        XCTAssertNil(center.request)
        XCTAssertEqual(center.authorizeCount, 0)
        XCTAssertTrue(notifications.status.contains("系统通知已关闭"))
        center.authorization = .authorized
        await notifications.flush()
        XCTAssertNotNil(center.request)
        center.authorization = .denied
        await notifications.flush()
        XCTAssertNil(center.request)
    }

    func testExplicitAuthorizationAndNoPromptInBackground() async {
        center.authorization = .notDetermined
        store.startRest(entry: 0, seconds: 90)
        await notifications.flush()
        XCTAssertEqual(center.authorizeCount, 0)
        await notifications.authorize()
        XCTAssertEqual(center.authorizeCount, 1)
        XCTAssertNotNil(center.request)
    }

    func testFinishedWorkoutDuringAuthorizationDoesNotScheduleOldRest() async {
        center.authorization = .notDetermined
        store.startRest(entry: 0, seconds: 90)
        center.onAuthorize = { self.store.draft = nil }
        await notifications.authorize()
        XCTAssertNil(center.request)
    }

    func testSkipWhileAddIsSuspendedRemovesStaleReminder() async {
        store.startRest(entry: 0, seconds: 90)
        center.onAdd = { self.store.restUntil = nil }
        await notifications.flush()
        XCTAssertNil(center.request)
    }

    func testExpiredRestIsNotReplayedAndDeliveredReminderIsNotCancelled() async {
        store.restUntil = Date().addingTimeInterval(-10)
        await notifications.flush()
        XCTAssertEqual(center.addCount, 0)
        store.restUntil = Date().addingTimeInterval(0.05)
        await notifications.flush()
        XCTAssertNotNil(center.request)
        let cancellations = center.cancelCount
        try? await Task.sleep(for: .milliseconds(100))
        await notifications.flush()
        XCTAssertEqual(center.addCount, 1)
        XCTAssertEqual(center.cancelCount, cancellations)
    }

    func testDeletingWorkoutAndAccountChangeCancelReminder() async {
        store.startRest(entry: 0, seconds: 90)
        await notifications.flush()
        store.userID = nil
        await notifications.flush()
        XCTAssertNil(center.request)
        store.userID = "notification-test"
        await notifications.flush()
        XCTAssertNotNil(center.request)
        store.deleteCurrentWorkout()
        await notifications.flush()
        XCTAssertNil(center.request)
    }

    func testOpeningAppClearsDeliveredWithoutCancellingUpcomingRest() async throws {
        store.startRest(entry: 0, seconds: 90)
        await notifications.flush()
        let pending = try XCTUnwrap(center.request)
        let cancellations = center.cancelCount
        center.delivered = true
        notifications.clearDelivered()
        XCTAssertFalse(center.delivered)
        XCTAssertEqual(center.request?.identifier, pending.identifier)
        foreground = true
        await notifications.flush()
        XCTAssertEqual(center.cancelCount, cancellations)
        XCTAssertEqual(center.addCount, 1, "Opening the app must not reschedule the deadline")
        XCTAssertNotNil(center.request, "A future rest still needs its background fallback")
    }

    func testExpiredNotificationStaysInBackgroundAndClearsInForeground() async {
        store.restUntil = Date().addingTimeInterval(-10)
        center.delivered = true
        await notifications.flush()
        XCTAssertTrue(center.delivered)
        foreground = true
        await notifications.flush()
        XCTAssertFalse(center.delivered)
        XCTAssertEqual(center.addCount, 0)
        center.delivered = true
        await notifications.flush()
        XCTAssertFalse(center.delivered, "Foreground updates also remove delivered reminders")
    }

    func testSchedulingFailureIsVisibleAndRetried() async {
        store.startRest(entry: 0, seconds: 90)
        center.failAdd = true
        await notifications.flush()
        XCTAssertNotNil(notifications.issue)
        center.failAdd = false
        await notifications.flush()
        XCTAssertNil(notifications.issue)
        XCTAssertNotNil(center.request)
    }

    func testCoalescedReminderLogsKeepBothCommandTraces() async {
        await notifications.flush()
        var records: [WorkoutActivityDiagnostics.Record] = []
        await WorkoutActivityDiagnostics.$observer.withValue({ records.append($0) }) {
            WorkoutActivityDiagnostics.$traceID.withValue("tap-a") { store.startRest(entry: 0, seconds: 90) }
            WorkoutActivityDiagnostics.$traceID.withValue("tap-b") { notifications.publish() }
            await notifications.flush()
        }
        let starts = records.filter { $0.event == "reminder.reconcile.begin" }
        XCTAssertEqual(starts.count, 1)
        XCTAssertEqual(Set(starts.first?.traces ?? []), ["tap-a", "tap-b"])
        for event in ["reminder.permission.begin", "reminder.permission.end", "reminder.schedule.begin", "reminder.schedule.end", "reminder.reconcile.end"] {
            XCTAssertTrue(records.contains { $0.event == event && Set($0.traces) == ["tap-a", "tap-b"] })
        }
        XCTAssertEqual(center.addCount, 1)
    }
}

@MainActor private final class FakeRestNotificationCenter: RestNotificationCenter {
    var authorization: UNAuthorizationStatus = .authorized
    var request: UNNotificationRequest?
    var addCount = 0
    var cancelCount = 0
    var authorizeCount = 0
    var delivered = false
    var failAdd = false
    var onAuthorize: (() -> Void)?
    var onAdd: (() -> Void)?
    func permission() async -> RestNotificationPermission {
        RestNotificationPermission(authorization: authorization, alerts: authorization == .authorized)
    }
    func authorize() async throws {
        authorizeCount += 1; authorization = .authorized
        onAuthorize?(); await Task.yield()
    }
    func add(_ request: UNNotificationRequest) async throws {
        if failAdd { throw NSError(domain: "test", code: 1) }
        addCount += 1
        onAdd?(); onAdd = nil
        await Task.yield()
        self.request = request
    }
    func clearDelivered() { delivered = false }
    func cancel() { cancelCount += 1; request = nil; clearDelivered() }
}
