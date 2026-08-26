import SwiftUI

struct ProjectsHomeView: View {
    let projectName: String
    let fileCount: Int
    let lastBuild: ProjectBuildRecord?
    let activity: CompilerViewModel.Activity
    let isCompilerDraining: Bool
    let recentProjects: [ProjectLibraryItem]
    let onOpenCurrentProject: () -> Void
    let onNewProject: () -> Void
    let onOpenGitHub: () -> Void
    let onOpenFiles: () -> Void
    let onSaveProject: () -> Void
    let onArchiveProject: () -> Void
    let onOpenRecent: (UUID) -> Void
    let onOpenRunnableSample: () -> Void
    let onOpenBorrowSample: () -> Void
    let onOpenModulesSample: () -> Void
    let onOpenShowcase: (String) -> Void

    private let columns = [GridItem(.adaptive(minimum: 210), spacing: 14)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                brandHeader
                hero
                newProjectBanner
                LazyVGrid(columns: columns, spacing: 14) {
                    ProjectActionCard(
                        title: "Open from GitHub",
                        detail: "Import a public repository snapshot",
                        systemImage: "arrow.down.circle.fill",
                        tint: CrabrixTheme.blue,
                        action: onOpenGitHub
                    )
                    ProjectActionCard(
                        title: "iCloud Drive / Files",
                        detail: "Open a folder from Apple's document picker",
                        systemImage: "icloud.and.arrow.down.fill",
                        tint: CrabrixTheme.mint,
                        action: onOpenFiles
                    )
                    ProjectActionCard(
                        title: "Save Project to Cloud / Files",
                        detail: "Keep an editable Crabrix package in iCloud Drive or on device",
                        systemImage: "square.and.arrow.down.fill",
                        tint: CrabrixTheme.amber,
                        action: onSaveProject
                    )
                    ProjectActionCard(
                        title: "Archive & Share",
                        detail: "Create a standard ZIP for AirDrop, Messages, Mail, or Files",
                        systemImage: "archivebox.fill",
                        tint: CrabrixTheme.coral,
                        action: onArchiveProject
                    )
                }

                sectionTitle("Project Library", detail: "Pythonista-style examples that build fully offline")
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(Array(RustShowcaseLibrary.projects.enumerated()), id: \.element.id) { index, showcase in
                        ShowcaseProjectCard(
                            project: showcase,
                            tint: [CrabrixTheme.coral, CrabrixTheme.blue, CrabrixTheme.mint, CrabrixTheme.amber][index % 4],
                            action: { onOpenShowcase(showcase.id) }
                        )
                    }
                }

                sectionTitle("Recent Projects", detail: "Stored locally on this device")
                if recentProjects.isEmpty {
                    Text("Projects you open or build will appear here.")
                        .foregroundStyle(CrabrixTheme.muted)
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .crabrixPanel()
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(recentProjects) { item in
                            Button { onOpenRecent(item.id) } label: {
                                RecentProjectRow(
                                    item: item,
                                    activity: item.project.name == projectName ? activity : .idle,
                                    isCompilerDraining: item.project.name == projectName && isCompilerDraining
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                sectionTitle("Compiler Labs", detail: "Three working projects bundled with Crabrix")
                LazyVGrid(columns: columns, spacing: 12) {
                    SampleProjectCard(
                        title: "Hello Rust",
                        detail: "stdout · local Run",
                        icon: "play.fill",
                        action: onOpenRunnableSample
                    )
                    SampleProjectCard(
                        title: "Borrow Checker",
                        detail: "E0502 · explain · repair",
                        icon: "link.badge.plus",
                        action: onOpenBorrowSample
                    )
                    SampleProjectCard(
                        title: "Cargo Modules",
                        detail: "Cargo.toml · multi-file",
                        icon: "square.stack.3d.up.fill",
                        action: onOpenModulesSample
                    )
                }
            }
            .padding(22)
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
        }
        .background(CrabrixTheme.background.ignoresSafeArea())
        .foregroundStyle(CrabrixTheme.primary)
    }

    private var brandHeader: some View {
        HStack(spacing: 12) {
            Image("CrabrixMark")
                .resizable()
                .scaledToFit()
                .frame(width: 42, height: 42)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("Crabrix").font(.title2.bold())
                Text("Native Rust workspace")
                    .font(.caption.monospaced())
                    .foregroundStyle(CrabrixTheme.muted)
            }
            Spacer()
            Label("OFFLINE COMPILER", systemImage: "checkmark.seal.fill")
                .font(.caption2.monospaced().bold())
                .foregroundStyle(CrabrixTheme.mint)
        }
    }

    private var hero: some View {
        Button(action: onOpenCurrentProject) {
            HStack(alignment: .center, spacing: 18) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("CURRENT PROJECT")
                        .font(.caption2.monospaced().bold())
                        .foregroundStyle(CrabrixTheme.coral)
                    Text(projectName)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    Text("\(fileCount) files ready in the native editor")
                        .foregroundStyle(CrabrixTheme.muted)
                }
                Spacer()
                BuildStatusBadge(
                    record: lastBuild,
                    activity: activity,
                    isCompilerDraining: isCompilerDraining
                )
                Image(systemName: "chevron.right")
                    .font(.headline)
                    .foregroundStyle(CrabrixTheme.muted)
            }
            .padding(20)
            .background(
                LinearGradient(
                    colors: [CrabrixTheme.raised, CrabrixTheme.panel],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 16).stroke(CrabrixTheme.border) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open current project \(projectName)")
    }

