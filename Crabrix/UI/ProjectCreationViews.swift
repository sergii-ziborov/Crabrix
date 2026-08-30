import SwiftUI

enum ProjectItemCreation: String, Identifiable {
    case rustFile
    case moduleFolder

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rustFile: "New Rust File"
        case .moduleFolder: "New Module Folder"
        }
    }

    var detail: String {
        switch self {
        case .rustFile: "Creates an editable .rs file inside the project."
        case .moduleFolder: "Creates a folder with mod.rs so it persists and works as a Rust module."
        }
    }

    var placeholder: String {
        switch self {
        case .rustFile: "src/models.rs"
        case .moduleFolder: "src/models"
        }
    }

    var systemImage: String {
        switch self {
        case .rustFile: "doc.badge.plus"
        case .moduleFolder: "folder.badge.plus"
        }
    }
}

struct NewProjectSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ProjectDetailsDraft(kind: .learning)
    @State private var template: RustProjectTemplate = .hello

    let onCreate: (NewRustProjectRequest) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Label("Create a real Cargo project", systemImage: "shippingbox.and.arrow.backward.fill")
                        .font(.title2.bold())
                        .foregroundStyle(CrabrixTheme.coral)

                    Text("Choose a starting structure. Every template stays editable and builds with the bundled compiler.")
                        .font(.subheadline)
                        .foregroundStyle(CrabrixTheme.muted)

                    TextField("Project name", text: $draft.name)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)

                    VStack(spacing: 10) {
                        ForEach(RustProjectTemplate.allCases) { option in
                            Button {
                                template = option
                                draft.kind = option.defaultProjectKind
                            } label: {
                                HStack(spacing: 13) {
                                    Image(systemName: option.systemImage)
                                        .font(.title3)
                                        .foregroundStyle(option == template ? CrabrixTheme.coral : CrabrixTheme.blue)
                                        .frame(width: 34)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(option.title).font(.subheadline.bold())
                                        Text(option.detail)
                                            .font(.caption2)
                                            .foregroundStyle(CrabrixTheme.muted)
                                    }
                                    Spacer()
                                    Image(systemName: option == template ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(option == template ? CrabrixTheme.mint : CrabrixTheme.muted)
                                }
                                .padding(14)
                                .background(option == template ? CrabrixTheme.coral.opacity(0.08) : CrabrixTheme.panel)
                                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                                        .stroke(option == template ? CrabrixTheme.coral.opacity(0.5) : CrabrixTheme.border)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("ORGANIZE")
                            .font(.caption2.monospaced().bold())
                            .foregroundStyle(CrabrixTheme.mint)
                        ProjectMetadataFields(
                            draft: $draft,
                            showsName: false
                        )
                    }

                    Button {
                        onCreate(
                            NewRustProjectRequest(
                                name: draft.name,
                                template: template,
                                projectDescription: draft.projectDescription,
                                folder: draft.optionalFolder,
                                tags: draft.tags,
                                kind: draft.kind
                            )
                        )
                        dismiss()
                    } label: {
                        Label("Create Rust Project", systemImage: "plus.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(CrabrixTheme.coral)
                    .disabled(
                        draft.name
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                            .isEmpty
                    )
                }
                .padding(22)
            }
            .background(CrabrixTheme.background.ignoresSafeArea())
            .foregroundStyle(CrabrixTheme.primary)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

struct NewProjectItemSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var path = ""
    @State private var showError = false

    let mode: ProjectItemCreation
    let onCreate: (String) -> Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Label(mode.title, systemImage: mode.systemImage)
                    .font(.title2.bold())
                    .foregroundStyle(mode == .rustFile ? CrabrixTheme.coral : CrabrixTheme.blue)
                Text(mode.detail)
                    .font(.subheadline)
                    .foregroundStyle(CrabrixTheme.muted)
                TextField(mode.placeholder, text: $path)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(create)
                if showError {
                    Label("The path is invalid or already exists.", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(CrabrixTheme.amber)
                }
                Button(mode.title, action: create)
                    .buttonStyle(.borderedProminent)
                    .tint(mode == .rustFile ? CrabrixTheme.coral : CrabrixTheme.blue)
                    .frame(maxWidth: .infinity)
                    .disabled(path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Spacer()
            }
            .padding(22)
            .background(CrabrixTheme.background.ignoresSafeArea())
            .foregroundStyle(CrabrixTheme.primary)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func create() {
        if onCreate(path) {
            dismiss()
        } else {
            showError = true
        }
    }
}
