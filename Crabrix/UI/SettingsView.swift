import SwiftUI

struct SettingsView: View {
    @AppStorage("crabrix.appearance") private var appearanceRaw = CrabrixAppearance.system.rawValue
    @AppStorage("crabrix.editorFontSize") private var editorFontSize = 14.0
    @AppStorage("crabrix.keepAwakeDuringBuild") private var keepAwakeDuringBuild = true
    @AppStorage("crabrix.appleIntelligenceCompletion") private var appleIntelligenceCompletion = true
    @State private var isAddingDependency = false

    let toolchain: ToolchainStatus
    let manifest: CargoManifest?
    let onAddDependency: (String, String) -> Bool

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    settingsHeader
                    appearanceSection
                    editorSection
                    cargoSection
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

                Label(
                    "The catalog searches crates.io on demand. Phase 0 records the selected dependency but local builds remain offline and source-only.",
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
            detail: "Use this number to confirm which build is installed."
        ) {
            SettingsFactRow(
                title: "Version",
                value: "\(appVersion) (build \(appBuild))",
                icon: "app.badge.checkmark.fill",
                tint: CrabrixTheme.mint
            )
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
