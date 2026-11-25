import XCTest

/// Learn with AI from top to bottom, page by page, in light mode: with the
/// one-time feedback card and before connecting, then connected. The frames
/// are for reviewing the layout; the checks keep the main pieces in place.
///
/// `CRABRIX_AI_DESIGN_SCREENSHOTS` (as `TEST_RUNNER_CRABRIX_AI_DESIGN_SCREENSHOTS`)
/// names a directory for the PNGs.
@MainActor
final class LearnWithAIDesignUITests: XCTestCase {
    private let app = XCUIApplication()

    func testLearnWithAIPageByPage() throws {
        continueAfterFailure = true
        app.launchArguments = [
            "-crabrix.appearance", "light", "-CrabrixTab", "learn", "-CrabrixLearn", "with-ai",
            "-CrabrixAIStatus", "on", "-CrabrixLearningLinkStub",
            // A copy was made earlier and the question is still open.
            "-crabrix.ai.firstCopyAt.v1", "1764000000", "-crabrix.ai.feedback.v1", "",
        ]
        app.launch()

        let connect = app.buttons["link-connect"]
        XCTAssertTrue(connect.waitForExistence(timeout: 60))
        XCTAssertTrue(app.otherElements["ai-feedback-card"].exists, "the feedback card shows after a copy")
        Thread.sleep(forTimeInterval: 1)
        tour("a-start")

        scrollToTop()
        scrollTo(connect)
        connect.tap()
        let confirm = app.buttons["link-confirm-connect"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10))
        capture("b-confirm-1")
        scrollTo(confirm)
        capture("b-confirm-2")
        confirm.tap()
        XCTAssertTrue(app.descendants(matching: .any)["link-url"].waitForExistence(timeout: 15))
        Thread.sleep(forTimeInterval: 1)
        scrollToTop()
        tour("c-connected")
    }

    /// The whole page in screen-high steps.
    private func tour(_ name: String) {
        scrollToTop()
        var previous = Data()
        for page in 1...14 {
            let shot = XCUIScreen.main.screenshot()
            // The same picture twice: the page did not move, so it ended.
            if shot.pngRepresentation == previous { break }
            previous = shot.pngRepresentation
            save(shot, "\(name)-\(String(format: "%02d", page))")
            app.swipeUp()
            Thread.sleep(forTimeInterval: 0.8)
        }
    }

    private func scrollToTop() {
        for _ in 0..<12 { app.swipeDown(velocity: .fast) }
        Thread.sleep(forTimeInterval: 0.8)
    }

    private func scrollTo(_ element: XCUIElement) {
        for _ in 0..<14 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
    }

    private func capture(_ name: String) {
        save(XCUIScreen.main.screenshot(), name)
    }

    private func save(_ screenshot: XCUIScreenshot, _ name: String) {
        let file = "learn-with-ai-design-\(name).png"
        if let directory = ProcessInfo.processInfo.environment["CRABRIX_AI_DESIGN_SCREENSHOTS"], !directory.isEmpty {
            let url = URL(fileURLWithPath: directory).appendingPathComponent(file)
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? screenshot.pngRepresentation.write(to: url)
        }
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = file
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
