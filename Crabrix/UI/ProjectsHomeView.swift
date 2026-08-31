import SwiftUI

struct ProjectsHomeView: View {
    let projectID: UUID
    let projectName: String
    let fileCount: Int
    let lastBuild: ProjectBuildRecord?
    let activity: CompilerViewModel.Activity
    let isCompilerDraining: Bool
    let recentProjects: [ProjectLibraryItem]
    let allProjects: [ProjectLibraryItem]
    let onOpenCurrentProject: () -> Void
    let onNewProject: () -> Void
    let onOpenGitHub: () -> Void
    let onOpenFiles: () -> Void
    let onOpenRecent: (UUID) -> Void
    let onOpenShowcase: (String) -> Void
    let onOpenLibrary: () -> Void
    let onOpenMyProjects: () -> Void

    @State private var projectQuery = ""
    @State private var selectedProjectFolder: String?
    @State private var selectedProjectTag: String?
    @State private var favoritesOnly = false

    private let columns = [GridItem(.adaptive(minimum: 210), spacing: 14)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                brandHeader
                hero
                projectBrowser
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
                }
                libraryBanner

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

    private var projectBrowser: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "folder.fill")
                    .font(.headline)
                    .foregroundStyle(CrabrixTheme.blue)
                    .frame(width: 38, height: 38)
                    .background(
                        CrabrixTheme.blue.opacity(0.13),
                        in: RoundedRectangle(cornerRadius: 11)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text("My Projects")
                        .font(.headline)
                    Text("\(allProjects.count) saved · \(projectFolderCount) folders")
                        .font(.caption2.monospaced())
                        .foregroundStyle(CrabrixTheme.muted)
                }
                Spacer(minLength: 0)
                Button("Manage", action: onOpenMyProjects)
                    .font(.caption.bold())
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(CrabrixTheme.muted)
                TextField("Search projects, folders, or tags", text: $projectQuery)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if !projectQuery.isEmpty {
                    Button {
                        projectQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(CrabrixTheme.muted)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear project search")
                }
            }
            .padding(.horizontal, 11)
            .frame(height: 38)
            .background(CrabrixTheme.raised, in: RoundedRectangle(cornerRadius: 11))
            .overlay {
                RoundedRectangle(cornerRadius: 11)
                    .stroke(CrabrixTheme.border)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    HomeProjectFilterChip(
                        title: "All",
                        systemImage: "tray.full.fill",
                        isSelected: !favoritesOnly
                            && selectedProjectFolder == nil
                            && selectedProjectTag == nil
                    ) {
                        favoritesOnly = false
                        selectedProjectFolder = nil
                        selectedProjectTag = nil
                    }
                    HomeProjectFilterChip(
                        title: "Favorites",
                        systemImage: "star.fill",
                        isSelected: favoritesOnly
                    ) {
                        favoritesOnly.toggle()
                    }
                    ForEach(projectFolders, id: \.self) { folder in
                        HomeProjectFilterChip(
                            title: folder,
                            systemImage: "folder.fill",
                            isSelected: selectedProjectFolder == folder
                        ) {
                            favoritesOnly = false
                            selectedProjectFolder = selectedProjectFolder == folder
                                ? nil
                                : folder
                        }
                    }
                }
            }

            if !projectTags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(projectTags, id: \.self) { tag in
                            HomeProjectFilterChip(
                                title: "#\(tag)",
                                systemImage: "tag.fill",
                                isSelected: selectedProjectTag == tag
                            ) {
                                selectedProjectTag = selectedProjectTag == tag
                                    ? nil
                                    : tag
                            }
                        }
                    }
                }
            }

            if filteredProjects.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: allProjects.isEmpty ? "folder.badge.plus" : "magnifyingglass")
                        .font(.title2)
                        .foregroundStyle(CrabrixTheme.muted)
                    Text(allProjects.isEmpty
                         ? "Projects you create or open will appear here."
                         : "No projects match these filters.")
                        .font(.caption)
                        .foregroundStyle(CrabrixTheme.muted)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            } else {
                LazyVStack(spacing: 7) {
                    ForEach(Array(filteredProjects.prefix(3))) { item in
                        Button { onOpenRecent(item.id) } label: {
                            RecentProjectRow(
                                item: item,
                                activity: item.id == projectID ? activity : .idle,
                                isCompilerDraining: item.id == projectID && isCompilerDraining
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                if filteredProjects.count > 3 {
                    Button(action: onOpenMyProjects) {
                        Label(
                            "Browse all \(filteredProjects.count) matching projects",
                            systemImage: "rectangle.grid.1x2.fill"
                        )
                        .font(.caption.bold())
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .padding(14)
        .crabrixPanel(cornerRadius: 16)
    }

    private var projectFolders: [String] {
        Array(Set(allProjects.map { $0.project.folderLabel }))
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private var projectTags: [String] {
        Array(Set(allProjects.flatMap { $0.project.tags }))
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private var filteredProjects: [ProjectLibraryItem] {
        let needle = projectQuery
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let recentOrder = Dictionary(
            uniqueKeysWithValues: recentProjects.enumerated().map { ($0.element.id, $0.offset) }
        )
        return allProjects
            .filter { item in
                (!favoritesOnly || item.project.isFavorite)
                    && (selectedProjectFolder == nil
                        || item.project.folderLabel == selectedProjectFolder)
                    && (selectedProjectTag.map { item.project.tags.contains($0) } ?? true)
                    && (needle.isEmpty || item.project.searchHaystack.contains(needle))
            }
            .sorted { left, right in
                if left.project.isFavorite != right.project.isFavorite {
                    return left.project.isFavorite
                }
                let leftOrder = recentOrder[left.id] ?? Int.max
                let rightOrder = recentOrder[right.id] ?? Int.max
                if leftOrder != rightOrder { return leftOrder < rightOrder }
                return left.lastOpenedAt > right.lastOpenedAt
            }
    }

    private var libraryCategoryCount: Int {
        Set(RustShowcaseLibrary.projects.map(\.category)).count
    }

    private var projectFolderCount: Int {
        Set(allProjects.map { $0.project.folderLabel }).count
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

private struct HomeProjectFilterChip: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption2.bold())
                .lineLimit(1)
                .padding(.horizontal, 9)
                .frame(height: 29)
                .background(
                    isSelected
                        ? CrabrixTheme.blue.opacity(0.17)
                        : CrabrixTheme.raised,
                    in: Capsule()
                )
                .overlay {
                    Capsule().stroke(
                        isSelected ? CrabrixTheme.blue : CrabrixTheme.border
                    )
                }
        }
        .buttonStyle(.plain)
    }
}

private struct RecentProjectRow: View {
    let item: ProjectLibraryItem
    let activity: CompilerViewModel.Activity
    let isCompilerDraining: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.project.provenance?.source == .github
                  ? "arrow.triangle.branch" : item.project.kind.systemImage)
                .foregroundStyle(item.project.provenance?.source == .github
                                 ? CrabrixTheme.blue : CrabrixTheme.mint)
                .frame(width: 25)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(item.project.name)
                        .font(.subheadline.bold())
                        .foregroundStyle(CrabrixTheme.primary)
                        .lineLimit(1)
                    if item.project.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(CrabrixTheme.amber)
                    }
                }
                Text(projectLocation)
                    .font(.caption2.monospaced())
                    .foregroundStyle(CrabrixTheme.muted)
                    .lineLimit(1)
            }
            .layoutPriority(1)
            Spacer()
            BuildStatusBadge(
                record: item.lastBuild,
                compact: true,
                activity: activity,
                isCompilerDraining: isCompilerDraining
            )
            Image(systemName: "chevron.right").foregroundStyle(CrabrixTheme.muted)
        }
        .padding(.horizontal, 11)
        .frame(minHeight: 58)
        .background(CrabrixTheme.raised.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12).stroke(CrabrixTheme.border)
        }
    }

    private var projectLocation: String {
        let tags = item.project.tags.prefix(2).map { "#\($0)" }
        return ([item.project.folderLabel] + tags + ["\(item.project.files.count) files"])
            .joined(separator: " · ")
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
