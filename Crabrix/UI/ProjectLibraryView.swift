import SwiftUI

/// Navigation targets inside the Projects tab.
enum ProjectsRoute: Hashable {
    case myProjects
    case library
}

/// The full project catalogue, with search and category filters.
///
/// The dashboard links here instead of listing everything, so the library can
/// keep growing without turning the first screen into a wall of cards.
struct ProjectLibraryView: View {
    @State private var query = ""
    @State private var category: RustShowcaseCategory?
    @State private var difficulty: RustShowcaseDifficulty?
    /// `-CrabrixCanvasGallery` opens the library already filtered to the Rust
    /// Canvas projects, the same way `-CrabrixTab` opens a tab: store frames
    /// and review walkthroughs then come out of every build identically.
    @State private var visualOnly = ProcessInfo.processInfo
        .arguments.contains("-CrabrixCanvasGallery")

    let onOpen: (String) -> Void

    private let columns = [GridItem(.adaptive(minimum: 260), spacing: 14)]

    private var results: [RustShowcaseProject] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return RustShowcaseLibrary.projects.filter { project in
            if let category, project.category != category { return false }
            if let difficulty, project.difficulty != difficulty { return false }
            if visualOnly, !project.isVisual { return false }
            guard !needle.isEmpty else { return true }
            return project.searchHaystack.contains(needle)
        }
    }

    /// Categories that actually have something in them right now.
    private var availableCategories: [RustShowcaseCategory] {
        let present = Set(RustShowcaseLibrary.projects.map(\.category))
        return RustShowcaseCategory.allCases.filter { present.contains($0) }
    }

    private var guidedCount: Int {
        RustShowcaseLibrary.projects.filter(\.isGuided).count
    }

    private var visualCount: Int {
        RustShowcaseLibrary.projects.filter(\.isVisual).count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                filters
                if results.isEmpty {
                    ContentUnavailableView.search(text: query)
                        .padding(.top, 40)
                } else {
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(results) { project in
                            Button { onOpen(project.id) } label: {
                                ProjectLibraryCard(project: project)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(20)
            // Room for the last card to clear the floating tab bar instead of
            // ending underneath it.
            .padding(.bottom, 24)
            .frame(maxWidth: 1_100)
            .frame(maxWidth: .infinity)
        }
        .background(CrabrixTheme.background.ignoresSafeArea())
        .foregroundStyle(CrabrixTheme.primary)
        .navigationTitle("Project Library")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Search projects, concepts, categories")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(RustShowcaseLibrary.projects.count) PROJECTS · \(guidedCount) GUIDED · \(visualCount) VISUAL")
                .font(.caption.monospaced().bold())
                .foregroundStyle(CrabrixTheme.mint)
            Text("Open a working Rust project")
                .font(.system(size: 26, weight: .bold, design: .rounded))
            Text("Every project builds with the bundled compiler, uses only the standard library, and is yours to edit.")
                .font(.subheadline)
                .foregroundStyle(CrabrixTheme.muted)
        }
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: 9) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    FilterChip(title: "All", isSelected: category == nil) { category = nil }
                    FilterChip(
                        title: "Rust Canvas",
                        systemImage: "paintpalette.fill",
                        isSelected: visualOnly
                    ) {
                        visualOnly.toggle()
                    }
                    ForEach(availableCategories) { option in
                        FilterChip(
                            title: option.title,
                            systemImage: option.systemImage,
                            isSelected: category == option
                        ) {
                            category = category == option ? nil : option
                        }
                    }
                }
                .padding(.horizontal, 1)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    FilterChip(title: "Any level", isSelected: difficulty == nil) { difficulty = nil }
                    ForEach(RustShowcaseDifficulty.allCases) { option in
                        FilterChip(title: option.title, isSelected: difficulty == option) {
                            difficulty = difficulty == option ? nil : option
                        }
                    }
                    Text("\(results.count) shown")
                        .font(.caption.monospaced())
                        .foregroundStyle(CrabrixTheme.muted)
                        .padding(.leading, 4)
                }
                .padding(.horizontal, 1)
            }
        }
    }
}

private struct FilterChip: View {
    let title: String
    var systemImage: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if let systemImage {
                    Label(title, systemImage: systemImage)
                } else {
                    Text(title)
                }
            }
            .font(.caption.bold())
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(
                isSelected ? CrabrixTheme.coral.opacity(0.18) : CrabrixTheme.raised,
                in: Capsule()
            )
            .overlay {
                Capsule().stroke(isSelected ? CrabrixTheme.coral : CrabrixTheme.border)
            }
            .foregroundStyle(isSelected ? CrabrixTheme.coral : CrabrixTheme.muted)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct ProjectLibraryCard: View {
    let project: RustShowcaseProject

    private var tint: Color {
        switch project.difficulty {
        case .starter: CrabrixTheme.mint
        case .intermediate: CrabrixTheme.blue
        case .advanced: CrabrixTheme.coral
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if project.isVisual {
                VisualShowcaseThumbnail(projectID: project.id)
                    .frame(height: 104)
                    .clipShape(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(CrabrixTheme.border)
                    }
                    .overlay(alignment: .bottomLeading) {
                        Label("RUST CANVAS", systemImage: "sparkles")
                            .font(.system(
                                size: 8,
                                weight: .bold,
                                design: .monospaced
                            ))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .frame(height: 19)
                            .background(.black.opacity(0.55), in: Capsule())
                            .padding(6)
                    }
                    .frame(maxWidth: .infinity)
            }

            HStack(spacing: 10) {
                Image(systemName: project.systemImage)
                    .font(.headline)
                    .foregroundStyle(tint)
                    .frame(width: 38, height: 38)
                    .background(tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 11))
                Spacer(minLength: 0)
                Text(project.difficulty.title.uppercased())
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(tint)
                if project.isGuided {
                    Text("GUIDED")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(CrabrixTheme.amber)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(project.title)
                    .font(.headline)
                    .foregroundStyle(CrabrixTheme.primary)
                Text(project.detail)
                    .font(.caption)
                    .foregroundStyle(CrabrixTheme.muted)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 5) {
                ForEach(project.concepts.prefix(3), id: \.self) { concept in
                    Text(concept)
                        .font(.system(size: 9, design: .monospaced))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(CrabrixTheme.raised, in: Capsule())
                        .foregroundStyle(CrabrixTheme.muted)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .crabrixPanel(cornerRadius: 15)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(project.title), \(project.difficulty.title), \(project.detail)")
    }
}

