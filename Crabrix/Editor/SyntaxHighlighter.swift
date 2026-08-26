import Foundation

enum SyntaxTokenKind: String, CaseIterable, Sendable {
    case comment
    case string
    case keyword
    case type
    case number
    case macro
    case attribute
    case section
    case key
}

struct SyntaxToken: Equatable, Sendable {
    let kind: SyntaxTokenKind
    let range: NSRange
}

enum SyntaxHighlighter {
    static func tokens(in source: String, filePath: String) -> [SyntaxToken] {
        switch URL(fileURLWithPath: filePath).pathExtension.lowercased() {
        case "rs": rustTokens(in: source)
        case "toml", "lock": tomlTokens(in: source)
        default: []
        }
    }

    private static func rustTokens(in source: String) -> [SyntaxToken] {
        let keywords = [
            "as", "async", "await", "break", "const", "continue", "crate", "dyn", "else",
            "enum", "extern", "false", "fn", "for", "if", "impl", "in", "let", "loop",
            "match", "mod", "move", "mut", "pub", "ref", "return", "self", "Self", "static",
            "struct", "super", "trait", "true", "type", "unsafe", "use", "where", "while",
        ].joined(separator: "|")
        let types = [
            "bool", "char", "f32", "f64", "i8", "i16", "i32", "i64", "i128", "isize",
            "str", "u8", "u16", "u32", "u64", "u128", "usize", "Box", "Option", "Result",
            "String", "Vec",
        ].joined(separator: "|")
        let pattern = #"""
        (?<comment>//[^\n]*|/\*[\s\S]*?\*/)|(?<string>r(#+)?\"[\s\S]*?\"\2|b?\"(?:\\.|[^\"\\])*\"|'(?:\\.|[^'\\])')|(?<attribute>#!?\[[^\]]*\])|(?<macro>\b[A-Za-z_][A-Za-z0-9_]*!)|(?<keyword>\b(?:\#(keywords))\b)|(?<type>\b(?:\#(types))\b)|(?<number>\b(?:0x[0-9A-Fa-f_]+|0b[01_]+|\d[\d_]*(?:\.\d[\d_]*)?)\b)
        """#
        return matches(
            pattern: pattern,
            source: source,
            groups: [
                ("comment", .comment), ("string", .string), ("attribute", .attribute),
                ("macro", .macro), ("keyword", .keyword), ("type", .type), ("number", .number),
            ]
        )
    }

    private static func tomlTokens(in source: String) -> [SyntaxToken] {
        let pattern = #"""
        (?<comment>#[^\n]*)|(?<section>^\s*\[+[^\]\n]+\]+)|(?<key>^\s*[A-Za-z0-9_.-]+(?=\s*=))|(?<string>\"(?:\\.|[^\"\\])*\"|'[^']*')|(?<keyword>\b(?:true|false)\b)|(?<number>\b\d+(?:\.\d+)*\b)
        """#
        return matches(
            pattern: pattern,
            source: source,
            options: [.anchorsMatchLines],
            groups: [
                ("comment", .comment), ("section", .section), ("key", .key),
                ("string", .string), ("keyword", .keyword), ("number", .number),
            ]
        )
    }

    private static func matches(
        pattern: String,
        source: String,
        options: NSRegularExpression.Options = [],
        groups: [(String, SyntaxTokenKind)]
    ) -> [SyntaxToken] {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: options) else {
            return []
        }
        let fullRange = NSRange(source.startIndex..<source.endIndex, in: source)
        return expression.matches(in: source, range: fullRange).compactMap { match in
            for (group, kind) in groups {
                let range = match.range(withName: group)
                if range.location != NSNotFound { return SyntaxToken(kind: kind, range: range) }
            }
            return nil
        }
    }
}
