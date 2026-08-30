import Foundation

/// How much of each durable project was typed instead of pasted/imported.
/// Keys are ProjectID + file path; pending rewards are also project-scoped so
/// switching workspaces cannot drain another project's input.
final class TypingLedger: @unchecked Sendable {
    static let shared = TypingLedger()
    static let typedInsertionLimit = 12

    private struct Counts: Codable {
        var typed = 0
        var bulk = 0
    }

    private struct State: Codable {
        var filesByProject: [String: [String: Counts]] = [:]
        var pendingByProject: [String: Int] = [:]
    }

    private let lock = NSLock()
    private let defaults: UserDefaults
    private static let storageKey = "crabrix.typing.v2"
    private var cache: State?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func record(projectID: UUID, filePath: String, inserted text: String) {
        let count = text.count
        guard count > 0 else { return }

        lock.lock()
        defer { lock.unlock() }
        var state = loadLocked()
        let projectKey = projectID.uuidString.lowercased()
        var files = state.filesByProject[projectKey] ?? [:]
        var entry = files[filePath] ?? Counts()
        if count <= Self.typedInsertionLimit {
            entry.typed += count
            state.pendingByProject[projectKey, default: 0] += count
        } else {
            entry.bulk += count
        }
        files[filePath] = entry
        state.filesByProject[projectKey] = files
        cache = state
        persistLocked(state)
    }

    /// Aggregates every file in one ProjectID. An unseen imported project is
    /// neutral rather than treated as pasted code.
    func typedShare(projectID: UUID) -> Double {
        lock.lock()
        defer { lock.unlock() }
        let key = projectID.uuidString.lowercased()
        guard let files = loadLocked().filesByProject[key] else { return 0.5 }
        let typed = files.values.reduce(0) { $0 + $1.typed }
        let bulk = files.values.reduce(0) { $0 + $1.bulk }
        let total = typed + bulk
        guard total > 0 else { return 0.5 }
        return Double(typed) / Double(total)
    }

    func drainPendingTyped(projectID: UUID) -> Int {
        lock.lock()
        defer { lock.unlock() }
        var state = loadLocked()
        let key = projectID.uuidString.lowercased()
        let pending = state.pendingByProject.removeValue(forKey: key) ?? 0
        cache = state
        persistLocked(state)
        return pending
    }

    func pendingTyped(projectID: UUID) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return loadLocked().pendingByProject[projectID.uuidString.lowercased()] ?? 0
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        cache = State()
        defaults.removeObject(forKey: Self.storageKey)
    }

    private func loadLocked() -> State {
        if let cache { return cache }
        guard let data = defaults.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode(State.self, from: data)
        else {
            let empty = State()
            cache = empty
            return empty
        }
        cache = decoded
        return decoded
    }

    private func persistLocked(_ value: State) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