    private var newProjectBanner: some View {
        Button(action: onNewProject) {
            HStack(spacing: 16) {
                Image(systemName: "plus")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 54, height: 54)
                    .background(CrabrixTheme.coral, in: RoundedRectangle(cornerRadius: 15))
                VStack(alignment: .leading, spacing: 5) {
                    Text("Create New Rust Project")
                        .font(.title3.bold())
                        .foregroundStyle(CrabrixTheme.primary)
                    Text("Choose Empty, Hello Rust, Cargo Modules, or a CLI starter")
                        .font(.subheadline)
                        .foregroundStyle(CrabrixTheme.muted)
                }
                Spacer()
                Label("NEW", systemImage: "arrow.right.circle.fill")
                    .font(.caption.monospaced().bold())
                    .foregroundStyle(CrabrixTheme.coral)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CrabrixTheme.coral.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(CrabrixTheme.coral.opacity(0.45), lineWidth: 1.5)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Create a new Rust project from a template")
    }

    private func sectionTitle(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.title3.bold())
            Text(detail).font(.caption).foregroundStyle(CrabrixTheme.muted)
        }
    }
}

private struct ProjectActionCard: View {
    let title: String
    let detail: String
    let systemImage: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 13) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(tint)
                    .frame(width: 34)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.subheadline.bold()).foregroundStyle(CrabrixTheme.primary)
                    Text(detail).font(.caption2).foregroundStyle(CrabrixTheme.muted)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(CrabrixTheme.muted)
            }
            .padding(15)
            .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
            .crabrixPanel()
        }
        .buttonStyle(.plain)
    }
}

private struct RecentProjectRow: View {
    let item: ProjectLibraryItem
    let activity: CompilerViewModel.Activity
    let isCompilerDraining: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.project.provenance?.source == .github
                  ? "arrow.triangle.branch" : "folder.fill")
                .foregroundStyle(item.project.provenance?.source == .github
                                 ? CrabrixTheme.blue : CrabrixTheme.mint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.project.name).font(.subheadline.bold()).foregroundStyle(CrabrixTheme.primary)
                Text("\(item.project.files.count) files · \(item.project.rustFileCount) Rust")
                    .font(.caption2.monospaced())
                    .foregroundStyle(CrabrixTheme.muted)
            }
            Spacer()
            BuildStatusBadge(
                record: item.lastBuild,
                compact: true,
                activity: activity,
                isCompilerDraining: isCompilerDraining
            )
            Image(systemName: "chevron.right").foregroundStyle(CrabrixTheme.muted)
        }
        .padding(14)
        .crabrixPanel()
    }
}

private struct BuildStatusBadge: View {
    let record: ProjectBuildRecord?
    var compact = false
    var activity: CompilerViewModel.Activity = .idle
    var isCompilerDraining = false

    var body: some View {
        if activity != .idle {
            HStack(spacing: 7) {
                ProgressView().controlSize(.small).tint(CrabrixTheme.blue)
                Text(activity == .checking ? "Checking…" : "Building…")
            }
            .font((compact ? Font.caption2 : Font.caption).monospaced().bold())
            .foregroundStyle(CrabrixTheme.blue)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(CrabrixTheme.blue.opacity(0.1), in: Capsule())
        } else if isCompilerDraining {
            Label("Stopping…", systemImage: "stop.circle.fill")
                .font((compact ? Font.caption2 : Font.caption).monospaced().bold())
                .foregroundStyle(CrabrixTheme.amber)
        } else if let record {
            Label(
                compact ? (record.succeeded ? "Passed" : "Failed")
                    : "Last \(record.phase.rawValue): \(record.succeeded ? "passed" : "failed")",
                systemImage: record.succeeded ? "checkmark.circle.fill" : "xmark.octagon.fill"
            )
            .font((compact ? Font.caption2 : Font.caption).monospaced().bold())
            .foregroundStyle(record.succeeded ? CrabrixTheme.mint : CrabrixTheme.coral)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(CrabrixTheme.background.opacity(0.65))
            .clipShape(Capsule())
        } else {
            Label(compact ? "Not built" : "No build yet", systemImage: "circle.dashed")
                .font((compact ? Font.caption2 : Font.caption).monospaced())
                .foregroundStyle(CrabrixTheme.muted)
        }
    }
}

private struct SampleProjectCard: View {
    let title: String
    let detail: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 9) {
                Image(systemName: icon).foregroundStyle(CrabrixTheme.coral)
                Text(title).font(.subheadline.bold()).foregroundStyle(CrabrixTheme.primary)
                Text(detail).font(.caption2.monospaced()).foregroundStyle(CrabrixTheme.muted)
            }
            .padding(15)
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
            .crabrixPanel()
        }
        .buttonStyle(.plain)
    }
}

private struct ShowcaseProjectCard: View {
    let project: RustShowcaseProject
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: project.systemImage)
                        .font(.title2)
                        .foregroundStyle(tint)
                        .frame(width: 42, height: 42)
                        .background(tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 12))
                    Spacer()
                    Label("OPEN", systemImage: "arrow.up.right")
                        .font(.caption2.monospaced().bold())
                        .foregroundStyle(tint)
                }
                Text(project.title)
                    .font(.headline)
                    .foregroundStyle(CrabrixTheme.primary)
                Text(project.detail)
                    .font(.caption)
                    .foregroundStyle(CrabrixTheme.muted)
                    .lineLimit(2)
                HStack(spacing: 5) {
                    ForEach(project.concepts.prefix(3), id: \.self) { concept in
                        Text(concept)
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundStyle(tint)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(tint.opacity(0.1), in: Capsule())
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 168, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [tint.opacity(0.08), CrabrixTheme.panel],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 16).stroke(tint.opacity(0.25)) }
        }
        .buttonStyle(.plain)
    }
}
