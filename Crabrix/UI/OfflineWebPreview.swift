import SwiftUI
import WebKit

struct WebPreviewFailure: Sendable {
    let message: String
    let file: String?
    let line: Int
    let column: Int
}

enum OfflineWebPreviewPolicy {
    static let scheme = "crabrix-preview"
    static let host = "project"
    static let contentSecurityPolicy = "default-src 'none'; script-src 'self' crabrix-preview: 'unsafe-inline'; style-src 'self' crabrix-preview: 'unsafe-inline'; img-src 'self' crabrix-preview: data: blob:; font-src 'self' crabrix-preview: data:; connect-src 'self' crabrix-preview:; worker-src 'none'; frame-src 'none'; object-src 'none'; form-action 'none'; base-uri 'self'"
    // Independent of CSP: external resource loads are blocked by WebKit before
    // any document is loaded, including nested CSS/script requests.
    static let contentRules = #"[{"trigger":{"url-filter":"^https?://"},"action":{"type":"block"}},{"trigger":{"url-filter":"^wss?://"},"action":{"type":"block"}},{"trigger":{"url-filter":"^ftp://"},"action":{"type":"block"}},{"trigger":{"url-filter":"^file://"},"action":{"type":"block"}}]"#

    static func allows(_ url: URL) -> Bool {
        url.scheme == scheme && url.host == host
    }
}

/// This handler has no filesystem or networking capability. Its immutable
/// source snapshot is the complete set of resources the web process can read.
final class OfflineWebAssetHandler: NSObject, WKURLSchemeHandler, @unchecked Sendable {
    let snapshot: WebPreviewSnapshot
    init(snapshot: WebPreviewSnapshot) { self.snapshot = snapshot }

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url, OfflineWebPreviewPolicy.allows(url),
              ["GET", "HEAD"].contains(urlSchemeTask.request.httpMethod ?? "GET")
        else {
            urlSchemeTask.didFailWithError(URLError(.noPermissionsToReadFile))
            return
        }
        var path = String(url.path.drop(while: { $0 == "/" }))
        if path.isEmpty { path = snapshot.entryPath }
        else if path.hasSuffix("/") { path += "index.html" }
        guard WebPreviewSnapshot.isSafePath(path) else {
            urlSchemeTask.didFailWithError(URLError(.noPermissionsToReadFile))
            return
        }
        let data = snapshot.assets[path]
        let response = HTTPURLResponse(url: url, statusCode: data == nil ? 404 : 200,
                                       httpVersion: "HTTP/1.1", headerFields: [
            "Content-Type": (WebPreviewSnapshot.mimeType(for: path) ?? "text/plain")
                + ((WebPreviewSnapshot.mimeType(for: path) ?? "").hasPrefix("text/") ? "; charset=utf-8" : ""),
            "Content-Security-Policy": OfflineWebPreviewPolicy.contentSecurityPolicy,
            "X-Content-Type-Options": "nosniff",
            "Access-Control-Allow-Origin": "*",
            "Cache-Control": "no-store",
        ])!
        urlSchemeTask.didReceive(response)
        if urlSchemeTask.request.httpMethod != "HEAD" {
            urlSchemeTask.didReceive(data ?? Data("Preview asset not found: \(path)".utf8))
        }
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {}
}

