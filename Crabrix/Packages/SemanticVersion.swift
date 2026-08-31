import Foundation

/// A SemVer 2.0.0 version, ordered the way Cargo orders registry versions.
struct SemanticVersion: Hashable, Comparable, Sendable, CustomStringConvertible, Codable {
    let major: Int
    let minor: Int
    let patch: Int
    let prerelease: [String]
    let build: String?

    init(major: Int, minor: Int, patch: Int, prerelease: [String] = [], build: String? = nil) {
        self.major = major
        self.minor = minor
        self.patch = patch
        self.prerelease = prerelease
        self.build = build
    }

    init?(_ text: String) {
        var body = text.trimmingCharacters(in: .whitespaces)
        guard !body.isEmpty else { return nil }

        var build: String?
        if let plus = body.firstIndex(of: "+") {
            build = String(body[body.index(after: plus)...])
            body = String(body[..<plus])
        }

        var prerelease: [String] = []
        if let dash = body.firstIndex(of: "-") {
            let identifiers = body[body.index(after: dash)...]
            body = String(body[..<dash])
            prerelease = identifiers.split(separator: ".", omittingEmptySubsequences: false)
                .map(String.init)
            guard !prerelease.contains(where: \.isEmpty) else { return nil }
        }

        let numbers = body.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(numbers.count) else { return nil }
        var parsed: [Int] = []
        for number in numbers {
            guard let value = Int(number), value >= 0 else { return nil }
            parsed.append(value)
        }
        major = parsed[0]
        minor = parsed.count > 1 ? parsed[1] : 0
        patch = parsed.count > 2 ? parsed[2] : 0
        self.prerelease = prerelease
        self.build = build
    }

    var isPrerelease: Bool { !prerelease.isEmpty }

    var description: String {
        var text = "\(major).\(minor).\(patch)"
        if !prerelease.isEmpty { text += "-" + prerelease.joined(separator: ".") }
        if let build { text += "+" + build }
        return text
    }

    /// Build metadata is explicitly excluded from precedence by the spec.
    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }
        switch (lhs.prerelease.isEmpty, rhs.prerelease.isEmpty) {
        case (true, true): return false
        case (true, false): return false
        case (false, true): return true
        case (false, false): break
        }
        for index in 0..<max(lhs.prerelease.count, rhs.prerelease.count) {
            guard index < lhs.prerelease.count else { return true }
            guard index < rhs.prerelease.count else { return false }
            let left = lhs.prerelease[index]
            let right = rhs.prerelease[index]
            switch (Int(left), Int(right)) {
            case let (leftNumber?, rightNumber?):
                if leftNumber != rightNumber { return leftNumber < rightNumber }
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                if left != right { return left < right }
            }
        }
        return false
    }

    /// Two versions are compatible when Cargo would refuse to link both: the
    /// leftmost non-zero component has to match.
    func isCaretCompatible(with other: SemanticVersion) -> Bool {
        if major != 0 || other.major != 0 { return major == other.major }
        if minor != 0 || other.minor != 0 { return minor == other.minor }
        return patch == other.patch
    }
}

/// A Cargo version requirement, i.e. a comma-separated list of comparators.
struct VersionRequirement: Hashable, Sendable, CustomStringConvertible {
    enum Comparator: Hashable, Sendable {
        case exact(SemanticVersion)
        case greater(SemanticVersion)
        case greaterOrEqual(SemanticVersion)
        case less(SemanticVersion)
        case lessOrEqual(SemanticVersion)
        /// Half-open `>= lower, < upper`, which is how `^`, `~`, and `x.*` behave.
        case range(lower: SemanticVersion, upper: SemanticVersion?)
    }

    let comparators: [Comparator]
    let source: String

    var description: String { source }

    static let any = VersionRequirement(comparators: [], source: "*")

    init(comparators: [Comparator], source: String) {
        self.comparators = comparators
        self.source = source
    }

