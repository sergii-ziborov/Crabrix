import SwiftUI

/// The resolved dependency graph, its per-package compatibility, and the
/// offline-readiness of the current project.
struct CargoPackagesPanel: View {
    let stage: CargoPreparationStage
    let workspace: CargoWorkspaceSnapshot
    let manifest: CargoManifest?
    let isBusy: Bool
    let onRefresh: () -> Void
    let onPinForOffline: () -> Void
    let onAddDependency: () -> Void
    let vendoredFiles: (String, SemanticVersion) -> [String: String]
    let onVendor: (String, SemanticVersion) -> Bool
    let onOpenVendor: (String, SemanticVersion) -> Bool
    let onResetVendor: (String, SemanticVersion) -> Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if stage.isWorking {
                stageRow
            }
            if case let .failed(message) = stage, !workspace.packages.isEmpty {
                // A stale graph plus a fresh failure is a state the sidebar has
                // to show, not swallow.
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(CrabrixTheme.amber)
            }
            if workspace.packages.isEmpty {
                emptyState
            } else {
                offlineBanner
                packageList
            }
            if !workspace.unresolvedDependencies.isEmpty {
                unresolvedList
            }
            if !workspace.warnings.isEmpty {
                warningList
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Label("PACKAGES", systemImage: "shippingbox.fill")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(CrabrixTheme.muted)
            Spacer(minLength: 0)
            Button(action: onAddDependency) {
                Image(systemName: "plus.circle.fill").foregroundStyle(CrabrixTheme.mint)
            }
            .buttonStyle(.plain)
            .disabled(manifest == nil || isBusy)
            .accessibilityLabel("Add a Cargo dependency")
            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise.circle.fill")
                    .foregroundStyle(CrabrixTheme.blue)
            }
            .buttonStyle(.plain)
            .disabled(manifest == nil || stage.isWorking || isBusy)
            .accessibilityLabel("Resolve dependencies")
        }
    }

    private var stageRow: some View {
        HStack(spacing: 7) {
            ProgressView().controlSize(.mini).tint(CrabrixTheme.coral)
            Text(stage.label)
                .font(.caption2.monospaced())
                .foregroundStyle(CrabrixTheme.muted)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if manifest == nil {
            Text("This project has no Cargo.toml.")
                .font(.caption2)
                .foregroundStyle(CrabrixTheme.muted)
        } else if case let .failed(message) = stage {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundStyle(CrabrixTheme.amber)
        } else if manifest?.dependencies.isEmpty == false {
            Text("Resolve to download and build these packages locally.")
                .font(.caption2)
                .foregroundStyle(CrabrixTheme.muted)
        } else {
            Text("No dependencies yet.")
                .font(.caption2)
                .foregroundStyle(CrabrixTheme.muted)
        }
    }

    private var offlineBanner: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(offlineLabel, systemImage: offlineSystemImage)
                .font(.caption2.monospaced())
                .foregroundStyle(offlineTint)
            if workspace.isOfflineReady, !workspace.isOfflinePinned {
                Button(action: onPinForOffline) {
                    Label("Pin exact graph for offline", systemImage: "pin.fill")
                        .font(.caption2.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .tint(CrabrixTheme.mint)
                .disabled(isBusy || stage.isWorking)
            }
        }
    }

    private var offlineLabel: String {
        if workspace.isOfflinePinned { return "\(workspace.summary) · offline pinned" }
        if workspace.isOfflineReady { return "\(workspace.summary) · offline while cached" }
        return "\(workspace.summary) · download pending"
    }

    private var offlineSystemImage: String {
        workspace.isOfflinePinned ? "pin.fill" : (workspace.isOfflineReady ? "wifi.slash" : "arrow.down.circle")
    }

    private var offlineTint: Color {
        workspace.isOfflinePinned ? CrabrixTheme.mint : (workspace.isOfflineReady ? CrabrixTheme.blue : CrabrixTheme.amber)
    }

    private var packageList: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(workspace.packages) { package in
                if package.isDownloaded {
                    // Downloaded code has to be readable — see CrateSourceView.
                    NavigationLink {
                        CrateSourceView(
                            name: package.name,
                            version: package.version,
                            localPatch: vendoredFiles(package.name, package.version),
                            onVendor: { onVendor(package.name, package.version) },
                            onOpenVendor: { onOpenVendor(package.name, package.version) },
                            onResetVendor: { onResetVendor(package.name, package.version) }
                        )
                    } label: {
                        CargoPackageRow(status: package, isBrowsable: true)
                    }
                    .buttonStyle(.plain)
                } else {
                    CargoPackageRow(status: package)
                }
            }
        }
    }

    private var unresolvedList: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("NOT RESOLVED")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(CrabrixTheme.muted)
            ForEach(workspace.unresolvedDependencies, id: \.self) { entry in
                Text(entry)
                    .font(.caption2.monospaced())
                    .foregroundStyle(CrabrixTheme.amber)
            }
            Text("Crabrix resolves crates.io registry dependencies.")
                .font(.caption2)
                .foregroundStyle(CrabrixTheme.muted)
        }
    }

    private var warningList: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(workspace.warnings, id: \.self) { warning in
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.caption2)
                    .foregroundStyle(CrabrixTheme.amber)
            }
        }
    }
}

