import XCTest
import SwiftUI
import UIKit
@testable import OpenGYM

@MainActor final class HistorySaveButtonTests: XCTestCase {
    func testSavingKeepsButtonSizeInBothLanguages() {
        for language in ["en", "zh-Hans"] {
            let idle = UIHostingController(rootView: HistorySaveButton(submitting: false) {}
                .environment(\.locale, Locale(identifier: language)))
            let saving = UIHostingController(rootView: HistorySaveButton(submitting: true) {}
                .environment(\.locale, Locale(identifier: language)))
            let proposal = CGSize(width: 320, height: 100)
            let a = idle.sizeThatFits(in: proposal)
            let b = saving.sizeThatFits(in: proposal)
            XCTAssertGreaterThanOrEqual(a.width, 44)
            XCTAssertGreaterThanOrEqual(a.height, 44)
            XCTAssertEqual(a.width, b.width, accuracy: 0.5, language)
            XCTAssertEqual(a.height, b.height, accuracy: 0.5, language)
        }
    }

    func testBothSaveStatesRenderInSimulator() throws {
        for language in ["en", "zh-Hans"] {
            let content = HStack(spacing: 24) {
                HistorySaveButton(submitting: false) {}
                HistorySaveButton(submitting: true) {}
            }
            .environment(\.locale, Locale(identifier: language))
            .padding(24).foregroundStyle(.white).tint(GymTheme.green).background(GymTheme.background)
            let controller = UIHostingController(rootView: content)
            let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let previous = scene.keyWindow
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 320, height: 120)
            window.rootViewController = controller
            window.makeKeyAndVisible()
            controller.view.frame = window.bounds
            controller.view.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = "history-save-idle-and-loading-\(language)"
            attachment.lifetime = .keepAlways
            add(attachment)
            XCTAssertNotNil(image.cgImage)
            window.isHidden = true
            previous?.makeKey()
        }
    }
}