@MainActor
struct OfflineWebPreview: UIViewRepresentable {
    let snapshot: WebPreviewSnapshot
    let onMessage: (String) -> Void
    let onError: (WebPreviewFailure) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onMessage: onMessage, onError: onError) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.processPool = WKProcessPool()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.setURLSchemeHandler(OfflineWebAssetHandler(snapshot: snapshot),
                                          forURLScheme: OfflineWebPreviewPolicy.scheme)
        // A read-only, bounded console channel: no project edits, native
        // commands, account data or host functions are exposed to scripts.
        configuration.userContentController.add(context.coordinator, name: "previewConsole")
        configuration.userContentController.addUserScript(WKUserScript(source: Self.consoleScript,
            injectionTime: .atDocumentStart, forMainFrameOnly: true))
        let web = WKWebView(frame: .zero, configuration: configuration)
        web.navigationDelegate = context.coordinator
        web.uiDelegate = context.coordinator
        web.isInspectable = false
        web.accessibilityLabel = "Offline website preview"
        context.coordinator.prepareAndLoad(web, entry: snapshot.entryPath)
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        coordinator.isActive = false
        uiView.stopLoading()
        uiView.navigationDelegate = nil
        uiView.uiDelegate = nil
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "previewConsole")
        uiView.configuration.userContentController.removeAllUserScripts()
        uiView.configuration.userContentController.removeAllContentRuleLists()
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        var isActive = true
        private var messageCount = 0
        let onMessage: (String) -> Void
        let onError: (WebPreviewFailure) -> Void
        init(onMessage: @escaping (String) -> Void, onError: @escaping (WebPreviewFailure) -> Void) {
            self.onMessage = onMessage; self.onError = onError
        }

        func prepareAndLoad(_ web: WKWebView, entry: String) {
            WKContentRuleListStore.default().compileContentRuleList(
                forIdentifier: "CrabrixOfflinePreview-v1", encodedContentRuleList: OfflineWebPreviewPolicy.contentRules
            ) { [weak self, weak web] rules, error in
                guard let self, self.isActive, let web else { return }
                guard let rules, error == nil else {
                    self.onMessage("Preview could not enable offline resource blocking: \(error?.localizedDescription ?? "no rules returned")")
                    return
                }
                web.configuration.userContentController.add(rules)
                let root = URL(string: "\(OfflineWebPreviewPolicy.scheme)://\(OfflineWebPreviewPolicy.host)/")!
                web.load(URLRequest(url: root.appending(path: entry)))
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            decisionHandler(navigationAction.request.url.map(OfflineWebPreviewPolicy.allows) == true ? .allow : .cancel)
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? { nil }

        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard isActive, messageCount < 128, message.frameInfo.isMainFrame,
                  message.frameInfo.request.url.map(OfflineWebPreviewPolicy.allows) == true,
                  let body = message.body as? [String: Any], let text = body["text"] as? String
            else { return }
            messageCount += 1
            let bounded = String(text.prefix(2_048))
            onMessage("\(body["kind"] as? String ?? "log"): \(bounded)")
            if body["kind"] as? String == "error" {
                let file = (body["file"] as? String).flatMap(URL.init(string:))
                    .flatMap { OfflineWebPreviewPolicy.allows($0) ? String($0.path.dropFirst()) : nil }
                onError(WebPreviewFailure(message: bounded, file: file,
                    line: max(1, min(body["line"] as? Int ?? 1, 1_000_000)),
                    column: max(1, min(body["column"] as? Int ?? 1, 1_000_000))))
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
            guard isActive else { return }; onMessage("Preview could not open: \(error.localizedDescription)")
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
            guard isActive else { return }; onMessage("Preview navigation failed: \(error.localizedDescription)")
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            guard isActive else { return }
            onMessage("The preview process stopped. Reload the preview to run it again.")
        }
    }

    private static let consoleScript = #"""
    (() => {
      let sent = 0;
      const report = (kind, values, file = "", line = 1, column = 1) => {
        if (sent++ >= 128) return;
        const text = values.map(v => {
          try { return typeof v === 'string' ? v : JSON.stringify(v); }
          catch (_) { return String(v); }
        }).join(' ').slice(0, 2048);
        window.webkit.messageHandlers.previewConsole.postMessage({kind, text, file, line, column});
      };
      for (const kind of ['log', 'warn', 'error']) {
        const previous = console[kind].bind(console);
        console[kind] = (...args) => { report(kind, args); previous(...args); };
      }
      addEventListener('error', e => report('error', [e.message], e.filename, e.lineno, e.colno));
      addEventListener('unhandledrejection', e => report('error', [String(e.reason)]));
    })();
    """#
}

struct OfflineWebPreviewPanel: View {
    let snapshot: WebPreviewSnapshot
    let height: CGFloat
    let onError: (WebPreviewFailure) -> Void
    @State private var isOpen = true
    @State private var reloadID = UUID()
    @State private var messages: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("OFFLINE WEB PREVIEW", systemImage: "globe").font(.caption.monospaced().bold())
                Spacer(minLength: 8)
                if isOpen {
                    Button("Reload") { messages = []; reloadID = UUID() }
                    Button("Close") { isOpen = false }
                } else { Button("Open") { isOpen = true; messages = [] } }
            }
            .font(.caption.weight(.semibold))
            if isOpen {
                OfflineWebPreview(snapshot: snapshot, onMessage: { if messages.count < 128 { messages.append($0) } }, onError: onError)
                    .id(reloadID)
                    .frame(height: max(180, height))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            if !messages.isEmpty {
                DisclosureGroup("Web console · \(messages.count)") {
                    Text(messages.joined(separator: "\n"))
                        .font(.caption.monospaced()).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.caption)
            }
        }
        .padding(12)
        .background(CrabrixTheme.panel, in: RoundedRectangle(cornerRadius: 14))
    }
}
