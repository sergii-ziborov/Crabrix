import XCTest
import UIKit

/// Manual screenshot and legal-reader QA. This runs in disposable Xcode Cloud
/// Simulators; it does not install or reset anything on a learner's device.
@MainActor
final class ReleaseScreenshotTests: XCTestCase {
    private let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    func testReleaseScreenshotsAndLegalReaders() throws {
        let family = UIDevice.current.userInterfaceIdiom == .pad ? "ipad-13" : "iphone-6.9"
        launch(["-CrabrixTab", "learn"])
        let basics = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Open Rust Basics")).firstMatch
        XCTAssertTrue(basics.waitForExistence(timeout: 120), "The signed offline transition courses must finish loading")
        capture("\(family)-03-learn")

        let frames: [(String, [String])] = family == "ipad-13" ? [
            ("01-build", ["--crabrix-auto-multifile"]),
            ("02-projects", ["-CrabrixTab", "projects"]),
            ("07-my-courses", ["-CrabrixTab", "learn"]),
            ("04-lesson", ["-CrabrixTab", "learn", "-CrabrixLearn", "borrowing"]),
            ("05-profile", ["-CrabrixTab", "learn", "-CrabrixLearn", "profile"]),
            ("06-library", ["-CrabrixTab", "learn", "-CrabrixLearn", "examples"])
        ] : [
            ("01-build", ["--crabrix-auto-borrow"]),
            ("02-projects", ["-CrabrixTab", "projects"]),
            ("09-my-courses", ["-CrabrixTab", "learn"]),
            ("04-course", ["-CrabrixTab", "learn", "-CrabrixLearn", "basics"]),
            ("05-lesson", ["-CrabrixTab", "learn", "-CrabrixLearn", "borrowing"]),
            ("06-profile", ["-CrabrixTab", "learn", "-CrabrixLearn", "profile"]),
            ("07-library", ["-CrabrixTab", "learn", "-CrabrixLearn", "examples"]),
            ("10-example-detail", ["-CrabrixTab", "learn", "-CrabrixLearn", "example:ferris-pixel-art"]),
            ("08-settings", ["-CrabrixTab", "settings", "-crabrix.appearance", "cyberpunk"])
        ]
        for (name, arguments) in frames {
            launch(arguments)
            capture("\(family)-\(name)")
        }

        // Also retain authentic Duo-size frames. The extractor identifies the
        // destination, so a Duo frame is never labelled as an ordinary iPhone.
        launch(["--crabrix-auto-dock=code"])
        capture("workspace-code")
        launch(["--crabrix-auto-dock=output"])
        capture("workspace-output")

        for (id, label) in [
            ("about", "About Crabrix"), ("privacy", "Privacy Policy"),
            ("terms", "Terms of Use"), ("content-license", "Educational content rights"),
            ("source-license", "Application source license")
        ] {
            launch(["-CrabrixTab", "settings"])
            let link = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", label)).firstMatch
            for _ in 0..<20 {
                if link.exists && link.isHittable { break }
                app.swipeUp()
            }
            XCTAssertTrue(link.exists && link.isHittable, "Missing native legal link: \(label)")
            link.tap()
            let copy = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "BUNDLED COPY")).firstMatch
            XCTAssertTrue(copy.waitForExistence(timeout: 15), "The offline document must render: \(id)")
            XCTAssertFalse(app.staticTexts["This document could not be read from the app bundle."].exists)
            capture("legal-\(id)")
        }
    }

    private func launch(_ arguments: [String]) {
        app.terminate()
        // Start as an existing learner, activating the real bundled signed
        // packs. No alternate/fabricated lesson data or UI is supplied.
        app.launchArguments = ["-crabrix.appearance", "dark"] + arguments
        app.launch()
        XCTAssertEqual(app.state, .runningForeground)
        // Academy installation and navigation routing are asynchronous.
        Thread.sleep(forTimeInterval: 12)
    }

    private func capture(_ name: String) {
        XCTAssertEqual(app.state, .runningForeground)
        XCTAssertEqual(app.alerts.count, 0, "Do not publish an alert-covered frame")
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
