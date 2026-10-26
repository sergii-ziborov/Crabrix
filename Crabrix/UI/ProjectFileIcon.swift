import SwiftUI

/// Shared by the project tree, open-file label and file picker menu.
struct ProjectFileAppearance {
    let symbol: String
    let tint: Color
    var badge: String? = nil

    static func forPath(_ path: String) -> Self {
        let name = (path as NSString).lastPathComponent.lowercased()
        let ext = (name as NSString).pathExtension
        if name == "cargo.toml" { return Self(symbol: "shippingbox.fill", tint: CrabrixTheme.amber) }
        if name == "package.json" { return Self(symbol: "shippingbox.fill", tint: CrabrixTheme.mint) }
        if ext == "lock" || ext == "lockb"
            || ["package-lock.json", "npm-shrinkwrap.json", "pnpm-lock.yaml"].contains(name) {
            return Self(symbol: "lock.fill", tint: CrabrixTheme.amber)
        }
        switch name {
        case "main.rs": return Self(symbol: "play.square.fill", tint: CrabrixTheme.coral)
        case "lib.rs": return Self(symbol: "books.vertical.fill", tint: CrabrixTheme.blue)
        case "build.rs": return Self(symbol: "hammer.fill", tint: CrabrixTheme.amber)
        case "mod.rs": return Self(symbol: "square.stack.3d.up.fill", tint: CrabrixTheme.mint)
        case ".gitignore", ".gitattributes", ".gitmodules":
            return Self(symbol: "arrow.triangle.branch", tint: CrabrixTheme.muted)
        default: break
        }
        if name.hasPrefix("license") || name.hasPrefix("copying") {
            return Self(symbol: "checkmark.seal.fill", tint: CrabrixTheme.mint)
        }
        if name == "tsconfig.json" || name.hasPrefix("tsconfig.") && ext == "json" {
            return Self(symbol: "gearshape.fill", tint: CrabrixTheme.blue)
        }
        if ext == "svg" { return Self(symbol: "bezier.path", tint: CrabrixTheme.violet) }
        if ["png", "jpg", "jpeg", "gif", "webp", "ico"].contains(ext) {
            return Self(symbol: "photo.fill", tint: CrabrixTheme.violet)
        }
        switch SourceLanguage(filePath: path) {
        case .rust:
            return Self(symbol: "chevron.left.forwardslash.chevron.right", tint: CrabrixTheme.coral)
        case .html:
            return Self(symbol: "chevron.left.forwardslash.chevron.right", tint: CrabrixTheme.coral, badge: "<>")
        case .css:
            return Self(symbol: "number", tint: CrabrixTheme.violet, badge: "#")
        case .javascript:
            return Self(symbol: "j.square.fill", tint: CrabrixTheme.amber, badge: ext == "jsx" ? "JSX" : "JS")
        case .typescript:
            return Self(symbol: "t.square.fill", tint: CrabrixTheme.blue, badge: ext == "tsx" ? "TSX" : "TS")
        case .json:
            return Self(symbol: "curlybraces", tint: CrabrixTheme.mint)
        case .toml:
            return Self(symbol: "slider.horizontal.3", tint: CrabrixTheme.amber)
        case .yaml:
            return Self(symbol: "list.bullet.rectangle", tint: CrabrixTheme.violet)
        case .markdown:
            return Self(symbol: "doc.richtext.fill", tint: CrabrixTheme.blue)
        case .plainText:
            return Self(symbol: "doc.text", tint: CrabrixTheme.muted)
        }
    }
}

struct ProjectFileIcon: View {
    let path: String

    var body: some View {
        let appearance = ProjectFileAppearance.forPath(path)
        Group {
            if let badge = appearance.badge {
                Text(badge)
                    .font(.system(size: badge.count > 2 ? 7 : 9, weight: .heavy, design: .monospaced))
                    .foregroundStyle(Color.black.opacity(0.9))
                    .frame(width: 18, height: 18)
                    .background(appearance.tint, in: RoundedRectangle(cornerRadius: 3))
            } else {
                Image(systemName: appearance.symbol)
                    .foregroundStyle(appearance.tint)
                    .frame(width: 18)
            }
        }
        .accessibilityHidden(true)
    }
}
