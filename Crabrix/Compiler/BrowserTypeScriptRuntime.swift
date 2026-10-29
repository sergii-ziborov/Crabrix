import CryptoKit
import Foundation
@preconcurrency import WebKit

/// The WebKit document contains only bundled bridge code. User source is data
/// sent to an isolated Worker; it is never evaluated as JavaScript or uploaded.
@MainActor
final class BrowserTypeScriptRuntime: NSObject, WKNavigationDelegate {
    private var web: WKWebView?
    private var preparation: Task<Void, Error>?
    private var preparationToken: UUID?
    private var activeID: UUID?
    private var ready: CheckedContinuation<Void, Error>?
    private var request: (id: UUID, continuation: CheckedContinuation<Data, Error>)?
    private var timeout: Task<Void, Never>?

    func perform(_ payload: Data) async throws -> Data {
        guard payload.count <= 20 * 1024 * 1024, let json = String(data: payload, encoding: .utf8) else {
            throw BrowserBuildError(message: "This snapshot exceeds the checking input profile.")
        }
        guard activeID == nil else { throw BrowserBuildError(message: "TypeScript checking is already working.") }
        let id = UUID()
        activeID = id
        defer { if activeID == id { activeID = nil } }
        return try await withTaskCancellationHandler {
            try await prepare()
            try Task.checkCancellation()
            guard let web, activeID == id else { throw CancellationError() }
            return try await withCheckedThrowingContinuation { continuation in
                request = (id, continuation)
                timeout = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(15)) } catch { return }
                    guard self?.request?.id == id else { return }
                    self?.releaseMemory(message: "TypeScript checking reached its time limit. Editing and ordinary Run remain available.")
                }
                web.callAsyncJavaScript(
                    "return await window.crabrixTypeScript.request(JSON.parse(payload));",
                    arguments: ["payload": json], in: nil, in: .page
                ) { [weak self] result in
                    guard let self, request?.id == id else { return }
                    switch result {
                    case let .success(value):
                        guard let text = value as? String, let data = text.data(using: .utf8), data.count <= 2 * 1024 * 1024 else {
                            releaseMemory(message: "TypeScript checking returned an invalid response."); return
                        }
                        finish(id: id, result: .success(data))
                    case .failure:
                        releaseMemory(message: "TypeScript checking stopped. Editing and ordinary Run remain available.")
                    }
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                if self?.activeID == id { self?.releaseMemory(message: "TypeScript checking canceled.") }
            }
        }
    }

    func releaseMemory(message: String = "TypeScript checking stopped.") {
        preparation?.cancel(); preparation = nil
        preparationToken = nil; activeID = nil
        timeout?.cancel(); timeout = nil
        let error = BrowserBuildError(message: message)
        if let pending = ready { ready = nil; pending.resume(throwing: error) }
        if let pending = request { request = nil; pending.continuation.resume(throwing: error) }
        web?.evaluateJavaScript("window.crabrixTypeScript?.dispose()", completionHandler: nil)
        web?.stopLoading(); web?.navigationDelegate = nil; web = nil
    }

    private func finish(id: UUID, result: Result<Data, Error>) {
        guard let pending = request, pending.id == id else { return }
        request = nil; timeout?.cancel(); timeout = nil
        pending.continuation.resume(with: result)
    }

    private func prepare() async throws {
        if let preparation { return try await preparation.value }
        if web != nil { return }
        let token = UUID()
        preparationToken = token
        let task = Task { @MainActor [weak self] in
            guard let self else { throw CancellationError() }
            guard let root = Bundle.main.url(forResource: "TypeScriptCore", withExtension: nil) else {
                throw BrowserBuildError(message: "Bundled TypeScript checking is unavailable.")
            }
            let assets = try await Task.detached(priority: .userInitiated) { try BrowserTypeScriptAssets.load(root: root) }.value
            try Task.checkCancellation()
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = .nonPersistent()
            configuration.processPool = WKProcessPool()
            configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
            configuration.defaultWebpagePreferences.allowsContentJavaScript = true
            configuration.setURLSchemeHandler(BrowserTypeScriptAssetHandler(assets: assets), forURLScheme: BrowserTypeScriptAssets.scheme)
            guard let rules = try await WKContentRuleListStore.default().compileContentRuleList(
                forIdentifier: "crabrix-typescript-no-network-v1", encodedContentRuleList: OfflineWebPreviewPolicy.contentRules
            ) else { throw BrowserBuildError(message: "TypeScript checking could not prepare its local-only resource policy.") }
            try Task.checkCancellation()
            configuration.userContentController.add(rules)
            let document = WKWebView(frame: .zero, configuration: configuration)
            document.navigationDelegate = self
            document.isInspectable = false
            web = document
            let deadline = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: .seconds(15)) } catch { return }
                if self?.web === document, self?.ready != nil { self?.releaseMemory(message: "TypeScript checking could not initialize within its time limit.") }
            }
            defer { deadline.cancel() }
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                ready = continuation
                document.load(URLRequest(url: URL(string: "crabrix-typescript://runtime/index.html")!))
            }
        }
        preparation = task
        do { try await task.value; if preparationToken == token { preparation = nil; preparationToken = nil } }
        catch { if preparationToken == token { releaseMemory() }; throw error }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard web === webView, let pending = ready else { return }
        ready = nil; pending.resume()
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        if web === webView { releaseMemory(message: "TypeScript checking could not load its bundled document.") }
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        if web === webView { releaseMemory(message: "TypeScript checking could not load its bundled document.") }
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        if web === webView { releaseMemory(message: "TypeScript checking was released by iOS. Editing and ordinary Run remain available.") }
    }
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(action.request.url.map(BrowserTypeScriptAssets.allows) == true ? .allow : .cancel)
    }
}

