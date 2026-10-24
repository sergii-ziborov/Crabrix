import Foundation
import JavaScriptCore

/// Runs only the bundled grammar. Project JavaScript is tokenized as text;
/// it is never evaluated in this context.
enum WebSyntaxHighlighter {
    private final class Grammar: @unchecked Sendable {
        let queue = DispatchQueue(label: "com.crabrix.web-syntax", qos: .userInitiated)
        var context: JSContext?
        func tokens(_ source: String, language: String) -> [SyntaxToken] {
            queue.sync {
                if context == nil, let url = Bundle.main.url(forResource: "WebSyntax", withExtension: "js"),
                   let script = try? String(contentsOf: url, encoding: .utf8), let created = JSContext() {
                    created.evaluateScript(script)
                    if created.exception == nil { context = created }
                }
                guard let context else { return [] }
                context.exception = nil
                guard let function = context.objectForKeyedSubscript("crabrixHighlighter"),
                      let rows = function.call(withArguments: [source, language])?.toArray() as? [[String: Any]],
                      context.exception == nil else { return [] }
                let count = (source as NSString).length
                return rows.compactMap { row in
                    guard let raw = row["kind"] as? String, let kind = SyntaxTokenKind(rawValue: raw),
                          let start = row["start"] as? Int, let length = row["length"] as? Int,
                          start >= 0, length > 0, start <= count, length <= count - start else { return nil }
                    return SyntaxToken(kind: kind, range: NSRange(location: start, length: length))
                }
            }
        }
    }
    private static let grammar = Grammar()
    static func tokens(in source: String, language: SourceLanguage) -> [SyntaxToken] {
        let name: String
        switch language {
        case .html: name = "xml"
        case .css: name = "css"
        case .javascript: name = "javascript"
        case .typescript: name = "typescript"
        case .json: name = "json"
        case .markdown: name = "markdown"
        case .yaml: name = "yaml"
        default: return []
        }
        return grammar.tokens(source, language: name)
    }
}
