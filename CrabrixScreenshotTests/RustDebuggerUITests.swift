import XCTest
import UIKit

@MainActor
final class RustDebuggerUITests: XCTestCase {
    func testRustToolsMenuTerminalAndUndoKeepDockAndSource() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--crabrix-auto-rust-tools-fixture", "-crabrix.appearance", "cyberpunk"]
        app.launch()
        let editor = app.textViews["Source code editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 60))
        let original = editor.value as? String
        openProjectSettings(app)
        let format = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Format current Rust file")).firstMatch
        if !format.isHittable { app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(format.waitForExistence(timeout: 10)); format.tap()
        XCTAssertTrue(app.buttons["Run project"].waitForExistence(timeout: 60))
        XCTAssertNotEqual(editor.value as? String, original)
        XCTAssertTrue((editor.value as? String ?? "").contains("Keep this comment 🦀"))
        capture("native-rustfmt-source")
        openProjectSettings(app)
        let undo = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Undo formatting")).firstMatch
        for _ in 0..<3 where !undo.isHittable { app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(undo.waitForExistence(timeout: 10)); undo.tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        XCTAssertEqual(editor.value as? String, original)
        app.buttons["build-dock-terminal"].tap()
        let input = app.textFields["Terminal command"]
        XCTAssertTrue(input.waitForExistence(timeout: 10)); input.tap(); input.typeText("cargo test\n")
        let summary = app.staticTexts["SELECTED-ENTRY UNIT TESTS"]
        XCTAssertTrue(summary.waitForExistence(timeout: 120), app.debugDescription)
        XCTAssertTrue(app.staticTexts["PASSED"].exists)
        XCTAssertTrue(app.staticTexts["FAILED"].exists)
        capture("native-unit-test-results")
        app.buttons["build-dock-code"].tap()
        XCTAssertEqual(editor.value as? String, original)
        for tab in ["build-dock-code", "build-dock-problems", "build-dock-output", "build-dock-terminal"] {
            XCTAssertTrue(app.buttons[tab].exists)
        }
    }
    func testSaveFailureAndRecoveryActionsKeepTheEditorIntact() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--crabrix-auto-save-failure-fixture"]
        app.launch()
        let editor = app.textViews["Source code editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 60))
        let original = editor.value as? String
        let status = app.buttons["Save failed"]
        XCTAssertTrue(status.waitForExistence(timeout: 15))
        status.tap()
        XCTAssertTrue(app.alerts["Save failed"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.alerts.buttons["Save project to Files…"].exists)
        XCTAssertTrue(app.alerts.buttons["Export current file…"].exists)
        capture("save-failure-recovery-actions")
        app.alerts.buttons["Retry save"].tap()
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        XCTAssertEqual(editor.value as? String, original)
        status.tap()
        app.alerts.buttons["Export current file…"].tap()
        // The rescue uses the same native sharing surface as the project ZIP;
        // Save to Files is available there without a second file-export modal.
        let close = app.buttons["Close"].firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: 15), app.debugDescription)
        capture("save-failure-file-export")
        close.tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        XCTAssertEqual(editor.value as? String, original)
    }
    func testIncludedWebResourcesBreakpointAndOfflinePreview() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--crabrix-auto-debug-web-fixture"]
        app.launch()
        let editor = app.textViews["Source code editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 60))
        XCTAssertTrue((editor.value as? String ?? "").contains("include_str!"))
        if UIDevice.current.userInterfaceIdiom == .phone {
            let edge = editor.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 4, dy: 145))
            let destination = editor.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 220, dy: 145))
            edge.press(forDuration: 0.1, thenDragTo: destination)
            XCTAssertTrue(app.buttons["Close project files"].waitForExistence(timeout: 8), "The edge swipe must still open Files")
            app.buttons["Close project files"].tap()
        }
        let addBreakpoint = app.buttons["Add breakpoint at line 7"]
        let removeBreakpoint = app.buttons["Remove breakpoint at line 7"]
        addBreakpoint.tap()
        XCTAssertTrue(removeBreakpoint.waitForExistence(timeout: 5), app.debugDescription)
        capture("debug-web-resources-breakpoint-set")
        openProjectSettings(app)
        let debug = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Debug Rust project")).firstMatch
        XCTAssertTrue(debug.waitForExistence(timeout: 15)); debug.tap()
        try waitLine(5, in: app, timeout: 120)
        XCTAssertTrue(removeBreakpoint.exists, "The breakpoint must survive Debug preparation")
        app.buttons["Continue"].tap(); try waitLine(7, in: app)
        capture("debug-web-resources-breakpoint")
        app.buttons["Step over"].tap(); try waitLine(8, in: app)
        app.buttons["Remove breakpoint at line 7"].tap()
        app.buttons["Continue"].tap()
        XCTAssertTrue(app.buttons["Run project"].waitForExistence(timeout: 60))
        app.buttons["build-dock-output"].tap()
        XCTAssertTrue(app.staticTexts["OFFLINE WEB PREVIEW"].waitForExistence(timeout: 15))
        let counter = app.webViews.buttons["Clicks: 0"].firstMatch
        XCTAssertTrue(counter.waitForExistence(timeout: 20), app.debugDescription)
        counter.tap()
        XCTAssertTrue(app.webViews.buttons["Clicks: 1"].firstMatch.waitForExistence(timeout: 10), "Generated JavaScript must execute after Debug")
        capture("debug-web-resources-preview")
    }
    func testNormalEditorStillAcceptsTouchAndTyping() {
        let app = XCUIApplication(); app.launchArguments = ["--crabrix-auto-debug-fixture"]; app.launch()
        let editor = app.textViews["Source code editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 60))
        editor.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 120, dy: 25)).tap()
        if !app.keyboards.firstMatch.waitForExistence(timeout: 3) {
            // A fresh fixture can finish replacing its document after the first
            // AX tree. Re-tap the real editor once its final layout is present.
            editor.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15)).tap()
        }
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 8), app.debugDescription)
        editor.typeText("focus_proof")
        XCTAssertTrue((editor.value as? String ?? "").contains("focus_proof"))
    }
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
    func testAggregateLocalsFitNativeInspector() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--crabrix-auto-debug-values-fixture", "-crabrix.appearance", "light"]
        app.launch()
        XCTAssertTrue(app.textViews["Source code editor"].waitForExistence(timeout: 60))
        openProjectSettings(app)
        let debug = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Debug Rust project")).firstMatch
        XCTAssertTrue(debug.waitForExistence(timeout: 15), app.debugDescription)
        debug.tap()
        try waitLine(3, in: app, timeout: 120)
        app.buttons["Add breakpoint at line 6"].tap()
        app.buttons["Continue"].tap(); try waitLine(6, in: app)
        app.buttons["Inspect debugger state"].tap()
        XCTAssertTrue(app.staticTexts["Locals"].waitForExistence(timeout: 10))
        for expected in ["Ferris 🦀", "[len=3] [1, 2, 42]", "scores: [len=2] [7, 8]"] {
            let value = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", expected)).firstMatch
            XCTAssertTrue(value.waitForExistence(timeout: 10), "Actual aggregate preview missing: \(expected)")
        }
        capture("native-debug-aggregate-locals")
        XCTAssertTrue(app.buttons["Close debugger state"].isHittable)
        app.buttons["Close debugger state"].tap()
        app.buttons["Remove breakpoint at line 6"].tap()
        app.buttons["Continue"].tap()
        XCTAssertTrue(app.buttons["Run project"].waitForExistence(timeout: 60))
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
