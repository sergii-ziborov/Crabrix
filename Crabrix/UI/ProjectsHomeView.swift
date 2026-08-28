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
    let onOpenLibrary: () -> Void
    let onOpenProgress: () -> Void

    @EnvironmentObject private var progress: CrabrixProgressStore
    @EnvironmentObject private var vitals: CrabrixVitalsStore

    private let columns = [GridItem(.adaptive(minimum: 210), spacing: 14)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                brandHeader
                progressStrip
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

                libraryBanner
                sampleChips

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

            }
            .padding(22)
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
        }
        .background(CrabrixTheme.background.ignoresSafeArea())
        .foregroundStyle(CrabrixTheme.primary)
    }

    /// One door into the catalogue, so the dashboard stays short as the library
    /// grows.
    private var libraryBanner: some View {
        Button(action: onOpenLibrary) {
            HStack(spacing: 15) {
                Image(systemName: "books.vertical.fill")
                    .font(.title2)
                    .foregroundStyle(CrabrixTheme.mint)
                    .frame(width: 52, height: 52)
                    .background(CrabrixTheme.mint.opacity(0.13), in: RoundedRectangle(cornerRadius: 15))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Project Library")
                        .font(.title3.bold())
                    Text("\(RustShowcaseLibrary.projects.count) working projects across \(libraryCategoryCount) categories, all building fully offline")
                        .font(.caption)
                        .foregroundStyle(CrabrixTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.headline)
                    .foregroundStyle(CrabrixTheme.muted)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .crabrixPanel(cornerRadius: 16)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the full project catalogue")
    }

    /// The three bundled labs, kept as one quiet row rather than a second
    /// section listing what the library above already contains.
    private var sampleChips: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("OR START FROM A BUNDLED LAB")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(CrabrixTheme.muted)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 9) { sampleChipRow }
                VStack(alignment: .leading, spacing: 9) { sampleChipRow }
            }
        }
    }

    @ViewBuilder
    private var sampleChipRow: some View {
        SampleChip(title: "Hello Rust", icon: "play.fill", tint: CrabrixTheme.mint, action: onOpenRunnableSample)
        SampleChip(title: "Borrow Checker", icon: "link.badge.plus", tint: CrabrixTheme.coral, action: onOpenBorrowSample)
        SampleChip(title: "Cargo Modules", icon: "square.stack.3d.up.fill", tint: CrabrixTheme.blue, action: onOpenModulesSample)
    }

    /// Rating, rank, and both pools, on the screen the app opens on.
    private var progressStrip: some View {
        Button(action: onOpenProgress) {
            HStack(spacing: 14) {
                Image(systemName: progress.rank.systemImage)
                    .font(.title3)
                    .foregroundStyle(CrabrixTheme.amber)
                    .frame(width: 40, height: 40)
                    .background(CrabrixTheme.amber.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 7) {
                        Text(CrabrixPointsFormatter.string(progress.state.totalPoints))
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                        Text(progress.rank.title)
                            .font(.caption.bold())
                            .foregroundStyle(CrabrixTheme.mint)
                    }
                    Text("\(progress.earnedAchievements.count) of \(CrabrixAchievementCatalog.all.count) achievements")
                        .font(.caption2.monospaced())
                        .foregroundStyle(CrabrixTheme.muted)
                }

                Spacer(minLength: 0)

                VitalsPill(store: vitals, showsCountdown: false, isInteractive: true)

                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(CrabrixTheme.muted)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .crabrixPanel(cornerRadius: 15)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Rating \(progress.state.totalPoints), rank \(progress.rank.title). Opens your progress.")
    }

    private var libraryCategoryCount: Int {
        Set(RustShowcaseLibrary.projects.map(\.category)).count
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
                    Text("Empty, Hello Rust, Cargo Modules, a CLI starter, or real crates.io packages")
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

private struct SampleChip: View {
    let title: String
    let icon: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.caption.bold())
                .foregroundStyle(tint)
                .padding(.horizontal, 13)
                .padding(.vertical, 9)
                .background(tint.opacity(0.10), in: Capsule())
                .overlay { Capsule().stroke(tint.opacity(0.32)) }
        }
        .buttonStyle(.plain)
    }
}

