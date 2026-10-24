import Foundation

enum WebLocalCompleter {
    static func suggestion(for prefix: String, language: SourceLanguage) -> RustCodeCompletion? {
        let line = prefix.components(separatedBy: "\n").last?.trimmingCharacters(in: .whitespaces) ?? ""
        let candidates: [(String, String)]
        switch language {
        case .html:
            candidates = [("<!doc", "<!doctype html>"), ("<but", "<button type=\"button\">Click</button>"),
                          ("<scr", "<script src=\"app.js\" defer></script>"),
                          ("<lin", "<link rel=\"stylesheet\" href=\"styles.css\">"),
                          ("<mai", "<main>\n    \n</main>")]
        case .javascript, .typescript:
            candidates = [("document.query", "document.querySelector(\"#counter\")"),
                          ("console.lo", "console.log(\"Hello, Crabrix!\");"),
                          ("addEvent", "addEventListener(\"click\", () => {\n    \n});")]
        case .css:
            candidates = [("display: fl", "display: flex;"), ("display: gr", "display: grid;"),
                          ("@media (pref", "@media (prefers-reduced-motion: reduce) {\n    * { animation: none; transition: none; }\n}")]
        default: return nil
        }
        guard let candidate = candidates.first(where: { line.hasSuffix($0.0) }) else { return nil }
        return RustCodeCompletion(insertion: String(candidate.1.dropFirst(candidate.0.count)),
            provider: .local, detail: "Local web snippet · no network required")
    }
}
