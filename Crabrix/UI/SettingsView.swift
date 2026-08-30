import SwiftUI

struct SettingsView: View {
    @AppStorage("crabrix.appearance") private var appearanceRaw = CrabrixAppearance.system.rawValue
    @AppStorage("crabrix.editorFontSize") private var editorFontSize = 14.0
    @AppStorage("crabrix.keepAwakeDuringBuild") private var keepAwakeDuringBuild = true
    @AppStorage("crabrix.appleIntelligenceCompletion") private var appleIntelligenceCompletion = true
    @AppStorage("crabrix.appleIntelligenceDiagnostics") private var appleIntelligenceDiagnostics = true
    @State private var isAddingDependency = false

    let toolchain: ToolchainStatus
    let manifest: CargoManifest?
    let workspace: CargoWorkspaceSnapshot
    let storage: CrateStorageUsage
    let onAddDependency: (String, String) -> Bool
    let onRefreshStorage: () async -> Void
    let onClearBuildArtifacts: () async -> Void
    let onClearDownloadedArchives: () async -> Void
    let onClearPackageCache: () async -> Void

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    settingsHeader
                    appearanceSection
                    editorSection
                    cargoSection
                    cargoStorageSection
                    compilerSection
                    aboutSection
                }
                .padding(22)
                .frame(maxWidth: 850)
                .frame(maxWidth: .infinity)
            }
            .background(CrabrixTheme.background.ignoresSafeArea())
            .foregroundStyle(CrabrixTheme.primary)
            .navigationTitle("Settings")
        }
        .task { await onRefreshStorage() }
        .sheet(isPresented: $isAddingDependency) {
            CargoDependencyCatalogSheet(onAdd: onAddDependency)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    private var settingsHeader: some View {
        HStack(spacing: 14) {
            Image(systemName: "gearshape.2.fill")
                .font(.title2)
                .foregroundStyle(CrabrixTheme.coral)
                .frame(width: 48, height: 48)
                .background(CrabrixTheme.coral.opacity(0.14), in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 3) {
                Text("Make Crabrix yours")
                    .font(.title2.bold())
                Text("Appearance, editor comfort, and local Rust project options")
                    .font(.caption)
                    .foregroundStyle(CrabrixTheme.muted)
            }
        }
    }

    private var appearanceSection: some View {
        SettingsSection(
            title: "Appearance",
            detail: "Auto follows the device setting immediately."
        ) {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(CrabrixAppearance.allCases) { appearance in
                    Button {
                        appearanceRaw = appearance.rawValue
                    } label: {
                        VStack(spacing: 9) {
                            Image(systemName: appearance.systemImage)
                                .font(.title2)
                                .foregroundStyle(
                                    appearanceRaw == appearance.rawValue
                                        ? CrabrixTheme.coral : CrabrixTheme.muted
                                )
                            Text(appearance.title)
                                .font(.subheadline.bold())
                            if appearanceRaw == appearance.rawValue {
                                Label("Selected", systemImage: "checkmark.circle.fill")
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(CrabrixTheme.mint)
                            } else {
                                Text(" ").font(.caption2)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 104)
                        .background(
                            appearanceRaw == appearance.rawValue
                                ? CrabrixTheme.coral.opacity(0.08) : CrabrixTheme.panel
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(
                                    appearanceRaw == appearance.rawValue
                                        ? CrabrixTheme.coral.opacity(0.55) : CrabrixTheme.border,
                                    lineWidth: appearanceRaw == appearance.rawValue ? 1.5 : 1
                                )
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var editorSection: some View {
        SettingsSection(
            title: "Editor & builds",
            detail: "These options apply to the native SwiftUI workspace."
        ) {
            VStack(spacing: 18) {
                HStack(spacing: 16) {
                    Label("Editor text", systemImage: "textformat.size")
                    Slider(value: $editorFontSize, in: 11...22, step: 1)
                        .tint(CrabrixTheme.blue)
                    Text("\(Int(editorFontSize)) pt")
                        .font(.caption.monospaced().bold())
                        .foregroundStyle(CrabrixTheme.blue)
                        .frame(width: 44, alignment: .trailing)
                }

                Divider().overlay(CrabrixTheme.border)

                Toggle(isOn: $keepAwakeDuringBuild) {
                    VStack(alignment: .leading, spacing: 3) {
                        Label("Keep screen awake while compiling", systemImage: "bolt.circle.fill")
                        Text("Useful for the first local run, which can be noticeably longer.")
                            .font(.caption2)
                            .foregroundStyle(CrabrixTheme.muted)
                    }
                }
                .tint(CrabrixTheme.mint)

                Divider().overlay(CrabrixTheme.border)

                Toggle(isOn: $appleIntelligenceCompletion) {
                    VStack(alignment: .leading, spacing: 3) {
                        Label("Apple Intelligence code completion", systemImage: "apple.intelligence")
                        Text("\(RustCompletionSupport.appleIntelligenceStatus). Crabrix always keeps an instant offline Rust fallback.")
                            .font(.caption2)
                            .foregroundStyle(CrabrixTheme.muted)
                    }
                }
                .tint(CrabrixTheme.blue)

                Divider().overlay(CrabrixTheme.border)

                Toggle(isOn: $appleIntelligenceDiagnostics) {
                    VStack(alignment: .leading, spacing: 3) {
                        Label("Apple Intelligence diagnostic fixes", systemImage: "apple.intelligence")
                        Text("After a failed Check, analyze the rustc error and offer only edits that pass a temporary compiler verification.")
                            .font(.caption2)
                            .foregroundStyle(CrabrixTheme.muted)
                    }
                }
                .tint(CrabrixTheme.blue)
            }
        }
    }

    private var cargoSection: some View {
        SettingsSection(
            title: "Cargo package",
            detail: manifest == nil
                ? "Open or create a Cargo project to manage its manifest."
                : "Changes are written to the editable Cargo.toml in this project."
        ) {
            if let manifest {
                HStack {
                    Label(manifest.name, systemImage: "shippingbox.fill")
                        .font(.headline)
                        .foregroundStyle(CrabrixTheme.amber)
                    Spacer()
                    Text("edition \(manifest.edition ?? "—")")
                        .font(.caption.monospaced())
                        .foregroundStyle(CrabrixTheme.muted)
                }

                if manifest.dependencies.isEmpty {
                    Text("No dependencies yet")
                        .font(.caption)
                        .foregroundStyle(CrabrixTheme.muted)
                } else {
                    ForEach(manifest.dependencies) { dependency in
                        HStack {
                            Image(systemName: "cube.fill")
                                .foregroundStyle(CrabrixTheme.blue)
                            Text(dependency.name)
                                .font(.subheadline.monospaced().bold())
                            Spacer()
                            Text(dependency.requirement ?? dependency.source.rawValue)
                                .font(.caption.monospaced())
                                .foregroundStyle(CrabrixTheme.muted)
                        }
                        .padding(.vertical, 3)
                    }
                }

                Button {
                    isAddingDependency = true
                } label: {
                    Label("Add Cargo dependency", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(CrabrixTheme.blue)

                if !workspace.packages.isEmpty {
                    Divider().overlay(CrabrixTheme.border)
                    HStack {
                        Label("Resolved graph", systemImage: "point.3.filled.connected.trianglepath.dotted")
                            .font(.caption.bold())
                        Spacer()
                        Text(workspace.summary)
                            .font(.caption2.monospaced())
                            .foregroundStyle(CrabrixTheme.muted)
                    }
                    ForEach(workspace.packages) { package in
                        CargoPackageRow(status: package)
                            .padding(.vertical, 2)
                    }
                }

                Label(
                    "Crabrix downloads packages from crates.io, verifies each SHA-256 checksum, and compiles them with the bundled rustc. Builds run locally.",
                    systemImage: "info.circle"
                )
                .font(.caption2)
                .foregroundStyle(CrabrixTheme.muted)
            } else {
                ContentUnavailableView(
                    "No Cargo.toml",
                    systemImage: "shippingbox",
                    description: Text("New Rust Project creates one automatically.")
                )
                .foregroundStyle(CrabrixTheme.muted)
            }
        }
    }

    private var cargoStorageSection: some View {
        SettingsSection(
            title: "Local build storage",
            detail: "Compiled projects, Cargo packages, and downloaded sources live in the app cache."
        ) {
            SettingsFactRow(
                title: "Downloaded archives",
                value: Self.formatted(storage.archiveBytes),
                icon: "arrow.down.circle.fill",
                tint: CrabrixTheme.blue
            )
            SettingsFactRow(
                title: "Extracted sources",
                value: "\(Self.formatted(storage.sourceBytes)) · \(storage.packageCount) packages",
                icon: "folder.fill",
                tint: CrabrixTheme.amber
            )
            SettingsFactRow(
                title: "Package artifacts",
                value: Self.formatted(storage.artifactBytes),
                icon: "cube.transparent.fill",
                tint: CrabrixTheme.mint
            )
            SettingsFactRow(
                title: "Project builds",
                value: Self.formatted(storage.projectArtifactBytes),
                icon: "hammer.circle.fill",
                tint: CrabrixTheme.amber
            )
            SettingsFactRow(
                title: "Total",
                value: Self.formatted(storage.totalBytes),
                icon: "internaldrive.fill",
                tint: CrabrixTheme.coral
            )

            Button {
                Task { await onClearBuildArtifacts() }
            } label: {
                Label("Clear build artifacts and results", systemImage: "cube.transparent")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(CrabrixTheme.mint)

            Button {
                Task { await onClearDownloadedArchives() }
            } label: {
                Label("Remove downloaded archives", systemImage: "archivebox")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(CrabrixTheme.blue)

            Button(role: .destructive) {
                Task { await onClearPackageCache() }
            } label: {
                Label("Clear the whole package cache", systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Label(
                "Clearing artifacts removes cached project programs and forgets recorded package build results, so the next Run recompiles them. Clearing the whole cache also removes offline packages, and a project that used them needs the network again.",
                systemImage: "exclamationmark.triangle"
            )
            .font(.caption2)
            .foregroundStyle(CrabrixTheme.muted)
        }
    }

    private static func formatted(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private var compilerSection: some View {
        SettingsSection(
            title: "Local compiler",
            detail: "The proof-of-concept toolchain is included in the app bundle."
        ) {
            SettingsFactRow(
                title: "Status",
                value: toolchain.isReady ? "Offline ready" : "Missing",
                icon: toolchain.isReady ? "checkmark.seal.fill" : "exclamationmark.triangle.fill",
                tint: toolchain.isReady ? CrabrixTheme.mint : CrabrixTheme.amber
            )
            SettingsFactRow(
                title: "Runtime",
                value: "WasmKit in a background queue",
                icon: "cpu.fill",
                tint: CrabrixTheme.blue
            )
            SettingsFactRow(
                title: "Network during build",
                value: "Not used",
                icon: "network.slash",
                tint: CrabrixTheme.coral
            )
        }
    }

    private var aboutSection: some View {
        SettingsSection(
            title: "About Crabrix",
            detail: "Version, licences, and where to reach a human."
        ) {
            SettingsFactRow(
                title: "Version",
                value: "\(appVersion) (build \(appBuild))",
                icon: "app.badge.checkmark.fill",
                tint: CrabrixTheme.mint
            )

            SettingsFactRow(
                title: "Made by",
                value: "Serhii Ziborov",
                icon: "person.fill",
                tint: CrabrixTheme.blue
            )

            Divider().overlay(CrabrixTheme.border)

            NavigationLink {
                LicensesView()
            } label: {
                SettingsLinkRow(
                    title: "Open-source licenses",
                    detail: "The compiler, standard library, and every bundled library",
                    icon: "doc.text.fill",
                    tint: CrabrixTheme.amber,
                    isExternal: false
                )
            }
            .buttonStyle(.plain)

            // These are the URLs App Store Connect points at, kept in one place
            // so the app and the listing can never disagree.
            Link(destination: CrabrixLinks.support) {
                SettingsLinkRow(
                    title: "Support",
                    detail: "Questions, release notes, and bug reports",
                    icon: "lifepreserver.fill",
                    tint: CrabrixTheme.mint,
                    isExternal: true
                )
            }

            Link(destination: CrabrixLinks.privacy) {
                SettingsLinkRow(
                    title: "Privacy Policy",
                    detail: "What leaves this device, which is almost nothing",
                    icon: "hand.raised.fill",
                    tint: CrabrixTheme.blue,
                    isExternal: true
                )
            }

            Link(destination: CrabrixLinks.terms) {
                SettingsLinkRow(
                    title: "Terms of Use",
                    detail: "Your code stays yours",
                    icon: "text.book.closed.fill",
                    tint: CrabrixTheme.muted,
                    isExternal: true
                )
            }

            Text("Rust and the Rust logo are trademarks of the Rust Foundation. Crabrix is an independent project, not affiliated with or endorsed by the Rust Foundation or by Apple.")
                .font(.caption2)
                .foregroundStyle(CrabrixTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
        }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private var appBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    let detail: String
    @ViewBuilder let content: () -> Content

    init(
        title: String,
        detail: String,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.detail = detail
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.title3.bold())
                Text(detail).font(.caption).foregroundStyle(CrabrixTheme.muted)
            }
            content()
        }
        .padding(18)
        .crabrixPanel(cornerRadius: 16)
    }
}

private struct SettingsFactRow: View {
    let title: String
    let value: String
    let icon: String
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(tint).frame(width: 24)
            Text(title).font(.subheadline)
            Spacer()
            Text(value)
                .font(.caption.monospaced())
                .foregroundStyle(CrabrixTheme.muted)
                .multilineTextAlignment(.trailing)
        }
    }
}


/// The public pages the app links to. One definition, so the in-app links and
/// the App Store Connect fields can never drift apart.
enum CrabrixLinks {
    static let site = URL(string: "https://crabrix.com")!
    static let about = URL(string: "https://crabrix.com/about")!
    static let support = URL(string: "https://crabrix.com/support")!
    static let privacy = URL(string: "https://crabrix.com/privacy")!
    static let terms = URL(string: "https://crabrix.com/terms")!
    static let leaderboard = URL(string: "https://crabrix.com/leaderboard")!
    static let supportEmail = "support@crabrix.com"
}

private struct SettingsLinkRow: View {
    let title: String
    let detail: String
    let icon: String
    let tint: Color
    let isExternal: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(tint).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(CrabrixTheme.primary)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(CrabrixTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Image(systemName: isExternal ? "arrow.up.right" : "chevron.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(CrabrixTheme.muted)
        }
        .contentShape(Rectangle())
        .accessibilityAddTraits(.isButton)
    }
}
