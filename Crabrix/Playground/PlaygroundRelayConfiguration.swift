import Foundation

enum PlaygroundRelayConfiguration {
    static var origin: URL {
        #if DEBUG || CRABRIX_LEGACY_FIXTURES
        // QA-only local relay, never available in App Store builds or accepted
        // from a shared link. Source URLs cannot redirect the transport.
        if let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--crabrix-playground-relay=") }),
           let url = URL(string: String(argument.dropFirst("--crabrix-playground-relay=".count))),
           url.scheme == "http", ["127.0.0.1", "localhost"].contains(url.host), url.user == nil, url.password == nil { return url }
        #endif
        return URL(string: "https://crabrix.com")!
    }
}
