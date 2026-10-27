import XCTest
import UIKit

/// An actual app editor talks to a second native engine in the independent UI
/// runner process. Browser/native matrix is also exercised by the CLI probe.
@MainActor
final class PlaygroundTests: XCTestCase {
    func testNativeEditorSharesEditsAndSelectionsAndRunsLocally() async throws {
        let origin = URL(string: "http://127.0.0.1:3393")!
        let codec = Bundle(for: Self.self).url(forResource: "PlaygroundCodec", withExtension: "js")!
        let document = PlaygroundDocument(name: "playground-ui-proof", entryFile: "main.rs", files: ["main.rs": "fn main() { println!(\"native-shared-proof\"); }"])
        let peer = try await PlaygroundLiveSession.create(document: document, lifetimeSeconds: 3600, origin: origin, codecURL: codec)
        defer { peer.stop() }
        peer.start()
        let app = XCUIApplication()
        app.launchArguments = ["--crabrix-playground-relay=\(origin.absoluteString)", "--crabrix-auto-playground=\(peer.link.url.absoluteString)", "-crabrix.appearance", "dark"]
        app.launch()
        let editor = app.textViews["Source code editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 45))
        let foundnativesharedproof = await waitForSource(editor, containing: "native-shared-proof")
        XCTAssertTrue(foundnativesharedproof)
        peer.edit(file: "main.rs", text: "fn main() { println!(\"from-second-native\"); }")
        let foundfromsecondnative = await waitForSource(editor, containing: "from-second-native")
        XCTAssertTrue(foundfromsecondnative)
        peer.select(file: "main.rs", range: NSRange(location: 3, length: 4))
        try await Task.sleep(for: .seconds(1))
        capture("playground-native-selection")
        editor.coordinate(withNormalizedOffset: CGVector(dx: 0.32, dy: 0.03)).tap()
        editor.typeText(" //from-app-editor")
        let deadline = Date().addingTimeInterval(20)
        while peer.document?.files["main.rs"]?.contains("from-app-editor") != true, Date() < deadline { try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertTrue(peer.document?.files["main.rs"]?.contains("from-app-editor") == true, "Actual UITextView edits must reach the other native client")
        // Revert to runnable source remotely, then run with the app's real compiler.
        peer.edit(file: "main.rs", text: "fn main() { println!(\"offline-playground-run\"); }")
        let foundofflineplaygroundrun = await waitForSource(editor, containing: "offline-playground-run")
        XCTAssertTrue(foundofflineplaygroundrun)
        if let hide = app.buttons.matching(identifier: "Hide keyboard").allElementsBoundByIndex.first(where: { $0.isHittable }) { hide.tap() }
        app.buttons["Run project"].tap()
        XCTAssertTrue(app.buttons["Run project"].waitForExistence(timeout: 180), "Wait for the local compiler to finish")
        app.buttons["build-dock-output"].tap()
        XCTAssertTrue(app.staticTexts["STDOUT"].waitForExistence(timeout: 15))
        let output = app.staticTexts.matching(NSPredicate(format: "label == %@ OR label == %@", "offline-playground-run", "offline-playground-run\n")).firstMatch
        XCTAssertTrue(output.waitForExistence(timeout: 15), "The actual STDOUT must contain the executed result, not source text")
        capture("playground-native-run")
    }
    private func waitForSource(_ editor: XCUIElement, containing text: String) async -> Bool {
        let deadline = Date().addingTimeInterval(40)
        while Date() < deadline {
            if (editor.value as? String)?.contains(text) == true { return true }
            try? await Task.sleep(for: .milliseconds(200))
        }
        return false
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}

@MainActor
final class PlaygroundTwoDeviceTests: XCTestCase {
    func testTwoRealAppsAndBrowserShareTheSameRoom() async throws {
        struct Fixture: Decodable { let url: URL; let origin: URL? }
        let (data, _) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:3395/fixture")!)
        let fixture = try JSONDecoder().decode(Fixture.self, from: data)
        let app = XCUIApplication()
        app.launchArguments = ["--crabrix-playground-relay=\(fixture.origin?.absoluteString ?? "http://127.0.0.1:3393")", "--crabrix-auto-playground=\(fixture.url.absoluteString)", "-crabrix.appearance", UIDevice.current.userInterfaceIdiom == .pad ? "amber" : "dark"]
        app.launch()
        let editor = app.textViews["Source code editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 45))
        let pad = UIDevice.current.userInterfaceIdiom == .pad
        var deadline = Date().addingTimeInterval(60)
        while Date() < deadline, (editor.value as? String)?.contains(pad ? "from-phone" : "native-pair") != true { try await Task.sleep(for: .milliseconds(200)) }
        XCTAssertTrue((editor.value as? String)?.contains(pad ? "from-phone" : "native-pair") == true)
        editor.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 80, dy: 22)).tap()
        editor.typeText(pad ? " from-pad " : " from-phone ")
        deadline = Date().addingTimeInterval(60)
        while Date() < deadline, (editor.value as? String)?.contains("pair-run") != true { try await Task.sleep(for: .milliseconds(200)) }
        XCTAssertTrue((editor.value as? String)?.contains("pair-run") == true, "Both app edits must reach the shared room and its browser participant")
        let selected = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); selected.name = "pair-\(pad ? "ipad" : "iphone")-editor"; selected.lifetime = .keepAlways; add(selected)
        if let hide = app.buttons.matching(identifier: "Hide keyboard").allElementsBoundByIndex.first(where: { $0.isHittable }) { hide.tap() }
        app.buttons["Run project"].tap()
        XCTAssertTrue(app.buttons["Run project"].waitForExistence(timeout: 180), "Wait for the local compiler to finish")
        app.buttons["build-dock-output"].tap()
        XCTAssertTrue(app.staticTexts["STDOUT"].waitForExistence(timeout: 15))
        let output = app.staticTexts.matching(NSPredicate(format: "label == %@ OR label == %@", "pair-run=42", "pair-run=42\n")).firstMatch
        XCTAssertTrue(output.waitForExistence(timeout: 15))
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); screenshot.name = "pair-\(pad ? "ipad" : "iphone")-run"; screenshot.lifetime = .keepAlways; add(screenshot)
    }
}