    init?(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        var comparators: [Comparator] = []
        for piece in trimmed.split(separator: ",") {
            guard let comparator = Self.parseComparator(String(piece)) else { return nil }
            if let comparator { comparators.append(comparator) }
        }
        self.comparators = comparators
        source = trimmed
    }

    func isSatisfied(by version: SemanticVersion) -> Bool {
        guard !comparators.isEmpty else { return !version.isPrerelease }
        for comparator in comparators where !Self.matches(comparator, version) {
            return false
        }
        // Cargo only offers a prerelease when a comparator explicitly names one
        // at the same major.minor.patch.
        guard version.isPrerelease else { return true }
        return comparators.contains { comparator in
            let bound = Self.boundVersion(comparator)
            return bound.isPrerelease
                && bound.major == version.major
                && bound.minor == version.minor
                && bound.patch == version.patch
        }
    }

    /// The highest version in `versions` that satisfies the requirement.
    func bestMatch(in versions: [SemanticVersion]) -> SemanticVersion? {
        versions.filter(isSatisfied(by:)).max()
    }

    private static func matches(_ comparator: Comparator, _ version: SemanticVersion) -> Bool {
        switch comparator {
        case let .exact(target):
            return version.major == target.major
                && version.minor == target.minor
                && version.patch == target.patch
                && version.prerelease == target.prerelease
        case let .greater(target): return version > target
        case let .greaterOrEqual(target): return version >= target
        case let .less(target): return version < target
        case let .lessOrEqual(target): return version <= target
        case let .range(lower, upper):
            guard version >= lower else { return false }
            guard let upper else { return true }
            return version < upper
        }
    }

    private static func boundVersion(_ comparator: Comparator) -> SemanticVersion {
        switch comparator {
        case let .exact(version), let .greater(version), let .greaterOrEqual(version),
             let .less(version), let .lessOrEqual(version):
            return version
        case let .range(lower, _):
            return lower
        }
    }

