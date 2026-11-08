import XCTest
import SwiftUI
import UIKit
@testable import OpenGYM

@MainActor final class RefreshTests: XCTestCase {
    private func store(token: String? = "test") throws -> GymStore {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { StubProtocol.handler = nil; try? FileManager.default.removeItem(at: root) }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        let api = APIClient(address: try ServerAddress("https://test.invalid"), token: token,
                            session: URLSession(configuration: config))
        let store = GymStore(client: api, userID: "sync-test", storage: LocalTrainingStorage(root: root))
        store.serverURL = "https://test.invalid"
        store.userName = "Sync test"
        return store
    }

    private func serveProfile() {
        StubProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            switch request.url!.path {
            case "/api/health": return (200, ["ok": true])
            case "/api/me": return (200, ["user": ["id": "sync-test", "name": "Sync test"]])
            default: return (200, ["state": ["customEx": [["id": "gym-specific", "n": "DPC GYM"]]], "rev": 1])
            }
        }
    }

    func testSyncFeedbackStaysInOneRowInBothLanguages() {
        let states: [SettingsSyncControls.Feedback] = [.idle, .syncing, .succeeded, .failed("Offline")]
        for language in ["en", "zh-Hans"] {
            for state in states {
                let controller = UIHostingController(rootView:
                    SettingsSyncControls(initialFeedback: state, onSync: { .success(()) }, onPairAgain: {})
                        .environment(\.locale, Locale(identifier: language)))
                let size = controller.sizeThatFits(in: CGSize(width: 320, height: 100))
                XCTAssertGreaterThan(size.height, 0)
                XCTAssertLessThanOrEqual(size.height, 28, "\(language): \(state)")
                XCTAssertLessThanOrEqual(size.width, 320)
            }
        }
    }

    func testSuccessFeedbackReturnsToTheSameIdleButtonAfterThreeSeconds() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 320, height: 80)
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKey() }
        window.rootViewController = UIHostingController(rootView:
            SettingsSyncControls(onSync: { .success(()) }, onPairAgain: {})
                .environment(\.locale, Locale(identifier: "en")))
        window.makeKeyAndVisible()
        func image() throws -> Data {
            window.rootViewController?.view.layoutIfNeeded()
            return try XCTUnwrap(UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }.pngData())
        }
        let idle = try image()
        window.rootViewController = UIHostingController(rootView:
            SettingsSyncControls(initialFeedback: .succeeded, onSync: { .success(()) }, onPairAgain: {})
                .environment(\.locale, Locale(identifier: "en")))
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertNotEqual(try image(), idle)
        try await Task.sleep(for: .seconds(1))
        XCTAssertNotEqual(try image(), idle, "Success must remain visible before three seconds")
        try await Task.sleep(for: .milliseconds(2300))
        XCTAssertEqual(try image(), idle, "The same button must return to its idle appearance")
    }

    func testSuccessConfirmsDownloadedDataAndUpdatesLastSync() async throws {
        let store = try store()
        store.lastSync = Date(timeIntervalSince1970: 1)
        serveProfile()
        let result = await store.refresh()
        try result.get()
        XCTAssertEqual(store.customExercises.first?["id"] as? String, "gym-specific")
        XCTAssertTrue(store.online)
        XCTAssertGreaterThan(try XCTUnwrap(store.lastSync).timeIntervalSince1970, 1)
    }

    func testOfflineFailureKeepsLocalDataAndLastSuccessfulSync() async throws {
        let store = try store()
        let lastSync = Date(timeIntervalSince1970: 1)
        store.lastSync = lastSync
        store.state = ["local": "keep"]
        StubProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        let result = await store.refresh()
        guard case let .failure(error) = result else { return XCTFail("Offline refresh must not report success") }
        XCTAssertEqual((error as? URLError)?.code, .notConnectedToInternet)
        XCTAssertEqual(store.state["local"] as? String, "keep")
        XCTAssertEqual(store.lastSync, lastSync)
        XCTAssertFalse(store.online)
    }

    func testDataFailureIsNotSuccessEvenWhenHealthCheckPassed() async throws {
        let store = try store()
        serveProfile()
        let serve = try XCTUnwrap(StubProtocol.handler)
        StubProtocol.handler = { request in
            if request.url!.path == "/api/data" { return (503, ["error": "state unreadable"]) }
            return try serve(request)
        }
        let result = await store.refresh()
        guard case let .failure(APIError.response(code, message)) = result else { return XCTFail("Expected the data request failure") }
        XCTAssertEqual(code, 503)
        XCTAssertEqual(message, "state unreadable")
        XCTAssertNil(store.lastSync)
    }

    func testExpiredSessionReportsFailureAndRequiresPairingAgain() async throws {
        let store = try store()
        StubProtocol.handler = { request in
            request.url!.path == "/api/health" ? (200, ["ok": true]) : (401, ["error": "not signed in"])
        }
        let result = await store.refresh()
        guard case .failure(APIError.response(401, _)) = result else { return XCTFail("Expected expired-session failure") }
        XCTAssertNil(store.userName)
        XCTAssertNil(store.lastSync)
    }

    func testBusyRefreshReportsFailureWithoutMakingRequests() async throws {
        let store = try store()
        store.syncing = true
        StubProtocol.handler = { _ in XCTFail("Busy refresh must not make requests"); return (200, [:]) }
        let result = await store.refresh()
        guard case .failure(APIError.busy) = result else { return XCTFail("Expected busy failure") }
        XCTAssertNil(store.lastSync)
    }

    func testConcurrentRefreshDoesNotReportSkippedRequestAsSuccess() async throws {
        let store = try store()
        serveProfile()
        let serve = try XCTUnwrap(StubProtocol.handler)
        let started = expectation(description: "First refresh started")
        let release = DispatchSemaphore(value: 0)
        StubProtocol.handler = { request in
            if request.url!.path == "/api/health" {
                started.fulfill()
                guard release.wait(timeout: .now() + 5) == .success else { throw URLError(.timedOut) }
            }
            return try serve(request)
        }
        let first = Task { await store.refresh() }
        await fulfillment(of: [started], timeout: 2)
        let second = await store.refresh()
        release.signal()
        let completed = await first.value
        try completed.get()
        guard case .failure(APIError.busy) = second else { return XCTFail("Skipped refresh must report busy") }
    }

    func testMissingClientOrUnpairedAccountNeverReportsSuccess() async throws {
        let disconnected = GymStore()
        let missingClient = await disconnected.refresh()
        guard case .failure(APIError.signIn) = missingClient else { return XCTFail("Expected missing-client failure") }
        let store = try store(token: nil)
        StubProtocol.handler = { request in
            XCTAssertEqual(request.url!.path, "/api/health")
            return (200, ["ok": true])
        }
        let unpaired = await store.refresh()
        guard case .failure(APIError.signIn) = unpaired else { return XCTFail("Unpaired refresh must not report success") }
        XCTAssertNil(store.lastSync)
    }

    func testBackupFailureReportsFailureWithoutReplacingLocalData() async throws {
        let store = try store()
        store.state = ["local": "keep"]
        try Data([1]).write(to: store.localStorage.backupRoot)
        serveProfile()
        let result = await store.refresh()
        guard case let .failure(error) = result else { return XCTFail("Backup failure must not report success") }
        XCTAssertEqual(error.localizedDescription, store.localSaveIssues["serverBackup"])
        XCTAssertEqual(store.state["local"] as? String, "keep")
        XCTAssertNil(store.lastSync)
    }

    func testRefreshCanSucceedAfterFailure() async throws {
        let store = try store()
        StubProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        let failed = await store.refresh()
        guard case .failure = failed else { return XCTFail("Expected initial failure") }
        serveProfile()
        let retry = await store.refresh()
        try retry.get()
        XCTAssertTrue(store.online)
        XCTAssertNotNil(store.lastSync)
    }
}
