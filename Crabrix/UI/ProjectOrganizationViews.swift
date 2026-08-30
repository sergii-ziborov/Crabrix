import Foundation
import SwiftUI

struct ProjectDetailsDraft: Equatable {
    var name: String
    var projectDescription: String
    var folder: String
    var tagsText: String
    var kind: CrabrixProject.Kind
    var isFavorite: Bool

    init(
        name: String = "my-rust-project",
        projectDescription: String = "",
        folder: String = "",
        tagsText: String = "",
        kind: CrabrixProject.Kind = .general,
        isFavorite: Bool = false
    ) {
        self.name = name
        self.projectDescription = projectDescription
        self.folder = folder
        self.tagsText = tagsText
        self.kind = kind
        self.isFavorite = isFavorite
    }

    init(project: CrabrixProject) {
        self.init(
            name: project.name,
            projectDescription: project.projectDescription,
            folder: project.folder ?? "",
            tagsText: project.tags.joined(separator: ", "),
            kind: project.kind,
            isFavorite: project.isFavorite
        )
    }

    var tags: [String] {
        CrabrixProject.normalizedTags([tagsText])
    }

    var optionalFolder: String? {
        CrabrixProject.normalizedFolder(folder)
    }
}

struct ProjectMetadataFields: View {
    @Binding var draft: ProjectDetailsDraft
    var showsName = true
    var suggestedFolders = [
        "Learning", "Personal", "Work", "Experiments",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if showsName {
                fieldLabel("Project name", systemImage: "textformat")
                TextField("my-rust-project", text: $draft.name)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
            }

            fieldLabel("What is this project?", systemImage: "text.alignleft")
            TextField(
                "A short description that will appear in My Projects",
                text: $draft.projectDescription,
                axis: .vertical
            )
            .lineLimit(2...4)
            .textFieldStyle(.roundedBorder)

            fieldLabel("Type", systemImage: draft.kind.systemImage)
            Picker("Project type", selection: $draft.kind) {
                ForEach(CrabrixProject.Kind.allCases) { kind in
                    Label(kind.title, systemImage: kind.systemImage)
                        .tag(kind)
                }
            }
            .pickerStyle(.menu)
            .tint(CrabrixTheme.blue)

            fieldLabel("Folder", systemImage: "folder.fill")
            TextField("Unfiled", text: $draft.folder)
                .textInputAutocapitalization(.words)
                .textFieldStyle(.roundedBorder)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(suggestedFolders, id: \.self) { folder in
                        Button(folder) { draft.folder = folder }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .tint(
                                draft.folder == folder
                                    ? CrabrixTheme.coral
                                    : CrabrixTheme.muted
                            )
                    }
                }
            }

            fieldLabel("Tags", systemImage: "tag.fill")
            TextField("parser, wasm, practice", text: $draft.tagsText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
            Text("Comma-separated · up to 8 tags")
                .font(.caption2)
                .foregroundStyle(CrabrixTheme.muted)
        }
    }

    private func fieldLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption.bold())
            .foregroundStyle(CrabrixTheme.muted)
    }
}

