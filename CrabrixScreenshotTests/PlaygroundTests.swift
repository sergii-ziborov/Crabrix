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
    func testHTTPSLinkOpensFreshRoomWithoutAutoOpenArguments() async throws {
        let nonce = "https-link-" + UUID().uuidString
        let codec = Bundle(for: Self.self).url(forResource: "PlaygroundCodec", withExtension: "js")!
        let document = PlaygroundDocument(name: nonce, entryFile: "main.rs", files: ["main.rs": "fn main(){println!(\"\(nonce)\");}\n"])
        let owner = try await PlaygroundLiveSession.create(document: document, lifetimeSeconds: 3600, origin: URL(string: "https://crabrix.com"), codecURL: codec)
        defer { owner.stop() }
        owner.start()
        let app = XCUIApplication(); app.launchArguments = ["-crabrix.appearance", "dark"]; app.launch()
        app.open(owner.link.url)
        let editor = app.textViews["Source code editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 45))
        let deadline = Date().addingTimeInterval(45)
        while Date() < deadline, (editor.value as? String)?.contains(nonce) != true { try await Task.sleep(for: .milliseconds(200)) }
        XCTAssertTrue((editor.value as? String)?.contains(nonce) == true, "The HTTPS entry point must load this new room, rather than a previous project")
        let capture = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); capture.name = "https-new-room"; capture.lifetime = .keepAlways; add(capture)
        try await owner.closeRoom()
    }

    /// Two independently running app editors and the production website share
    /// source/presence; each debugger executes on its own device.
    func testLinksSelectionsAndDebugAcrossTwoAppsAndWebsite() async throws {
        struct Fixture: Decodable { let url: URL; let nonce: String }
        let base = URL(string: "http://127.0.0.1:3395")!
        let (data, _) = try await URLSession.shared.data(from: base.appendingPathComponent("fixture"))
        let fixture = try JSONDecoder().decode(Fixture.self, from: data)
        let pad = UIDevice.current.userInterfaceIdiom == .pad
        let role = pad ? "pad" : "phone"
        func report(_ event: String) async throws {
            var request = URLRequest(url: base.appendingPathComponent("event")); request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["role": role, "event": event])
            _ = try await URLSession.shared.data(for: request)
        }
        func waitSource(_ editor: XCUIElement, _ text: String) async throws {
            let until = Date().addingTimeInterval(120)
            while Date() < until {
                if editor.exists, (editor.value as? String)?.contains(text) == true { return }
                try await Task.sleep(for: .milliseconds(200))
            }
            XCTFail("Shared source missing: \(text)"); throw NSError(domain: "CrossClient", code: 1)
        }
        func capture(_ name: String) {
            let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            image.name = "cross-\(role)-\(name)"; image.lifetime = .keepAlways; add(image)
        }
        let app = XCUIApplication()
        app.launchArguments = ["-crabrix.appearance", pad ? "amber" : "dark"]
        app.launch()
        // Exercise the production URL handler rather than the auto-open fixture.
        let native = fixture.url.absoluteString.replacingOccurrences(of: "https://crabrix.com/playground/", with: "crabrix://playground/")
        app.open(URL(string: native)!)
        let editor = app.textViews["Source code editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 45))
        try await waitSource(editor, fixture.nonce)
        try await report("opened-link")
        if pad { try await waitSource(editor, "from-phone") }
        editor.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 120, dy: 25)).tap()
        if !app.keyboards.firstMatch.waitForExistence(timeout: 3) { editor.tap() }
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 8))
        editor.typeText(" from-\(role) ")
        // Native UITextView selection must reach the other peers as a range.
        editor.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 115, dy: 25)).doubleTap()
        try await report("selected")
        let selectionDeadline = Date().addingTimeInterval(60)
        while Date() < selectionDeadline {
            let (phaseData, _) = try await URLSession.shared.data(from: base.appendingPathComponent("phase"))
            if let value = try JSONSerialization.jsonObject(with: phaseData) as? [String: String], value["phase"] == "selection-ready" { break }
            try await Task.sleep(for: .milliseconds(200))
        }
        capture("selection")
        try await report("selection-captured")
        try await waitSource(editor, "shared-debug")
        if let hide = app.buttons.matching(identifier: "Hide keyboard").allElementsBoundByIndex.first(where: { $0.isHittable }) { hide.tap() }
        if app.buttons["Project menu"].exists { app.buttons["Project menu"].tap() }
        if app.buttons["PROJECT"].exists { app.buttons["PROJECT"].tap(); app.buttons["Project Details & Share"].tap() }
        else { app.buttons["Project settings and share"].tap() }
        let debug = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Debug Rust project")).firstMatch
        XCTAssertTrue(debug.waitForExistence(timeout: 10)); debug.tap()
        let location = app.staticTexts["debugger-location"]
        func waitLine(_ line: Int) throws {
            let predicate = NSPredicate(format: "label CONTAINS %@", "main.rs:\(line) ·")
            let result = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: location)], timeout: 120)
            XCTAssertEqual(result, .completed)
            if result != .completed { throw NSError(domain: "CrossClientDebug", code: line) }
        }
        try waitLine(2)
        app.buttons["Step over"].tap(); try waitLine(3)
        app.buttons["Step over"].tap(); try waitLine(4)
        app.buttons["Inspect debugger state"].tap()
        let preview = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "shared-debug")).firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 10))
        let vector = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "[len=2] [2, 40]")).firstMatch
        XCTAssertTrue(vector.waitForExistence(timeout: 10)); capture("debug-values")
        app.buttons["Close debugger state"].tap()
        try await report("debug-paused")
        XCTAssertTrue(app.buttons["Run project"].waitForExistence(timeout: 120), "Remote edits cancel stale local Debug")
        XCTAssertFalse(app.buttons["Step over"].exists)
        app.buttons["build-dock-code"].tap()
        try await waitSource(editor, "shared-final=42")
        try await report("debug-stopped")
        app.buttons["Run project"].tap()
        XCTAssertTrue(app.buttons["Run project"].waitForExistence(timeout: 180))
        app.buttons["build-dock-output"].tap()
        let output = app.staticTexts.matching(NSPredicate(format: "label == %@ OR label == %@", "shared-final=42", "shared-final=42\n")).firstMatch
        XCTAssertTrue(output.waitForExistence(timeout: 15)); capture("local-output")
        // The HTTPS link must also be accepted by the app's link entry point.
        app.open(fixture.url)
        XCTAssertTrue(app.buttons["build-dock-code"].waitForExistence(timeout: 15))
        app.buttons["build-dock-code"].tap()
        try await waitSource(editor, "shared-final=42")
        try await report("done")
    }

    func testTwoRealAppsAndBrowserShareTheSameRoom() async throws {
        struct Fixture: Decodable { let url: URL; let origin: URL?; let nonce: String? }
        let (data, _) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:3395/fixture")!)
        let fixture = try JSONDecoder().decode(Fixture.self, from: data)
        let app = XCUIApplication()
        app.launchArguments = ["--crabrix-playground-relay=\(fixture.origin?.absoluteString ?? "http://127.0.0.1:3393")", "--crabrix-auto-playground=\(fixture.url.absoluteString)", "-crabrix.appearance", UIDevice.current.userInterfaceIdiom == .pad ? "amber" : "dark"]
        app.launch()
        let editor = app.textViews["Source code editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 45))
        let pad = UIDevice.current.userInterfaceIdiom == .pad
        var deadline = Date().addingTimeInterval(60)
        if let nonce = fixture.nonce {
            while Date() < deadline, (editor.value as? String)?.contains(nonce) != true { try await Task.sleep(for: .milliseconds(200)) }
            XCTAssertTrue((editor.value as? String)?.contains(nonce) == true, "Wait for this room, not a persisted source copy from an earlier run")
        }
        deadline = Date().addingTimeInterval(60)
        while Date() < deadline, (editor.value as? String)?.contains(pad ? "from-phone" : "native-pair") != true { try await Task.sleep(for: .milliseconds(200)) }
        XCTAssertTrue((editor.value as? String)?.contains(pad ? "from-phone" : "native-pair") == true)
        editor.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 120, dy: 25)).tap()
        if !app.keyboards.firstMatch.waitForExistence(timeout: 5) { editor.tap() }
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 8), app.debugDescription)
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