    /// Returns `.some(nil)` for the wildcard, which imposes no constraint.
    private static func parseComparator(_ raw: String) -> Comparator?? {
        var body = raw.trimmingCharacters(in: .whitespaces)
        guard !body.isEmpty else { return .some(nil) }

        func take(_ prefix: String) -> Bool {
            guard body.hasPrefix(prefix) else { return false }
            body = String(body.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            return true
        }

        if take(">=") { return SemanticVersion(padding: body).map { .greaterOrEqual($0) } }
        if take("<=") { return SemanticVersion(padding: body).map { .lessOrEqual($0) } }
        if take("!=") { return nil } // Cargo does not support this; refuse the requirement.
        if take(">") { return SemanticVersion(padding: body).map { .greater($0) } }
        if take("<") { return SemanticVersion(padding: body).map { .less($0) } }
        if take("=") { return SemanticVersion(padding: body).map { .exact($0) } }
        if take("~") { return tilde(body).map { Comparator.range(lower: $0.0, upper: $0.1) } }
        let hasExplicitCaret = take("^")

        if body == "*" || body.isEmpty { return .some(nil) }
        let versionCore = body.split(separator: "-", maxSplits: 1).first.map(String.init) ?? body
        let hasWildcardComponent = versionCore
            .split(separator: ".", omittingEmptySubsequences: false)
            .map(String.init)
            .contains(where: isWildcard)
        if hasWildcardComponent {
            guard !hasExplicitCaret, let bounds = wildcard(body) else { return nil }
            return .some(.range(lower: bounds.0, upper: bounds.1))
        }
        return caret(body).map { Comparator.range(lower: $0.0, upper: $0.1) }
    }

    /// Cargo wildcards constrain exactly the component where the wildcard is
    /// written: `1.*` ends before 2.0, while `1.2.*` ends before 1.3. This is
    /// deliberately separate from caret parsing because `1.2` and `1.2.*`
    /// have different upper bounds.
    private static func wildcard(_ body: String) -> (SemanticVersion, SemanticVersion)? {
        let components = body
            .split(separator: ".", omittingEmptySubsequences: false)
            .map(String.init)
        guard components.count == 2 || components.count == 3,
              components.last.map(isWildcard) == true,
              !components.dropLast().contains(where: isWildcard),
              let major = Int(components[0]),
              major >= 0
        else {
            return nil
        }

        if components.count == 2 {
            return (
                SemanticVersion(major: major, minor: 0, patch: 0),
                SemanticVersion(major: major + 1, minor: 0, patch: 0)
            )
        }

        guard let minor = Int(components[1]), minor >= 0 else { return nil }
        return (
            SemanticVersion(major: major, minor: minor, patch: 0),
            SemanticVersion(major: major, minor: minor + 1, patch: 0)
        )
    }

    private static func isWildcard(_ component: String) -> Bool {
        component == "*" || component.lowercased() == "x"
    }

    /// `^` semantics, including Cargo's zero-version narrowing.
    private static func caret(_ body: String) -> (SemanticVersion, SemanticVersion?)? {
        guard let parts = numericParts(body) else { return nil }
        let lower = SemanticVersion(
            major: parts.major,
            minor: parts.minor ?? 0,
            patch: parts.patch ?? 0,
            prerelease: parts.prerelease
        )
        let upper: SemanticVersion
        if parts.major != 0 {
            upper = SemanticVersion(major: parts.major + 1, minor: 0, patch: 0)
        } else if let minor = parts.minor, minor != 0 {
            upper = SemanticVersion(major: 0, minor: minor + 1, patch: 0)
        } else if let minor = parts.minor, let patch = parts.patch {
            // ^0.0.z is only compatible with itself.
            upper = SemanticVersion(major: 0, minor: minor, patch: patch + 1)
        } else if parts.minor != nil {
            upper = SemanticVersion(major: 0, minor: 1, patch: 0)
        } else {
            upper = SemanticVersion(major: 1, minor: 0, patch: 0)
        }
        return (lower, upper)
    }

    /// `~` semantics: the last specified component may not change.
    private static func tilde(_ body: String) -> (SemanticVersion, SemanticVersion?)? {
        guard let parts = numericParts(body) else { return nil }
        let lower = SemanticVersion(
            major: parts.major,
            minor: parts.minor ?? 0,
            patch: parts.patch ?? 0,
            prerelease: parts.prerelease
        )
        let upper: SemanticVersion = parts.minor == nil
            ? SemanticVersion(major: parts.major + 1, minor: 0, patch: 0)
            : SemanticVersion(major: parts.major, minor: (parts.minor ?? 0) + 1, patch: 0)
        return (lower, upper)
    }

    private struct NumericParts {
        var major: Int
        var minor: Int?
        var patch: Int?
        var prerelease: [String] = []
    }

    /// Splits numeric caret/tilde requirements such as `1.2.3-beta.1`.
    private static func numericParts(_ body: String) -> NumericParts? {
        var text = body
        var prerelease: [String] = []
        if let plus = text.firstIndex(of: "+") { text = String(text[..<plus]) }
        if let dash = text.firstIndex(of: "-") {
            prerelease = text[text.index(after: dash)...]
                .split(separator: ".", omittingEmptySubsequences: false).map(String.init)
            text = String(text[..<dash])
        }
        let components = text.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard (1...3).contains(components.count) else { return nil }

        var numbers: [Int] = []
        for component in components {
            guard let value = Int(component), value >= 0 else { return nil }
            numbers.append(value)
        }
        guard let major = numbers.first else { return nil }
        var parts = NumericParts(major: major, prerelease: prerelease)
        if numbers.count > 1 { parts.minor = numbers[1] }
        if numbers.count > 2 { parts.patch = numbers[2] }
        return parts
    }
}

private extension SemanticVersion {
    /// Parses a possibly partial version such as `1` or `1.2` for comparators
    /// like `>=1.2`, where Cargo treats the missing components as zero.
    init?(padding text: String) {
        guard let parsed = SemanticVersion(text) else { return nil }
        self = parsed
    }
}
