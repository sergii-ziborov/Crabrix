import Foundation

/// The compile target Crabrix builds every crate for.
///
/// Registry dependencies carry `target` predicates that decide whether an edge
/// exists at all. Evaluating them locally is what keeps a Windows-only or
/// Linux-only dependency out of an iPad build graph.
struct RustTargetSpec: Sendable, Equatable {
    let triple: String
    let arch: String
    let os: String
    let env: String
    let family: String
    let vendor: String
    let pointerWidth: String
    let endian: String

    static let wasm32WasiP1 = RustTargetSpec(
        triple: "wasm32-wasip1",
        arch: "wasm32",
        os: "wasi",
        env: "p1",
        family: "wasm",
        vendor: "unknown",
        pointerWidth: "32",
        endian: "little"
    )

    /// rustc still reports the historical triple name for this target, and older
    /// crates spell the predicate either way.
    var acceptedTriples: Set<String> {
        [triple, "wasm32-wasi", "wasm32-unknown-wasi"]
    }

    func value(forKey key: String) -> String? {
        switch key {
        case "target_arch": arch
        case "target_os": os
        case "target_env": env
        case "target_family": family
        case "target_vendor": vendor
        case "target_pointer_width": pointerWidth
        case "target_endian": endian
        default: nil
        }
    }

    /// Bare predicates such as `unix` or `windows`.
    func flag(_ name: String) -> Bool {
        switch name {
        case "wasm", "wasi": true
        case "unix", "windows": false
        default: false
        }
    }
}

/// A `cfg(...)` predicate or a literal target triple.
indirect enum TargetCfgExpression: Hashable, Sendable {
    case triple(String)
    case all([TargetCfgExpression])
    case any([TargetCfgExpression])
    case not(TargetCfgExpression)
    case keyValue(String, String)
    case flag(String)
    /// A predicate Crabrix cannot model. Treated as not matching so unknown
    /// platform-specific dependencies stay out of the graph.
    case unsupported(String)

    static func parse(_ raw: String) -> TargetCfgExpression {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("cfg(") else { return .triple(trimmed) }
        var scanner = Scanner(characters: Array(trimmed))
        guard scanner.expectWord("cfg"), scanner.expect("("),
              let expression = scanner.parseExpression(),
              scanner.expect(")"), scanner.isAtEnd
        else {
            return .unsupported(trimmed)
        }
        return expression
    }

    func matches(_ target: RustTargetSpec) -> Bool {
        switch self {
        case let .triple(value):
            return target.acceptedTriples.contains(value)
        case let .all(children):
            return children.allSatisfy { $0.matches(target) }
        case let .any(children):
            return children.contains { $0.matches(target) }
        case let .not(child):
            return !child.matches(target)
        case let .keyValue(key, value):
            guard let actual = target.value(forKey: key) else { return false }
            return actual == value
        case let .flag(name):
            return target.flag(name)
        case .unsupported:
            return false
        }
    }

    private struct Scanner {
        let characters: [Character]
        var index = 0

        var isAtEnd: Bool {
            skippingWhitespaceIndex() >= characters.count
        }

        private func skippingWhitespaceIndex() -> Int {
            var cursor = index
            while cursor < characters.count, characters[cursor].isWhitespace { cursor += 1 }
            return cursor
        }

        mutating func skipWhitespace() {
            index = skippingWhitespaceIndex()
        }

        mutating func expect(_ character: Character) -> Bool {
            skipWhitespace()
            guard index < characters.count, characters[index] == character else { return false }
            index += 1
            return true
        }

        mutating func expectWord(_ word: String) -> Bool {
            skipWhitespace()
            let letters = Array(word)
            guard index + letters.count <= characters.count else { return false }
            for offset in letters.indices where characters[index + offset] != letters[offset] {
                return false
            }
            index += letters.count
            return true
        }

        mutating func parseExpression() -> TargetCfgExpression? {
            skipWhitespace()
            guard index < characters.count else { return nil }

            if peekIdentifier() == "not" {
                _ = expectWord("not")
                guard expect("("), let child = parseExpression(), expect(")") else { return nil }
                return .not(child)
            }
            if peekIdentifier() == "all" || peekIdentifier() == "any" {
                let isAll = peekIdentifier() == "all"
                _ = expectWord(isAll ? "all" : "any")
                guard expect("(") else { return nil }
                var children: [TargetCfgExpression] = []
                skipWhitespace()
                if expect(")") { return isAll ? .all(children) : .any(children) }
                while true {
                    guard let child = parseExpression() else { return nil }
                    children.append(child)
                    skipWhitespace()
                    if expect(",") {
                        skipWhitespace()
                        // Tolerate a trailing comma before the closing paren.
                        if expect(")") { break }
                        continue
                    }
                    guard expect(")") else { return nil }
                    break
                }
                return isAll ? .all(children) : .any(children)
            }

            guard let key = readIdentifier() else { return nil }
            skipWhitespace()
            guard expect("=") else { return .flag(key) }
            skipWhitespace()
            guard let value = readQuotedString() else { return nil }
            return .keyValue(key, value)
        }

        private func peekIdentifier() -> String? {
            var cursor = skippingWhitespaceIndex()
            var word = ""
            while cursor < characters.count, characters[cursor].isIdentifier {
                word.append(characters[cursor])
                cursor += 1
            }
            return word.isEmpty ? nil : word
        }

        private mutating func readIdentifier() -> String? {
            skipWhitespace()
            var word = ""
            while index < characters.count, characters[index].isIdentifier {
                word.append(characters[index])
                index += 1
            }
            return word.isEmpty ? nil : word
        }

        private mutating func readQuotedString() -> String? {
            skipWhitespace()
            guard index < characters.count, characters[index] == "\"" else { return nil }
            index += 1
            var value = ""
            while index < characters.count, characters[index] != "\"" {
                value.append(characters[index])
                index += 1
            }
            guard index < characters.count else { return nil }
            index += 1
            return value
        }
    }
}

private extension Character {
    var isIdentifier: Bool { isLetter || isNumber || self == "_" }
}
