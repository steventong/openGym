import XCTest
import UIKit
@testable import OpenGYM

@MainActor final class ExerciseImageCacheTests: XCTestCase {
    private func makeCache(maximumDownloads: Int = 4) -> ExerciseImageCache {
        DownloadProtocol.deferredHandler = nil
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DownloadProtocol.self]
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return ExerciseImageCache(directory: directory, session: URLSession(configuration: configuration), maximumDownloads: maximumDownloads)
    }

    private func fixture() throws -> Data {
        try Data(contentsOf: XCTUnwrap(Bundle(for: Self.self).url(forResource: "0289", withExtension: "webp")))
    }

    private func remote(_ id: String = "0289") -> URL {
        URL(string: "https://gym.example/exercise-media/still/\(id).webp")!
    }

    func testCatalogueImagesUseCurrentServerAndPreserveSubpathWithoutBundledThumbnails() throws {
        let store = GymStore()
        store.serverURL = "https://gym.example/base"
        let file = try XCTUnwrap(Bundle.main.url(forResource: "catalogue", withExtension: "json"))
        let data = try Data(contentsOf: file)
        let exercises = try JSONDecoder().decode([Exercise].self, from: data)
        store.registerCatalogue(exercises)
        XCTAssertFalse(exercises.isEmpty)
        for exercise in exercises {
            XCTAssertEqual(store.remoteImageURL(exercise.id)?.absoluteString, "https://gym.example/base/exercise-media/still/\(exercise.id).webp")
            XCTAssertTrue(store.hasCatalogueMedia(exercise.id))
        }
        let records = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        XCTAssertTrue(records.allSatisfy { $0["thumbnailAsset"] == nil })
        XCTAssertNil(UIImage(named: "ExerciseThumbnails/dumbbell-bench-press"))
        XCTAssertNotNil(UIImage(named: "BrandMark"))
        XCTAssertEqual(ExerciseImageCache.documentsFolder.lastPathComponent, "workout-images")
        XCTAssertEqual(ExerciseImageCache.documentsFolder.deletingLastPathComponent().lastPathComponent, "Documents")
        store.serverURL = "https://other.example/gym"
        XCTAssertEqual(store.remoteImageURL("0289")?.absoluteString, "https://other.example/gym/exercise-media/still/0289.webp")
        for id in ["99999", "custom-squat", "../0289", "0289\n", ""] {
            XCTAssertNil(store.remoteImageURL(id))
            XCTAssertFalse(store.hasCatalogueMedia(id))
        }
        store.serverURL = ""
        XCTAssertNil(store.remoteImageURL("0289"))
        XCTAssertTrue(store.hasCatalogueMedia("0289"))
    }

    func testDownloadDecodesWebPAndPersistsOriginalForOfflineUseAcrossInstances() async throws {
        let cache = makeCache()
        let data = try fixture()
        DownloadProtocol.handler = { _ in (200, data) }
        let image = try await cache.image(for: "0289", remoteURL: remote())
        XCTAssertGreaterThan(image.size.width, 0)
        XCTAssertGreaterThan(image.size.height, 0)
        let file = try XCTUnwrap(cache.cachedURL(for: "0289"))
        XCTAssertEqual(file, cache.directory.appendingPathComponent("0289.webp"))
        XCTAssertEqual(try Data(contentsOf: file), data)
        XCTAssertEqual(try cache.directory.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
        DownloadProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        let offline = ExerciseImageCache(directory: cache.directory)
        let restored = try await offline.image(for: "0289", remoteURL: nil)
        XCTAssertEqual(restored.size, image.size)
        XCTAssertEqual(try Data(contentsOf: file), data)
    }

    func testDeletedAndCorruptImagesDownloadAgain() async throws {
        let cache = makeCache()
        let data = try fixture()
        let requested = expectation(description: "Initial, deleted and corrupt image requests")
        requested.expectedFulfillmentCount = 3
        DownloadProtocol.handler = { _ in requested.fulfill(); return (200, data) }
        _ = try await cache.image(for: "0289", remoteURL: remote())
        let file = try XCTUnwrap(cache.cachedURL(for: "0289"))
        try FileManager.default.removeItem(at: file)
        XCTAssertNil(cache.cachedURL(for: "0289"))
        _ = try await cache.image(for: "0289", remoteURL: remote())
        try Data("broken image".utf8).write(to: file)
        _ = try await cache.image(for: "0289", remoteURL: remote())
        XCTAssertEqual(try Data(contentsOf: file), data)
        await fulfillment(of: [requested], timeout: 5)
    }

    func testInvalidAndInterruptedDownloadsNeverPublishFilesAndCanRetry() async throws {
        let cache = makeCache()
        let data = try fixture()
        for response in [(404, data), (500, data), (200, Data()), (200, Data("<html>Sign in</html>".utf8)),
                         (200, Data(data.prefix(data.count / 2))), (200, Data(repeating: 0, count: 2 * 1024 * 1024 + 1))] {
            DownloadProtocol.handler = { _ in response }
            do {
                _ = try await cache.image(for: "0289", remoteURL: remote())
                XCTFail("Invalid download must not be cached")
            } catch { }
            XCTAssertNil(cache.cachedURL(for: "0289"))
        }
        DownloadProtocol.handler = { _ in throw URLError(.networkConnectionLost) }
        do {
            _ = try await cache.image(for: "0289", remoteURL: remote())
            XCTFail("Interrupted download must fail")
        } catch { }
        XCTAssertNil(cache.cachedURL(for: "0289"))
        DownloadProtocol.handler = { _ in (200, data) }
        _ = try await cache.image(for: "0289", remoteURL: remote())
        XCTAssertNotNil(cache.cachedURL(for: "0289"))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: cache.directory.path), ["0289.webp"])
    }

    func testConcurrentViewersShareDownloadEvenWhenOneCancels() async throws {
        let cache = makeCache()
        let data = try fixture()
        let requested = expectation(description: "One shared download")
        requested.assertForOverFulfill = true
        DownloadProtocol.handler = { _ in requested.fulfill(); return (200, data) }
        let url = remote()
        let first = Task { try await cache.image(for: "0289", remoteURL: url) }
        let second = Task { try await cache.image(for: "0289", remoteURL: url) }
        first.cancel()
        let one = try await first.value
        let two = try await second.value
        XCTAssertEqual(one.size, two.size)
        await fulfillment(of: [requested], timeout: 5)
        XCTAssertNotNil(cache.cachedURL(for: "0289"))
    }

    func testDownloadConcurrencyIsBounded() async throws {
        let cache = makeCache(maximumDownloads: 2)
        let data = try fixture()
        let firstBatch = expectation(description: "Only two initial requests")
        firstBatch.expectedFulfillmentCount = 2
        let responses = PendingResponses()
        let excess = expectation(description: "No extra requests before the first batch finishes")
        excess.isInverted = true
        let counter = RequestCounter()
        DownloadProtocol.deferredHandler = { _, finish in
            let total = counter.begin()
            if total <= 2 { firstBatch.fulfill() }
            if total > 2 && !responses.isReleased { excess.fulfill() }
            responses.append { counter.end(); finish(200, data) }
        }
        let jobs = (1...5).map { index in
            let id = String(format: "%04d", index), url = remote(String(format: "%04d", index))
            return Task { try await cache.image(for: id, remoteURL: url) }
        }
        await fulfillment(of: [firstBatch], timeout: 5)
        await fulfillment(of: [excess], timeout: 0.1)
        XCTAssertEqual(counter.snapshot.total, 2)
        responses.releaseAll()
        for job in jobs { _ = try await job.value }
        XCTAssertEqual(counter.snapshot.total, 5)
        XCTAssertLessThanOrEqual(counter.snapshot.peak, 2)
    }

    func testFailureReleasesDownloadSlotForQueuedImages() async throws {
        let cache = makeCache(maximumDownloads: 1)
        let data = try fixture()
        DownloadProtocol.handler = { request in
            (request.url?.lastPathComponent == "0001.webp" ? 404 : 200, data)
        }
        let failed = Task { try await cache.image(for: "0001", remoteURL: remote("0001")) }
        let next = Task { try await cache.image(for: "0002", remoteURL: remote("0002")) }
        do { _ = try await failed.value; XCTFail("The first download must fail") } catch { }
        _ = try await next.value
        XCTAssertNotNil(cache.cachedURL(for: "0002"))
    }

    func testOfflineCacheHitDoesNotWaitForDownloadSlot() async throws {
        let cache = makeCache(maximumDownloads: 1)
        let data = try fixture()
        try FileManager.default.createDirectory(at: cache.directory, withIntermediateDirectories: true)
        try data.write(to: cache.directory.appendingPathComponent("0002.webp"))
        let started = expectation(description: "Network slot occupied")
        let offlineRead = expectation(description: "Offline read bypasses network queue")
        let responses = PendingResponses()
        DownloadProtocol.deferredHandler = { _, finish in
            started.fulfill()
            responses.append { finish(200, data) }
        }
        let network = Task { try await cache.image(for: "0001", remoteURL: remote("0001")) }
        await fulfillment(of: [started], timeout: 5)
        let local = Task {
            _ = try await cache.image(for: "0002", remoteURL: nil)
            offlineRead.fulfill()
        }
        await fulfillment(of: [offlineRead], timeout: 5)
        responses.releaseAll()
        _ = try await network.value
        try await local.value
    }

    func testOfflineMissAndCorruptFileDoNotBecomeCacheHits() async throws {
        let cache = makeCache()
        for data in [Data(), Data("broken image".utf8)] {
            try FileManager.default.createDirectory(at: cache.directory, withIntermediateDirectories: true)
            try data.write(to: cache.directory.appendingPathComponent("0289.webp"))
            do {
                _ = try await cache.image(for: "0289", remoteURL: nil)
                XCTFail("Corrupt files must not count as offline images")
            } catch { }
            XCTAssertNil(cache.cachedURL(for: "0289"))
        }
    }

    func testCacheRejectsInvalidIDsAndDoesNotFollowFileSymlinks() async throws {
        let cache = makeCache()
        for id in ["../0289", "", "custom-squat", "0289/other", "0289\n", "０２８９", "123456"] {
            XCTAssertNil(cache.cachedURL(for: id))
            do { _ = try await cache.image(for: id, remoteURL: nil); XCTFail("Invalid ID must fail") } catch { }
        }
        try FileManager.default.createDirectory(at: cache.directory, withIntermediateDirectories: true)
        let target = cache.directory.appendingPathComponent("untouched")
        let sentinel = Data("must not overwrite".utf8)
        try sentinel.write(to: target)
        let file = cache.directory.appendingPathComponent("0289.webp")
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: target)
        XCTAssertNil(cache.cachedURL(for: "0289"))
        let data = try fixture()
        DownloadProtocol.handler = { _ in (200, data) }
        _ = try await cache.image(for: "0289", remoteURL: remote())
        XCTAssertEqual(try Data(contentsOf: target), sentinel)
        XCTAssertEqual(try Data(contentsOf: file), data)
        XCTAssertNotEqual(try file.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink, true)
    }

    private final class PendingResponses {
        private let lock = NSLock()
        private var actions: [() -> Void] = []
        private var released = false
        var isReleased: Bool {
            lock.lock(); defer { lock.unlock() }
            return released
        }
        func append(_ action: @escaping () -> Void) {
            lock.lock()
            if released { lock.unlock(); action() }
            else { actions.append(action); lock.unlock() }
        }
        func releaseAll() {
            lock.lock()
            released = true
            let pending = actions
            actions.removeAll()
            lock.unlock()
            pending.forEach { $0() }
        }
    }

    private final class RequestCounter {
        private let lock = NSLock()
        private var total = 0, active = 0, peak = 0
        func begin() -> Int {
            lock.lock(); defer { lock.unlock() }
            total += 1; active += 1; peak = max(peak, active)
            return total
        }
        func end() { lock.lock(); active -= 1; lock.unlock() }
        var snapshot: (total: Int, peak: Int) {
            lock.lock(); defer { lock.unlock() }
            return (total, peak)
        }
    }

    private final class DownloadProtocol: URLProtocol {
        static var handler: ((URLRequest) throws -> (Int, Data))?
        static var deferredHandler: ((URLRequest, @escaping (Int, Data) -> Void) -> Void)?
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            if let deferred = Self.deferredHandler {
                deferred(request) { status, data in self.deliver(status: status, data: data) }
            } else {
                do {
                    let (status, data) = try Self.handler!(request)
                    deliver(status: status, data: data)
                } catch { client?.urlProtocol(self, didFailWithError: error) }
            }
        }
        private func deliver(status: Int, data: Data) {
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
                                           headerFields: ["Content-Type": "image/webp", "Content-Length": "\(data.count)"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() { }
    }
}
