import Foundation

enum SourceLanguage: String, Sendable {
    case rust = "Rust"
    case html = "HTML"
    case css = "CSS"
    case javascript = "JavaScript"
    case typescript = "TypeScript"
    case json = "JSON"
    case toml = "TOML"
    case markdown = "Markdown"
    case yaml = "YAML"
    case plainText = "Plain text"

    init(filePath: String) {
        switch (filePath as NSString).pathExtension.lowercased() {
        case "rs": self = .rust
        case "html", "htm": self = .html
        case "css": self = .css
        case "js", "mjs", "cjs", "jsx": self = .javascript
        case "ts", "tsx": self = .typescript
        case "json": self = .json
        case "toml", "lock": self = .toml
        case "md", "markdown": self = .markdown
        case "yaml", "yml": self = .yaml
        default: self = .plainText
        }
    }

    var supportsCompletion: Bool {
        [.rust, .html, .css, .javascript, .typescript, .json, .toml].contains(self)
    }
}
