import CryptoKit
import XCTest
import UIKit

/// Learning links end to end: "Connect my progress" in Learn with AI, the
/// confirmation before the first upload, the personal URL and client steps,
/// "From your AI tutor" in the Learn library, Open, Dismiss and Disconnect.
///
/// `-CrabrixLearningLinkStub` (Debug only) answers the learning-link API in
/// the app, and `-CrabrixAIStatus on` replaces the status request, so no frame
/// reaches the network for the link. Screenshots are XCTest attachments; when
/// `TEST_RUNNER_CRABRIX_LINK_SCREENSHOTS` names a directory they are also
/// written there.
///
/// `testEndToEndAgainstWebsiteAndMCP` runs only when
/// `TEST_RUNNER_CRABRIX_LINK_E2E_SITE` and `…_E2E_MCP` name the website and the
/// MCP origin: `https://crabrix.com` for production (the app's own default), or
/// a loopback website and `crabrix serve-http` (Debug override). The test link
/// is always deleted, by the app's Disconnect or, after a failure, by teardown.
@MainActor
final class LearningLinkUITests: XCTestCase {
    private let app = XCUIApplication()
    private var device: String { UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone" }
    /// Deletes an end-to-end test link that the app could not disconnect.
    private var deleteTestLink: (() async -> Void)?

    override func tearDown() async throws {
        if let deleteTestLink {
            await deleteTestLink()
            self.deleteTestLink = nil
        }
        try await super.tearDown()
    }

    func testConnectMyProgressTutorCardAndDisconnect() throws {
        continueAfterFailure = true
        launch(["-CrabrixTab", "learn", "-CrabrixAIStatus", "on", "-CrabrixLearningLinkStub"])
        ensureBasicsInstalled()
        XCTAssertFalse(app.otherElements["tutor-card"].exists, "no card before connecting")
        openLearnWithAI()

        // Not connected: what is and is not shared, and one Connect button.
        let connect = app.buttons["link-connect"]
        XCTAssertTrue(connect.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Connect my progress"].exists)
        // The full list is folded under the Connect button (and shown again
        // in the confirmation before anything is uploaded).
        let whatIsShared = app.buttons["What is shared, and what never is"]
        scrollTo(whatIsShared)
        whatIsShared.tap()
        XCTAssertTrue(element("Shared with your agent").waitForExistence(timeout: 3))
        XCTAssertTrue(element("Your answers, code and projects").exists)
        XCTAssertTrue(element("XP, rating and achievements").exists)
        XCTAssertTrue(app.staticTexts["Connect your agent"].exists, "the public setup stays below")
        capture("01-connect-section")
        scrollTo(connect)
        capture("02-connect-shared-list")

        // Confirmation before the first upload, with the exact content.
        connect.tap()
        XCTAssertTrue(app.staticTexts["Share your progress with your agent?"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["link-confirm-summary"].exists || element("From this iPhone").exists
                      || element("From this iPad").exists)
        capture("03-confirm-sheet")
        let preview = app.buttons["See exactly what is sent"]
        scrollTo(preview)
        if preview.exists { preview.tap() }
        XCTAssertTrue(containing("\"format\" : \"crabrix.learning-link-snapshot\"").waitForExistence(timeout: 3))
        capture("04-confirm-preview")
        let confirm = app.buttons["link-confirm-connect"]
        scrollTo(confirm)
        confirm.tap()

        // Connected: the personal URL, Copy, Share, steps and status.
        let url = app.descendants(matching: .any)["link-url"]
        XCTAssertTrue(url.waitForExistence(timeout: 10))
        let value = url.value as? String ?? ""
        XCTAssertTrue(value.hasPrefix("https://crabrix.com/mcp/learn/"), value)
        XCTAssertEqual(value.split(separator: "/").suffix(2).map(\.count), [24, 43])
        XCTAssertTrue(app.descendants(matching: .any)["link-connected-badge"].exists)
        XCTAssertTrue(app.buttons["link-copy-url"].exists)
        XCTAssertTrue(app.buttons["link-share-url"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["link-last-used"].waitForExistence(timeout: 5))
        capture("05-connected")
        let copyURL = app.buttons["link-copy-url"]
        for _ in 0..<6 where !copyURL.isHittable { app.swipeDown() }
        copyURL.tap()
        XCTAssertTrue(app.buttons["Copied"].waitForExistence(timeout: 2))

        // Connected, the personal URL replaces the public setup and its picker.
        XCTAssertTrue(app.descendants(matching: .any)["ai-public-setup-replaced"].exists)
        XCTAssertEqual(app.buttons.matching(identifier: "ai-client-claude-code").count, 1)
        let claudeCode = app.buttons["ai-client-claude-code"]
        scrollTo(claudeCode)
        claudeCode.tap()
        XCTAssertTrue(element("claude mcp add --transport http crabrix-me \(value)").waitForExistence(timeout: 5))
        capture("06-connected-claude-code")
        let disconnect = app.buttons["link-disconnect"]
        scrollTo(disconnect)
        XCTAssertTrue(element("Last used by your agent").exists || app.descendants(matching: .any)["link-last-used"].exists)
        capture("07-connected-status")

        // The Learn library shows the tutor's lessons after the inbox is read.
        goBack()
        scrollToTop()
        let card = app.otherElements["tutor-card"]
        XCTAssertTrue(card.waitForExistence(timeout: 15), "From your AI tutor")
        XCTAssertTrue(app.staticTexts["From your AI tutor"].exists)
        XCTAssertTrue(element("Reason: You asked how values get into a function: start here.").exists)
        XCTAssertTrue(element("Build a small HTTP service in Rust").exists)
        XCTAssertTrue(app.buttons["tutor-open-functions"].exists)
        XCTAssertTrue(app.buttons["tutor-dismiss-loops"].exists)
        capture("08-tutor-card")

        app.buttons["tutor-dismiss-loops"].tap()
        XCTAssertFalse(app.buttons["tutor-dismiss-loops"].waitForExistence(timeout: 2))
        app.buttons["tutor-open-functions"].tap()
        XCTAssertTrue(app.otherElements["lesson-page-heading"].waitForExistence(timeout: 10), "opens like any lesson")
        capture("09-tutor-lesson-opened")
        goBack()
        goBack()
        scrollToTop()

        // Disconnect: destructive confirmation, then nothing is left.
        openLearnWithAI()
        scrollTo(disconnect)
        disconnect.tap()
        let alert = app.alerts["Disconnect your agent?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        capture("10-disconnect-confirmation")
        alert.buttons["Disconnect"].tap()
        XCTAssertTrue(app.buttons["link-connect"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["link-notice"].exists)
        capture("11-disconnected")
        goBack()
        scrollToTop()
        XCTAssertFalse(app.otherElements["tutor-card"].waitForExistence(timeout: 3), "the card goes with the link")

        // Remote pause hides Connect.
        launch(["-CrabrixTab", "learn", "-CrabrixLearn", "with-ai", "-CrabrixAIStatus", "on",
                "-CrabrixLearningLinks", "paused", "-CrabrixLearningLinkStub"])
        XCTAssertTrue(app.descendants(matching: .any)["link-paused"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["link-connect"].exists)
        capture("12-paused")

        // Light mode and the largest accessibility text size.
        launch(["-CrabrixTab", "learn", "-CrabrixAIStatus", "on", "-CrabrixLearningLinkStub"], appearance: "light")
        openLearnWithAI()
        XCTAssertTrue(app.buttons["link-connect"].waitForExistence(timeout: 10))
        capture("13-light-connect")
        app.buttons["link-connect"].tap()
        let lightConfirm = app.buttons["link-confirm-connect"]
        scrollTo(lightConfirm)
        lightConfirm.tap()
        XCTAssertTrue(app.descendants(matching: .any)["link-url"].waitForExistence(timeout: 10))
        capture("14-light-connected")
        goBack()
        scrollToTop()
        XCTAssertTrue(app.otherElements["tutor-card"].waitForExistence(timeout: 15))
        capture("15-light-tutor-card")

        launch(["-CrabrixTab", "learn", "-CrabrixAIStatus", "on", "-CrabrixLearningLinkStub",
                "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"])
        openLearnWithAI()
        let largeConnect = app.buttons["link-connect"]
        XCTAssertTrue(largeConnect.waitForExistence(timeout: 10))
        capture("16-accessibility-connect")
        scrollTo(largeConnect)
        largeConnect.tap()
        let largeConfirm = app.buttons["link-confirm-connect"]
        scrollTo(largeConfirm)
        largeConfirm.tap()
        XCTAssertTrue(app.descendants(matching: .any)["link-url"].waitForExistence(timeout: 10))
        goBack()
        scrollToTop()
        XCTAssertTrue(app.otherElements["tutor-card"].waitForExistence(timeout: 15))
        capture("17-accessibility-tutor-card")
    }

    /// The real website and SDK MCP on this Mac: the app connects and uploads,
    /// the agent reads progress through the personal URL and assigns a lesson,
    /// and the app shows it and acknowledges it.
    func testEndToEndAgainstWebsiteAndMCP() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let site = environment["CRABRIX_LINK_E2E_SITE"], let mcp = environment["CRABRIX_LINK_E2E_MCP"],
              !site.isEmpty, !mcp.isEmpty else {
            throw XCTSkip("Set TEST_RUNNER_CRABRIX_LINK_E2E_SITE and TEST_RUNNER_CRABRIX_LINK_E2E_MCP to run")
        }
        continueAfterFailure = false
        let target = site.hasPrefix("https://") ? "production" : "local"
        var arguments = ["-CrabrixTab", "learn", "-CrabrixAIStatus", "on"]
        if site.hasPrefix("http://127.0.0.1") || site.hasPrefix("http://localhost") {
            arguments += ["-CrabrixLearningLinkOrigin", site, "-CrabrixLearningLinkMCPOrigin", mcp]
        }
        launch(arguments)
        ensureBasicsInstalled()
        openLearnWithAI()
        // A link left by an interrupted run goes first.
        let leftover = app.buttons["link-disconnect"]
        if leftover.waitForExistence(timeout: 3) {
            scrollTo(leftover)
            leftover.tap()
            app.alerts["Disconnect your agent?"].buttons["Disconnect"].tap()
        }
        let connect = app.buttons["link-connect"]
        XCTAssertTrue(connect.waitForExistence(timeout: 10))
        connect.tap()
        let confirm = app.buttons["link-confirm-connect"]
        scrollTo(confirm)
        confirm.tap()
        let urlElement = app.descendants(matching: .any)["link-url"]
        XCTAssertTrue(urlElement.waitForExistence(timeout: 20), app.descendants(matching: .any)["link-status-line"].label)
        let personal = try XCTUnwrap(urlElement.value as? String)
        XCTAssertTrue(personal.hasPrefix(mcp + "/mcp/learn/"), personal)
        let parts = personal.split(separator: "/").suffix(2).map(String.init)
        let link = try E2ELink(linkID: parts[0], secret: parts[1])
        deleteTestLink = { _ = try? await link.request(site: site, method: "DELETE", path: "", token: link.writeToken) }
        capture("e2e-\(target)-01-connected")

        // The agent reads the app's snapshot through the SDK MCP.
        let progress = try await callTool(mcp: personal, name: "crabrix_my_progress", arguments: [:])
        XCTAssertFalse(progress.isError, progress.text)
        XCTAssertTrue(progress.text.contains("crabrix-app"), progress.text)

        // The agent assigns a lesson (through the tool, as an agent would).
        let assigned = try await callTool(mcp: personal, name: "crabrix_assign_lessons", arguments: [
            "lessons": [["courseId": "basics", "lessonId": "functions", "reason": "End-to-end check from the SDK"]],
            "note": "Sent by the local MCP server",
        ])
        XCTAssertFalse(assigned.isError, assigned.text)
        // And one more message posted straight to the inbox with the read token.
        let message = #"{"format":"crabrix.tutor-message","schemaVersion":1,"createdAt":"2026-11-24T06:29:42Z","kind":"focus","pathId":"rust-backend","goal":"Ship a small Axum service","concepts":["borrowing","lifetimes"]}"#
        let posted = try await link.request(site: site, method: "POST", path: "inbox/", token: link.readToken,
                                            body: try link.envelope(Data(message.utf8)))
        XCTAssertEqual(posted.status, 201, String(decoding: posted.body, as: UTF8.self))
        let pending = try await link.request(site: site, method: "GET", path: "inbox/", token: link.writeToken)
        XCTAssertEqual((try JSONSerialization.jsonObject(with: pending.body) as? [String: Any]).flatMap { $0["items"] as? [Any] }?.count, 2)

        goBack()
        scrollToTop()
        let card = app.otherElements["tutor-card"]
        XCTAssertTrue(card.waitForExistence(timeout: 20), "From your AI tutor")
        XCTAssertTrue(element("Reason: End-to-end check from the SDK").exists)
        XCTAssertTrue(element("Ship a small Axum service").exists)
        capture("e2e-\(target)-02-tutor-card")

        // Every message was acknowledged.
        var remaining = -1
        for _ in 0..<10 {
            let inbox = try await link.request(site: site, method: "GET", path: "inbox/", token: link.writeToken)
            remaining = (try JSONSerialization.jsonObject(with: inbox.body) as? [String: Any])
                .flatMap { $0["items"] as? [Any] }?.count ?? -1
            if remaining == 0 { break }
            try await Task.sleep(for: .seconds(1))
        }
        XCTAssertEqual(remaining, 0, "the app acknowledged the inbox")

        // The snapshot now echoes the plan to the agent.
        try await Task.sleep(for: .seconds(4))
        let lesson = try await callTool(mcp: personal, name: "crabrix_my_lesson",
                                        arguments: ["courseId": "basics", "lessonId": "functions"])
        XCTAssertFalse(lesson.isError, lesson.text)

        // Disconnect deletes the link on the website.
        openLearnWithAI()
        let disconnect = app.buttons["link-disconnect"]
        scrollTo(disconnect)
        disconnect.tap()
        app.alerts["Disconnect your agent?"].buttons["Disconnect"].tap()
        XCTAssertTrue(app.buttons["link-connect"].waitForExistence(timeout: 15))
        let gone = try await link.request(site: site, method: "GET", path: "status/", token: link.writeToken)
        XCTAssertEqual(gone.status, 404)
        if gone.status == 404 { deleteTestLink = nil }
        let after = try await callTool(mcp: personal, name: "crabrix_my_progress", arguments: [:])
        XCTAssertTrue(after.isError || after.text.contains("LEARN_LINK_NOT_FOUND"), after.text)
        capture("e2e-\(target)-03-disconnected")
    }

    // MARK: Local end-to-end helpers

    private struct E2ELink {
        let linkID: String
        let key: SymmetricKey
        let writeToken: String
        let readToken: String

        init(linkID: String, secret: String) throws {
            self.linkID = linkID
            let raw = try XCTUnwrap(Data(base64Encoded: Self.standard(secret)))
            func derive(_ info: String) -> Data {
                HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: raw), salt: Data("crabrix-learning-link-v1".utf8),
                                       info: Data(info.utf8), outputByteCount: 32).withUnsafeBytes { Data($0) }
            }
            key = SymmetricKey(data: derive("encryption"))
            writeToken = Self.url(derive("app-write"))
            readToken = Self.url(derive("agent-read"))
        }

        static func url(_ data: Data) -> String {
            data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }

        static func standard(_ text: String) -> String {
            let base = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            return base + String(repeating: "=", count: (4 - base.count % 4) % 4)
        }

        func envelope(_ plaintext: Data) throws -> Data {
            let box = try AES.GCM.seal(plaintext, using: key, nonce: AES.GCM.Nonce(),
                                       authenticating: Data("crabrix-learning-link-v1|\(linkID)|inbox".utf8))
            let nonce = box.nonce.withUnsafeBytes { Data($0) }
            return try JSONSerialization.data(withJSONObject: ["v": 1, "nonce": Self.url(nonce),
                                                               "ct": Self.url(box.ciphertext + box.tag)])
        }

        func request(site: String, method: String, path: String, token: String,
                     body: Data? = nil) async throws -> (status: Int, body: Data) {
            var request = URLRequest(url: try XCTUnwrap(URL(string: "\(site)/api/learn-links/v1/\(linkID)/\(path)")))
            request.httpMethod = method
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            if let body {
                request.httpBody = body
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
            let (data, response) = try await URLSession(configuration: .ephemeral).data(for: request)
            return ((response as? HTTPURLResponse)?.statusCode ?? 0, data)
        }
    }

    /// One MCP `tools/call` over Streamable HTTP (JSON or an SSE answer).
    private func callTool(mcp url: String, name: String, arguments: [String: Any]) async throws -> (isError: Bool, text: String) {
        func post(_ body: [String: Any]) async throws -> [String: Any] {
            var request = URLRequest(url: try XCTUnwrap(URL(string: url)))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, _) = try await URLSession(configuration: .ephemeral).data(for: request)
            var text = String(decoding: data, as: UTF8.self)
            if text.contains("data:") {
                text = text.split(separator: "\n").filter { $0.hasPrefix("data:") }.map { $0.dropFirst(5) }.joined()
            }
            return try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        }
        _ = try await post(["jsonrpc": "2.0", "id": 1, "method": "initialize", "params": [
            "protocolVersion": "2025-06-18", "capabilities": [String: Any](), "clientInfo": ["name": "crabrix-ui-test", "version": "1"],
        ]])
        let answer = try await post(["jsonrpc": "2.0", "id": 2, "method": "tools/call",
                                     "params": ["name": name, "arguments": arguments]])
        if let error = answer["error"] as? [String: Any] { return (true, "\(error)") }
        let result = answer["result"] as? [String: Any] ?? [:]
        let text = (result["content"] as? [[String: Any]])?.compactMap { $0["text"] as? String }.joined(separator: "\n") ?? "\(answer)"
        return (result["isError"] as? Bool ?? false, text)
    }

    // MARK: Navigation helpers

    private func openLearnWithAI() {
        let entry = app.buttons["learn-with-ai"]
        scrollTo(entry)
        XCTAssertTrue(entry.waitForExistence(timeout: 20), "Learn with AI entry")
        entry.tap()
        XCTAssertTrue(app.staticTexts["Connect my progress"].waitForExistence(timeout: 10))
    }

    private func goBack() {
        let back = app.navigationBars.buttons.element(boundBy: 0)
        if back.waitForExistence(timeout: 5) { back.tap() }
        Thread.sleep(forTimeInterval: 1)
    }

    private func element(_ label: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    private func containing(_ text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    private func ensureBasicsInstalled() {
        let course = app.otherElements["learn-course-basics"]
        if course.waitForExistence(timeout: 8) { return }
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

    private func scrollTo(_ element: XCUIElement) {
        for _ in 0..<14 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
    }

    private func scrollToTop() {
        for _ in 0..<6 { app.swipeDown(velocity: .fast) }
        Thread.sleep(forTimeInterval: 1)
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
        let file = "learning-link-\(device)-\(name).png"
        if let directory = ProcessInfo.processInfo.environment["CRABRIX_LINK_SCREENSHOTS"], !directory.isEmpty {
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
