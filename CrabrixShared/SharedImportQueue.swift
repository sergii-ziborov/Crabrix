import Foundation

enum SharedImportQueue {
    static let appGroupIdentifier = "group.com.sergiiziborov.Crabrix"
    private static let storageKey = "pendingGitHubImportURLs"
    private static let maximumPendingImports = 10

    @discardableResult
    static func enqueue(_ rawURL: String) throws -> GitHubRepositoryReference {
        let reference = try GitHubRepositoryReference.parse(rawURL)
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

    enum QueueError: LocalizedError {
        case appGroupUnavailable

        var errorDescription: String? {
            "Crabrix could not access its shared import queue."
        }
    }
}
