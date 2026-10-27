import XCTest
import WebKit
import UIKit
@testable import Crabrix

@MainActor
final class BrowserPlaygroundWebKitTests: XCTestCase {
    func testActualRustDebuggerPausesAndStepsInIOSWebKit() async throws {
        let configuration = WKWebViewConfiguration(); configuration.websiteDataStore = .nonPersistent()
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 1024, height: 768), configuration: configuration)
        let controller = UIViewController(); controller.view.addSubview(web)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1024, height: 768)); window.rootViewController = controller; window.makeKeyAndVisible()
        defer { web.stopLoading(); window.isHidden = true }
        web.load(URLRequest(url: URL(string: "http://127.0.0.1:3393/playground/")!))
        let loaded = await wait(web, script: "Boolean(document.querySelector('.cm-content'))", timeout: 45)
        XCTAssertTrue(loaded); guard loaded else { return }
        let isolated = try await web.evaluateJavaScript("crossOriginIsolated && typeof SharedArrayBuffer !== 'undefined'") as? Bool
        XCTAssertEqual(isolated, true, "Local browser Debug needs isolated shared control memory")
        _ = try await web.evaluateJavaScript("document.querySelector('[aria-label=\"Debug Rust\"]').click();true")
        let paused = await wait(web, script: "document.querySelector('.pg-debug-location')?.textContent.includes('main.rs:2')===true", timeout: 180)
        XCTAssertTrue(paused); guard paused else { return }
        _ = try await web.evaluateJavaScript("Array.from(document.querySelectorAll('button')).find(b=>b.textContent.trim()==='Step over').click();true")
        let next = await wait(web, script: "document.querySelector('.pg-debug-location')?.textContent.includes('main.rs:3')===true", timeout: 20)
        XCTAssertTrue(next)
        let attachment = XCTAttachment(image: try await web.takeSnapshot(configuration: nil)); attachment.name = "ios-webkit-local-debugger"; attachment.lifetime = .keepAlways; add(attachment)
        _ = try await web.evaluateJavaScript("Array.from(document.querySelectorAll('button')).find(b=>b.textContent.trim()==='▶ Continue').click();Array.from(document.querySelectorAll('[role=tab]')).find(b=>b.textContent.trim()==='Output').click();true")
        let output = await wait(web, script: "document.querySelector('.pg-output pre')?.textContent==='Hello, Crabrix! 🦀\\n'", timeout: 20)
        XCTAssertTrue(output)
    }
    func testRealRustCompilerRunsInIOSWebKitWorker() async throws {
        // The full public page, editor, actual compiler download and browser WASI
        // implementation run in iOS WebKit, not a substituted JavaScript VM.
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 1024, height: 768), configuration: configuration)
        let controller = UIViewController(); controller.view.addSubview(web)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1024, height: 768))
        window.rootViewController = controller; window.makeKeyAndVisible()
        defer { web.stopLoading(); window.isHidden = true }
        web.load(URLRequest(url: URL(string: "http://127.0.0.1:3393/playground/")!))
        let loaded = await wait(web, script: "Boolean(document.querySelector('.cm-content'))", timeout: 45)
        XCTAssertTrue(loaded, "The actual public editor must hydrate in iOS WebKit")
        guard loaded else { return }
        _ = try await web.evaluateJavaScript("Array.from(document.querySelectorAll('button')).find(b=>b.textContent.trim()==='▶ Run').click();true")
        let executed = await wait(web, script: "document.querySelector('.pg-output')?.textContent.includes('Hello, Crabrix!')===true", timeout: 180)
        let details = try await web.evaluateJavaScript("document.querySelector('.pg-output')?.textContent + ' NOTICE: ' + (document.querySelector('.pg-notice')?.textContent||'')")
        XCTAssertTrue(executed, "iOS WebKit compiler result: \(details)")
        let screenshot = try await web.takeSnapshot(configuration: nil)
        let attachment = XCTAttachment(image: screenshot); attachment.name = "playground-ios-webkit-rust"; attachment.lifetime = .keepAlways; add(attachment)
    }
    private func wait(_ web: WKWebView, script: String, timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if (try? await web.evaluateJavaScript(script)) as? Bool == true { return true }
            try? await Task.sleep(for: .milliseconds(250))
        }
        return false
    }
}
