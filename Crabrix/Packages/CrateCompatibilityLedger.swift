import Foundation

/// What actually happened the last time Crabrix compiled a crate.
///
/// Static inspection can only ever say "expected compatible". The bundled
/// `rustc` has real codegen gaps, so the only trustworthy compatibility signal
/// is a build that was actually attempted. This ledger remembers those results
/// per build unit, which is what lets the UI say "verified" or "does not build
/// here" without recompiling.
enum CrateBuildOutcome: Codable, Sendable, Equatable {
    /// rustc emitted metadata successfully (`cargo check`-level evidence).
    case checked
    /// rustc emitted a linkable library successfully.
    case built
    case failed(String)
}

/// A persisted record of a single dependency build.
struct CrateBuildRecord: Codable, Sendable, Equatable {
    let package: PackageID
    let fingerprint: String
    let outcome: CrateBuildOutcome
    let toolchain: String
    let recordedAt: Date
}

/// Survives cache eviction, because the knowledge is expensive to re-earn.
final class CrateCompatibilityLedger: @unchecked Sendable {
    static let shared = CrateCompatibilityLedger()

    private let lock = NSLock()
    private let storageURL: URL?
    private var records: [String: CrateBuildRecord]?
    private let maximumRecords = 2_000

    init(storageURL: URL? = CrateCompatibilityLedger.defaultStorageURL) {
        self.storageURL = storageURL
    }

    static var defaultStorageURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appending(path: "Crabrix", directoryHint: .isDirectory)
            .appending(path: "crate-compatibility.json")
    }

    func outcome(forFingerprint fingerprint: String) -> CrateBuildOutcome? {
        lock.lock()
        defer { lock.unlock() }
        return loadLocked()[fingerprint]?.outcome
    }

    func record(
        package: PackageID,
        fingerprint: String,
        outcome: CrateBuildOutcome,
        toolchain: String = CargoToolchain.bundledVersion
    ) {
        lock.lock()
        defer { lock.unlock() }
        var current = loadLocked()
        // A later cheap Check must not erase stronger link evidence for the
        // exact same fingerprint and toolchain.
        if current[fingerprint]?.outcome == .built, outcome == .checked {
            return
        }
        current[fingerprint] = CrateBuildRecord(
            package: package,
            fingerprint: fingerprint,
            outcome: outcome,
            toolchain: toolchain,
            recordedAt: Date()
        )
        if current.count > maximumRecords {
            let oldest = current.values.sorted { $0.recordedAt < $1.recordedAt }
                .prefix(current.count - maximumRecords)
            for record in oldest { current.removeValue(forKey: record.fingerprint) }
        }
        records = current
        persistLocked(current)
    }

    func removeAll() {
        lock.lock()
        defer { lock.unlock() }
        records = [:]
        guard let storageURL else { return }
        try? FileManager.default.removeItem(at: storageURL)
    }

    private func loadLocked() -> [String: CrateBuildRecord] {
        if let records { return records }
        guard let storageURL,
              let data = try? Data(contentsOf: storageURL)
        else {
            records = [:]
            return [:]
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = (try? decoder.decode([String: CrateBuildRecord].self, from: data)) ?? [:]
        // Records from an older toolchain say nothing about this one.
        let current = decoded.filter { $0.value.toolchain == CargoToolchain.bundledVersion }
        records = current
        return current
    }

    private func persistLocked(_ value: [String: CrateBuildRecord]) {
        guard let storageURL else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        try? FileManager.default.createDirectory(
            at: storageURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? encoder.encode(value).write(to: storageURL, options: .atomic)
    }
}
