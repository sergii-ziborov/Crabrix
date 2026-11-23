import XCTest
import UIKit

/// Learn with AI end to end: the Academy library entry, the client picker and
/// copy buttons, the opt-in learning state, the pause and offline notes, the
/// one-time feedback card and "Learn this lesson with AI" on a lesson.
///
/// `-CrabrixAIStatus on|paused|offline` (Debug only) replaces the status
/// request so frames do not depend on the network. Screenshots are XCTest
/// attachments; when `TEST_RUNNER_CRABRIX_AI_SCREENSHOTS` names a directory
/// they are also written there.
@MainActor
final class LearnWithAIUITests: XCTestCase {
    private let app = XCUIApplication()
    private var device: String { UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone" }

    func testLearnWithAIEntryClientsCopyAndLessonSheet() throws {
        continueAfterFailure = true

        // The Academy library keeps every existing section and adds one card.
        launch(["-CrabrixTab", "learn", "-CrabrixAIStatus", "on"])
        ensureBasicsInstalled()
        let entry = app.buttons["learn-with-ai"]
        scrollTo(entry)
        XCTAssertTrue(entry.waitForExistence(timeout: 20), "Learn with AI entry in the Academy library")
        XCTAssertTrue(app.otherElements["learn-course-basics"].exists || app.buttons["learn-open-course-basics"].exists,
                      "existing course rows stay")
        capture("01-library-entry")
        entry.tap()

        XCTAssertTrue(app.staticTexts["Connect your agent"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.otherElements["ai-offline-note"].exists)
        XCTAssertTrue(app.buttons["Open Claude"].exists)
        capture("02-setup-claude")

        // Copy the MCP URL: the button confirms and VoiceOver hears "Copied".
        let copyURL = app.buttons["ai-copy-claude-1"]
        XCTAssertTrue(copyURL.exists)
        XCTAssertEqual(copyURL.label, "Copy the Crabrix Academy MCP URL")
        copyURL.tap()
        XCTAssertTrue(app.buttons["Copied"].waitForExistence(timeout: 2))
        capture("03-copied-url")

        // Only the chosen client's steps are shown.
        app.buttons["ai-client-claude-code"].tap()
        XCTAssertTrue(app.otherElements["ai-steps-claude-code"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.otherElements["ai-steps-claude"].exists)
        XCTAssertTrue(element("claude mcp add --transport http crabrix-academy https://crabrix.com/mcp/academy").exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Claude Code runs on a computer'")).firstMatch.exists)
        XCTAssertTrue(app.buttons["Copy the Claude Code command"].exists)
        capture("04-setup-claude-code")

        app.buttons["ai-client-codex"].tap()
        XCTAssertTrue(app.buttons["Open ChatGPT"].waitForExistence(timeout: 5))
        XCTAssertTrue(element("codex mcp add crabrix-academy --url https://crabrix.com/mcp/academy").exists)
        capture("05-setup-codex")

        app.buttons["ai-client-cursor"].tap()
        let copyJSON = app.buttons["Copy the Cursor configuration JSON"]
        XCTAssertTrue(copyJSON.waitForExistence(timeout: 5))
        copyJSON.tap()
        XCTAssertTrue(app.buttons["Copied"].waitForExistence(timeout: 2))
        capture("06-setup-cursor")

        app.buttons["ai-client-other"].tap()
        XCTAssertTrue(app.otherElements["ai-steps-other"].waitForExistence(timeout: 5))

        // Prompts and the opt-in export.
        let beginner = app.buttons["ai-copy-prompt-beginner"]
        scrollTo(beginner)
        XCTAssertTrue(beginner.exists)
        capture("07-prompts")
        beginner.tap()

        let include = app.switches["ai-include-progress"]
        scrollTo(include)
        XCTAssertTrue(include.exists)
        XCTAssertEqual(include.value as? String, "0", "off by default")
        XCTAssertTrue(app.staticTexts["Off: the file and prompt contain no progress."].exists)
        capture("08-continue-off")
        // The switch itself sits at the trailing edge of the row.
        include.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        XCTAssertEqual(include.value as? String, "1")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'On: '")).firstMatch.waitForExistence(timeout: 3))
        let copyState = app.buttons["ai-copy-state"]
        scrollTo(copyState)
        copyState.tap()
        XCTAssertTrue(app.buttons["Copied"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["ai-share-state"].exists)
        capture("09-continue-on")
        app.buttons["ai-share-state"].tap()
        Thread.sleep(forTimeInterval: 3)
        capture("10-share-sheet")
        dismissShareSheet()

        let limits = app.staticTexts["What your agent can and cannot do"]
        scrollTo(limits)
        capture("11-limits")

        // A later visit after a copy shows the feedback card, once. The
        // argument domain hides any answer left by an earlier run.
        launch(["-CrabrixTab", "learn", "-CrabrixLearn", "with-ai", "-CrabrixAIStatus", "on",
                "-crabrix.ai.feedback.v1", "ui-test-reset"])
        let card = app.otherElements["ai-feedback-card"]
        XCTAssertTrue(card.waitForExistence(timeout: 15), "feedback card after an earlier copy")
        capture("12-feedback-card")
        app.buttons["ai-feedback-partly"].tap()
        XCTAssertTrue(app.textFields["ai-feedback-text"].waitForExistence(timeout: 3)
                      || app.textViews["ai-feedback-text"].exists)
        XCTAssertTrue(app.buttons["Email it"].exists)
        capture("13-feedback-answered")
        app.buttons["Done"].tap()
        XCTAssertFalse(card.waitForExistence(timeout: 2))

        launch(["-CrabrixTab", "learn", "-CrabrixLearn", "with-ai", "-CrabrixAIStatus", "on"])
        XCTAssertTrue(app.staticTexts["Connect your agent"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.otherElements["ai-feedback-card"].exists, "answered: it never returns")

        // Run-time pause and offline.
        launch(["-CrabrixTab", "learn", "-CrabrixLearn", "with-ai", "-CrabrixAIStatus", "paused"])
        XCTAssertTrue(app.otherElements["ai-paused-notice"].waitForExistence(timeout: 15)
                      || app.staticTexts["Learn with AI is paused"].exists)
        XCTAssertFalse(app.buttons["ai-client-claude"].exists, "no setup steps while paused")
        capture("14-paused")

        launch(["-CrabrixTab", "learn", "-CrabrixLearn", "with-ai", "-CrabrixAIStatus", "offline"])
        XCTAssertTrue(app.staticTexts["Offline — you can still copy the steps"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["ai-copy-claude-1"].exists)
        capture("15-offline")

        // Light mode and the largest accessibility text size.
        launch(["-CrabrixTab", "learn", "-CrabrixLearn", "with-ai", "-CrabrixAIStatus", "on"], appearance: "light")
        XCTAssertTrue(app.staticTexts["Connect your agent"].waitForExistence(timeout: 15))
        capture("16-light")
        launch(["-CrabrixTab", "learn", "-CrabrixLearn", "with-ai", "-CrabrixAIStatus", "on",
                "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"])
        XCTAssertTrue(app.buttons["ai-client-claude"].waitForExistence(timeout: 15))
        capture("17-accessibility-text")
        app.buttons["ai-client-claude-code"].tap()
        capture("18-accessibility-text-claude-code")

        // "Learn this lesson with AI" on a lesson: public details only.
        launch(["-CrabrixTab", "learn", "-CrabrixLearn", "variables"])
        XCTAssertTrue(app.otherElements["lesson-page-heading"].waitForExistence(timeout: 20))
        let action = app.buttons["lesson-learn-with-ai"]
        XCTAssertTrue(action.waitForExistence(timeout: 5))
        capture("19-lesson-with-action")
        action.tap()
        let prompt = app.descendants(matching: .any)["ai-lesson-prompt"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 5))
        XCTAssertTrue(prompt.label.contains("courseId \"basics\", lessonId \"variables\""), prompt.label)
        XCTAssertTrue(prompt.label.contains("https://crabrix.com/learn/basics/variables/"), prompt.label)
        XCTAssertTrue(app.buttons["ai-lesson-open-claude"].exists)
        capture("20-lesson-sheet")
        app.buttons["ai-copy-lesson-prompt"].tap()
        XCTAssertTrue(app.buttons["Copied"].waitForExistence(timeout: 2))
        app.buttons["ai-client-codex"].tap()
        XCTAssertTrue(app.buttons["ai-lesson-open-codex"].waitForExistence(timeout: 3))
        app.buttons["ai-client-cursor"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Cursor runs on a computer'")).firstMatch.waitForExistence(timeout: 3))
        capture("21-lesson-sheet-cursor")
        let setup = app.buttons["ai-lesson-open-setup"]
        scrollTo(setup)
        setup.tap()
        XCTAssertTrue(app.staticTexts["Connect your agent"].waitForExistence(timeout: 10))
        let sheetInclude = app.switches["ai-include-progress"]
        scrollTo(sheetInclude)
        XCTAssertTrue(element("Includes the lesson you came from: basics/variables").exists)
        capture("22-lesson-sheet-setup")
    }

    // MARK: Helpers

    /// Any element with exactly this label; selectable text is not always a static text.
    private func element(_ label: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    private func ensureBasicsInstalled() {
        let course = app.otherElements["learn-course-basics"]
        if course.waitForExistence(timeout: 8) { return }
        // A fresh Simulator has no courses yet: use the real signed download.
        let download = app.buttons["Download Rust Basics for offline use"]
        scrollTo(download)
        guard download.waitForExistence(timeout: 10) else { return }
        download.tap()
        let confirm = app.buttons.matching(NSPredicate(
            format: "label MATCHES %@", "^Download [0-9][0-9,. ]* (bytes|KB|MB|GB|TB)$"
        )).firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 10))
        confirm.tap()
        app.swipeDown()
        XCTAssertTrue(course.waitForExistence(timeout: 180), "Rust Basics installs")
    }

    private func dismissShareSheet() {
        let close = app.buttons["Close"]
        if close.waitForExistence(timeout: 2) {
            close.tap()
        } else {
            app.swipeDown(velocity: .fast)
        }
        Thread.sleep(forTimeInterval: 1)
    }

    private func scrollTo(_ element: XCUIElement) {
        for _ in 0..<14 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
    }

    private func launch(_ arguments: [String], appearance: String = "dark") {
        app.terminate()
        app.launchArguments = ["-crabrix.appearance", appearance] + arguments
        app.launch()
        XCTAssertEqual(app.state, .runningForeground)
        Thread.sleep(forTimeInterval: 6)
    }

    private func capture(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let file = "learn-with-ai-\(device)-\(name).png"
        if let directory = ProcessInfo.processInfo.environment["CRABRIX_AI_SCREENSHOTS"], !directory.isEmpty {
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
