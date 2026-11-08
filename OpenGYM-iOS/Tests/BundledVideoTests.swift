import XCTest
import AVFoundation
@testable import OpenGYM

@MainActor final class BundledVideoTests: XCTestCase {
    func testAudioSessionConfigurationDoesNotBlockMainThreadAndReleaseWaitsForIt() async throws {
        let configuring = expectation(description: "Configuration started off the main thread")
        let released = expectation(description: "Session released after configuration")
        let allowConfiguration = DispatchSemaphore(value: 0)
        let configurationFinished = DispatchSemaphore(value: 0)
        let session = ExerciseAudioSession(configure: {
            XCTAssertFalse(Thread.isMainThread)
            configuring.fulfill()
            XCTAssertEqual(allowConfiguration.wait(timeout: .now() + 5), .success)
            configurationFinished.signal()
        }, release: {
            XCTAssertFalse(Thread.isMainThread)
            XCTAssertEqual(configurationFinished.wait(timeout: .now()), .success)
            released.fulfill()
        })

        let start = Task { try await session.configureForPlayback() }
        await fulfillment(of: [configuring], timeout: 2)
        // The main actor must remain available while the audio service is busy.
        // Stop must return immediately, and its release must wait behind setup.
        session.deactivate()
        allowConfiguration.signal()
        try await start.value
        await fulfillment(of: [released], timeout: 2)
    }

    func testAudioSessionConfigurationFailureStillAllowsReleaseAndRetry() async throws {
        enum ConfigurationError: Error { case unavailable }
        let firstAttempt = DispatchSemaphore(value: 0)
        firstAttempt.signal()
        let released = expectation(description: "Release after failed configuration")
        let session = ExerciseAudioSession(configure: {
            if firstAttempt.wait(timeout: .now()) == .success {
                throw ConfigurationError.unavailable
            }
        }, release: {
            released.fulfill()
        })

        do {
            try await session.configureForPlayback()
            XCTFail("Configuration failure must reach the player")
        } catch ConfigurationError.unavailable {
            // Expected: the player can display its retry state.
        }
        session.deactivate()
        try await session.configureForPlayback()
        await fulfillment(of: [released], timeout: 2)
    }

