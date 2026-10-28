import XCTest
import UIKit

@MainActor
final class RustSemanticUITests: XCTestCase {
    func testActualCompletionImportPreviewAndEditorGeometry() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--crabrix-auto-semantic-fixture", "-crabrix.appearance", UIDevice.current.userInterfaceIdiom == .pad ? "cyberpunkNeon" : "cyberpunk"]
        app.launch()
        let editor = app.textViews["Source code editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 60), app.debugDescription)
        let before = editor.value as? String
        openSettings(app)
        let symbols = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Rust symbols")).firstMatch
        let settings = app.scrollViews["project-settings-scroll"]
        for _ in 0..<8 where !symbols.isHittable { settings.swipeUp() }
        XCTAssertTrue(symbols.isHittable, app.debugDescription); symbols.tap()
        let operation = app.descendants(matching: .any).matching(identifier: "semantic-operation").firstMatch
        XCTAssertTrue(operation.waitForExistence(timeout: 30), app.debugDescription)
        let ready = NSPredicate(format: "enabled == true")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: ready, object: operation)], timeout: 30), .completed)
        operation.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let complete = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Complete this symbol")).firstMatch
        XCTAssertTrue(complete.waitForExistence(timeout: 10), app.debugDescription)
        complete.tap()
        let completion = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Widget")).firstMatch
        XCTAssertTrue(completion.waitForExistence(timeout: 35), app.debugDescription); completion.tap()
        let apply = app.buttons["semantic-apply"]
        XCTAssertTrue(apply.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Review changes in 1 file"].exists)
        capture("semantic-auto-import-preview")
        let scroll = app.scrollViews.firstMatch
        for _ in 0..<10 where !apply.isHittable { scroll.swipeUp() }
        XCTAssertTrue(apply.isHittable, app.debugDescription); apply.tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 15))
        let after = editor.value as? String ?? ""
        XCTAssertNotEqual(after, before)
        XCTAssertTrue(after.contains("use") && after.contains("models::Widget"), after)
        XCTAssertTrue(after.contains("value: Widget"), after)
        for identifier in ["build-dock-code", "build-dock-problems", "build-dock-output", "build-dock-terminal"] {
            XCTAssertTrue(app.buttons[identifier].exists, identifier)
        }
        capture("semantic-editor-return")
        openSettings(app)
        let undo = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Undo symbol changes")).firstMatch
        for _ in 0..<8 where !undo.isHittable { settings.swipeUp() }
        XCTAssertTrue(undo.isHittable, app.debugDescription); undo.tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 15))
        XCTAssertEqual(editor.value as? String, before)
    }
    private func openSettings(_ app: XCUIApplication) {
        if app.buttons["Project menu"].exists { app.buttons["Project menu"].tap() }
        if app.buttons["PROJECT"].exists { app.buttons["PROJECT"].tap(); app.buttons["Project Details & Share"].tap(); return }
        let settings = app.buttons["Project settings and share"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10)); settings.tap()
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
