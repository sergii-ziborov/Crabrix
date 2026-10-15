import XCTest
import UIKit

/// Runs only in disposable QA simulators, through the actual navigation and
/// native reorder handles. No learner's library is reset or substituted.
@MainActor
final class BuildWorkspaceTests: XCTestCase {
    private let app = XCUIApplication()

    func testCompilerFailureUsesProblemsAndOutputHasNoDuplicateRun() throws {
        launch(["--crabrix-auto-borrow", "--crabrix-auto-dock=problems"])
        let check = app.buttons["Check project"]
        XCTAssertTrue(check.waitForExistence(timeout: 90))
        XCTAssertTrue(app.otherElements["editor-project-name"].exists
                      || app.staticTexts["editor-project-name"].exists)
        check.tap()
        let error = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "E0502")).firstMatch
        XCTAssertTrue(error.waitForExistence(timeout: 240), "The actual bundled compiler error must reach Problems")
        capture("qa-compiler-problems")
        app.buttons["build-dock-output"].tap()
        XCTAssertTrue(app.staticTexts["No output captured"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["PROJECT OUTPUT"].exists)
        XCTAssertFalse(app.buttons["Run again"].exists)
        XCTAssertEqual(app.buttons["Run project"].count, 1, "Keep the single primary toolbar Run control")
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "E0502")).firstMatch.exists)
        capture("qa-compiler-output")
    }

    func testArrangeCodeFitsAndNativeDragDoesNotScrollPage() throws {
        launch(["-CrabrixTab", "learn"])
        // The hosted compiler tests may have classified this simulator as a
        // fresh install before UI testing. Install one course through the real
        // UI so Quick Practice is available in either installation state.
        let download = app.buttons["Download Rust Basics for offline use"]
        if download.waitForExistence(timeout: 12) {
            for _ in 0..<8 {
                if download.isHittable { break }
                app.swipeUp()
            }
            download.tap()
            let confirm = app.buttons.matching(NSPredicate(format: "label MATCHES %@", "^Download [0-9].* (MB|KB|bytes)$")).firstMatch
            XCTAssertTrue(confirm.waitForExistence(timeout: 10))
            confirm.tap()
            let basics = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Open Rust Basics")).firstMatch
            XCTAssertTrue(basics.waitForExistence(timeout: 180))
        }
        let quick = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Quick Practice")).firstMatch
        for _ in 0..<16 {
            if quick.exists && quick.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(quick.exists && quick.isHittable)
        quick.tap()
        let answer = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Describes when a reference is valid")).firstMatch
        XCTAssertTrue(answer.waitForExistence(timeout: 15))
        answer.tap()
        app.buttons["Continue"].tap()
        let check = app.buttons["arrange-check-order"]
        XCTAssertTrue(check.waitForExistence(timeout: 10))
        let list = app.collectionViews["arrange-code-lines"].firstMatch
        let line = { (id: Int) in self.app.staticTexts["arrange-code-line-\(id)"] }
        XCTAssertTrue(line(0).waitForExistence(timeout: 10))
        XCTAssertTrue(check.isHittable)
        for id in 0...3 { XCTAssertTrue(line(id).isHittable, "Every line must fit before dragging") }
        let y = line(0).frame.midY
        line(0).swipeUp(velocity: .slow)
        XCTAssertEqual(line(0).frame.midY, y, accuracy: 3, "A swipe on code must not scroll the exercise")
        let listFrame = list.exists ? list.frame : app.descendants(matching: .any)["arrange-code-lines"].firstMatch.frame
        XCTAssertFalse(listFrame.isEmpty)
        func move(_ id: Int, before target: Int) {
            let from = app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: listFrame.maxX - 23, dy: line(id).frame.midY))
            let to = app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: listFrame.maxX - 23, dy: line(target).frame.minY + 5))
            from.press(forDuration: 0.5, thenDragTo: to)
        }
        move(0, before: 2)
        move(1, before: 2)
        XCTAssertLessThan(line(0).frame.midY, line(1).frame.midY)
        XCTAssertLessThan(line(1).frame.midY, line(2).frame.midY)
        XCTAssertLessThan(line(2).frame.midY, line(3).frame.midY)
        check.tap()
        XCTAssertTrue(app.buttons["Finish"].exists || check.label == "Finish")
        capture("qa-arrange-portrait")
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(check.waitForExistence(timeout: 10))
        XCTAssertTrue(check.isHittable)
        for id in 0...3 { XCTAssertTrue(line(id).isHittable) }
        capture("qa-arrange-landscape")
    }

    private func launch(_ arguments: [String]) {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app.terminate()
        app.launchArguments = ["-crabrix.appearance", "dark"] + arguments
        app.launch()
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
