import XCTest
import UIKit

@MainActor
final class RustDebuggerUITests: XCTestCase {
    func testDebuggerControlsSourceAndSharingOnNativeDevice() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--crabrix-auto-debug-fixture", "-crabrix.appearance", UIDevice.current.userInterfaceIdiom == .pad ? "cyberpunk" : "dark"]
        app.launch()
        let editor = app.textViews["Source code editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 60))
        openProjectSettings(app)
        let debug = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Debug Rust project")).firstMatch
        XCTAssertTrue(debug.waitForExistence(timeout: 15)); debug.tap()
        try waitLine(6, in: app, timeout: 120)
        app.buttons["Add breakpoint at line 8"].tap()
        capture("native-breakpoint-set")
        XCTAssertTrue(app.buttons["Remove breakpoint at line 8"].waitForExistence(timeout: 5), app.debugDescription)
        app.buttons["Step over"].tap(); try waitLine(7, in: app)
        app.buttons["Continue"].tap(); try waitLine(8, in: app)
        app.buttons["Step into"].tap(); try waitLine(2, in: app)
        app.buttons["Step over"].tap(); try waitLine(3, in: app)
        capture("native-debug-code")
        app.buttons["Inspect debugger state"].tap()
        XCTAssertTrue(app.staticTexts["Call stack"].waitForExistence(timeout: 10))
        let local = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'c' AND label CONTAINS 'i32' AND label CONTAINS '1'")).firstMatch
        XCTAssertTrue(local.waitForExistence(timeout: 10), "The actual primitive local c must be 1")
        capture("native-debug-locals")
        app.buttons["Close debugger state"].tap()
        app.buttons["Step out"].tap(); try waitLine(9, in: app)
        app.buttons["Remove breakpoint at line 8"].tap()
        app.buttons["Continue"].tap()
        XCTAssertTrue(app.buttons["Run project"].waitForExistence(timeout: 60))
        app.buttons["build-dock-output"].tap()
        XCTAssertTrue(app.staticTexts["STDOUT"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label == %@ OR label == %@", "total=6", "total=6\n")).firstMatch.waitForExistence(timeout: 10))
        capture("native-debug-finished")
        app.buttons["build-dock-code"].tap()
        XCTAssertFalse((editor.value as? String ?? "").contains("__crabrix_debug"), "Generated Debug code must never replace the editable source")
        openProjectSettings(app)
        let share = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Share a Playground")).firstMatch
        XCTAssertTrue(share.waitForExistence(timeout: 10)); share.tap()
        let hour = app.segmentedControls.buttons["1 hour"]
        XCTAssertTrue(hour.waitForExistence(timeout: 15)); XCTAssertTrue(hour.isSelected)
        capture("native-share-one-hour")
        app.buttons["Close Playground sharing"].tap()
    }
    private func openProjectSettings(_ app: XCUIApplication) {
        if app.buttons["Project menu"].exists { app.buttons["Project menu"].tap() }
        if app.buttons["PROJECT"].exists { app.buttons["PROJECT"].tap(); app.buttons["Project Details & Share"].tap(); return }
        let settings = app.buttons["Project settings and share"]
        if settings.waitForExistence(timeout: 10) { settings.tap() }
    }
    private func waitLine(_ line: Int, in app: XCUIApplication, timeout: TimeInterval = 20) throws {
        let label = app.staticTexts["debugger-location"]
        let predicate = NSPredicate(format: "label CONTAINS %@", "main.rs:\(line) ·")
        let result = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: label)], timeout: timeout)
        XCTAssertEqual(result, .completed, "Debugger must pause at the actual source line \(line)")
        if result != .completed { capture("native-debug-failure-\(line)"); let details = XCTAttachment(string: app.debugDescription); details.lifetime = .keepAlways; add(details); throw NSError(domain: "RustDebuggerUITest", code: line) }
    }
    private func capture(_ name: String) { let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); image.name = name; image.lifetime = .keepAlways; add(image) }
}
