import Foundation

/// A deliberately small TOML reader.
///
/// Crabrix only needs to understand the manifest subset that Cargo itself
/// writes: tables, arrays of tables, dotted keys, strings, integers, booleans,
/// arrays, and inline tables. Dates are kept as their literal text because no
/// Cargo key Crabrix reads is a date.
indirect enum TOMLValue: Equatable, Sendable {
    case string(String)
    case integer(Int64)
    case double(Double)
    case boolean(Bool)
    case array([TOMLValue])
    case table([String: TOMLValue])

    var stringValue: String? {
        if case let .string(value) = self { return value }
        return nil
    }

    var boolValue: Bool? {
        if case let .boolean(value) = self { return value }
        return nil
    }

    var integerValue: Int64? {
        if case let .integer(value) = self { return value }
        return nil
    }

    var arrayValue: [TOMLValue]? {
        if case let .array(value) = self { return value }
        return nil
    }

    var tableValue: [String: TOMLValue]? {
        if case let .table(value) = self { return value }
        return nil
    }

    var stringArrayValue: [String]? {
        arrayValue?.compactMap(\.stringValue)
    }

    subscript(key: String) -> TOMLValue? {
        tableValue?[key]
    }
}

enum TOMLParseError: LocalizedError, Equatable {
    case unexpectedCharacter(Character, line: Int)
    case unterminatedString(line: Int)
    case invalidKey(line: Int)
    case invalidValue(line: Int)
    case duplicateKey(String, line: Int)
    case tooLarge

    var errorDescription: String? {
        switch self {
        case let .unexpectedCharacter(character, line):
            "Unexpected character '\(character)' on line \(line)."
        case let .unterminatedString(line):
            "Unterminated string starting on line \(line)."
        case let .invalidKey(line):
            "Invalid key on line \(line)."
        case let .invalidValue(line):
            "Invalid value on line \(line)."
        case let .duplicateKey(key, line):
            "Duplicate key '\(key)' on line \(line)."
        case .tooLarge:
            "The manifest is larger than Crabrix parses."
        }
    }
}

enum TOMLParser {
    /// Manifests are text the app downloads from a registry. Cap the input so a
    /// hostile `Cargo.toml` cannot turn parsing into a denial of service.
    static let maximumInputBytes = 4 * 1024 * 1024

    static func parse(_ source: String) throws -> [String: TOMLValue] {
        guard source.utf8.count <= maximumInputBytes else { throw TOMLParseError.tooLarge }
        var scanner = Scanner(source: Array(source))
        return try scanner.parseDocument()
    }

    private struct Scanner {
        let source: [Character]
        var index = 0
        var line = 1

        /// Root document being assembled.
        var root: [String: TOMLValue] = [:]
        /// Path of the table that plain `key = value` lines currently target.
        var currentPath: [String] = []

        init(source: [Character]) {
            self.source = source
        }

        var isAtEnd: Bool { index >= source.count }

        var current: Character? { isAtEnd ? nil : source[index] }

        mutating func advance() {
            guard !isAtEnd else { return }
            if source[index] == "\n" { line += 1 }
            index += 1
        }

        mutating func parseDocument() throws -> [String: TOMLValue] {
            while true {
                skipWhitespaceAndComments(includingNewlines: true)
                guard let character = current else { break }
                if character == "[" {
                    try parseTableHeader()
                } else {
                    let (path, value) = try parseKeyValue()
                    try insert(value, at: currentPath + path, allowMerge: false)
                }
            }
            return root
        }

        // MARK: - Structure

        private mutating func parseTableHeader() throws {
            advance() // [
            var isArrayOfTables = false
            if current == "[" {
                isArrayOfTables = true
                advance()
            }
            skipInlineWhitespace()
            let path = try parseKeyPath()
            skipInlineWhitespace()
            guard current == "]" else { throw TOMLParseError.invalidKey(line: line) }
            advance()
            if isArrayOfTables {
                guard current == "]" else { throw TOMLParseError.invalidKey(line: line) }
                advance()
            }
            try requireEndOfLine()

            if isArrayOfTables {
                try appendArrayOfTables(at: path)
            } else {
                try ensureTable(at: path)
            }
            currentPath = path
        }

        private mutating func parseKeyValue() throws -> ([String], TOMLValue) {
            let path = try parseKeyPath()
            skipInlineWhitespace()
            guard current == "=" else { throw TOMLParseError.invalidKey(line: line) }
            advance()
            skipInlineWhitespace()
            let value = try parseValue()
            try requireEndOfLine()
            return (path, value)
        }

        private mutating func parseKeyPath() throws -> [String] {
            var path: [String] = []
            while true {
                skipInlineWhitespace()
                path.append(try parseKeyComponent())
                skipInlineWhitespace()
                if current == "." {
                    advance()
                    continue
                }
                break
            }
            return path
        }

        private mutating func parseKeyComponent() throws -> String {
            guard let character = current else { throw TOMLParseError.invalidKey(line: line) }
            if character == "\"" || character == "'" {
                return try parseString()
            }
            var key = ""
            while let character = current, character.isBareKeyCharacter {
                key.append(character)
                advance()
            }
            guard !key.isEmpty else { throw TOMLParseError.invalidKey(line: line) }
            return key
        }

