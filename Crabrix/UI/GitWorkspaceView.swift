import SwiftUI
import CrabrixGit

struct GitWorkspaceView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: CompilerViewModel
    @AppStorage("crabrix.git.author.name") private var author = ""
    @AppStorage("crabrix.git.author.email") private var email = ""
    @State private var tab = "Changes"
    @State private var selected: Set<String> = []
    @State private var message = ""
    @State private var branchName = ""
    @State private var showsDiff = false
    private enum Field: Hashable { case author, email, message, branch }
    @FocusState private var focusedField: Field?

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if model.gitIsWorking {
                        HStack { ProgressView(); Text(model.gitActivity).font(.subheadline); Spacer(); Button("Stop", action: model.stopGit) }
                    }
                    if model.gitNeedsRefresh {
                        Label("Newer editor changes · refresh this view", systemImage: "arrow.clockwise")
                            .font(.caption).foregroundStyle(CrabrixTheme.amber)
                    }
                    if let preview = model.gitRestorePreview {
                        restorePreview(preview)
                    } else if let commit = model.gitViewingCommit, let tree = model.gitRevisionTree {
                        version(commit, tree)
                    } else {
                        overview
                        if model.gitAvailable {
                            Picker("Git section", selection: $tab) {
                                ForEach(["Changes", "History", "Branches"], id: \.self) { Text($0) }
                            }.pickerStyle(.segmented)
                            switch tab {
                            case "History": history
                            case "Branches": branches
                            default: changes
                            }
                        }
                    }
                    if !model.gitMessage.isEmpty {
                        Text(String(model.gitMessage.prefix(2000)))
                            .font(.caption).foregroundStyle(CrabrixTheme.muted)
                            .textSelection(.enabled)
                    }
                }
                .padding(22).frame(maxWidth: 700).frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.immediately)
            .accessibilityIdentifier("local-git-scroll")
            .background(CrabrixTheme.background.ignoresSafeArea())
            .foregroundStyle(CrabrixTheme.primary)
            .navigationTitle("Local Git")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Refresh", systemImage: "arrow.clockwise", action: model.refreshGit)
                        .labelStyle(.iconOnly).disabled(model.gitIsWorking)
                }
                CrabrixModalCloseAction(label: "Close local Git") { dismiss() }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Hide Git keyboard", systemImage: "keyboard.chevron.compact.down") { focusedField = nil }
                        .labelStyle(.iconOnly)
                }
            }
            .onAppear { model.refreshGit() }
            .onChange(of: model.gitState?.revision) { _, _ in
                selected.formIntersection(Set(model.gitState?.changes.map(\.path) ?? []))
            }
        }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(model.exportProject().name, systemImage: "arrow.triangle.branch").font(.title3.bold())
            if let state = model.gitState {
                Text("\(state.branch) · \(state.head.map { String($0.prefix(8)) } ?? "no commits")")
                    .font(.subheadline.monospaced()).foregroundStyle(CrabrixTheme.muted)
            } else if !model.gitAvailable {
                Text("Record explicit local commits without an account. Autosave keeps protecting your current work; it does not create commits.")
                    .font(.subheadline).foregroundStyle(CrabrixTheme.muted)
                Text("A snapshot imported earlier starts a new history. Missing parent commits are not reconstructed.")
                    .font(.caption).foregroundStyle(CrabrixTheme.muted)
                Button("Start local Git history", action: model.initializeGit)
                    .buttonStyle(.borderedProminent).tint(CrabrixTheme.blue).foregroundStyle(Color.black)
                    .disabled(model.gitIsWorking)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(16).crabrixPanel()
    }

    private var changes: some View {
        LazyVStack(alignment: .leading, spacing: 12) {
            HStack {
                Button("Select all changes") { selected = Set(model.gitState?.changes.map(\.path) ?? []) }
                Spacer()
                Button("Clear selection") { selected.removeAll() }
            }.font(.caption)
            if let state = model.gitState, state.changes.isEmpty {
                Label("Working tree is clean", systemImage: "checkmark.circle").foregroundStyle(CrabrixTheme.primary)
            }
            ForEach(model.gitState?.changes ?? []) { change in
                HStack(spacing: 12) {
                    Button {
                        if selected.contains(change.path) { selected.remove(change.path) } else { selected.insert(change.path) }
                    } label: {
                        Image(systemName: selected.contains(change.path) ? "checkmark.square.fill" : "square")
                            .font(.title3).frame(width: 30, height: 38)
                    }
                    .accessibilityLabel("Select \(change.path) for commit")
                    Button {
                        model.showGitDiff(change.path); showsDiff = true
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(change.path).font(.subheadline.monospaced()).foregroundStyle(CrabrixTheme.primary)
                            Text(change.kind).font(.caption).foregroundStyle(CrabrixTheme.muted)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.padding(12).crabrixPanel()
            }
            if showsDiff, let diff = model.gitDiff {
                DisclosureGroup("Text diff", isExpanded: $showsDiff) {
                    ScrollView(.horizontal) {
                        Text(diff.text).font(.system(size: 12, design: .monospaced))
                            .textSelection(.enabled).fixedSize(horizontal: true, vertical: true).padding(.vertical, 10)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("Commit selected files").font(.headline)
                TextField("Author name", text: $author).textFieldStyle(.roundedBorder).focused($focusedField, equals: .author)
                TextField("Author email", text: $email).textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .email)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.emailAddress)
                TextField("Commit message", text: $message, axis: .vertical).lineLimit(2...4).textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .message)
                    .accessibilityIdentifier("git-commit-message")
                Button("Commit \(selected.count) selected file(s)") {
                    model.commitGit(paths: selected.sorted(), author: author, email: email, message: message)
                }
                .buttonStyle(.borderedProminent).tint(CrabrixTheme.blue).foregroundStyle(Color.black)
                .disabled(selected.isEmpty || author.isEmpty || email.isEmpty || message.isEmpty || model.gitNeedsRefresh || model.gitIsWorking)
            }.padding(16).crabrixPanel()
        }.disabled(model.gitIsWorking)
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.gitHistory.isEmpty { Text("Your first explicit commit will appear here.").foregroundStyle(CrabrixTheme.muted) }
            ForEach(model.gitHistory) { commit in
                Button { model.viewGitCommit(commit) } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(commit.message).font(.headline)
                        Text("\(commit.id.prefix(8)) · \(commit.author)").font(.caption.monospaced()).foregroundStyle(CrabrixTheme.muted)
                        Text(commit.date, style: .date).font(.caption).foregroundStyle(CrabrixTheme.muted)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(15).crabrixPanel()
                }.buttonStyle(.plain)
            }
        }.disabled(model.gitIsWorking)
    }

    private var branches: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("New branch name", text: $branchName).textInputAutocapitalization(.never).autocorrectionDisabled().textFieldStyle(.roundedBorder).focused($focusedField, equals: .branch)
            Button("Create branch") { model.createGitBranch(branchName) }
                .buttonStyle(.bordered).disabled(branchName.isEmpty || model.gitState?.head == nil || model.gitNeedsRefresh)
            if !model.gitCanSwitchBranch {
                Text("Commit or restore changes before switching. Leave a live Playground before changing the local branch.")
                    .font(.caption).foregroundStyle(CrabrixTheme.muted)
            }
            ForEach(model.gitBranches, id: \.self) { branch in
                Button { model.switchGitBranch(branch) } label: {
                    HStack {
                        Label(branch, systemImage: "arrow.triangle.branch").font(.subheadline.monospaced())
                        Spacer()
                        if model.gitState?.branch == branch { Image(systemName: "checkmark") }
                    }.padding(15).crabrixPanel()
                }.disabled(model.gitState?.branch == branch || !model.gitCanSwitchBranch)
            }
        }.disabled(model.gitIsWorking)
    }

    private func version(_ commit: GitCommit, _ tree: GitTreeSnapshot) -> some View {
        LazyVStack(alignment: .leading, spacing: 12) {
            Button("Back to history", systemImage: "chevron.left") { model.closeGitRevision() }
            Text(commit.message).font(.title3.bold())
            Text("\(commit.id.prefix(8)) · \(tree.opaquePaths.count) opaque files preserved").font(.caption).foregroundStyle(CrabrixTheme.muted)
            ForEach(tree.files.keys.sorted(), id: \.self) { path in
                Button { model.previewGitFile(commit: commit.id, path: path) } label: {
                    Label(path, systemImage: ProjectFileAppearance.forPath(path).symbol).font(.subheadline.monospaced())
                        .frame(maxWidth: .infinity, alignment: .leading).padding(13).crabrixPanel()
                }
            }
            if !tree.opaquePaths.isEmpty {
                Text(tree.opaquePaths.prefix(64).joined(separator: "\n") + (tree.opaquePaths.count > 64 ? "\n… \(tree.opaquePaths.count - 64) more opaque paths preserved" : ""))
                    .font(.caption.monospaced()).foregroundStyle(CrabrixTheme.muted)
            }
        }.disabled(model.gitIsWorking)
    }

    private func restorePreview(_ preview: GitRestorePreview) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Button("Back", systemImage: "chevron.left") { model.closeGitRestorePreview() }
            Text(preview.path).font(.title3.monospaced().bold())
            Text("From \(preview.commit.prefix(8))").font(.caption).foregroundStyle(CrabrixTheme.muted)
            Text("Current source").font(.headline)
            HighlightedCodeBlock(code: bounded(preview.original ?? "This file is absent from the current tree."), filePath: preview.path)
            Text("Version to restore").font(.headline)
            HighlightedCodeBlock(code: bounded(preview.replacement), filePath: preview.path)
            Button("Restore this file", action: model.restoreGitPreview)
                .buttonStyle(.borderedProminent).tint(CrabrixTheme.blue).foregroundStyle(Color.black)
                .disabled(model.gitIsWorking || model.playgroundIsReadOnly || preview.generation != model.workspaceGeneration)
        }
    }

    private func bounded(_ source: String) -> String {
        String(decoding: source.utf8.prefix(64 * 1024), as: UTF8.self)
            + (source.utf8.count > 64 * 1024 ? "\n// Preview limited to 64 KiB; Restore uses the complete file." : "")
    }
}
