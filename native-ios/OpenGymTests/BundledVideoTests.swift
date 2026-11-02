import XCTest
import AVFoundation
import UIKit
@testable import OpenGym

@MainActor final class BundledVideoTests: XCTestCase {
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