        // MARK: - Values

        private mutating func parseValue() throws -> TOMLValue {
            guard let character = current else { throw TOMLParseError.invalidValue(line: line) }
            switch character {
            case "\"", "'":
                return .string(try parseString())
            case "[":
                return try parseArray()
            case "{":
                return try parseInlineTable()
            case "t", "f":
                return .boolean(try parseBoolean())
            default:
                return try parseNumberOrBareLiteral()
            }
        }

        private mutating func parseBoolean() throws -> Bool {
            if matches("true") { return true }
            if matches("false") { return false }
            throw TOMLParseError.invalidValue(line: line)
        }

        private mutating func parseArray() throws -> TOMLValue {
            advance() // [
            var elements: [TOMLValue] = []
            while true {
                skipWhitespaceAndComments(includingNewlines: true)
                if current == "]" {
                    advance()
                    return .array(elements)
                }
                elements.append(try parseValue())
                skipWhitespaceAndComments(includingNewlines: true)
                if current == "," {
                    advance()
                    continue
                }
                skipWhitespaceAndComments(includingNewlines: true)
                guard current == "]" else { throw TOMLParseError.invalidValue(line: line) }
                advance()
                return .array(elements)
            }
        }

        private mutating func parseInlineTable() throws -> TOMLValue {
            advance() // {
            var table: [String: TOMLValue] = [:]
            skipInlineWhitespace()
            if current == "}" {
                advance()
                return .table(table)
            }
            while true {
                skipInlineWhitespace()
                let path = try parseKeyPath()
                skipInlineWhitespace()
                guard current == "=" else { throw TOMLParseError.invalidKey(line: line) }
                advance()
                skipInlineWhitespace()
                let value = try parseValue()
                table = try merging(value, into: table, path: path, allowMerge: false)
                skipInlineWhitespace()
                if current == "," {
                    advance()
                    continue
                }
                guard current == "}" else { throw TOMLParseError.invalidValue(line: line) }
                advance()
                return .table(table)
            }
        }

        private mutating func parseNumberOrBareLiteral() throws -> TOMLValue {
            var literal = ""
            while let character = current,
                  character != ",", character != "]", character != "}",
                  character != "\n", character != "#" {
                literal.append(character)
                advance()
            }
            let trimmed = literal.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { throw TOMLParseError.invalidValue(line: line) }

            let normalized = trimmed.replacingOccurrences(of: "_", with: "")
            if !normalized.contains("."), !normalized.lowercased().contains("e"),
               let integer = Int64(normalized) {
                return .integer(integer)
            }
            if let double = Double(normalized) { return .double(double) }
            // Dates and any other scalar Crabrix does not model stay as text.
            return .string(trimmed)
        }

        private mutating func parseString() throws -> String {
            let startLine = line
            guard let quote = current else { throw TOMLParseError.unterminatedString(line: startLine) }
            let isLiteral = quote == "'"

            if matches(String(repeating: String(quote), count: 3)) {
                // Multi-line strings ignore a newline immediately after the opener.
                if current == "\r" { advance() }
                if current == "\n" { advance() }
                var value = ""
                while true {
                    guard current != nil else {
                        throw TOMLParseError.unterminatedString(line: startLine)
                    }
                    if matches(String(repeating: String(quote), count: 3)) { return value }
                    if !isLiteral, current == "\\" {
                        if let escaped = try parseEscape(multiline: true) { value.append(escaped) }
                        continue
                    }
                    value.append(source[index])
                    advance()
                }
            }

            advance() // opening quote
            var value = ""
            while true {
                guard let character = current, character != "\n" else {
                    throw TOMLParseError.unterminatedString(line: startLine)
                }
                if character == quote {
                    advance()
                    return value
                }
                if !isLiteral, character == "\\" {
                    if let escaped = try parseEscape(multiline: false) { value.append(escaped) }
                    continue
                }
                value.append(character)
                advance()
            }
        }

        /// Returns nil for a line-continuation escape, which contributes nothing.
        private mutating func parseEscape(multiline: Bool) throws -> String? {
            advance() // backslash
            guard let character = current else {
                throw TOMLParseError.unterminatedString(line: line)
            }
            advance()
            switch character {
            case "n": return "\n"
            case "t": return "\t"
            case "r": return "\r"
            case "\"": return "\""
            case "\\": return "\\"
            case "b": return "\u{08}"
            case "f": return "\u{0C}"
            case "0": return "\0"
            case "u", "U":
                let width = character == "u" ? 4 : 8
                var digits = ""
                for _ in 0..<width {
                    guard let digit = current, digit.isHexDigit else {
                        throw TOMLParseError.invalidValue(line: line)
                    }
                    digits.append(digit)
                    advance()
                }
                guard let scalarValue = UInt32(digits, radix: 16),
                      let scalar = Unicode.Scalar(scalarValue) else {
                    throw TOMLParseError.invalidValue(line: line)
                }
                return String(Character(scalar))
            case "\n", "\r", " ", "\t":
                guard multiline else { throw TOMLParseError.invalidValue(line: line) }
                // Trim the escaped newline and every following whitespace character.
                index -= 1
                while let whitespace = current,
                      whitespace == " " || whitespace == "\t"
                        || whitespace == "\n" || whitespace == "\r" {
                    advance()
                }
                return nil
            default:
                throw TOMLParseError.invalidValue(line: line)
            }
        }

