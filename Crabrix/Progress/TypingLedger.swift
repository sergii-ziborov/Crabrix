import Foundation

/// How much of a project was actually typed, as opposed to pasted or imported.
///
/// Rating is meant to reward writing Rust, not producing it. A project typed by
/// hand and the same project pasted in one go produce an identical diff, so the
/// diff alone cannot tell them apart — this can.
final class TypingLedger: @unchecked Sendable {
    static let shared = TypingLedger()

    /// An insertion longer than this did not come from the keyboard.
    ///
    /// The accessory row inserts short fragments like `&mut ` and completion
    /// accepts a signature, so the line is drawn above a keystroke and well
    /// below a paste rather than at exactly one character.
    static let typedInsertionLimit = 12

    private struct Counts: Codable {
        var typed = 0
        var bulk = 0
    }

    private let lock = NSLock()
    private let defaults: UserDefaults
    private static let storageKey = "crabrix.typing.v1"
    private static let pendingKey = "crabrix.typing.pending.v1"
    private var cache: [String: Counts]?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Records one insertion.
    ///
    /// - Parameter text: exactly what was inserted, so the length can classify it.
    func record(project: String, inserted text: String) {
        let count = text.count
        guard count > 0 else { return }

        lock.lock()
        defer { lock.unlock() }
        var counts = loadLocked()
        var entry = counts[project] ?? Counts()
        if count <= Self.typedInsertionLimit {
            entry.typed += count
            defaults.set(pendingLocked() + count, forKey: Self.pendingKey)
        } else {
            entry.bulk += count
        }
        counts[project] = entry
        cache = counts
        persistLocked(counts)
    }

    /// 0…1: the share of this project's characters that were typed.
    ///
    /// A project with no record at all returns 0.5 rather than 0 — an imported
    /// repository is not cheating, it simply predates any typing.
    func typedShare(project: String) -> Double {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = loadLocked()[project] else { return 0.5 }
        let total = entry.typed + entry.bulk
        guard total > 0 else { return 0.5 }
        return Double(entry.typed) / Double(total)
    }

    /// Typed characters not yet turned into rating, taken and cleared.
    func drainPendingTyped() -> Int {
        lock.lock()
        defer { lock.unlock() }
        let pending = pendingLocked()
        defaults.set(0, forKey: Self.pendingKey)
        return pending
    }

    var pendingTyped: Int {
        lock.lock()
        defer { lock.unlock() }
        return pendingLocked()
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        cache = [:]
        defaults.removeObject(forKey: Self.storageKey)
        defaults.removeObject(forKey: Self.pendingKey)
    }

    private func pendingLocked() -> Int { defaults.integer(forKey: Self.pendingKey) }

    private func loadLocked() -> [String: Counts] {
        if let cache { return cache }
        guard let data = defaults.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([String: Counts].self, from: data)
        else {
            cache = [:]
            return [:]
        }
        cache = decoded
        return decoded
    }

    private func persistLocked(_ value: [String: Counts]) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
