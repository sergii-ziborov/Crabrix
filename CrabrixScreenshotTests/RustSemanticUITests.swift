import XCTest
import UIKit

@MainActor
final class BrowserTypeScriptUITests: XCTestCase {
    func testCheckShowsRealTypeErrorAndRunRemainsAvailableWithEditorTabsIntact() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--crabrix-auto-typescript-fixture", "-crabrix.appearance", UIDevice.current.userInterfaceIdiom == .pad ? "cyberpunkNeon" : "cyberpunk"]
        app.launch()
        let editor = app.textViews["Source code editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 60))
        let original = editor.value as? String
        app.buttons["Check project"].tap()
        let problems = app.buttons["build-dock-problems"]
        XCTAssertTrue(problems.waitForExistence(timeout: 30)); problems.tap()
        let error = app.buttons.matching(NSPredicate(format:"label CONTAINS %@", "TS2322")).firstMatch
        XCTAssertTrue(error.waitForExistence(timeout: 40), app.debugDescription)
        XCTAssertTrue(error.label.contains("main.ts:1:"),error.label)
        XCTAssertFalse(app.staticTexts["Tap to analyze this rustc error on device"].exists)
        XCTAssertFalse(app.staticTexts["This project has no Cargo.toml."].exists)
        XCTAssertTrue(app.staticTexts["Browser · local"].exists)
        let screen=app.frame
        XCTAssertGreaterThanOrEqual(error.frame.minX,0); XCTAssertLessThanOrEqual(error.frame.maxX,screen.maxX+1)
        let capture=XCTAttachment(screenshot:XCUIScreen.main.screenshot()); capture.name="typescript-diagnostic";capture.lifetime = .keepAlways;add(capture)
        XCTAssertTrue(app.buttons["Run project"].isEnabled,"Optional AI advice must not lock independent browser Run")
        let advisor=app.buttons.matching(NSPredicate(format:"label CONTAINS %@","Tap to analyze this diagnostic on device")).firstMatch
        XCTAssertTrue(advisor.exists,app.debugDescription);advisor.tap()
        XCTAssertTrue(app.staticTexts["On-device web diagnostic advisor"].waitForExistence(timeout:15),app.debugDescription)
        XCTAssertFalse(app.staticTexts["On-device Rust diagnostic advisor"].exists)
        XCTAssertFalse(app.buttons["Reinforce with micro-practice"].exists)
        let help=XCTAttachment(screenshot:XCUIScreen.main.screenshot());help.name="typescript-help";help.lifetime = .keepAlways;add(help)
        app.buttons["Close compiler help"].tap()
        XCTAssertTrue(error.waitForExistence(timeout:15))
        error.tap()
        XCTAssertTrue(editor.waitForExistence(timeout:15));XCTAssertEqual(editor.value as? String,original)
        for identifier in ["build-dock-code","build-dock-problems","build-dock-output","build-dock-terminal"]{XCTAssertTrue(app.buttons[identifier].exists,identifier)}
    }
}

@MainActor
final class ProjectPreflightUITests: XCTestCase {
    func testReportOpensFromFilesAndReturnsToTheUnchangedEditor() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--crabrix-auto-semantic-fixture", "-crabrix.appearance", UIDevice.current.userInterfaceIdiom == .pad ? "cyberpunkNeon" : "cyberpunk"]
        app.launch()
        let editor = app.textViews["Source code editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 60))
        let original = editor.value as? String
        if app.buttons["Show files"].exists { app.buttons["Show files"].tap() }
        let button = app.buttons["project-preflight"]
        for _ in 0..<8 where !button.isHittable { app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(button.isHittable, app.debugDescription); button.tap()
        let check = app.descendants(matching: .any)["preflight-check"]
        XCTAssertTrue(check.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(check.label.contains("Unverified"), check.label)
        let scroll = app.scrollViews.firstMatch
        let debug = app.descendants(matching: .any)["preflight-debug"]
        for _ in 0..<8 where !debug.isHittable { scroll.swipeUp() }
        XCTAssertTrue(debug.exists, app.debugDescription)
        let screen = app.frame
        for identifier in ["preflight-check", "preflight-build", "preflight-run", "preflight-debug"] {
            let row = app.descendants(matching: .any)[identifier]
            XCTAssertTrue(row.exists, identifier)
            XCTAssertGreaterThanOrEqual(row.frame.minX, 0)
            XCTAssertLessThanOrEqual(row.frame.maxX, screen.maxX + 1)
        }
        let capture = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        capture.name = "project-preflight"; capture.lifetime = .keepAlways; add(capture)
        app.buttons["Close project preflight"].tap()
        if app.buttons["Hide files"].exists { app.buttons["Hide files"].tap() }
        if app.buttons["Close Project files"].exists { app.buttons["Close Project files"].tap() }
        XCTAssertTrue(editor.waitForExistence(timeout: 15))
        XCTAssertEqual(editor.value as? String, original)
        for identifier in ["build-dock-code", "build-dock-problems", "build-dock-output", "build-dock-terminal"] {
            XCTAssertTrue(app.buttons[identifier].exists, identifier)
        }
    }
}

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
