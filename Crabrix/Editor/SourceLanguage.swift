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
    case shell = "Shell"
    case sql = "SQL"
    case http = "HTTP"
    case dockerfile = "Dockerfile"
    case diff = "Diff"
    case dotenv = "Environment"
    case plainText = "Plain text"

    init(filePath: String) {
        let name = (filePath as NSString).lastPathComponent.lowercased()
        if name == "dockerfile" || name.hasPrefix("dockerfile.") { self = .dockerfile; return }
        if name == ".env" || name.hasPrefix(".env.") { self = .dotenv; return }
        switch (filePath as NSString).pathExtension.lowercased() {
        case "rs": self = .rust
        case "html", "htm": self = .html
        case "css": self = .css
        case "js", "mjs", "cjs", "jsx": self = .javascript
        case "ts", "tsx", "mts", "cts": self = .typescript
        case "json": self = .json
        case "toml", "lock": self = .toml
        case "md", "markdown": self = .markdown
        case "yaml", "yml": self = .yaml
        case "sh", "bash", "zsh": self = .shell
        case "sql": self = .sql
        case "http", "rest": self = .http
        case "dockerfile": self = .dockerfile
        case "diff", "patch": self = .diff
        default: self = .plainText
        }
    }

    var supportsCompletion: Bool {
        [.rust, .html, .css, .javascript, .typescript, .json, .toml].contains(self)
    }
}
