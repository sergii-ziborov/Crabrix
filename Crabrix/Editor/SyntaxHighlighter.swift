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
        let language = SourceLanguage(filePath: filePath)
        if [.shell, .sql, .http, .dockerfile, .diff, .dotenv].contains(language) {
            return workflowTokens(in: source, language: language)
        }
        return switch URL(fileURLWithPath: filePath).pathExtension.lowercased() {
        case "rs": rustTokens(in: source)
        case "toml", "lock": tomlTokens(in: source)
        default: WebSyntaxHighlighter.tokens(in: source, language: SourceLanguage(filePath: filePath))
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
        (?<comment>//[^\n]*|/\*[\s\S]*?\*/)|(?<string>r(#+)\"[\s\S]*?\"\3|r\"[^\"]*\"|b?\"(?:\\.|[^\"\\])*\"|'(?:\\.|[^'\\])')|(?<attribute>#!?\[[^\]]*\])|(?<macro>\b[A-Za-z_][A-Za-z0-9_]*!)|(?<keyword>\b(?:\#(keywords))\b)|(?<type>\b(?:\#(types))\b)|(?<number>\b(?:0x[0-9A-Fa-f_]+|0b[01_]+|\d[\d_]*(?:\.\d[\d_]*)?)\b)
        """#
        let tokens = matches(
            pattern: pattern,
            source: source,
            groups: [
                ("comment", .comment), ("string", .string), ("attribute", .attribute),
                ("macro", .macro), ("keyword", .keyword), ("type", .type), ("number", .number),
            ]
        )
        // Regex finds the first block-comment terminator. Rust comments nest;
        // expand the opaque region and discard any inner regex tokens.
        let units = Array(source.utf16)
        var result: [SyntaxToken] = []
        var opaqueEnd = 0
        for token in tokens {
            guard token.range.location >= opaqueEnd else { continue }
            let start = token.range.location
            if token.kind == .comment, start + 1 < units.count,
               units[start] == 47, units[start + 1] == 42 {
                var cursor = start + 2
                var depth = 1
                while cursor < units.count, depth > 0 {
                    if cursor + 1 < units.count, units[cursor] == 47, units[cursor + 1] == 42 {
                        depth += 1; cursor += 2
                    } else if cursor + 1 < units.count, units[cursor] == 42, units[cursor + 1] == 47 {
                        depth -= 1; cursor += 2
                    } else { cursor += 1 }
                }
                opaqueEnd = cursor
                result.append(SyntaxToken(kind: .comment, range: NSRange(location: start, length: cursor - start)))
            } else { result.append(token) }
        }
        return result
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

    private static func workflowTokens(in source: String, language: SourceLanguage) -> [SyntaxToken] {
        let pattern: String
        var options: NSRegularExpression.Options = [.anchorsMatchLines]
        switch language {
        case .sql:
            options.insert(.caseInsensitive)
            pattern = #"(?<comment>--[^\n]*|/\*[\s\S]*?\*/)|(?<string>'(?:''|[^'])*'|"(?:""|[^"])*"|`[^`]*`)|(?<keyword>\b(?:select|from|where|and|or|not|is|null|as|join|left|right|inner|outer|on|group|by|order|having|limit|offset|asc|desc|create|table|index|unique|primary|key|foreign|references|check|default|insert|into|values|update|set|delete|begin|immediate|commit|rollback|savepoint|release|explain|query|plan|if|exists|drop|alter|add|conflict|do|returning|distinct|case|when|then|else|end)\b)|(?<type>\b(?:integer|int|bigint|text|varchar|real|blob|boolean|numeric|timestamp)\b)|(?<attribute>[:@$][A-Za-z_]\w*|\?[0-9]*)|(?<number>\b\d+(?:\.\d+)?\b)"#
        case .shell, .dotenv:
            pattern = #"(?<comment>(?:^|(?<=\s))#[^\n]*)|(?<string>'[^']*'|"(?:\\.|[^"\\])*")|(?<attribute>\$\{[^}]*\}|\$[A-Za-z_][A-Za-z_0-9]*|--?[A-Za-z][\w-]*)|(?<key>\b[A-Za-z_][A-Za-z_0-9]*(?==))|(?<keyword>\b(?:git|cargo|rustfmt|curl|http|sqlite3|sql|env|echo|cat|grep|head|tail|wc|pwd|cd|ls|mkdir|cp|mv|rm|touch|sh|bash|docker|npm|crabrix|if|then|else|fi|for|in|do|done|export|set|exit|printf)\b)|(?<section>&&|\|\||[|<>;])|(?<number>\b\d+\b)"#
        case .dockerfile:
            options.insert(.caseInsensitive)
            pattern = #"(?<comment>^\s*#[^\n]*)|(?<string>"(?:\\.|[^"\\])*"|'[^']*')|(?<keyword>^\s*(?:from|run|cmd|entrypoint|copy|add|workdir|env|arg|expose|user|healthcheck|label|volume|shell|stopsignal)\b)|(?<attribute>--[\w-]+|\$\{[^}]*\})|(?<number>\b\d+\b)"#
        case .diff:
            pattern = #"(?<section>^(?:diff |index |@@)[^\n]*)|(?<string>^\+[^\n]*)|(?<keyword>^-[^\n]*)"#
        case .http:
            pattern = #"(?<comment>^\s*#[^\n]*)|(?<keyword>\b(?:GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS|HTTP/1\.[01])\b)|(?<key>^[A-Za-z][A-Za-z0-9-]*(?=:))|(?<string>"(?:\\.|[^"\\])*")|(?<attribute>https?://[^\s]+)|(?<number>\b\d+\b)"#
        default: return []
        }
        return matches(pattern: pattern, source: source, options: options, groups: [
            ("comment", .comment), ("string", .string), ("keyword", .keyword),
            ("type", .type), ("number", .number), ("attribute", .attribute),
            ("section", .section), ("key", .key),
        ].filter { pattern.contains("?<" + $0.0 + ">") })
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
