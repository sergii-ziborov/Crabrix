import SwiftUI

struct AtlasValueView: View {
    let name: String
    let value: AtlasValue
    let previous: AtlasValue?
    let locals: [String: AtlasValue]
    let edge: AtlasReplay.Site.Edge?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let graph = AtlasGraph(value: value), ["graph", "g", "adj", "adjacency"].contains(name) {
                graphView(graph)
            } else if let tree = AtlasTree(value: value) {
                treeView(tree)
            } else {
                switch value {
                case let .list(items, tuple):
                    if !tuple, !items.isEmpty, items.allSatisfy({ if case .list(_, tuple: false) = $0 { true } else { false } }) {
                        matrix(items)
                    } else { cells(items, set: false) }
                case let .set(items): cells(items, set: true)
                case let .map(entries): map(entries)
                default: exactText(value.text)
                }
            }
            DisclosureGroup("Exact value · \(name)") { exactText(value.text) }
                .font(.caption).foregroundStyle(CrabrixTheme.muted)
        }
    }

    private func exactText(_ text: String) -> some View {
        ScrollView(.horizontal) {
            Text(String(text.prefix(16_384)) + (text.count > 16_384 ? "\n… preview limited to 16,384 characters" : ""))
                .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                .foregroundStyle(CrabrixTheme.primary).padding(.vertical, 6)
        }
    }
    private var pointers: [(String, Int)] {
        locals.compactMap { key, value in
            if case let .scalar(text) = value, let index = Int(text), index >= 0 { return (key, index) }
            return nil
        }.sorted { $0.0 < $1.0 }
    }
    private func cells(_ items: [AtlasValue], set: Bool) -> some View {
        let old: [AtlasValue]
        switch previous { case let .list(items, _), let .set(items): old = items; default: old = [] }
        return VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal) {
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(Array(items.prefix(64).enumerated()), id: \.offset) { i, item in
                        let changed = previous != nil && (set ? !old.contains(item) : old.indices.contains(i) ? old[i] != item : true)
                        let markers = set ? [] : pointers.filter { $0.1 == i }.map(\.0)
                        VStack(spacing: 6) {
                            if !set { Text("\(i)").foregroundStyle(CrabrixTheme.muted).font(.caption2.monospaced()) }
                            Text(String(item.text.prefix(80))).font(.system(.subheadline, design: .monospaced).bold())
                                .foregroundStyle(CrabrixTheme.primary).lineLimit(3)
                            if !markers.isEmpty { Text(markers.joined(separator: " · ")).font(.caption2).foregroundStyle(CrabrixTheme.blue) }
                            else if changed { Text("Changed").font(.caption2).foregroundStyle(CrabrixTheme.mint) }
                        }
                        .padding(10).frame(minWidth: 54, minHeight: 70)
                        .background((changed ? CrabrixTheme.mint : CrabrixTheme.blue).opacity(changed ? 0.16 : 0.07))
                        .overlay { RoundedRectangle(cornerRadius: 9).stroke(changed ? CrabrixTheme.mint : CrabrixTheme.border) }
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                    }
                    if items.isEmpty { Text("Empty collection").font(.subheadline).foregroundStyle(CrabrixTheme.muted) }
                }.padding(.vertical, 4)
            }
            if items.count > 64 { Text("Showing 64 of \(items.count) items. Inspect the exact value below.").font(.caption).foregroundStyle(CrabrixTheme.muted) }
        }
    }
    private func matrix(_ rows: [AtlasValue]) -> some View {
        let width = min(24, rows.compactMap { row -> Int? in
            if case let .list(cells, _) = row { cells.count } else { nil }
        }.max() ?? 0)
        let currentRow = pointers.first { ["i", "r", "row"].contains($0.0) }?.1
        let currentColumn = pointers.first { ["j", "c", "col"].contains($0.0) }?.1
        return ScrollView(.horizontal) {
            Grid(alignment: .trailing, horizontalSpacing: 8, verticalSpacing: 8) {
                GridRow {
                    Text("r/c").font(.caption2.monospaced()).foregroundStyle(CrabrixTheme.muted)
                    ForEach(0..<width, id: \.self) { Text("\($0)").font(.caption2.monospaced()).foregroundStyle(CrabrixTheme.muted) }
                }
                ForEach(Array(rows.prefix(24).enumerated()), id: \.offset) { r, row in
                    if case let .list(cells, _) = row {
                        GridRow {
                            Text("\(r)").font(.caption2.monospaced()).foregroundStyle(CrabrixTheme.muted)
                            ForEach(Array(cells.prefix(24).enumerated()), id: \.offset) { c, item in
                                let old = matrixValue(previous, row: r, column: c)
                                let changed = previous != nil && old != item
                                let current = currentRow == r && currentColumn == c
                                Text(String(item.text.prefix(32))).font(.system(.caption, design: .monospaced).bold())
                                    .foregroundStyle(CrabrixTheme.primary)
                                    .padding(9).frame(minWidth: 44)
                                    .background((current ? CrabrixTheme.blue : changed ? CrabrixTheme.mint : CrabrixTheme.blue).opacity(current ? 0.25 : 0.12))
                                    .overlay { RoundedRectangle(cornerRadius: 6).stroke(current ? CrabrixTheme.blue : changed ? CrabrixTheme.mint : CrabrixTheme.border) }
                                    .accessibilityLabel("Row \(r), column \(c): \(item.text)\(changed ? ", changed" : "")")
                            }
                        }
                    }
                }
            }.padding(.vertical, 6)
            Text("Row indices at left · preview up to 24 × 24").font(.caption2).foregroundStyle(CrabrixTheme.muted)
        }
    }
    private func matrixValue(_ value: AtlasValue?, row: Int, column: Int) -> AtlasValue? {
        guard case let .list(rows, _) = value, rows.indices.contains(row),
              case let .list(cells, _) = rows[row], cells.indices.contains(column) else { return nil }
        return cells[column]
    }
    private func map(_ entries: [[AtlasValue]]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(entries.prefix(64).enumerated()), id: \.offset) { _, pair in
                let old: AtlasValue? = {
                    if case let .map(before) = previous { return before.first(where: { $0[0] == pair[0] })?[1] }
                    return nil
                }()
                HStack(alignment: .top) {
                    Text(String(pair[0].text.prefix(80))).foregroundStyle(CrabrixTheme.blue)
                    Text("→").foregroundStyle(CrabrixTheme.muted)
                    Text(String(pair[1].text.prefix(512))).foregroundStyle(CrabrixTheme.primary)
                }
                .font(.system(.caption, design: .monospaced)).padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background((previous != nil && old != pair[1] ? CrabrixTheme.mint : CrabrixTheme.blue).opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            if entries.isEmpty { Text("Empty map").foregroundStyle(CrabrixTheme.muted) }
            if entries.count > 64 { Text("Showing 64 of \(entries.count) entries.").font(.caption).foregroundStyle(CrabrixTheme.muted) }
        }
    }
    private func graphView(_ graph: AtlasGraph) -> some View {
        let from = scalar(edge?.collection == name ? edge?.from : nil)
            ?? pointers.first(where: { ["u", "node", "vertex", "v"].contains($0.0) })?.1
        let to = edge?.collection == name ? scalar(edge?.to) : nil
        return VStack(alignment: .leading, spacing: 8) {
            Canvas { context, size in
                let points = (0..<graph.count).map { i in
                    let angle = -.pi / 2 + 2 * .pi * Double(i) / Double(graph.count)
                    return CGPoint(x: size.width / 2 + max(0, size.width / 2 - 44) * cos(angle),
                                   y: size.height / 2 + (size.height / 2 - 56) * sin(angle))
                }
                for item in graph.edges {
                    let active = item.from == from && item.to == to
                    let color = active ? CrabrixTheme.mint : CrabrixTheme.muted
                    let a = points[item.from], b = points[item.to]
                    var line = Path()
                    if item.from == item.to {
                        line.addEllipse(in: CGRect(x: a.x - 25, y: a.y - 41, width: 35, height: 35))
                    } else {
                        let angle = atan2(b.y - a.y, b.x - a.x)
                        let end = CGPoint(x: b.x - 22 * cos(angle), y: b.y - 22 * sin(angle))
                        line.move(to: a); line.addLine(to: end)
                        line.move(to: CGPoint(x: end.x - 9 * cos(angle - .pi / 6), y: end.y - 9 * sin(angle - .pi / 6)))
                        line.addLine(to: end)
                        line.addLine(to: CGPoint(x: end.x - 9 * cos(angle + .pi / 6), y: end.y - 9 * sin(angle + .pi / 6)))
                    }
                    context.stroke(line, with: .color(color), lineWidth: active ? 3 : 1.5)
                    if let weight = item.weight {
                        let label = item.from == item.to
                            ? CGPoint(x: a.x - 14, y: a.y - 50)
                            : CGPoint(x: (2 * a.x + b.x) / 3, y: (2 * a.y + b.y) / 3 - 8)
                        context.draw(Text(String(weight.prefix(12))).font(.caption2).foregroundColor(CrabrixTheme.primary), at: label)
                    }
                }
                for i in points.indices {
                    let p = points[i], circle = Path(ellipseIn: CGRect(x: p.x - 19, y: p.y - 19, width: 38, height: 38))
                    context.fill(circle, with: .color(i == from ? CrabrixTheme.blue : CrabrixTheme.panel))
                    context.stroke(circle, with: .color(i == from ? CrabrixTheme.blue : CrabrixTheme.border), lineWidth: 2)
                    context.draw(Text("\(i)").font(.subheadline.monospaced().bold())
                        .foregroundColor(i == from ? CrabrixTheme.onAccent : CrabrixTheme.primary), at: p)
                }
            }
            .frame(height: 280).accessibilityLabel("Directed adjacency graph with \(graph.count) vertices")
            DisclosureGroup("Directed edges and weights") {
                ForEach(Array(graph.edges.enumerated()), id: \.offset) { _, item in
                    Text("\(item.from) → \(item.to)" + (item.weight.map { " · weight \($0)" } ?? ""))
                        .font(.caption.monospaced()).foregroundStyle(CrabrixTheme.primary)
                }
            }.font(.caption)
        }
    }
    private func scalar(_ key: String?) -> Int? {
        guard let key, case let .scalar(text) = locals[key] else { return nil }
        return Int(text)
    }
    private func treeView(_ tree: AtlasTree) -> some View {
        ScrollView(.horizontal) {
            Canvas { context, _ in
                for edge in tree.edges {
                    let a = tree.nodes[edge.from], b = tree.nodes[edge.to]
                    var path = Path(); path.move(to: CGPoint(x: a.x, y: a.y + 18)); path.addLine(to: CGPoint(x: b.x, y: b.y - 18))
                    context.stroke(path, with: .color(CrabrixTheme.muted), lineWidth: 2)
                    context.draw(Text(edge.label).font(.caption2).foregroundColor(CrabrixTheme.muted),
                                 at: CGPoint(x: (a.x + b.x) / 2 + 14, y: (a.y + b.y) / 2))
                }
                for node in tree.nodes {
                    let box = Path(roundedRect: CGRect(x: node.x - 30, y: node.y - 18, width: 60, height: 36), cornerRadius: 9)
                    context.fill(box, with: .color(CrabrixTheme.blue.opacity(0.14)))
                    context.stroke(box, with: .color(CrabrixTheme.blue), lineWidth: 1.5)
                    context.draw(Text(String(node.label.prefix(8))).font(.caption.monospaced().bold()).foregroundColor(CrabrixTheme.primary),
                                 at: CGPoint(x: node.x, y: node.y))
                }
            }.frame(width: tree.width, height: tree.height)
                .accessibilityLabel("Linked nodes: " + tree.nodes.map(\.label).joined(separator: ", "))
        }
    }
}

