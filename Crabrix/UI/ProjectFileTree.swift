import SwiftUI

struct ProjectFileTree: View {
    let paths: [String]
    let selectedPath: String
    let onSelect: (String) -> Void

    private var nodes: [ProjectTreeNode] {
        ProjectTreeNode.build(paths: paths)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(nodes) { node in
                ProjectTreeBranch(node: node, selectedPath: selectedPath, onSelect: onSelect)
            }
        }
    }
}

private struct ProjectTreeBranch: View {
    let node: ProjectTreeNode
    let selectedPath: String
    let onSelect: (String) -> Void
    @State private var isExpanded = true

    var body: some View {
        if node.isDirectory {
            DisclosureGroup(isExpanded: $isExpanded) {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(node.children) { child in
                        ProjectTreeBranch(node: child, selectedPath: selectedPath, onSelect: onSelect)
                    }
                }
                .padding(.leading, 12)
            } label: {
                Label(node.name, systemImage: isExpanded ? "folder.fill" : "folder")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(CrabrixTheme.blue)
                    .padding(.vertical, 5)
            }
            .tint(CrabrixTheme.muted)
        } else {
            Button {
                onSelect(node.path)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: fileIcon(for: node.path).name)
                        .foregroundStyle(fileIcon(for: node.path).tint)
                        .frame(width: 18)
                    Text(node.name)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(CrabrixTheme.primary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
                .background(node.path == selectedPath ? fileIcon(for: node.path).tint.opacity(0.14) : .clear)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    if node.path == selectedPath {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(fileIcon(for: node.path).tint.opacity(0.35))
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func fileIcon(for path: String) -> (name: String, tint: Color) {
        let name = path.split(separator: "/").last.map(String.init) ?? path
        if name == "Cargo.toml" { return ("shippingbox.fill", CrabrixTheme.amber) }
        if name == "Cargo.lock" || path.hasSuffix(".lock") {
            return ("lock.fill", CrabrixTheme.amber)
        }
        if name == "main.rs" { return ("play.square.fill", CrabrixTheme.coral) }
        if name == "lib.rs" { return ("books.vertical.fill", CrabrixTheme.blue) }
        if name == "build.rs" { return ("hammer.fill", CrabrixTheme.amber) }
        if name == "mod.rs" { return ("square.stack.3d.up.fill", CrabrixTheme.mint) }
        if path.hasSuffix(".rs") { return ("chevron.left.forwardslash.chevron.right", CrabrixTheme.coral) }
        if path.hasSuffix(".toml") { return ("slider.horizontal.3", CrabrixTheme.amber) }
        if path.hasSuffix(".md") { return ("doc.richtext.fill", CrabrixTheme.blue) }
        if path.hasSuffix(".json") { return ("curlybraces", CrabrixTheme.mint) }
        if name.uppercased().hasPrefix("LICENSE") {
            return ("checkmark.seal.fill", CrabrixTheme.mint)
        }
        return ("doc.fill", CrabrixTheme.muted)
    }
}

private struct ProjectTreeNode: Identifiable {
    let name: String
    let path: String
    let isDirectory: Bool
    let children: [ProjectTreeNode]

    var id: String { isDirectory ? "folder:\(path)" : "file:\(path)" }

    static func build(paths: [String]) -> [ProjectTreeNode] {
        let root = MutableProjectTreeNode(name: "", path: "", isDirectory: true)
        for path in paths {
            let components = path.split(separator: "/").map(String.init)
            guard !components.isEmpty else { continue }
            var parent = root
            for (index, component) in components.enumerated() {
                let isDirectory = index < components.count - 1
                let accumulated = components[0...index].joined(separator: "/")
                if let existing = parent.children[component] {
                    parent = existing
                } else {
                    let child = MutableProjectTreeNode(
                        name: component,
                        path: accumulated,
                        isDirectory: isDirectory
                    )
                    parent.children[component] = child
                    parent = child
                }
            }
        }
        return root.frozenChildren
    }
}

private final class MutableProjectTreeNode {
    let name: String
    let path: String
    let isDirectory: Bool
    var children: [String: MutableProjectTreeNode] = [:]

    init(name: String, path: String, isDirectory: Bool) {
        self.name = name
        self.path = path
        self.isDirectory = isDirectory
    }

    var frozenChildren: [ProjectTreeNode] {
        children.values
            .sorted { lhs, rhs in
                if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
                if lhs.name == "Cargo.toml" { return true }
                if rhs.name == "Cargo.toml" { return false }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
            .map { node in
                ProjectTreeNode(
                    name: node.name,
                    path: node.path,
                    isDirectory: node.isDirectory,
                    children: node.frozenChildren
                )
            }
    }
}