struct BrowserTypeScriptAssets: Sendable {
    static let scheme = "crabrix-typescript"
    static func allows(_ url: URL) -> Bool { url.scheme == scheme && url.host == "runtime" }
    let files: [String: Data]
    struct Manifest: Decodable {
        struct Asset: Decodable { let bytes: Int; let sha256: String }
        let schemaVersion: Int
        let version: String
        let files: [String: Asset]
    }
    static func load(root: URL) throws -> Self {
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: root.appending(path: "manifest.json")))
        let names: Set<String> = ["index.html", "host.js", "worker.js", "compiler.js", "library.json"]
        guard manifest.schemaVersion == 1, manifest.version == BrowserTypeScriptProfile.version,
              Set(manifest.files.keys) == names else {
            throw BrowserBuildError(message: "TypeScript checking does not match its pinned compiler profile.")
        }
        var files: [String: Data] = [:]
        for name in names {
            let item = manifest.files[name]!
            guard item.bytes > 0, item.bytes <= 20 * 1024 * 1024 else { throw CocoaError(.fileReadCorruptFile) }
            let bytes = try Data(contentsOf: root.appending(path: name), options: .mappedIfSafe)
            let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
            guard bytes.count == item.bytes, digest == item.sha256 else { throw CocoaError(.fileReadCorruptFile) }
            files[name] = bytes
        }
        return Self(files: files)
    }
}

private final class BrowserTypeScriptAssetHandler: NSObject, WKURLSchemeHandler, @unchecked Sendable {
    let assets: BrowserTypeScriptAssets
    init(assets: BrowserTypeScriptAssets) { self.assets = assets }
    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        guard let url = task.request.url, BrowserTypeScriptAssets.allows(url),
              ["GET", "HEAD"].contains(task.request.httpMethod ?? "GET"),
              let data = assets.files[String(url.path.dropFirst())] else {
            task.didFailWithError(URLError(.noPermissionsToReadFile)); return
        }
        let mime = url.path.hasSuffix(".js") ? "text/javascript" : url.path.hasSuffix(".json") ? "application/json" : "text/html"
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [
            "Content-Type": mime, "Access-Control-Allow-Origin": "*", "Cache-Control": "no-store",
            "X-Content-Type-Options": "nosniff",
            "Content-Security-Policy": "default-src 'none'; script-src 'self'; connect-src 'self' crabrix-typescript:; worker-src blob:; frame-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'",
        ])!
        task.didReceive(response)
        if task.request.httpMethod != "HEAD" { task.didReceive(data) }
        task.didFinish()
    }
    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {}
}