        // MARK: - Assembly

        private mutating func ensureTable(at path: [String]) throws {
            root = try merging(.table([:]), into: root, path: path, allowMerge: true)
        }

        private mutating func appendArrayOfTables(at path: [String]) throws {
            root = try appendingArrayOfTables(into: root, path: path)
        }

        private mutating func insert(
            _ value: TOMLValue,
            at path: [String],
            allowMerge: Bool
        ) throws {
            root = try merging(value, into: root, path: path, allowMerge: allowMerge)
        }

        private func merging(
            _ value: TOMLValue,
            into table: [String: TOMLValue],
            path: [String],
            allowMerge: Bool
        ) throws -> [String: TOMLValue] {
            guard let head = path.first else { return table }
            var table = table
            if path.count == 1 {
                if let existing = table[head] {
                    // A later `[a.b]` header may re-open a table an earlier dotted
                    // key created. Merging keeps both halves.
                    if case let .table(existingTable) = existing,
                       case let .table(newTable) = value {
                        guard allowMerge || newTable.isEmpty else {
                            throw TOMLParseError.duplicateKey(head, line: line)
                        }
                        table[head] = .table(existingTable.merging(newTable) { _, new in new })
                        return table
                    }
                    if case .array = existing, case let .table(newTable) = value, newTable.isEmpty {
                        return table
                    }
                    throw TOMLParseError.duplicateKey(head, line: line)
                }
                table[head] = value
                return table
            }

            let rest = Array(path.dropFirst())
            switch table[head] {
            case let .table(child):
                table[head] = .table(try merging(value, into: child, path: rest, allowMerge: allowMerge))
            case var .array(elements):
                // Keys under `[[a]]` land in the most recent element.
                guard case let .table(last)? = elements.last else {
                    throw TOMLParseError.duplicateKey(head, line: line)
                }
                elements[elements.count - 1] = .table(
                    try merging(value, into: last, path: rest, allowMerge: allowMerge)
                )
                table[head] = .array(elements)
            case .none:
                table[head] = .table(try merging(value, into: [:], path: rest, allowMerge: allowMerge))
            default:
                throw TOMLParseError.duplicateKey(head, line: line)
            }
            return table
        }

        private func appendingArrayOfTables(
            into table: [String: TOMLValue],
            path: [String]
        ) throws -> [String: TOMLValue] {
            guard let head = path.first else { return table }
            var table = table
            if path.count == 1 {
                switch table[head] {
                case var .array(elements):
                    elements.append(.table([:]))
                    table[head] = .array(elements)
                case .none:
                    table[head] = .array([.table([:])])
                default:
                    throw TOMLParseError.duplicateKey(head, line: line)
                }
                return table
            }

            let rest = Array(path.dropFirst())
            switch table[head] {
            case let .table(child):
                table[head] = .table(try appendingArrayOfTables(into: child, path: rest))
            case var .array(elements):
                guard case let .table(last)? = elements.last else {
                    throw TOMLParseError.duplicateKey(head, line: line)
                }
                elements[elements.count - 1] = .table(
                    try appendingArrayOfTables(into: last, path: rest)
                )
                table[head] = .array(elements)
            case .none:
                table[head] = .table(try appendingArrayOfTables(into: [:], path: rest))
            default:
                throw TOMLParseError.duplicateKey(head, line: line)
            }
            return table
        }

        // MARK: - Lexing helpers

        private mutating func matches(_ text: String) -> Bool {
            let characters = Array(text)
            guard index + characters.count <= source.count else { return false }
            for offset in characters.indices where source[index + offset] != characters[offset] {
                return false
            }
            for _ in characters { advance() }
            return true
        }

        private mutating func skipInlineWhitespace() {
            while let character = current, character == " " || character == "\t" {
                advance()
            }
        }

        private mutating func skipWhitespaceAndComments(includingNewlines: Bool) {
            while let character = current {
                if character == " " || character == "\t" || character == "\r" {
                    advance()
                } else if character == "\n", includingNewlines {
                    advance()
                } else if character == "#" {
                    while let comment = current, comment != "\n" { advance() }
                } else {
                    return
                }
            }
        }

        private mutating func requireEndOfLine() throws {
            skipWhitespaceAndComments(includingNewlines: false)
            guard let character = current else { return }
            guard character == "\n" else {
                throw TOMLParseError.unexpectedCharacter(character, line: line)
            }
            advance()
        }
    }
}

private extension Character {
    var isBareKeyCharacter: Bool {
        isLetter || isNumber || self == "_" || self == "-"
    }
}
