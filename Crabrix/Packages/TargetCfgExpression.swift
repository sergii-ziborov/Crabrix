import Foundation

enum TargetMatchResult: Sendable, Equatable {
    case yes
    case no
    case unknown(reason: String)

    var isMatch: Bool { self == .yes }
}

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
    /// Canonical facts captured from the exact bundled compiler with:
    /// `rustc --print cfg --target wasm32-wasip1`.
    let cfgFlags: Set<String>
    let cfgValues: [String: Set<String>]

    static let wasm32WasiP1 = RustTargetSpec(
        triple: "wasm32-wasip1",
        arch: "wasm32",
        os: "wasi",
        env: "p1",
        family: "wasm",
        vendor: "unknown",
        pointerWidth: "32",
        endian: "little",
        cfgFlags: [
            "debug_assertions",
            "emscripten_wasm_eh",
            "overflow_checks",
            "target_has_atomic",
            "target_has_atomic_load_store",
            "target_has_reliable_f128",
            "target_has_reliable_f16",
            "target_has_reliable_f16_math",
            "target_thread_local",
            "ub_checks",
        ],
        cfgValues: [
            "fmt_debug": ["full"],
            "panic": ["abort"],
            "relocation_model": ["static"],
            "target_abi": [""],
            "target_arch": ["wasm32"],
            "target_endian": ["little"],
            "target_env": ["p1"],
            "target_family": ["wasm"],
            "target_feature": ["crt-static"],
            "target_has_atomic": ["8", "16", "32", "64", "ptr"],
            "target_has_atomic_equal_alignment": ["8", "16", "32", "64", "ptr"],
            "target_has_atomic_load_store": ["8", "16", "32", "64", "ptr"],
            "target_os": ["wasi"],
            "target_pointer_width": ["32"],
            "target_vendor": ["unknown"],
        ]
    )

    /// rustc still reports the historical triple name for this target, and older
    /// crates spell the predicate either way.
    var acceptedTriples: Set<String> {
        [triple, "wasm32-wasi", "wasm32-unknown-wasi"]
    }

    func matches(key: String, value: String) -> Bool {
        cfgValues[key]?.contains(value) == true
    }

    /// Bare predicates such as `unix` or `windows`.
    func flag(_ name: String) -> Bool {
        cfgFlags.contains(name)
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
    /// A predicate Crabrix could not parse or model. It is never guessed true
    /// or false by boolean negation/composition.
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

    func matchResult(_ target: RustTargetSpec) -> TargetMatchResult {
        switch self {
        case let .triple(value):
            return target.acceptedTriples.contains(value) ? .yes : .no
        case let .all(children):
            let results = children.map { $0.matchResult(target) }
            if results.contains(.no) { return .no }
            return results.first(where: {
                if case .unknown = $0 { true } else { false }
            }) ?? .yes
        case let .any(children):
            let results = children.map { $0.matchResult(target) }
            if results.contains(.yes) { return .yes }
            return results.first(where: {
                if case .unknown = $0 { true } else { false }
            }) ?? .no
        case let .not(child):
            switch child.matchResult(target) {
            case .yes: return .no
            case .no: return .yes
            case let .unknown(reason): return .unknown(reason: reason)
            }
        case let .keyValue(key, value):
            return target.matches(key: key, value: value) ? .yes : .no
        case let .flag(name):
            return target.flag(name) ? .yes : .no
        case let .unsupported(raw):
            return .unknown(reason: "Could not evaluate target predicate \"\(raw)\".")
        }
    }

    /// Compatibility convenience for UI/tests. Resolution uses `matchResult`
    /// and rejects `.unknown` rather than silently treating it as false.
    func matches(_ target: RustTargetSpec) -> Bool {
        matchResult(target).isMatch
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
