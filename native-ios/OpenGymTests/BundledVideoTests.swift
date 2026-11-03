import XCTest
import AVFoundation
import UIKit
@testable import OpenGym

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

    func testEveryCatalogueVideoIsBundledWithoutServerConfiguration() throws {
        let store = GymStore()
        store.serverURL = ""
        let catalogue = try XCTUnwrap(Bundle.main.url(forResource:"catalogue",withExtension:"json"))
        let exercises = try JSONDecoder().decode([Exercise].self,from:Data(contentsOf:catalogue))
        XCTAssertFalse(exercises.isEmpty)
        for exercise in exercises {
            let video = try XCTUnwrap(store.mediaURL(exercise.id,video:true),exercise.id)
            XCTAssertTrue(video.isFileURL,exercise.id)
            XCTAssertTrue(video.path.hasPrefix(Bundle.main.bundleURL.path + "/"),exercise.id)
            XCTAssertGreaterThan(try video.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0,0,exercise.id)
        }
    }

    func testMissingOrCustomVideoDoesNotFallBackToNetwork() {
        let store = GymStore()
        store.serverURL = "https://gym.example"
        for id in ["99999", "custom-squat", "../0289", ""] {
            XCTAssertNil(store.mediaURL(id,video:true))
        }
        XCTAssertTrue(store.mediaURL("0289")?.isFileURL == true)
        XCTAssertNil(store.mediaURL("custom-squat"))
        XCTAssertNil(store.mediaURL("99999"))
    }

    func testEveryCatalogueThumbnailIsBundledAndDecodableOffline() throws {
        let store = GymStore()
        store.serverURL = ""
        let catalogue = try XCTUnwrap(Bundle.main.url(forResource:"catalogue",withExtension:"json"))
        let exercises = try JSONDecoder().decode([Exercise].self,from:Data(contentsOf:catalogue))
        for exercise in exercises {
            try autoreleasepool {
                let url = try XCTUnwrap(store.mediaURL(exercise.id), exercise.id)
                XCTAssertTrue(url.isFileURL)
                let image = try XCTUnwrap(UIImage(contentsOfFile:url.path), exercise.id)
                XCTAssertGreaterThan(image.size.width, 0, exercise.id)
            }
        }
    }

    func testBundledVideoIsPlayableWithAVFoundation() async throws {
        let store = GymStore()
        store.serverURL = ""
        let video = try XCTUnwrap(store.mediaURL("0289",video:true))
        let asset = AVURLAsset(url:video)
        let playable = try await asset.load(.isPlayable)
        let duration = try await asset.load(.duration)
        let tracks = try await asset.loadTracks(withMediaType:.video)
        XCTAssertTrue(playable)
        XCTAssertGreaterThan(duration.seconds,0)
        XCTAssertFalse(tracks.isEmpty)
    }
}
