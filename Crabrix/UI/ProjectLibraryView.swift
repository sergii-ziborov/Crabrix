import SwiftUI
import UIKit

/// Navigation targets inside the Projects tab.
enum ProjectsRoute: Hashable {
    case myProjects
}

/// The path is for browsing. Every downloaded example is open from the start.
struct ProjectLibraryView: View {
    /// Keep the deterministic visual gallery screenshot route.
    private let visualOnly = ProcessInfo.processInfo.arguments.contains("-CrabrixCanvasGallery")

    let projects: [RustShowcaseProject]
    let onSelect: (RustShowcaseProject) -> Void

    private var visibleProjects: [RustShowcaseProject] {
        visualOnly ? projects.filter(\.isVisual) : projects
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(visualOnly ? "RUST CANVAS" : "ALL OPEN")
                        .font(.caption.monospaced().bold())
                        .foregroundStyle(CrabrixTheme.mint)
                    Text(visualOnly ? "Visual examples" : "Choose any example")
                        .font(.title2.bold())
                    Text("Explore \(visibleProjects.count) Rust projects in any order.")
                        .font(.subheadline)
                        .foregroundStyle(CrabrixTheme.muted)
                }
                ExamplePathMap(projects: visibleProjects, onSelect: onSelect)
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 22)
            .padding(.bottom, 20)
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
        .background {
            ZStack {
                CrabrixTheme.background.ignoresSafeArea()
                LinearGradient(
                    colors: [CrabrixTheme.coral.opacity(0.08), .clear, CrabrixTheme.mint.opacity(0.06)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            }
        }
        .foregroundStyle(CrabrixTheme.primary)
        .navigationTitle("Code Examples")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ExamplePathMap: View {
    let projects: [RustShowcaseProject]
    let onSelect: (RustShowcaseProject) -> Void
    private let rowHeight: CGFloat = 118

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .topLeading) {
                ExampleTrailLine(count: projects.count, width: width, rowHeight: rowHeight)
                ForEach(Array(projects.enumerated()), id: \.element.id) { index, project in
                    ExamplePathNode(
                        project: project,
                        number: index + 1,
                        width: width,
                        rowHeight: rowHeight,
                        onSelect: { onSelect(project) }
                    )
                    .offset(y: CGFloat(index) * rowHeight)
                }
            }
        }
        .frame(height: CGFloat(projects.count) * rowHeight + 8)
        .padding(.horizontal, 4)
        .background(CrabrixTheme.panel.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(CrabrixTheme.border, lineWidth: 1)
        }
    }
}

private struct ExampleTrailLine: View {
    let count: Int
    let width: CGFloat
    let rowHeight: CGFloat

    var body: some View {
        Path { path in
            guard count > 0 else { return }
            var current = point(at: 0)
            path.move(to: current)
            for index in 1..<count {
                let next = point(at: index)
                let midway = (current.y + next.y) / 2
                path.addCurve(
                    to: next,
                    control1: CGPoint(x: current.x, y: midway),
                    control2: CGPoint(x: next.x, y: midway)
                )
                current = next
            }
        }
        .stroke(
            CrabrixTheme.coral.opacity(0.38),
            style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round, dash: [5, 8])
        )
        .accessibilityHidden(true)
    }

    private func point(at index: Int) -> CGPoint {
        CGPoint(
            x: LessonMapLayout.nodeCenterX(width: width, index: index),
            y: CGFloat(index) * rowHeight + rowHeight / 2
        )
    }
}

private struct ExamplePathNode: View {
    @Environment(\.colorScheme) private var colorScheme

    let project: RustShowcaseProject
    let number: Int
    let width: CGFloat
    let rowHeight: CGFloat
    let onSelect: () -> Void

    private var tint: Color {
        switch project.difficulty {
        case .starter: CrabrixTheme.mint
        case .intermediate: CrabrixTheme.blue
        case .advanced: CrabrixTheme.coral
        }
    }

