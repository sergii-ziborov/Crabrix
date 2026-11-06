import Foundation

/// Source labels, not every non-negative scalar. Parameters such as cost or a
/// window size are not automatically indices into every visible collection.
enum AtlasIndexBindings {
    static func collect(source: String) -> [String: Set<String>] {
        let code = NSMutableString(string: source)
        for token in SyntaxHighlighter.tokens(in: source, filePath: "example.rs")
            where token.kind == .comment || token.kind == .string {
            code.replaceCharacters(in: token.range, with: String(repeating: " ", count: token.range.length))
        }
        let text = code as String, range = NSRange(location: 0, length: code.length)
        var result: [String: Set<String>] = [:]
        let identifier = #"[A-Za-z_][A-Za-z0-9_]*"#
        if let access = try? NSRegularExpression(pattern: #"\b(\#(identifier))\s*((?:\[\s*\#(identifier)\s*\])+)"#),
           let index = try? NSRegularExpression(pattern: #"\[\s*(\#(identifier))\s*\]"#) {
            for match in access.matches(in: text, range: range) {
                let name = code.substring(with: match.range(at: 1))
                let expression = code.substring(with: match.range(at: 2)) as NSString
                for variable in index.matches(in: expression as String, range: NSRange(location: 0, length: expression.length)) {
                    result[name, default: []].insert(expression.substring(with: variable.range(at: 1)))
                }
            }
        }
        if let enumeration = try? NSRegularExpression(pattern:
            #"\bfor\s*\(\s*(?:mut\s+)?(\#(identifier))\s*,[^\n]*?\)\s+in\s+(\#(identifier))\s*\.\s*(?:iter|iter_mut|into_iter)\s*\(\s*\)\s*\.\s*enumerate\s*\("#) {
            for match in enumeration.matches(in: text, range: range) {
                result[code.substring(with: match.range(at: 2)), default: []].insert(code.substring(with: match.range(at: 1)))
            }
        }
        return result
    }
}