struct CargoPackageRow: View {
    let status: CratePackageStatus
    /// Shows the chevron that says this row opens the crate's source.
    var isBrowsable = false

    /// Read from the crate's own Cargo.toml once it is on disk, so a package
    /// says what it is rather than only what it is called.
    private var description: String? {
        guard status.isDownloaded else { return nil }
        return CrateGuide.cached(name: status.name, version: status.version)?.summaryLine
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: status.compatibility.systemImage)
                    .font(.caption2)
                    .foregroundStyle(status.compatibility.tint)
                Text(status.name)
                    .font(.caption.monospaced().weight(status.isDirect ? .semibold : .regular))
                    .foregroundStyle(CrabrixTheme.primary)
                Text(status.version.description)
                    .font(.caption2.monospaced())
                    .foregroundStyle(CrabrixTheme.blue)
                Spacer(minLength: 0)
                if status.isLocallyPatched {
                    Text("LOCAL PATCH")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(CrabrixTheme.amber)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(CrabrixTheme.amber.opacity(0.12), in: Capsule())
                }
                if !status.isDownloaded {
                    Image(systemName: "arrow.down.circle")
                        .font(.caption2)
                        .foregroundStyle(CrabrixTheme.amber)
                        .accessibilityLabel("Not downloaded")
                } else if isBrowsable {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(CrabrixTheme.muted)
                }
            }
            if let description {
                Text(description)
                    .font(.caption2)
                    .foregroundStyle(CrabrixTheme.muted)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let detail = status.compatibility.detail {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(CrabrixTheme.amber)
                    .lineLimit(2)
            } else if !status.features.isEmpty {
                Text(status.features.joined(separator: " "))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(CrabrixTheme.muted)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(status.name) \(status.version.description), \(status.compatibility.label)"
        )
        .accessibilityHint(isBrowsable ? "Opens the downloaded source of this crate" : "")
    }
}

extension CrateCompatibility {
    var tint: Color {
        switch self {
        case .verified: CrabrixTheme.mint
        case .checkVerified: CrabrixTheme.blue
        case .expected: CrabrixTheme.blue
        case .review: CrabrixTheme.amber
        case .unsupported: CrabrixTheme.coral
        }
    }

    var systemImage: String {
        switch self {
        case .verified: "checkmark.seal.fill"
        case .checkVerified: "checkmark.circle.fill"
        case .expected: "circle.dashed"
        case .review: "exclamationmark.triangle.fill"
        case .unsupported: "xmark.octagon.fill"
        }
    }
}
