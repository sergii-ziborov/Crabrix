import XCTest
import UIKit

/// Manual screenshot and legal-reader QA. This runs in disposable Xcode Cloud
/// Simulators; it does not install or reset anything on a learner's device.
@MainActor
final class ReleaseScreenshotTests: XCTestCase {
    private let app = XCUIApplication()

    func testAlignedSettingsAndLearnOnPhoneAndIPad() throws {
        continueAfterFailure = true
        let isPad = UIDevice.current.userInterfaceIdiom == .pad
        let orientations: [UIDeviceOrientation] = isPad ? [.portrait, .landscapeLeft] : [.portrait]
        defer { XCUIDevice.shared.orientation = .portrait }

        for orientation in orientations {
            XCUIDevice.shared.orientation = orientation
            let name = "layout-\(isPad ? "ipad" : "iphone")-\(orientation == .portrait ? "portrait" : "landscape")"
            let appearance = ["-crabrix.appearance", "cyberpunk"] // retained Amber Circuit
            launch(["-CrabrixTab", "settings"] + appearance)
            let settings = app.otherElements["settings-section-Appearance"]
            XCTAssertTrue(settings.waitForExistence(timeout: 15))
            let settingsFrame = settings.frame
            print("LAYOUT \(name) Settings=\(settingsFrame), app=\(app.frame)")
            capture(name + "-settings")
            XCTAssertGreaterThan(settingsFrame.width, 250)
            XCTAssertLessThanOrEqual(settingsFrame.width, 851)

            launch(["-CrabrixTab", "learn"] + appearance)
            let course = app.otherElements["learn-course-basics"]
            if !course.exists {
                // A simulator used for first-install tests may correctly have
                // no courses yet. Use the real download flow, preserving its
                // saved learner state and signature verification.
                let download = app.buttons["Download Rust Basics for offline use"]
                if download.waitForExistence(timeout: 10) {
                    download.tap()
                    let confirm = app.buttons.matching(NSPredicate(
                        format: "label MATCHES %@", "^Download [0-9][0-9,. ]* (bytes|KB|MB|GB|TB)$"
                    )).firstMatch
                    XCTAssertTrue(confirm.waitForExistence(timeout: 10))
                    confirm.tap()
                }
            }
            XCTAssertTrue(course.waitForExistence(timeout: 120))
            if orientation == .portrait {
                let update = app.buttons["Update Rust Basics lessons"]
                if update.exists {
                    update.tap()
                    let confirm = app.buttons.matching(NSPredicate(
                        format: "label MATCHES %@", "^Update [0-9][0-9,. ]* (bytes|KB|MB|GB|TB)$"
                    )).firstMatch
                    XCTAssertTrue(confirm.waitForExistence(timeout: 10))
                    confirm.tap()
                    let installed = XCTNSPredicateExpectation(
                        predicate: NSPredicate(format: "exists == false"), object: update
                    )
                    XCTAssertEqual(XCTWaiter.wait(for: [installed], timeout: 180), .completed)
                }
            }
            let courseFrame = course.frame
            print("LAYOUT \(name) Learn=\(courseFrame)")
            XCTAssertEqual(courseFrame.minX, settingsFrame.minX, accuracy: 1)
            XCTAssertEqual(courseFrame.width, settingsFrame.width, accuracy: 1)
            capture(name + "-learn")

            for identifier in ["learn-quick-practice", "learn-term-train", "learn-code-recall"] {
                let card = app.buttons[identifier]
                scrollTo(card)
                XCTAssertTrue(card.exists && card.isHittable)
                XCTAssertGreaterThanOrEqual(card.frame.minX, courseFrame.minX - 1)
                XCTAssertLessThanOrEqual(card.frame.maxX, courseFrame.maxX + 1)
                if !isPad { XCTAssertEqual(card.frame.width, settingsFrame.width, accuracy: 1) }
                else { XCTAssertGreaterThan(card.frame.width, 260) }
            }
            capture(name + "-practice-cards")

            launch(["-CrabrixTab", "learn", "-CrabrixLearn", "basics"] + appearance)
            let courseAction = app.buttons.matching(NSPredicate(
                format: "label IN %@", ["Start course", "Continue course", "Review course from start"]
            )).firstMatch
            XCTAssertTrue(courseAction.waitForExistence(timeout: 20))
            capture(name + "-course")

            launch(["-CrabrixTab", "learn", "-CrabrixLearn", "hello-rust"] + appearance)
            let heading = app.otherElements["lesson-page-heading"]
            XCTAssertTrue(heading.waitForExistence(timeout: 20))
            let step = app.staticTexts["LESSON · STEP 1 OF 3"]
            XCTAssertTrue(step.exists)
            let readingFrame = heading.frame
            print("LAYOUT \(name) Lesson heading=\(readingFrame), step=\(step.frame)")
            XCTAssertEqual(step.frame.minX, readingFrame.minX, accuracy: 2)
            XCTAssertLessThanOrEqual(readingFrame.width, 717)
            capture(name + "-lesson")

            let next = app.buttons["Try a quick check"]
            scrollTo(next)
            XCTAssertTrue(next.exists && next.isHittable)
            print("LAYOUT \(name) Lesson footer=\(next.frame)")
            // Accessibility groups exclude trailing spacers. Derive the
            // reading column's right edge from its actual left edge instead.
            let readingRight = app.frame.maxX - (step.frame.minX - app.frame.minX)
            XCTAssertEqual(next.frame.maxX, readingRight, accuracy: 2)
            XCTAssertGreaterThanOrEqual(next.frame.minX, readingFrame.minX - 2)
            capture(name + "-lesson-footer")
        }
    }

