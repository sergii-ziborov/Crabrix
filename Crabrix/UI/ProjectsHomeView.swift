import SwiftUI

struct ProjectsHomeView: View {
    let projectName: String
    let fileCount: Int
    let lastBuild: ProjectBuildRecord?
    let activity: CompilerViewModel.Activity
    let isCompilerDraining: Bool
    let projectCount: Int
    let onOpenCurrentProject: () -> Void
    let onNewProject: () -> Void
    let onOpenLibrary: () -> Void
    let onOpenMyProjects: () -> Void

    private let columns = [GridItem(.adaptive(minimum: 230), spacing: 14)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                brandHeader
                currentProject
                LazyVGrid(columns: columns, spacing: 14) {
                    actionCard(
                        title: "My Projects",
                        detail: "Manage \(projectCount) saved projects",
                        systemImage: "folder.fill",
                        tint: CrabrixTheme.blue,
                        action: onOpenMyProjects
                    )
                    actionCard(
                        title: "New Project",
                        detail: "Create or import from GitHub and Files",
                        systemImage: "plus.circle.fill",
                        tint: CrabrixTheme.coral,
                        action: onNewProject
                    )
                }
                actionCard(
                    title: "Project Library",
                    detail: "\(RustShowcaseLibrary.projects.count) editable Rust examples",
                    systemImage: "books.vertical.fill",
                    tint: CrabrixTheme.mint,
                    action: onOpenLibrary
                )
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
                .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text("Crabrix").font(.title2.bold())
                Text("Native Rust workspace")
                    .font(.caption.monospaced())
                    .foregroundStyle(CrabrixTheme.muted)
            }
            Spacer()
        }
    }

    private var currentProject: some View {
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

    private func actionCard(
        title: String,
        detail: String,
        systemImage: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
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
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(CrabrixTheme.blue.opacity(0.1), in: Capsule())
        } else if isCompilerDraining {
            Label("Stopping…", systemImage: "stop.circle.fill")
                .font((compact ? Font.caption2 : Font.caption).monospaced().bold())
                .foregroundStyle(CrabrixTheme.amber)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        } else if let record {
            // "Last run: passed" wrapped to three lines inside its own capsule
            // on a small iPhone, and the compact form broke mid-word. The badge
            // keeps its intrinsic width now and the project title, which has
            // room to wrap, gives way instead.
            Group {
                if compact {
                    Label(
                        record.succeeded ? "Passed" : "Failed",
                        systemImage: record.succeeded
                            ? "checkmark.circle.fill"
                            : "xmark.octagon.fill"
                    )
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                } else {
                    // The mark alone. Spelling it out crowded the card and
                    // truncated the project's name to make room for a word the
                    // icon already carries.
                    Image(
                        systemName: record.succeeded
                            ? "checkmark.circle.fill"
                            : "xmark.octagon.fill"
                    )
                }
            }
            .font((compact ? Font.caption2 : Font.callout).monospaced().bold())
            .foregroundStyle(record.succeeded ? CrabrixTheme.mint : CrabrixTheme.coral)
            .padding(.horizontal, compact ? 10 : 8)
            .padding(.vertical, 7)
            .background(CrabrixTheme.background.opacity(0.65))
            .clipShape(Capsule())
            .accessibilityLabel(
                "\(record.phase.rawValue) \(record.succeeded ? "passed" : "failed")"
            )
        } else {
            Group {
                if compact {
                    Label("Not built", systemImage: "circle.dashed")
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                } else {
                    Image(systemName: "circle.dashed")
                }
            }
            .font((compact ? Font.caption2 : Font.callout).monospaced())
            .foregroundStyle(CrabrixTheme.muted)
            .accessibilityLabel("No build yet")
        }
    }
}