    func testCatalogueVideosUseServerAndAreNotBundled() throws {
        let store = GymStore()
        store.serverURL = "https://gym.example/base"
        let catalogue = try XCTUnwrap(Bundle.main.url(forResource:"catalogue",withExtension:"json"))
        let exercises = try JSONDecoder().decode([Exercise].self,from:Data(contentsOf:catalogue))
        XCTAssertFalse(exercises.isEmpty)
        store.registerCatalogue(exercises)
        for exercise in exercises {
            let video = try XCTUnwrap(store.videoURL(exercise.id),exercise.id)
            XCTAssertFalse(video.path.hasPrefix(Bundle.main.bundleURL.path + "/"),exercise.id)
            XCTAssertEqual(store.remoteVideoURL(exercise.id)?.absoluteString, "https://gym.example/base/exercise-media/clip/\(exercise.id).mp4")
            XCTAssertNil(Bundle.main.url(forResource: exercise.id, withExtension: "mp4", subdirectory: "clip"))
        }
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "UIFileSharingEnabled") as? Bool, true)
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "LSSupportsOpeningDocumentsInPlace") as? Bool, true)
        XCTAssertEqual(ExerciseVideoCache.documentsFolder.lastPathComponent, "workout-videos")
        XCTAssertEqual(ExerciseVideoCache.documentsFolder.deletingLastPathComponent().lastPathComponent, "Documents")
    }

    func testMissingOrCustomVideoDoesNotFallBackToNetwork() throws {
        let store = GymStore()
        store.serverURL = "https://gym.example"
        let catalogue = try XCTUnwrap(Bundle.main.url(forResource: "catalogue", withExtension: "json"))
        store.registerCatalogue(try JSONDecoder().decode([Exercise].self, from: Data(contentsOf: catalogue)))
        for id in ["99999", "custom-squat", "../0289", ""] {
            XCTAssertNil(store.videoURL(id))
        }
        XCTAssertTrue(store.hasCatalogueMedia("0289"))
        XCTAssertFalse(store.hasCatalogueMedia("custom-squat"))
        XCTAssertFalse(store.hasCatalogueMedia("99999"))
    }

    private func makeCache() -> ExerciseVideoCache {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [VideoDownloadProtocol.self]
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return ExerciseVideoCache(directory: root, session: URLSession(configuration: config))
    }

    private func fixture() throws -> Data {
        try Data(contentsOf: XCTUnwrap(Bundle(for: Self.self).url(forResource: "0289", withExtension: "mp4")))
    }

    func testDownloadPersistsPlayableVideoAndReusesItOfflineAcrossInstances() async throws {
        let cache = makeCache()
        let data = try fixture()
        VideoDownloadProtocol.handler = { _ in (200, data) }
        let file = try await cache.video(for: "0289", remoteURL: URL(string: "https://gym.example/0289.mp4"))
        XCTAssertEqual(file, cache.directory.appendingPathComponent("0289.mp4"))
        XCTAssertEqual(try Data(contentsOf: file), data)
        XCTAssertEqual(try cache.directory.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
        VideoDownloadProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        let offlineCache = ExerciseVideoCache(directory: cache.directory)
        let local = try await offlineCache.video(for: "0289", remoteURL: nil)
        XCTAssertEqual(local, file)
    }

    func testDeletedOrCorruptedVideoDownloadsAgain() async throws {
        let cache = makeCache()
        let data = try fixture()
        let remote = URL(string: "https://gym.example/0289.mp4")
        VideoDownloadProtocol.handler = { _ in (200, data) }
        let file = try await cache.video(for: "0289", remoteURL: remote)
        try FileManager.default.removeItem(at: file)
        XCTAssertNil(cache.cachedURL(for: "0289"))
        _ = try await cache.video(for: "0289", remoteURL: remote)
        XCTAssertEqual(try Data(contentsOf: file), data)
        try Data("not a video".utf8).write(to: file)
        _ = try await cache.video(for: "0289", remoteURL: remote)
        XCTAssertEqual(try Data(contentsOf: file), data)
    }

    func testFailedDownloadsNeverPublishFilesAndCanRetry() async throws {
        let cache = makeCache()
        let remote = URL(string: "https://gym.example/0289.mp4")
        let data = try fixture()
        for response in [(404, data), (200, Data("<html>Login</html>".utf8)), (200, Data())] {
            VideoDownloadProtocol.handler = { _ in response }
            do {
                _ = try await cache.video(for: "0289", remoteURL: remote)
                XCTFail("Invalid downloads must fail")
            } catch { }
            XCTAssertNil(cache.cachedURL(for: "0289"))
        }
        VideoDownloadProtocol.handler = { _ in throw URLError(.networkConnectionLost) }
        do {
            _ = try await cache.video(for: "0289", remoteURL: remote)
            XCTFail("Interrupted downloads must fail")
        } catch { }
        XCTAssertNil(cache.cachedURL(for: "0289"))
        VideoDownloadProtocol.handler = { _ in (200, data) }
        _ = try await cache.video(for: "0289", remoteURL: remote)
        XCTAssertNotNil(cache.cachedURL(for: "0289"))
    }

    func testConcurrentLoadsShareDownloadEvenWhenOneViewerCancels() async throws {
        let cache = makeCache()
        let data = try fixture()
        let requested = expectation(description: "Only one download")
        requested.assertForOverFulfill = true
        VideoDownloadProtocol.handler = { _ in
            requested.fulfill()
            return (200, data)
        }
        let remote = URL(string: "https://gym.example/0289.mp4")
        let first = Task { try await cache.video(for: "0289", remoteURL: remote) }
        let second = Task { try await cache.video(for: "0289", remoteURL: remote) }
        first.cancel()
        let one = try await first.value
        let two = try await second.value
        XCTAssertEqual(one, two)
        await fulfillment(of: [requested], timeout: 5)
    }

    func testCacheRejectsPathTraversal() async throws {
        let cache = makeCache()
        for id in ["../0289", "", "custom-squat", "0289/other"] {
            XCTAssertNil(cache.cachedURL(for: id))
            do {
                _ = try await cache.video(for: id, remoteURL: nil)
                XCTFail("Invalid IDs must fail")
            } catch { }
        }
    }
}

private final class VideoDownloadProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, data) = try Self.handler!(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
                                           headerFields: ["Content-Type": "video/mp4", "Content-Length": "\(data.count)"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() { }
}