struct AtlasGraph {
    struct Edge { let from: Int; let to: Int; let weight: String? }
    let count: Int
    let edges: [Edge]
    init?(value: AtlasValue) {
        guard case let .list(rows, _) = value, (1...24).contains(rows.count) else { return nil }
        var edges: [Edge] = []
        for (from, row) in rows.enumerated() {
            guard case let .list(items, _) = row else { return nil }
            for item in items {
                let target: AtlasValue, weight: String?
                if case let .list(parts, _) = item {
                    guard let first = parts.first, parts.count <= 2 else { return nil }
                    target = first; weight = parts.count == 2 ? parts[1].text : nil
                } else { target = item; weight = nil }
                guard case let .scalar(text) = target, let to = Int(text), rows.indices.contains(to),
                      edges.count < 576 else { return nil }
                edges.append(Edge(from: from, to: to, weight: weight))
            }
        }
        count = rows.count; self.edges = edges
    }
}

struct AtlasTree {
    struct Node { let label: String; var x: CGFloat; let y: CGFloat }
    struct Edge { let from: Int; let to: Int; let label: String }
    private(set) var nodes: [Node] = []
    private(set) var edges: [Edge] = []
    private(set) var width: CGFloat = 0
    private(set) var height: CGFloat = 0
    init?(value: AtlasValue) {
        var leaves = 0
        guard place(value, depth: 0, leaves: &leaves) != nil else { return nil }
        width = max(180, CGFloat(leaves) * 100); height = (nodes.map(\.y).max() ?? 0) + 40
    }
    private mutating func place(_ value: AtlasValue, depth: Int, leaves: inout Int) -> Int? {
        guard depth <= 12, nodes.count < 64 else { return nil }
        if case let .named("Some", .list(items, _)) = value, let first = items.first {
            return place(first, depth: depth, leaves: &leaves)
        }
        guard case let .named(type, .map(entries)) = value else { return nil }
        let fields = Dictionary(entries.map { ($0[0].text, $0[1]) }, uniquingKeysWith: { first, _ in first })
        guard ["left", "right", "next"].contains(where: { fields[$0] != nil }) else { return nil }
        let id = nodes.count
        nodes.append(Node(label: (fields["key"] ?? fields["value"] ?? fields["val"])?.text ?? type,
                          x: 0, y: 28 + CGFloat(depth) * 70))
        var children: [Int] = []
        for key in ["left", "right", "next"] {
            if let child = fields[key], let childID = place(child, depth: depth + 1, leaves: &leaves) {
                children.append(childID); edges.append(Edge(from: id, to: childID, label: key))
            }
        }
        if children.isEmpty { nodes[id].x = 50 + CGFloat(leaves) * 100; leaves += 1 }
        else { nodes[id].x = children.map { nodes[$0].x }.reduce(0, +) / CGFloat(children.count) }
        return id
    }
}
