import XCTest
import SwiftUI
import WebKit
@testable import Crabrix

final class OfflineWebPreviewTests: XCTestCase {
    func testSnapshotRejectsTraversalAndEnforcesByteBudget() throws {
        for path in ["../index.html", "/index.html", "a/../index.html", "a\\b.html", "a%2fb.html", "a\nb.html"] {
            XCTAssertFalse(WebPreviewSnapshot.isSafePath(path), path)
        }
        XCTAssertNil(WebPreviewSnapshot(textFiles: ["index.html": String(repeating: "x", count: WebPreviewSnapshot.maximumAssetBytes + 1)]))
        let one = try XCTUnwrap(WebPreviewSnapshot(textFiles: ["index.html": "<h1>A</h1>", "src/main.rs": "ignored"]))
        let two = try XCTUnwrap(WebPreviewSnapshot(textFiles: ["index.html": "<h1>B</h1>"]))
        XCTAssertEqual(one.assets.count, 1)
        XCTAssertNotEqual(one.id, two.id)
        XCTAssertFalse(OfflineWebPreviewPolicy.allows(URL(string: "https://example.com")!))
        XCTAssertFalse(OfflineWebPreviewPolicy.allows(URL(string: "file:///etc/passwd")!))
    }

    func testWebLanguagesUseUTF16RangesAndKeepStringsOutOfKeywords() {
        let source = "// 🦀 const ignored\nconst value = \"return\"; console.log(42);"
        let tokens = SyntaxHighlighter.tokens(in: source, filePath: "app.js")
        let text = source as NSString
        XCTAssertEqual(tokens.filter { $0.kind == .keyword }.map { text.substring(with: $0.range) }, ["const"])
        XCTAssertTrue(tokens.contains { $0.kind == .string && text.substring(with: $0.range) == "\"return\"" })
        XCTAssertTrue(tokens.contains { $0.kind == .number && text.substring(with: $0.range) == "42" })
        for (path, code) in [("index.html", "<button id=\"counter\">Go</button>"), ("styles.css", "button { color: coral; }"), ("data.json", "{\"answer\":42}")] {
            XCTAssertFalse(SyntaxHighlighter.tokens(in: code, filePath: path).isEmpty, path)
        }
        XCTAssertEqual(WebLocalCompleter.suggestion(for: "<scr", language: .html)?.insertion, "ipt src=\"app.js\" defer></script>")
    }

    @MainActor
    func testActualWebKitExecutesLocalJavaScriptCSSAndBlocksExternalResources() async throws {
        var files = WebProjectSamples.files
        files["index.html"]! += """
        <script>window.externalBlocked=false;
        fetch('https://example.com/crabrix-preview-probe').then(()=>window.externalBlocked=false).catch(()=>window.externalBlocked=true);
        </script>
        """
        let snapshot = try XCTUnwrap(WebPreviewSnapshot(textFiles: files))
        try await verifyPreview(snapshot, react: false)
    }

    @MainActor
    func testActualWebKitRunsPreparedReactTSXAndCSSOffline() async throws {
        var files = try BrowserProjectBuilderTests.reactFiles()
        files["index.html"]! += "<script>window.externalBlocked=false;fetch('https://example.com/crabrix-preview-probe').catch(()=>window.externalBlocked=true)</script>"
        let built = try await BrowserProjectBuilder().build(files: files, preferredEntry: "index.html")
        try await verifyPreview(built.preview, react: true)
    }

    @MainActor
    private func verifyPreview(_ snapshot: WebPreviewSnapshot, react: Bool) async throws {
        let root = UIHostingController(rootView: OfflineWebPreview(snapshot: snapshot, onMessage: { print("WEB CONSOLE", $0) }, onError: { print("WEB ERROR", $0) }))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 600)
        window.rootViewController = root
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKey() }
        root.loadViewIfNeeded()
        root.view.frame = CGRect(x: 0, y: 0, width: 390, height: 600)
        root.view.layoutIfNeeded()
        func find(_ view: UIView) -> WKWebView? {
            if let web = view as? WKWebView { return web }
            return view.subviews.lazy.compactMap(find).first
        }
        var web: WKWebView?
        for _ in 0..<100 {
            if let found = find(root.view) { web = found; break }
            try await Task.sleep(for: .milliseconds(100))
        }
        let preview = try XCTUnwrap(web)
        var ready = false
        for _ in 0..<200 {
            if let value = try? await preview.evaluateJavaScript("document.readyState === 'complete' && document.querySelector('#counter') !== null && window.externalBlocked === true"), value as? Bool == true { ready = true; break }
            try await Task.sleep(for: .milliseconds(100))
        }
        if !ready { print("WEB FAILURE", preview.url?.absoluteString ?? "no URL", preview.isLoading, (try? await preview.evaluateJavaScript("document.documentElement.outerHTML")) ?? "no document") }
        XCTAssertTrue(ready, "Local script did not initialize or external fetch was not blocked")
        _ = try await preview.evaluateJavaScript("document.querySelector('#counter').click()")
        try await Task.sleep(for: .milliseconds(200))
        let count = try await preview.evaluateJavaScript("document.querySelector('#counter').textContent") as? String
        XCTAssertTrue(count?.contains("1") == true, count ?? "missing counter")
        let style = try await preview.evaluateJavaScript(react ? "getComputedStyle(document.querySelector('#counter')).color" : "getComputedStyle(document.body).fontFamily") as? String
        XCTAssertTrue(style?.contains(react ? "20, 120, 50" : "system-ui") == true, style ?? "missing stylesheet")
        try await Task.sleep(for: .milliseconds(250))
        let capture = try await preview.takeSnapshot(configuration: nil)
        let attachment = XCTAttachment(image: capture)
        attachment.name = react ? "offline-react-tsx-preview" : "offline-web-preview"
        attachment.lifetime = .keepAlways
        add(attachment)
        withExtendedLifetime(root) {}
    }
}
