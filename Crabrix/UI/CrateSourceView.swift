import SwiftUI

/// Browses the source of a downloaded crate, file by file.
///
/// This exists because Crabrix downloads code. App Store guideline 2.5.2 permits
/// that for an app that teaches or develops code only while the source stays
/// fully viewable, so every file the package manager extracts is readable here —
/// not just the ones the build happened to compile.
struct CrateSourceView: View {
    let name: String
    let version: SemanticVersion

    @State private var entries: [CrateSourceBrowser.Entry] = []
    @State private var selected: CrateSourceBrowser.Entry?
    @State private var contents: String?
    @State private var guide: CrateGuide?
    @State private var hasLoaded = false

    var body: some View {
        Group {
            if entries.isEmpty {
                ContentUnavailableView(
                    hasLoaded ? "Not downloaded yet" : "Reading crate…",
                    systemImage: hasLoaded ? "arrow.down.circle" : "clock",
                    description: Text(
                        hasLoaded
                            ? "Fetch packages for this project and the full source appears here."
                            : ""
                    )
                )
            } else {
                fileList
            }
        }
        .background(CrabrixTheme.background.ignoresSafeArea())
        .foregroundStyle(CrabrixTheme.primary)
        .navigationTitle("\(name) \(version.description)")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard !hasLoaded else { return }
            entries = CrateSourceBrowser.entries(name: name, version: version)
            guide = CrateGuide.cached(name: name, version: version)
            hasLoaded = true
        }
        .navigationDestination(item: $selected) { entry in
            fileViewer(entry)
        }
    }

    private var fileList: some View {
        List {
            if let guide, guide.hasAnything {
                guideSection(guide)
            }

            Section {
                ForEach(entries) { entry in
                    Button {
                        contents = CrateSourceBrowser.contents(
                            name: name,
                            version: version,
                            path: entry.path
                        )
                        selected = entry
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: entry.isRust ? "doc.text.fill" : "doc")
                                .font(.caption)
                                .foregroundStyle(entry.isRust ? CrabrixTheme.coral : CrabrixTheme.muted)
                                .frame(width: 18)
                            Text(entry.path)
                                .font(.caption.monospaced())
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 0)
                            Text(entry.sizeLabel)
                                .font(.caption2.monospaced())
                                .foregroundStyle(CrabrixTheme.muted)
                        }
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("\(entries.count) files, exactly as downloaded from crates.io")
            } footer: {
                Text("Crabrix compiles this source on your device. Nothing here is hidden from you.")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    /// What the crate says about itself, above its files.
    @ViewBuilder
    private func guideSection(_ guide: CrateGuide) -> some View {
        Section {
            if let description = guide.summaryLine {
                Text(description)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !guide.keywords.isEmpty || guide.license != nil {
                HStack(spacing: 6) {
                    if let license = guide.license {
                        chip(license, tint: CrabrixTheme.mint)
                    }
                    ForEach(guide.keywords.prefix(3), id: \.self) { keyword in
                        chip(keyword, tint: CrabrixTheme.blue)
                    }
                    Spacer(minLength: 0)
                }
            }

            if guide.readme != nil {
                NavigationLink {
                    readmeViewer(guide)
                } label: {
                    Label("Read the guide", systemImage: "book.fill")
                        .font(.subheadline.bold())
                }
            }

            ForEach(guide.examples, id: \.self) { path in
                Button {
                    contents = CrateSourceBrowser.contents(name: name, version: version, path: path)
                    selected = CrateSourceBrowser.Entry(path: path, byteCount: 0)
                } label: {
                    Label(
                        (path as NSString).lastPathComponent,
                        systemImage: "curlybraces"
                    )
                    .font(.caption.monospaced())
                }
                .buttonStyle(.plain)
            }

            ForEach(guide.links, id: \.label) { link in
                Link(destination: link.url) {
                    Label(link.label, systemImage: "arrow.up.right.square")
                        .font(.caption)
                }
            }
        } header: {
            Text(guide.examples.isEmpty ? "About this crate" : "About this crate · \(guide.examples.count) examples")
        }
    }

    private func chip(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.13), in: Capsule())
    }

    /// The crate's own README, which is the closest thing to a guide that is
    /// guaranteed to be present and correct for the version installed.
    private func readmeViewer(_ guide: CrateGuide) -> some View {
        ScrollView {
            Text(MarkdownRenderer.attributed(guide.readme ?? ""))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
        }
        .background(CrabrixTheme.background.ignoresSafeArea())
        .navigationTitle("\(name) guide")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func fileViewer(_ entry: CrateSourceBrowser.Entry) -> some View {
        Group {
            if let contents {
                ScrollView([.vertical, .horizontal]) {
                    Text(
                        SyntaxTheme.attributedString(
                            contents,
                            filePath: entry.path,
                            fontSize: 12
                        )
                    )
                    .textSelection(.enabled)
                    // Both axes: without the vertical half a long file is
                    // compressed to the viewport and cannot be scrolled past
                    // its first screenful.
                    .fixedSize(horizontal: true, vertical: true)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                ContentUnavailableView(
                    "Not shown as text",
                    systemImage: "doc.badge.ellipsis",
                    description: Text(
                        "This file is binary, or larger than "
                            + "\(CrateSourceBrowser.maximumViewableBytes / 1_024 / 1_024) MB."
                    )
                )
            }
        }
        .background(CrabrixTheme.background.ignoresSafeArea())
        .navigationTitle(entry.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
