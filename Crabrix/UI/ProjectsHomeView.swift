import SwiftUI

struct ProjectsHomeView: View {
    let projectName: String
    let fileCount: Int
    let lastBuild: ProjectBuildRecord?
    let recentProjects: [ProjectLibraryItem]
    let onNewProject: () -> Void
    let onOpenGitHub: () -> Void
    let onOpenFiles: () -> Void
    let onSaveProject: () -> Void
    let onOpenRecent: (UUID) -> Void
    let onOpenRunnableSample: () -> Void
    let onOpenBorrowSample: () -> Void
    let onOpenModulesSample: () -> Void

    private let columns = [GridItem(.adaptive(minimum: 210), spacing: 14)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                brandHeader
                hero
                LazyVGrid(columns: columns, spacing: 14) {
                    ProjectActionCard(
                        title: "New Rust Project",
                        detail: "Start with a local compiler-ready project",
                        systemImage: "plus.square.fill",
                        tint: CrabrixTheme.coral,
                        action: onNewProject
                    )
                    ProjectActionCard(
                        title: "Open from GitHub",
                        detail: "Import a public repository snapshot",
                        systemImage: "arrow.down.circle.fill",
                        tint: CrabrixTheme.blue,
                        action: onOpenGitHub
                    )
                    ProjectActionCard(
                        title: "Open from Files",
                        detail: "Use Files or a Working Copy folder",
                        systemImage: "folder.fill",
                        tint: CrabrixTheme.mint,
                        action: onOpenFiles
                    )
                    ProjectActionCard(
                        title: "Save Project",
                        detail: "Export editable files as a Crabrix package",
                        systemImage: "square.and.arrow.down.fill",
                        tint: CrabrixTheme.amber,
                        action: onSaveProject
                    )
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
                                RecentProjectRow(item: item)
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
        .foregroundStyle(.white)
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
            BuildStatusBadge(record: lastBuild)
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
                    Text(title).font(.subheadline.bold()).foregroundStyle(.white)
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

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.project.provenance?.source == .github
                  ? "arrow.triangle.branch" : "folder.fill")
                .foregroundStyle(item.project.provenance?.source == .github
                                 ? CrabrixTheme.blue : CrabrixTheme.mint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.project.name).font(.subheadline.bold()).foregroundStyle(.white)
                Text("\(item.project.files.count) files · \(item.project.rustFileCount) Rust")
                    .font(.caption2.monospaced())
                    .foregroundStyle(CrabrixTheme.muted)
            }
            Spacer()
            BuildStatusBadge(record: item.lastBuild, compact: true)
            Image(systemName: "chevron.right").foregroundStyle(CrabrixTheme.muted)
        }
        .padding(14)
        .crabrixPanel()
    }
}

private struct BuildStatusBadge: View {
    let record: ProjectBuildRecord?
    var compact = false

    var body: some View {
        if let record {
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
                Text(title).font(.subheadline.bold()).foregroundStyle(.white)
                Text(detail).font(.caption2.monospaced()).foregroundStyle(CrabrixTheme.muted)
            }
            .padding(15)
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
            .crabrixPanel()
        }
        .buttonStyle(.plain)
    }
}
