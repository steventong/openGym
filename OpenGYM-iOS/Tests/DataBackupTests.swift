import XCTest
@testable import OpenGYM

@MainActor final class DataBackupTests: XCTestCase {
    private var root: URL!
    private var defaults: UserDefaults!
    private var suite: String!
    private var folder: URL { root.appendingPathComponent("data-backup", isDirectory: true) }

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        suite = "data-backup-tests-" + UUID().uuidString
        defaults = UserDefaults(suiteName: suite)
    }
    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
        defaults.removePersistentDomain(forName: suite)
    }

    private func store(_ persistence: PersistenceController = PersistenceController(inMemory: true), backsUp: Bool = true) -> GymStore {
        GymStore(userID: "local", storage: LocalTrainingStorage(root: root.appendingPathComponent("local")), defaults: defaults, persistence: persistence,
                 dataBackup: backsUp ? DataBackup(directory: folder) : nil)
    }
    private func names() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted()
    }
    private func documents() throws -> [[String: Any]] {
        try names().map { try DataBackup.decode(Data(contentsOf: folder.appendingPathComponent($0))) }
    }
    private func set(_ key: String, _ value: Any, in store: GymStore) async {
        let saved = await store.mutate { source in var next = source; next[key] = value; return next }
        XCTAssertTrue(saved)
    }

    // MARK: - 自动备份

    func testEveryChangeSavesWholeDocumentAsJSON() async throws {
        let s = store()
        s.prepareOfflineLaunch()
        XCTAssertEqual(names().count, 1, "启动时留下第一次修改之前的版本")
        let added = await s.addRoutine(name: "推", exerciseIDs: ["c-own"])
        XCTAssertTrue(added)
        await set("restSec", 120, in: s)

        let saved = try documents()
        XCTAssertEqual(saved.count, 3)
        XCTAssertTrue(names().allSatisfy { $0.range(of: #"^\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}-\d{3}\.json$"#, options: .regularExpression) != nil })
        XCTAssertEqual((saved[0]["routines"] as? [Any])?.count, 0)
        XCTAssertEqual((saved[1]["routines"] as? [[String: Any]])?.first?["name"] as? String, "推")
        XCTAssertNil(saved[1]["restSec"])
        XCTAssertTrue(StateDocument.same(saved[2], s.state))
        XCTAssertEqual(try folder.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, false, "随系统 iCloud 备份保存")
    }

    func testUnchangedOrRejectedSavesAndRelaunchAddNoFile() async throws {
        let persistence = PersistenceController(inMemory: true)
        let s = store(persistence)
        s.prepareOfflineLaunch()
        await set("restSec", 90.5, in: s)
        let before = names()
        await set("restSec", 90.5, in: s)
        let rejected = await s.mutate(reportError: false) { _ in throw APIError.response(0, "拒绝") }
        XCTAssertFalse(rejected)
        store(persistence).prepareOfflineLaunch()
        XCTAssertEqual(names(), before)
    }

    func testChangeFromAnotherDeviceIsBackedUp() async throws {
        let persistence = PersistenceController(inMemory: true)
        let s = store(persistence)
        s.prepareOfflineLaunch()
        let other = store(persistence, backsUp: false)
        try other.reloadDocument()
        await set("unit", "lb", in: other)
        XCTAssertEqual(names().count, 1)
        try s.reloadDocument()
        XCTAssertEqual(try documents().last?["unit"] as? String, "lb")
        XCTAssertEqual(names().count, 2)
    }

    func testVersionsAtTheSameMomentNeverOverwriteEachOther() throws {
        let backup = DataBackup(directory: folder), now = Date(timeIntervalSince1970: 1_800_000_000)
        for rest in [60, 90, 120] { try backup.save(StateDocument.canonical(["restSec": rest]), at: now) }
        XCTAssertEqual(try documents().compactMap { $0["restSec"] as? Int }, [60, 90, 120])
    }

    func testBackupFailureKeepsTheChangeAndIsReportedUntilNextSuccess() async throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data([1]).write(to: folder)
        let s = store()
        s.prepareOfflineLaunch()
        await set("restSec", 120, in: s)
        XCTAssertEqual(s.state["restSec"] as? Int, 120)
        XCTAssertNotNil(s.dataBackupIssue)
        XCTAssertNil(s.localSaveError, "备份失败不能拦住训练和历史的保存")

        try FileManager.default.removeItem(at: folder)
        await set("restSec", 150, in: s)
        XCTAssertNil(s.dataBackupIssue)
        XCTAssertEqual(try documents().last?["restSec"] as? Int, 150)
    }

    // MARK: - 导出与导入

    func testExportedBackupRestoresEverythingOnAnotherDevice() async throws {
        let first = store(backsUp: false)
        first.prepareOfflineLaunch()
        await set("unit", "lb", in: first)
        await set("futureField", ["keep": true], in: first)
        await set("bodyweight", [["d": "2026-11-01", "w": 80.4, "t": 1]], in: first)
        let added = await first.addRoutine(name: "推", exerciseIDs: ["c-own"])
        XCTAssertTrue(added)
        let data = try first.exportedBackup()

        let persistence = PersistenceController(inMemory: true)
        let second = store(persistence)
        second.prepareOfflineLaunch()
        let removed = await second.addRoutine(name: "将被替换", exerciseIDs: ["c-own"])
        XCTAssertTrue(removed)
        await set("restSec", 45, in: second)
        let replaced = second.state
        try await second.restoreBackup(DataBackup.decode(data))

        XCTAssertTrue(StateDocument.same(second.state, first.state))
        XCTAssertTrue(StateDocument.same(try StateRepository(persistence: persistence).load(), first.state))
        let saved = try documents()
        XCTAssertTrue(StateDocument.same(saved[saved.count - 2], replaced), "被替换的版本留在备份里")
        XCTAssertTrue(StateDocument.same(saved.last, first.state))
        // 误导入后可以用自动备份退回。
        try await second.restoreBackup(saved[saved.count - 2])
        XCTAssertTrue(StateDocument.same(second.state, replaced))
    }

    func testRestoreAlsoReplacesRecordsNotYetLoadedFromICloud() async throws {
        let persistence = PersistenceController(inMemory: true)
        let s = store(persistence)
        s.prepareOfflineLaunch()
        let backup = try DataBackup.decode(s.exportedBackup())
        let other = store(persistence, backsUp: false)
        try other.reloadDocument()
        let added = await other.addRoutine(name: "刚导入", exerciseIDs: ["c-own"])
        XCTAssertTrue(added)

        try await s.restoreBackup(backup)
        XCTAssertTrue(try StateRepository(persistence: persistence).load()["routines"].map { ($0 as? [Any])?.isEmpty == true } ?? false)
        XCTAssertTrue(try documents().contains { ($0["routines"] as? [[String: Any]])?.first?["name"] as? String == "刚导入" })
    }

    func testRestoreStopsWhenDraftIsOpenOrCurrentVersionCannotBeKept() async throws {
        let s = store()
        s.prepareOfflineLaunch()
        await set("restSec", 120, in: s)
        let before = s.state, backup = StateDocument.canonical(["unit": "lb"])
        func assertRefused(_ line: UInt = #line) async {
            do { try await s.restoreBackup(backup); XCTFail("应拒绝导入", line: line) } catch {}
            XCTAssertTrue(StateDocument.same(s.state, before), line: line)
        }
        s.draft = TrainingDraft(name: "training", entries: [], unit: "kg")
        await assertRefused()
        s.draft = nil
        s.historyEdits = ["w1": ["proposed": ["id": "w1"]]]
        await assertRefused()
        s.historyEdits = [:]

        let persistence = PersistenceController(inMemory: true)
        try FileManager.default.removeItem(at: folder)
        try Data([1]).write(to: folder)
        let blocked = store(persistence)
        blocked.prepareOfflineLaunch()
        await set("restSec", 60, in: blocked)
        do { try await blocked.restoreBackup(backup); XCTFail("留不下当前版本时应拒绝") } catch {}
        XCTAssertEqual(blocked.state["restSec"] as? Int, 60)
        XCTAssertNil(blocked.state["unit"])
    }

    func testOtherFilesAreRejected() {
        let invalid = ["", "[]", "{}", #"{"routines":[],"customEx":[]}"#, #"{"workouts":{},"routines":[]}"#,
                       #"{"workouts":[1],"routines":[]}"#, #"{"workouts":[],"routines":[],"unit":"stone"}"#, #"{"workouts":[],"routines":[],"unit":1}"#]
        for text in invalid { XCTAssertThrowsError(try DataBackup.decode(Data(text.utf8)), text) }
        XCTAssertNoThrow(try DataBackup.decode(Data(#"{"workouts":[],"routines":[]}"#.utf8)))
    }
}