    var body: some View {
        let index = number - 1
        let nodeX = LessonMapLayout.nodeCenterX(width: width, index: index)
        let labelWidth = LessonMapLayout.labelWidth(for: width)
        let labelOnRight = LessonMapLayout.labelToRight(at: index)
        let labelX = LessonMapLayout.labelCenterX(
            width: width,
            nodeX: nodeX,
            labelWidth: labelWidth,
            labelToRight: labelOnRight
        )

        return Button(action: onSelect) {
            ZStack {
                VStack(alignment: labelOnRight ? .leading : .trailing, spacing: 6) {
                    Text(String(format: "%02d", number))
                        .font(.caption2.monospaced().bold())
                        .foregroundStyle(tint)
                    Text(project.title)
                        .font(.subheadline.bold())
                        .foregroundStyle(CrabrixTheme.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(labelOnRight ? .leading : .trailing)
                    Text(project.category.title)
                        .font(.caption)
                        .foregroundStyle(CrabrixTheme.muted)
                }
                .frame(width: labelWidth, alignment: labelOnRight ? .leading : .trailing)
                .position(x: labelX, y: rowHeight / 2)

                ZStack {
                    Circle()
                        .stroke(tint.opacity(0.28), lineWidth: 3)
                        .frame(width: 86, height: 86)
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [tint, tint.opacity(0.78)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 70, height: 70)
                        .shadow(color: tint.opacity(0.32), radius: 12, y: 6)
                    Image(systemName: project.systemImage)
                        .font(.title3.bold())
                        .foregroundStyle(colorScheme == .light
                                         ? CrabrixTheme.primary : CrabrixTheme.background)
                }
                .frame(width: 96, height: 96)
                .position(x: nodeX, y: rowHeight / 2)
            }
            .frame(width: width, height: rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Example \(number), \(project.title), open")
        .accessibilityIdentifier("code-example-\(project.id)")
    }
}

/// Read the authored guide before opening an editable project copy.
struct ExampleDetailView: View {
    let project: RustShowcaseProject
    let onOpenInCode: () -> Void

    private var sourcePreview: String {
        guard let source = project.project.files[project.project.entryFile] else { return "" }
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
        let excerpt = lines.prefix(20).joined(separator: "\n")
        return lines.count > 20 ? excerpt + "\n…" : excerpt
    }

    private var guideSections: [ExampleGuideSection] {
        ExampleGuideSection.sections(in: project.project.files["README.md"] ?? "")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 12) {
                    Label(project.category.title.uppercased(), systemImage: project.systemImage)
                        .font(.caption.monospaced().bold())
                        .foregroundStyle(CrabrixTheme.coral)
                    Text(project.title)
                        .font(.largeTitle.bold())
                    Text(project.detail)
                        .font(.body)
                        .foregroundStyle(CrabrixTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !project.concepts.isEmpty {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 7) {
                            ForEach(project.concepts.prefix(3), id: \.self) { concept in
                                conceptChip(concept)
                            }
                        }
                        VStack(alignment: .leading, spacing: 7) {
                            ForEach(project.concepts.prefix(3), id: \.self) { concept in
                                conceptChip(concept)
                            }
                        }
                    }
                }

                ForEach(guideSections) { section in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(section.title)
                            .font(.title3.bold())
                        Text(.init(section.body))
                            .font(.body)
                            .foregroundStyle(CrabrixTheme.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if section.id == guideSections.first?.id,
                       let illustration = project.illustration,
                       let image = UIImage(contentsOfFile: illustration.url.path) {
                        VStack(alignment: .leading, spacing: 10) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: image.size.height > image.size.width ? 300 : .infinity)
                                .frame(maxWidth: .infinity)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .accessibilityLabel(illustration.alt)
                            Text(illustration.caption)
                                .font(.caption)
                                .foregroundStyle(CrabrixTheme.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Code preview").font(.headline)
                        Spacer()
                        Text(project.project.entryFile)
                            .font(.caption.monospaced())
                            .foregroundStyle(CrabrixTheme.muted)
                            .lineLimit(1)
                    }
                    ScrollView(.horizontal) {
                        Text(sourcePreview)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(CrabrixTheme.primary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(CrabrixTheme.editor, in: RoundedRectangle(cornerRadius: 12))
                }
                .padding(16)
                .background(CrabrixTheme.panel, in: RoundedRectangle(cornerRadius: 18))

            }
            .padding(.horizontal, 26)
            .padding(.vertical, 22)
            .padding(.bottom, 20)
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
        .background(CrabrixTheme.background.ignoresSafeArea())
        .foregroundStyle(CrabrixTheme.primary)
        .navigationTitle(project.title)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button(action: onOpenInCode) {
                Label("Open in Code", systemImage: "curlybraces")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(CrabrixTheme.coral)
            .accessibilityIdentifier("code-example-open-in-code")
            .padding(.horizontal, 26)
            .padding(.vertical, 12)
            .frame(maxWidth: 700)
            .background(CrabrixTheme.background)
        }
    }

    private func conceptChip(_ concept: String) -> some View {
        Text(concept)
            .font(.caption.monospaced())
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(CrabrixTheme.raised, in: Capsule())
    }
}