/// Metadata-only editor used by the library. Unlike ProjectActionsSheet it can
/// organize a project without opening it and intentionally has no export
/// actions, which always belong to the active workspace.
struct ProjectOrganizerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ProjectDetailsDraft
    @State private var isSaving = false
    @State private var saveFailed = false

    let projectID: UUID
    let suggestedFolders: [String]
    let onSave: (UUID, ProjectDetailsDraft) async -> Bool

    init(
        project: CrabrixProject,
        suggestedFolders: [String],
        onSave: @escaping (UUID, ProjectDetailsDraft) async -> Bool
    ) {
        projectID = project.id
        self.suggestedFolders = suggestedFolders
        self.onSave = onSave
        _draft = State(initialValue: ProjectDetailsDraft(project: project))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 12) {
                        Image(systemName: draft.kind.systemImage)
                            .font(.title2)
                            .foregroundStyle(CrabrixTheme.coral)
                            .frame(width: 48, height: 48)
                            .background(
                                CrabrixTheme.coral.opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 14)
                            )
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Organize project")
                                .font(.title3.bold())
                            Text("Project identity and files stay unchanged.")
                                .font(.caption)
                                .foregroundStyle(CrabrixTheme.muted)
                        }
                        Spacer(minLength: 0)
                        Toggle("Favorite", isOn: $draft.isFavorite)
                            .labelsHidden()
                            .tint(CrabrixTheme.amber)
                    }

                    ProjectMetadataFields(
                        draft: $draft,
                        suggestedFolders: suggestedFolders
                    )

                    if saveFailed {
                        Label(
                            "Could not save these details. The project may have been removed.",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.caption)
                        .foregroundStyle(CrabrixTheme.coral)
                    }
                }
                .padding(20)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
            }
            .background(CrabrixTheme.background.ignoresSafeArea())
            .foregroundStyle(CrabrixTheme.primary)
            .navigationTitle(draft.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") {
                        save()
                    }
                    .disabled(
                        isSaving
                            || draft.name
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                                .isEmpty
                    )
                }
            }
        }
    }

    private func save() {
        isSaving = true
        saveFailed = false
        Task {
            let didSave = await onSave(projectID, draft)
            isSaving = false
            saveFailed = !didSave
            if didSave { dismiss() }
        }
    }
}

struct ProjectActionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ProjectDetailsDraft
    @State private var showSaved = false

    let project: CrabrixProject
    let onUpdate: (ProjectDetailsDraft) -> Bool
    let onSaveToFiles: () -> Void
    let onShareArchive: () -> Void

    init(
        project: CrabrixProject,
        onUpdate: @escaping (ProjectDetailsDraft) -> Bool,
        onSaveToFiles: @escaping () -> Void,
        onShareArchive: @escaping () -> Void
    ) {
        self.project = project
        self.onUpdate = onUpdate
        self.onSaveToFiles = onSaveToFiles
        self.onShareArchive = onShareArchive
        _draft = State(initialValue: ProjectDetailsDraft(project: project))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    overview

                    VStack(spacing: 10) {
                        actionButton(
                            title: "Save editable project",
                            detail: "Keep a .crabrixproject package in Files or iCloud Drive",
                            systemImage: "square.and.arrow.down.fill",
                            tint: CrabrixTheme.amber,
                            action: presentFileExporter
                        )
                        actionButton(
                            title: "Archive & share ZIP",
                            detail: "AirDrop, Messages, Mail, or another app",
                            systemImage: "archivebox.fill",
                            tint: CrabrixTheme.coral,
                            action: presentArchiveShare
                        )
                    }

                    Divider().overlay(CrabrixTheme.border)

                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Organize project")
                                .font(.title3.bold())
                            Text("These details stay with exported Crabrix packages.")
                                .font(.caption)
                                .foregroundStyle(CrabrixTheme.muted)
                        }
                        Spacer()
                        Toggle("Favorite", isOn: $draft.isFavorite)
                            .labelsHidden()
                            .tint(CrabrixTheme.amber)
                    }

                    ProjectMetadataFields(draft: $draft)

                    Button {
                        guard onUpdate(draft) else { return }
                        showSaved = true
                    } label: {
                        Label(
                            showSaved ? "Details saved" : "Save project details",
                            systemImage: showSaved
                                ? "checkmark.circle.fill"
                                : "checkmark.circle"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(showSaved ? CrabrixTheme.mint : CrabrixTheme.blue)
                    .disabled(
                        draft.name
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                            .isEmpty
                    )
                }
                .padding(22)
                .frame(maxWidth: 700)
                .frame(maxWidth: .infinity)
            }
            .background(CrabrixTheme.background.ignoresSafeArea())
            .foregroundStyle(CrabrixTheme.primary)
            .navigationTitle("Project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onChange(of: draft) { _, _ in
                showSaved = false
            }
        }
    }

    private var overview: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: draft.kind.systemImage)
                .font(.title2)
                .foregroundStyle(CrabrixTheme.coral)
                .frame(width: 50, height: 50)
                .background(
                    CrabrixTheme.coral.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 14)
                )
            VStack(alignment: .leading, spacing: 4) {
                Text(draft.name)
                    .font(.title2.bold())
                Text("\(project.files.count) files · \(project.rustFileCount) Rust · \(project.folderLabel)")
                    .font(.caption.monospaced())
                    .foregroundStyle(CrabrixTheme.muted)
            }
            Spacer(minLength: 0)
            Button {
                draft.isFavorite.toggle()
            } label: {
                Image(
                    systemName: draft.isFavorite
                        ? "star.fill"
                        : "star"
                )
                .font(.title3)
                .foregroundStyle(CrabrixTheme.amber)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                draft.isFavorite
                    ? "Remove from favorites"
                    : "Add to favorites"
            )
        }
    }

    private func actionButton(
        title: String,
        detail: String,
        systemImage: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 13) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(tint)
                    .frame(width: 38, height: 38)
                    .background(
                        tint.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 11)
                    )
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.subheadline.bold())
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(CrabrixTheme.muted)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(CrabrixTheme.muted)
            }
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .crabrixPanel(cornerRadius: 13)
        }
        .buttonStyle(.plain)
    }

    private func presentFileExporter() {
        guard onUpdate(draft) else { return }
        dismiss()
        DispatchQueue.main.async { onSaveToFiles() }
    }

    private func presentArchiveShare() {
        guard onUpdate(draft) else { return }
        dismiss()
        DispatchQueue.main.async { onShareArchive() }
    }
}

