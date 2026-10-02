import SwiftUI

/// Navigation targets inside the Projects tab.
enum ProjectsRoute: Hashable {
    case myProjects
}

/// The installed Academy example gallery, with search and category filters.
struct ProjectLibraryView: View {
    @State private var query = ""
    @State private var category: RustShowcaseCategory?
    @State private var difficulty: RustShowcaseDifficulty?
    /// `-CrabrixCanvasGallery` opens the library already filtered to the Rust
    /// Canvas projects, the same way `-CrabrixTab` opens a tab: store frames
    /// and review walkthroughs then come out of every build identically.
    @State private var visualOnly = ProcessInfo.processInfo
        .arguments.contains("-CrabrixCanvasGallery")

    let projects: [RustShowcaseProject]
    let onOpen: (RustShowcaseProject) -> Void

    private let columns = [GridItem(.adaptive(minimum: 260), spacing: 14)]

    private var results: [RustShowcaseProject] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return projects.filter { project in
            if let category, project.category != category { return false }
            if let difficulty, project.difficulty != difficulty { return false }
            if visualOnly, !project.isVisual { return false }
            guard !needle.isEmpty else { return true }
            return project.searchHaystack.contains(needle)
        }
    }

    /// Categories that actually have something in them right now.
    private var availableCategories: [RustShowcaseCategory] {
        let present = Set(projects.map(\.category))
        return RustShowcaseCategory.allCases.filter { present.contains($0) }
    }

    private var guidedCount: Int {
        projects.filter(\.isGuided).count
    }

    private var visualCount: Int {
        projects.filter(\.isVisual).count
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
                            Button { onOpen(project) } label: {
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
        .navigationTitle("Examples")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Search projects, concepts, categories")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(projects.count) EXAMPLES · \(guidedCount) GUIDED · \(visualCount) VISUAL")
                .font(.caption.monospaced().bold())
                .foregroundStyle(CrabrixTheme.mint)
            Text("Open an Academy example")
                .font(.system(size: 26, weight: .bold, design: .rounded))
            Text("Copy an installed Rust example into your projects and edit it. The signed Academy package stays unchanged.")
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
                Label("RUST CANVAS", systemImage: "paintpalette.fill")
                    .font(.caption.monospaced().bold())
                    .foregroundStyle(CrabrixTheme.cyan)
                    .frame(maxWidth: .infinity, minHeight: 72)
                    .background(CrabrixTheme.raised, in: RoundedRectangle(cornerRadius: 9))
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
