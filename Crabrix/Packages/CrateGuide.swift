import Foundation

/// What a downloaded crate says about itself.
///
/// Every field here is read from the crate's own extracted files rather than
/// fetched: the description and links come from its `Cargo.toml`, the guide is
/// its README, and the examples are the ones its author shipped. That means a
/// package explains itself with the network off, which is the same promise the
/// rest of the app makes.
struct CrateGuide: Sendable, Equatable {
    let name: String
    let version: SemanticVersion
    let description: String?
    let license: String?
    let keywords: [String]
    let categories: [String]
    let homepage: String?
    let repository: String?
    let documentation: String?
    /// The README, as written by the crate's author.
    let readme: String?
    /// Paths of `examples/*.rs`, relative to the crate root.
    let examples: [String]

    var hasAnything: Bool {
        description != nil || readme != nil || !examples.isEmpty
    }

    /// A one-line summary for a package row.
    var summaryLine: String? {
        guard let description else { return nil }
        return description
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Links worth offering, in the order they are useful.
    var links: [(label: String, url: URL)] {
        var found: [(String, URL)] = []
        func add(_ label: String, _ raw: String?) {
            guard let raw, let url = URL(string: raw), url.scheme?.hasPrefix("http") == true else { return }
            found.append((label, url))
        }
        add("Documentation", documentation ?? "https://docs.rs/\(name)/\(version)")
        add("Repository", repository)
        add("Homepage", homepage)
        add("crates.io", "https://crates.io/crates/\(name)")
        return found
    }

    /// READMEs can be long; past this the reader gets the file browser instead.
    static let maximumReadmeBytes = 512 * 1_024

    /// Guides are read from disk but rendered in a row that lays out often, so
    /// the result is memoised. The extracted source of a given version never
    /// changes, which makes the cache safe to keep for the session.
    private static let cache = GuideCache()

    static func cached(name: String, version: SemanticVersion) -> CrateGuide? {
        cache.value(name: name, version: version) { load(name: name, version: version) }
    }

    static func load(name: String, version: SemanticVersion) -> CrateGuide? {
        guard let root = CrateStorageLayout.sourceDirectory(name: name, version: version),
              FileManager.default.fileExists(atPath: root.path)
        else { return nil }

        let package = manifestTable(at: root)

        return CrateGuide(
            name: name,
            version: version,
            description: package?["description"]?.stringValue?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nonEmpty,
            license: package?["license"]?.stringValue?.nonEmpty,
            keywords: package?["keywords"]?.stringArrayValue ?? [],
            categories: package?["categories"]?.stringArrayValue ?? [],
            homepage: package?["homepage"]?.stringValue?.nonEmpty,
            repository: package?["repository"]?.stringValue?.nonEmpty,
            documentation: package?["documentation"]?.stringValue?.nonEmpty,
            readme: readme(at: root),
            examples: examples(at: root)
        )
    }

    private static func manifestTable(at root: URL) -> TOMLValue? {
        let url = root.appending(path: "Cargo.toml")
        guard let text = try? String(contentsOf: url, encoding: .utf8),
              let document = try? TOMLParser.parse(text)
        else { return nil }
        return document["package"]
    }

    /// The README under any of the spellings crates use.
    private static func readme(at root: URL) -> String? {
        let candidates = ["README.md", "readme.md", "Readme.md", "README", "README.markdown", "README.txt"]
        for candidate in candidates {
            let url = root.appending(path: candidate)
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
                  (values.fileSize ?? 0) <= maximumReadmeBytes,
                  let text = try? String(contentsOf: url, encoding: .utf8),
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { continue }
            return text
        }
        return nil
    }

    private static func examples(at root: URL) -> [String] {
        let directory = root.appending(path: "examples", directoryHint: .isDirectory)
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return [] }
        return entries
            .filter { $0.pathExtension == "rs" }
            .map { "examples/" + $0.lastPathComponent }
            .sorted()
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}


/// Session-lifetime memo for `CrateGuide.cached`.
private final class GuideCache: @unchecked Sendable {
    private let lock = NSLock()
    /// nil is cached too: a crate with no README should not be re-read on
    /// every layout pass just because the answer was "nothing".
    private var entries: [String: CrateGuide?] = [:]

    func value(
        name: String,
        version: SemanticVersion,
        make: () -> CrateGuide?
    ) -> CrateGuide? {
        let key = "\(name)-\(version)"
        lock.lock()
        if let hit = entries[key] {
            lock.unlock()
            return hit
        }
        lock.unlock()

        // Built outside the lock: reading a README should not block other rows.
        let made = make()
        lock.lock()
        entries[key] = made
        lock.unlock()
        return made
    }
}
