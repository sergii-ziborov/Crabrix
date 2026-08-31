import CryptoKit
import Foundation

/// What one file looked like when a project was last scored.
///
/// The text is kept while it fits the per-project budget. When it does not, the
/// digest and line count stay behind in its place: dropping the entry outright
/// is what used to make a large untouched file look new on every later run and
/// earn rating for work nobody did.
struct FileBaseline: Codable, Equatable, Sendable {
    /// Nil once the file was too large to keep verbatim.
    var text: String?
    var digest: String
    var lineCount: Int

    init(text: String) {
        self.text = text
        digest = Self.digest(of: text)
        lineCount = Self.lineCount(of: text)
    }

    private init(digest: String, lineCount: Int) {
        text = nil
        self.digest = digest
        self.lineCount = lineCount
    }

    /// The same file, remembered by identity alone.
    var withoutText: FileBaseline { FileBaseline(digest: digest, lineCount: lineCount) }

    static func digest(of text: String) -> String {
        SHA256.hash(data: Data(text.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    static func lineCount(of text: String) -> Int {
        text.split(separator: "\n", omittingEmptySubsequences: false).count
    }
}

/// How much a project's source actually changed between two successful runs.
///
/// Rating used to pay a flat fee for any successful build, which meant pressing
/// Run on an untouched sample earned the same as writing something. Measuring
/// the diff instead ties the reward to work rather than to taps.
struct CodeContribution: Equatable, Sendable {
    var addedLines = 0
    var removedLines = 0
    /// Files that did not exist in the previous snapshot.
    var newFiles = 0

    var changedLines: Int { addedLines + removedLines }
    var isFirstRun = false
    /// 0…1, the share of this project's characters that were typed rather than
    /// pasted or imported.
    var typedShare = 0.5

    /// What the diff is worth before the day's run reward is considered.
    ///
    /// Typed code is worth more than the same code pasted: producing a diff is
    /// not the same as writing one, and the diff alone cannot tell them apart.
    var craftMultiplier: Double { 0.4 + 0.6 * min(max(typedShare, 0), 1) }

    /// Rating for running a source revision this project has not run before.
    ///
    /// The curve is logarithmic on purpose: real edits are paid well, and
    /// pasting a thousand lines does not out-earn a whole course. Showing up at
    /// all is paid once a day by a separate reward, so this number is only ever
    /// about the diff.
    var points: Int {
        // A revision can be new to the workspace and still leave the scored
        // files identical — a rename, or a baseline the ledger had to shorten.
        guard changedLines > 0 else { return 3 }
        let scaled = 12.0 * log2(Double(changedLines) + 1)
        let fileBonus = min(newFiles, 5) * 6
        let raw = Double(6 + Int(scaled.rounded()) + fileBonus) * craftMultiplier
        return min(150, max(1, Int(raw.rounded())))
    }

    var summary: String {
        guard changedLines > 0 else { return "unchanged" }
        var parts = ["+\(addedLines)", "−\(removedLines)"]
        if newFiles > 0 { parts.append("\(newFiles) new file\(newFiles == 1 ? "" : "s")") }
        if typedShare >= 0.8 { parts.append("hand-written") }
        return parts.joined(separator: " ")
    }

    /// Compares two file sets and reports what moved.
    static func measure(
        previous: [String: String],
        current: [String: String]
    ) -> CodeContribution {
        measure(baseline: previous.mapValues { FileBaseline(text: $0) }, current: current)
    }

    /// Compares the current files against the last scored baseline, which may
    /// remember some files by digest rather than by text.
    static func measure(
        baseline: [String: FileBaseline],
        current: [String: String]
    ) -> CodeContribution {
        var result = CodeContribution()
        result.isFirstRun = baseline.isEmpty

        for (name, text) in current {
            guard let before = baseline[name] else {
                result.newFiles += 1
                result.addedLines += lines(of: text).count
                continue
            }
            if let beforeText = before.text {
                let diff = lineDiff(from: lines(of: beforeText), to: lines(of: text))
                result.addedLines += diff.added
                result.removedLines += diff.removed
                continue
            }
            // Too large to keep verbatim. The digest still answers whether it
            // changed at all, and the line counts bound by how much. A
            // deliberately conservative estimate beats calling it new.
            guard before.digest != FileBaseline.digest(of: text) else { continue }
            let delta = FileBaseline.lineCount(of: text) - before.lineCount
            result.addedLines += max(delta, 0)
            result.removedLines += max(-delta, 0)
            if delta == 0 { result.addedLines += 1 }
        }

        // A deleted file is work too, and ignoring it would let a delete-then-
        // re-add cycle look like pure addition.
        for (name, before) in baseline where current[name] == nil {
            result.removedLines += before.lineCount
        }
        return result
    }

    private static func lines(of text: String) -> [Substring] {
        text.split(separator: "\n", omittingEmptySubsequences: false)
    }

    /// Added and removed line counts from a longest-common-subsequence diff.
    ///
    /// Very large files fall back to a multiset comparison rather than running
    /// an O(n·m) table over them; the number only has to be a fair measure of
    /// effort, not a rendered patch.
    static func lineDiff(from before: [Substring], to after: [Substring]) -> (added: Int, removed: Int) {
        let limit = 2_000
        guard before.count <= limit, after.count <= limit else {
            return multisetDiff(from: before, to: after)
        }

        var table = [[Int]](
            repeating: [Int](repeating: 0, count: after.count + 1),
            count: before.count + 1
        )
        for i in stride(from: before.count - 1, through: 0, by: -1) {
            for j in stride(from: after.count - 1, through: 0, by: -1) {
                table[i][j] = before[i] == after[j]
                    ? table[i + 1][j + 1] + 1
                    : max(table[i + 1][j], table[i][j + 1])
            }
        }
        let common = table[0][0]
        return (added: after.count - common, removed: before.count - common)
    }

    private static func multisetDiff(
        from before: [Substring],
        to after: [Substring]
    ) -> (added: Int, removed: Int) {
        var counts: [Substring: Int] = [:]
        for line in before { counts[line, default: 0] += 1 }
        var added = 0
        for line in after {
            if let count = counts[line], count > 0 {
                counts[line] = count - 1
            } else {
                added += 1
            }
        }
        let removed = counts.values.reduce(0, +)
        return (added: added, removed: removed)
    }
}

/// Remembers the source each project was last scored at.
///
/// Bounded on purpose: it is a scoring aid, not a backup, so it drops the
/// least recently used project rather than growing without limit.
final class CodeContributionLedger: @unchecked Sendable {
    static let shared = CodeContributionLedger()

    private struct Snapshot: Codable {
        var files: [String: FileBaseline]
        var recordedAt: Date
    }

    /// The pre-digest shape, kept only so an update does not throw away every
    /// baseline and pay for a whole project as if it were newly written.
    private struct LegacySnapshot: Codable {
        var files: [String: String]
        var recordedAt: Date
    }

    private let lock = NSLock()
    private let defaults: UserDefaults
    private static let storageKey = "crabrix.contribution.v3"
    private static let legacyStorageKey = "crabrix.contribution.v2"
    /// Enough for a real multi-file project, far short of anything worth worrying about.
    private static let maxBytesPerProject = 256 * 1_024
    private static let maxProjects = 30

    private var cache: [String: Snapshot]?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Measures this run against the last scored one and stores the new baseline.
    func record(projectID: UUID, files: [String: String]) -> CodeContribution {
        lock.lock()
        defer { lock.unlock() }

        var snapshots = loadLocked()
        let key = projectID.uuidString.lowercased()
        let previous = snapshots[key]?.files ?? [:]
        let contribution = CodeContribution.measure(baseline: previous, current: files)

        let trimmed = Self.trim(files)
        snapshots[key] = Snapshot(files: trimmed, recordedAt: Date())
        if snapshots.count > Self.maxProjects {
            let oldest = snapshots.min { $0.value.recordedAt < $1.value.recordedAt }
            if let oldest { snapshots.removeValue(forKey: oldest.key) }
        }
        cache = snapshots
        persistLocked(snapshots)
        return contribution
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        cache = [:]
        defaults.removeObject(forKey: Self.storageKey)
    }

    /// Keeps the snapshot under the per-project cap by forgetting the text of
    /// the largest files first, so a big generated file cannot evict what the
    /// reader wrote.
    ///
    /// Every file keeps its entry. Removing them is what made an untouched
    /// 3,000-line file read as new on the next run, paying again for code
    /// nobody had touched since.
    private static func trim(_ files: [String: String]) -> [String: FileBaseline] {
        var baselines = files.mapValues { FileBaseline(text: $0) }
        var total = files.values.reduce(0) { $0 + $1.utf8.count }
        guard total > maxBytesPerProject else { return baselines }
        for (name, text) in files.sorted(by: { $0.value.utf8.count > $1.value.utf8.count }) {
            guard total > maxBytesPerProject else { break }
            baselines[name] = baselines[name]?.withoutText
            total -= text.utf8.count
        }
        return baselines
    }

    private func loadLocked() -> [String: Snapshot] {
        if let cache { return cache }
        if let data = defaults.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([String: Snapshot].self, from: data) {
            cache = decoded
            return decoded
        }
        let migrated = loadLegacyLocked()
        cache = migrated
        if !migrated.isEmpty { persistLocked(migrated) }
        return migrated
    }

    /// Converts a pre-digest snapshot rather than starting from nothing: an
    /// empty baseline would score the reader's whole project as newly written.
    private func loadLegacyLocked() -> [String: Snapshot] {
        guard let data = defaults.data(forKey: Self.legacyStorageKey),
              let decoded = try? JSONDecoder().decode([String: LegacySnapshot].self, from: data)
        else { return [:] }
        defaults.removeObject(forKey: Self.legacyStorageKey)
        return decoded.mapValues {
            Snapshot(files: Self.trim($0.files), recordedAt: $0.recordedAt)
        }
    }

    private func persistLocked(_ value: [String: Snapshot]) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
