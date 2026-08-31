import SwiftUI

/// Browses the source of a downloaded crate, file by file.
///
/// This exists because Crabrix downloads code. App Store guideline 2.5.2 permits
/// that for an app that teaches or develops code only while the source stays
/// completely viewable and editable. Every extracted path is listed here; all
/// UTF-8 source can be copied into the editable project overlay through Vendor
/// & Edit, while binary assets remain visible as bounded metadata.
struct CrateSourceView: View {
    @Environment(\.dismiss) private var dismiss

    let name: String
    let version: SemanticVersion
    let localPatch: [String: String]
    let onVendor: () -> Bool
    let onOpenVendor: () -> Bool
    let onResetVendor: () -> Bool

    @State private var entries: [CrateSourceBrowser.Entry] = []
    @State private var selected: CrateSourceBrowser.Entry?
    @State private var contents: String?
    @State private var guide: CrateGuide?
    @State private var hasLoaded = false
    @State private var isResetConfirmationPresented = false

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
        .confirmationDialog(
            "Reset this local patch?",
            isPresented: $isResetConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Reset to Registry Source", role: .destructive) {
                if onResetVendor() { dismiss() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Editable vendor files are removed. The checksum-verified original stays unchanged.")
        }
    }

    private var fileList: some View {
        List {
            sourceStatusSection

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
                Text(
                    localPatch.isEmpty
                        ? "The checksum-verified registry tree is immutable. Use Vendor & Edit to create an editable project-local overlay."
                        : "The registry tree remains immutable. Your edited overlay receives a new source hash and build fingerprint."
                )
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private var sourceStatusSection: some View {
        Section {
            Label("Registry source checksum verified", systemImage: "checkmark.seal.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(CrabrixTheme.mint)

            if localPatch.isEmpty {
                Button {
                    if onVendor() { dismiss() }
                } label: {
                    Label("Vendor & Edit", systemImage: "square.and.pencil")
                        .font(.subheadline.bold())
                }
                .tint(CrabrixTheme.coral)
            } else {
                Label("Using Local Patch", systemImage: "hammer.circle.fill")
                    .font(.subheadline.bold())
                    .foregroundStyle(CrabrixTheme.amber)

                Button {
                    if onOpenVendor() { dismiss() }
                } label: {
                    Label("Open Editable Source", systemImage: "doc.text.fill")
                }

                NavigationLink {
                    CratePatchDiffView(
                        name: name,
                        version: version,
                        localPatch: localPatch
                    )
                } label: {
                    Label("View Diff", systemImage: "arrow.left.arrow.right")
                }

                Button(role: .destructive) {
                    isResetConfirmationPresented = true
                } label: {
                    Label("Reset to Registry Source", systemImage: "arrow.counterclockwise")
                }
            }
        } header: {
            Text(localPatch.isEmpty ? "Verified Registry Source" : "Locally Patched")
        }
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

private struct CratePatchDiffView: View {
    let name: String
    let version: SemanticVersion
    let localPatch: [String: String]

    private var changedPaths: [String] {
        localPatch.keys.filter { path in
            CrateSourceBrowser.contents(name: name, version: version, path: path)
                != localPatch[path]
        }
        .sorted()
    }

    var body: some View {
        Group {
            if changedPaths.isEmpty {
                ContentUnavailableView(
                    "No local edits yet",
                    systemImage: "equal.circle",
                    description: Text("The editable overlay still matches the verified registry source.")
                )
            } else {
                List(changedPaths, id: \.self) { path in
                    NavigationLink {
                        CratePatchFileComparison(
                            path: path,
                            original: CrateSourceBrowser.contents(
                                name: name,
                                version: version,
                                path: path
                            ) ?? "",
                            patched: localPatch[path] ?? ""
                        )
                    } label: {
                        Label(path, systemImage: "doc.badge.ellipsis")
                            .font(.caption.monospaced())
                            .lineLimit(1)
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .background(CrabrixTheme.background.ignoresSafeArea())
        .navigationTitle("Local Patch Diff")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct CratePatchFileComparison: View {
    let path: String
    let original: String
    let patched: String

    var body: some View {
        ScrollView([.vertical, .horizontal]) {
            VStack(alignment: .leading, spacing: 18) {
                sourceBlock(title: "REGISTRY · READ ONLY", source: original, tint: CrabrixTheme.muted)
                sourceBlock(title: "LOCAL PATCH · EDITABLE", source: patched, tint: CrabrixTheme.amber)
            }
            .padding(14)
        }
        .background(CrabrixTheme.background.ignoresSafeArea())
        .navigationTitle((path as NSString).lastPathComponent)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func sourceBlock(title: String, source: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(tint)
            Text(SyntaxTheme.attributedString(source, filePath: path, fontSize: 12))
                .textSelection(.enabled)
                .fixedSize(horizontal: true, vertical: true)
                .padding(10)
                .background(CrabrixTheme.panel, in: RoundedRectangle(cornerRadius: 10))
                .overlay { RoundedRectangle(cornerRadius: 10).stroke(CrabrixTheme.border) }
        }
    }
}