    private func scrollTo(_ element: XCUIElement) {
        for _ in 0..<24 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
    }

    func testDuoDisplayScreenshots() throws {
        continueAfterFailure = false
        for (orientation, name) in [(UIDeviceOrientation.portrait, "portrait"), (.landscapeLeft, "landscape")] {
            XCUIDevice.shared.orientation = orientation
            for tab in ["code", "output"] {
                launch(["--crabrix-auto-dock=\(tab)"])
                let application = XCTAttachment(screenshot: app.screenshot())
                application.name = "duo-\(name)-\(tab)-application"
                application.lifetime = .keepAlways
                add(application)
                for (index, screen) in XCUIScreen.screens.enumerated() {
                    let attachment = XCTAttachment(screenshot: screen.screenshot())
                    attachment.name = "duo-\(name)-\(tab)-screen-\(index)"
                    attachment.lifetime = .keepAlways
                    add(attachment)
                }
            }
        }
    }

    func testReleaseScreenshotsAndLegalReaders() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let family = UIDevice.current.userInterfaceIdiom == .pad ? "ipad-13" : "iphone-6.9"
        launch(["-CrabrixTab", "learn"])
        let basics = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Open Rust Basics")).firstMatch
        XCTAssertTrue(basics.waitForExistence(timeout: 120), "The signed offline transition courses must finish loading")
        try updateTeachingContent()
        launch(["-CrabrixTab", "learn"])
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
            ("08-settings", ["-CrabrixTab", "settings", "-crabrix.appearance", "cyberpunkNeon"])
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

    private func updateTeachingContent() throws {
        let update = app.buttons["Update all"]
        XCTAssertTrue(update.waitForExistence(timeout: 90), "The public catalog must offer the current teaching packs")
        update.tap()
        let confirm = app.buttons.matching(NSPredicate(format: "label MATCHES %@", "^Update [0-9]+ courses$")).firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 10))
        confirm.tap()
        let banner = app.staticTexts["New lessons available"]
        let completed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: banner)
        XCTAssertEqual(XCTWaiter.wait(for: [completed], timeout: 480), .completed,
                       "All installed courses must update before the lesson captures")
        XCTAssertFalse(app.staticTexts["Academy unavailable"].exists)

        // Examples moved into their own downloadable pack. Install it through
        // the real UI rather than silently reusing the old projects archive.
        let examples = app.buttons["Download 46 Code Examples for offline use"]
        for _ in 0..<20 {
            if examples.exists && examples.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(examples.exists && examples.isHittable)
        examples.tap()
        let download = app.buttons.matching(NSPredicate(format: "label MATCHES %@", "^Download [0-9][0-9,. ]* (bytes|KB|MB|GB|TB)$")).firstMatch
        XCTAssertTrue(download.waitForExistence(timeout: 10))
        download.tap()
        XCTAssertTrue(app.buttons["Browse 46 Code Examples, available offline"].waitForExistence(timeout: 180))
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
        let screenshot = XCUIScreen.main.screenshot()
        if name.hasPrefix("layout-") {
            let path = FileManager.default.temporaryDirectory.appendingPathComponent(name + ".png")
            try? screenshot.pngRepresentation.write(to: path)
            print("LAYOUT_IMAGE_PATH \(path.path)")
        }
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
