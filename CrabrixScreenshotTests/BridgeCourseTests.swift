import XCTest
import UIKit

/// Bridge courses end to end: download the production-signed "Rust for C
/// Developers" pack through the real catalog flow, open a bridge lesson and an
/// Academy lesson it credits, and capture both for review.
@MainActor
final class BridgeCourseTests: XCTestCase {
    private let app = XCUIApplication()

    func testDownloadOpenAndCaptureABridgeLesson() throws {
        continueAfterFailure = true
        launch(["-CrabrixTab", "learn"])
        let course = app.otherElements["learn-course-rust-for-c-developers"]
        if !course.exists {
            let download = app.buttons["Download Rust for C Developers for offline use"]
            scrollTo(download)
            XCTAssertTrue(download.waitForExistence(timeout: 20), "bridge course must be offered by the bundled catalog")
            download.tap()
            let confirm = app.buttons.matching(NSPredicate(
                format: "label MATCHES %@", "^Download [0-9][0-9,. ]* (bytes|KB|MB|GB|TB)$"
            )).firstMatch
            XCTAssertTrue(confirm.waitForExistence(timeout: 10))
            confirm.tap()
        }
        scrollTo(course)
        XCTAssertTrue(course.waitForExistence(timeout: 180), "signed bridge pack must download and install")
        capture("bridge-01-learn")

        launch(["-CrabrixTab", "learn", "-CrabrixLearn", "rust-for-c-developers"])
        capture("bridge-02-course")

        launch(["-CrabrixTab", "learn", "-CrabrixLearn", "c-malloc-free-to-ownership"])
        XCTAssertTrue(app.otherElements["lesson-page-heading"].waitForExistence(timeout: 20))
        capture("bridge-03-lesson")
        for index in 4...7 {
            app.swipeUp()
            capture("bridge-0\(index)-lesson-scrolled")
        }
    }

    private func scrollTo(_ element: XCUIElement) {
        for _ in 0..<12 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
    }

    private func launch(_ arguments: [String]) {
        app.terminate()
        app.launchArguments = ["-crabrix.appearance", "dark"] + arguments
        app.launch()
        XCTAssertEqual(app.state, .runningForeground)
        Thread.sleep(forTimeInterval: 10)
    }

    private func capture(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(name + ".png")
        try? screenshot.pngRepresentation.write(to: path)
        print("BRIDGE_IMAGE_PATH \(path.path)")
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