struct MyProjectsView: View {
    enum Sort: String, CaseIterable, Identifiable {
        case recentlyUpdated
        case name
        case folder

        var id: String { rawValue }
        var title: String {
            switch self {
            case .recentlyUpdated: "Recently updated"
            case .name: "Name"
            case .folder: "Folder"
            }
        }
    }

    @State private var query = ""
    @State private var selectedFolder: String?
    @State private var selectedTag: String?
    @State private var favoritesOnly = false
    @State private var sort: Sort = .recentlyUpdated
    @State private var deletionCandidate: ProjectLibraryItem?
    @State private var editCandidate: ProjectLibraryItem?

    let items: [ProjectLibraryItem]
    let onOpen: (UUID) -> Void
    let onToggleFavorite: (UUID) -> Void
    let onDelete: (UUID) -> Void
    let onUpdate: (UUID, ProjectDetailsDraft) async -> Bool

    private let columns = [
        GridItem(.adaptive(minimum: 270), spacing: 12),
    ]

    private var folders: [String] {
        Array(Set(items.map { $0.project.folderLabel }))
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private var tags: [String] {
        Array(Set(items.flatMap { $0.project.tags }))
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private var results: [ProjectLibraryItem] {
        let needle = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        var values = items.filter { item in
            if favoritesOnly, !item.project.isFavorite {
                return false
            }
            if let selectedFolder,
               item.project.folderLabel != selectedFolder {
                return false
            }
            if let selectedTag,
               !item.project.tags.contains(selectedTag) {
                return false
            }
            return needle.isEmpty
                || item.project.searchHaystack.contains(needle)
        }
        values.sort { left, right in
            if left.project.isFavorite != right.project.isFavorite {
                return left.project.isFavorite
            }
            switch sort {
            case .recentlyUpdated:
                return left.lastOpenedAt > right.lastOpenedAt
            case .name:
                return left.project.name.localizedStandardCompare(
                    right.project.name
                ) == .orderedAscending
            case .folder:
                let folderOrder = left.project.folderLabel
                    .localizedStandardCompare(right.project.folderLabel)
                if folderOrder != .orderedSame {
                    return folderOrder == .orderedAscending
                }
                return left.project.name.localizedStandardCompare(
                    right.project.name
                ) == .orderedAscending
            }
        }
        return values
    }

    private var groupedResults: [(folder: String, items: [ProjectLibraryItem])] {
        let groups = Dictionary(grouping: results) {
            $0.project.folderLabel
        }
        return groups.keys.sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }.map { ($0, groups[$0] ?? []) }
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
                    ForEach(groupedResults, id: \.folder) { group in
                        MyProjectFolderSection(
                            folder: group.folder,
                            items: group.items,
                            columns: columns,
                            onOpen: onOpen,
                            onToggleFavorite: onToggleFavorite,
                            onRequestEdit: {
                                editCandidate = $0
                            },
                            onRequestDelete: {
                                deletionCandidate = $0
                            }
                        )
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 1_100)
            .frame(maxWidth: .infinity)
        }
        .background(CrabrixTheme.background.ignoresSafeArea())
        .foregroundStyle(CrabrixTheme.primary)
        .navigationTitle("My Projects")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $query,
            prompt: "Search names, descriptions, folders, tags"
        )
        .confirmationDialog(
            "Delete \(deletionCandidate?.project.name ?? "project")?",
            isPresented: Binding(
                get: { deletionCandidate != nil },
                set: { if !$0 { deletionCandidate = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Project", role: .destructive) {
                guard let id = deletionCandidate?.id else { return }
                deletionCandidate = nil
                onDelete(id)
            }
            Button("Cancel", role: .cancel) {
                deletionCandidate = nil
            }
        } message: {
            Text("This removes its local files. Export it first if you need a copy.")
        }
        .sheet(item: $editCandidate) { item in
            ProjectOrganizerSheet(
                project: item.project,
                suggestedFolders: folders.filter { $0 != "Unfiled" },
                onSave: onUpdate
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(items.count) PROJECTS · \(folders.count) FOLDERS · \(tags.count) TAGS · \(items.filter { $0.project.isFavorite }.count) FAVORITES")
                .font(.caption.monospaced().bold())
                .foregroundStyle(CrabrixTheme.mint)
            Text("Everything you build, organized")
                .font(.system(size: 26, weight: .bold, design: .rounded))
            Text("Folders and tags change how projects are shown, never where their durable files are stored.")
                .font(.subheadline)
                .foregroundStyle(CrabrixTheme.muted)
        }
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: 9) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ProjectFilterChip(
                        title: "All folders",
                        systemImage: "tray.full.fill",
                        isSelected: selectedFolder == nil && !favoritesOnly
                    ) {
                        selectedFolder = nil
                        favoritesOnly = false
                    }
                    ProjectFilterChip(
                        title: "Favorites",
                        systemImage: "star.fill",
                        isSelected: favoritesOnly
                    ) {
                        favoritesOnly.toggle()
                    }
                    ForEach(folders, id: \.self) { folder in
                        ProjectFilterChip(
                            title: folder,
                            systemImage: "folder.fill",
                            isSelected: selectedFolder == folder
                        ) {
                            favoritesOnly = false
                            selectedFolder = selectedFolder == folder
                                ? nil
                                : folder
                        }
                    }
                }
            }

