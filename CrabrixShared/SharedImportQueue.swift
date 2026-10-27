import Foundation

enum SharedImportQueue {
    static let appGroupIdentifier = "group.com.sergiiziborov.Crabrix"
    private static let storageKey = "pendingGitHubImportURLs"
    private static let maximumPendingImports = 10

    @discardableResult
    static func enqueue(_ rawURL: String) throws -> SharedLink {
        let reference: SharedLink
        if let playground = try? PlaygroundLink.parse(rawURL) {
            guard playground.expiresAt > Date() else { throw PlaygroundFailureProxy.expired }
            reference = .playground(playground)
        } else { reference = .github(try GitHubRepositoryReference.parse(rawURL)) }
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else {
            throw QueueError.appGroupUnavailable
        }
        var values = defaults.stringArray(forKey: storageKey) ?? []
        values.removeAll { $0 == rawURL }
        values.append(rawURL)
        if values.count > maximumPendingImports {
            values.removeFirst(values.count - maximumPendingImports)
        }
        defaults.set(values, forKey: storageKey)
        return reference
    }

    static func dequeue() -> String? {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else { return nil }
        var values = defaults.stringArray(forKey: storageKey) ?? []
        guard !values.isEmpty else { return nil }
        let value = values.removeFirst()
        defaults.set(values, forKey: storageKey)
        return value
    }

    enum SharedLink {
        case github(GitHubRepositoryReference)
        case playground(PlaygroundLink)
        var label: String { switch self { case .github(let value): "\(value.owner)/\(value.repository)"; case .playground: "The encrypted Playground" } }
    }
    enum PlaygroundFailureProxy: LocalizedError {
        case expired
        var errorDescription: String? { "This temporary Playground has expired." }
    }
    enum QueueError: LocalizedError {
        case appGroupUnavailable

        var errorDescription: String? {
            "Crabrix could not access its shared import queue."
        }
    }
}