            if !tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ProjectFilterChip(
                            title: "All tags",
                            systemImage: "tag",
                            isSelected: selectedTag == nil
                        ) { selectedTag = nil }
                        ForEach(tags, id: \.self) { tag in
                            ProjectFilterChip(
                                title: "#\(tag)",
                                systemImage: "tag.fill",
                                isSelected: selectedTag == tag
                            ) {
                                selectedTag = selectedTag == tag ? nil : tag
                            }
                        }
                    }
                }
            }

            HStack {
                Menu {
                    Picker("Sort", selection: $sort) {
                        ForEach(Sort.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                } label: {
                    Label(sort.title, systemImage: "arrow.up.arrow.down")
                        .font(.caption.bold())
                }
                Spacer()
                Text("\(results.count) shown")
                    .font(.caption.monospaced())
                    .foregroundStyle(CrabrixTheme.muted)
            }
        }
    }
}

private struct MyProjectFolderSection: View {
    @State private var isExpanded = true

    let folder: String
    let items: [ProjectLibraryItem]
    let columns: [GridItem]
    let onOpen: (UUID) -> Void
    let onToggleFavorite: (UUID) -> Void
    let onRequestEdit: (ProjectLibraryItem) -> Void
    let onRequestDelete: (ProjectLibraryItem) -> Void

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(items) { item in
                    ZStack(alignment: .topTrailing) {
                        Button { onOpen(item.id) } label: {
                            MyProjectCard(item: item)
                        }
                        .buttonStyle(.plain)

                        projectMenu(for: item)
                            .padding(9)
                    }
                    .contextMenu {
                        Button {
                            onToggleFavorite(item.id)
                        } label: {
                            Label(
                                item.project.isFavorite
                                    ? "Remove Favorite"
                                    : "Favorite",
                                systemImage: item.project.isFavorite
                                    ? "star.slash"
                                    : "star"
                            )
                        }
                        Button {
                            onRequestEdit(item)
                        } label: {
                            Label("Edit Folder & Tags", systemImage: "slider.horizontal.3")
                        }
                        Button(role: .destructive) {
                            onRequestDelete(item)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .padding(.top, 10)
        } label: {
            HStack {
                Label(folder, systemImage: "folder.fill")
                    .font(.headline)
                    .foregroundStyle(CrabrixTheme.blue)
                Spacer()
                Text("\(items.count)")
                    .font(.caption.monospaced().bold())
                    .foregroundStyle(CrabrixTheme.muted)
            }
        }
        .tint(CrabrixTheme.blue)
    }

    private func projectMenu(for item: ProjectLibraryItem) -> some View {
        Menu {
            Button {
                onRequestEdit(item)
            } label: {
                Label("Edit Folder & Tags", systemImage: "slider.horizontal.3")
            }
            Button {
                onToggleFavorite(item.id)
            } label: {
                Label(
                    item.project.isFavorite ? "Remove Favorite" : "Favorite",
                    systemImage: item.project.isFavorite ? "star.slash" : "star"
                )
            }
            Divider()
            Button(role: .destructive) {
                onRequestDelete(item)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.subheadline.bold())
                .foregroundStyle(CrabrixTheme.muted)
                .frame(width: 32, height: 32)
                .background(.ultraThinMaterial, in: Circle())
                .contentShape(Circle())
        }
        .accessibilityLabel("Actions for \(item.project.name)")
    }
}

private struct MyProjectCard: View {
    let item: ProjectLibraryItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: item.project.kind.systemImage)
                    .font(.headline)
                    .foregroundStyle(CrabrixTheme.coral)
                    .frame(width: 38, height: 38)
                    .background(
                        CrabrixTheme.coral.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 11)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.project.name)
                        .font(.headline)
                        .lineLimit(1)
                    Text(item.project.kind.title.uppercased())
                        .font(.system(
                            size: 8,
                            weight: .bold,
                            design: .monospaced
                        ))
                        .foregroundStyle(CrabrixTheme.muted)
                }
                Spacer()
                if item.project.isFavorite {
                    Image(systemName: "star.fill")
                        .foregroundStyle(CrabrixTheme.amber)
                }
                Color.clear.frame(width: 28, height: 1)
            }

            Text(
                item.project.projectDescription.isEmpty
                    ? "No description yet — open Project actions to add one."
                    : item.project.projectDescription
            )
            .font(.caption)
            .foregroundStyle(CrabrixTheme.muted)
            .lineLimit(2)

            HStack(spacing: 5) {
                ForEach(item.project.tags.prefix(3), id: \.self) { tag in
                    Text("#\(tag)")
                        .font(.system(size: 9, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(CrabrixTheme.raised, in: Capsule())
                        .foregroundStyle(CrabrixTheme.blue)
                }
                if item.project.tags.isEmpty {
                    Text("\(item.project.files.count) files")
                        .font(.caption2.monospaced())
                        .foregroundStyle(CrabrixTheme.muted)
                }
                Spacer()
                if let build = item.lastBuild {
                    Image(
                        systemName: build.succeeded
                            ? "checkmark.circle.fill"
                            : "xmark.circle.fill"
                    )
                    .foregroundStyle(
                        build.succeeded
                            ? CrabrixTheme.mint
                            : CrabrixTheme.coral
                    )
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .crabrixPanel(cornerRadius: 15)
        .accessibilityElement(children: .combine)
    }
}

private struct ProjectFilterChip: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption.bold())
                .lineLimit(1)
                .padding(.horizontal, 11)
                .frame(height: 32)
                .background(
                    isSelected
                        ? CrabrixTheme.blue.opacity(0.16)
                        : CrabrixTheme.raised,
                    in: Capsule()
                )
                .overlay {
                    Capsule().stroke(
                        isSelected
                            ? CrabrixTheme.blue
                            : CrabrixTheme.border
                    )
                }
        }
        .buttonStyle(.plain)
    }
}
