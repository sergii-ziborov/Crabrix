import SwiftUI

struct RustSemanticInvocation: Identifiable {
    let id = UUID()
    let file: String
    let offset: Int
    let action: RustSemanticAction
    let revision: WorkspaceRevision
}

private struct RustSemanticRequest: Encodable, Sendable {
    struct Query: Encodable, Sendable {
        let op: String
        let file: String
        let offset: Int
        var name: String? = nil
        var imports: [String]? = nil
    }
    let workspace: RustSemanticWorkspace
    let query: Query
}

@MainActor
final class RustSemanticInspectorController: ObservableObject {
    private enum Output {
        case analysis(RustSemanticResult, RustSemanticProposal?)
        case proposal(RustSemanticProposal)
        case library(String, String, Int)
    }
    @Published private(set) var working = false
    @Published private(set) var message: String?
    @Published private(set) var result: RustSemanticResult?
    @Published private(set) var proposal: RustSemanticProposal?
    @Published private(set) var library: (file: String, text: String, line: Int)?
    @Published private(set) var sourcePosition: String?
    private(set) var context: RustSemanticContext?
    private var workspace: RustSemanticWorkspace?
    private var queryFile = ""
    private var queryOffset = 0
    private let runtime = RustSemanticRuntime()
    private var job: Task<Void, Never>?
    private var preparing: Task<(RustSemanticWorkspace, Int), Error>?
    private var token = UUID()

    func prepare(model: CompilerViewModel, invocation: RustSemanticInvocation) async {
        let identity = UUID(); token = identity
        working = true; message = "Preparing local Rust analysis…"
        do {
            let snapshot = try model.semanticContext()
            guard snapshot.revision == invocation.revision else {
                throw RustSemanticError.unavailable("Source changed before analysis opened. Reopen Rust symbols at the current cursor.")
            }
            guard let source = snapshot.project.files[invocation.file] else { throw RustSemanticError.unavailable("The selected source is unavailable.") }
            let preparation = Task.detached(priority: .userInitiated) {
                (try RustSemanticWorkspaceBuilder.build(snapshot), try RustSemanticText.utf8Offset(invocation.offset, in: source))
            }
            preparing = preparation
            let (workspace, offset) = try await withTaskCancellationHandler { try await preparation.value } onCancel: { preparation.cancel() }
            try Task.checkCancellation()
            guard token == identity else { return }
            preparing = nil
            guard model.workspaceRevision == snapshot.revision else { invalidate(); return }
            context = snapshot; self.workspace = workspace; queryFile = invocation.file; queryOffset = offset
            if let position = RustSemanticText.location(offset: offset, in: source) {
                sourcePosition = "Line \(position.line), column \(position.column)"
            }
            working = false; message = nil
            if invocation.action != .rename { query(invocation.action, model: model) }
        } catch {
            guard token == identity else { return }
            preparing = nil
            working = false; message = error.localizedDescription
        }
    }

    func query(_ action: RustSemanticAction, model: CompilerViewModel, name: String = "") {
        run(model: model, clearResults: true) { [self] workspace, files in
            let request = RustSemanticRequest(workspace: workspace, query: .init(op: action.rawValue, file: queryFile, offset: queryOffset, name: action == .rename ? name : nil))
            let result = try await perform(request)
            if action == .rename {
                guard !(result.annotations ?? []).contains(where: \.needsConfirmation) else {
                    throw RustSemanticError.unavailable("This name conflicts with another declaration. Choose another name before applying a rename.")
                }
                return .analysis(result, try await preview(result.files ?? [], files: files))
            }
            return .analysis(result, nil)
        }
    }

    func complete(_ item: RustSemanticCompletion, model: CompilerViewModel) {
        run(model: model) { [self] workspace, files in
            var imports: [RustSemanticEdit] = []
            if !item.imports.isEmpty {
                let request = RustSemanticRequest(workspace: workspace, query: .init(op: "completionImports", file: queryFile, offset: queryOffset, imports: item.imports))
                imports = try await perform(request).edits ?? []
            }
            // Imports precede the primary edit for stable same-offset insertions.
            return .proposal(try await preview([.init(file: queryFile, edits: imports + item.edits)], files: files))
        }
    }

    func openLibrary(_ target: RustSemanticTarget, model: CompilerViewModel) {
        run(model: model) { [self] workspace, _ in
            let request = RustSemanticRequest(workspace: workspace, query: .init(op: "source", file: target.file, offset: target.range.start))
            let source = try await perform(request)
            guard let text = source.text else { throw RustSemanticError.unavailable("Library source is unavailable in this profile.") }
            return .library(target.file, text, RustSemanticText.location(offset: target.range.start, in: text)?.line ?? 1)
        }
    }

    func backFromLibrary() { library = nil }
    func clearPreview() { proposal = nil }
    func invalidate() {
        stop()
        message = "Source changed. Reopen Rust symbols at the current cursor; stale results cannot be applied."
    }
    func stop() {
        token = UUID(); preparing?.cancel(); preparing = nil; job?.cancel(); job = nil; runtime.releaseMemory()
        working = false; context = nil; workspace = nil; result = nil; proposal = nil; library = nil
        sourcePosition = nil
        message = "Analysis stopped. Reopen Rust symbols to analyze the current cursor."
    }

    private func run(model: CompilerViewModel, clearResults: Bool = false,
                     operation: @escaping @MainActor (RustSemanticWorkspace, [String: String]) async throws -> Output) {
        guard let context, let workspace, model.workspaceRevision == context.revision else { invalidate(); return }
        if job != nil { job?.cancel(); runtime.releaseMemory() }
        let identity = UUID(); token = identity
        working = true; message = nil; proposal = nil
        if clearResults { result = nil }
        job = Task { [weak self, weak model] in
            guard let self, let model else { return }
            defer { if token == identity { working = false; job = nil } }
            do {
                let output = try await operation(workspace, context.project.files)
                try Task.checkCancellation()
                guard token == identity else { return }
                guard model.workspaceRevision == context.revision else { invalidate(); return }
                switch output {
                case let .analysis(result, proposal): self.result = result; self.proposal = proposal
                case let .proposal(proposal): self.proposal = proposal
                case let .library(file, text, line): library = (file, text, line)
                }
            } catch {
                guard token == identity, !Task.isCancelled else { return }
                result = nil; proposal = nil; message = error.localizedDescription
            }
        }
    }

    private func perform(_ request: RustSemanticRequest) async throws -> RustSemanticResult {
        let data = try await Task.detached { try JSONEncoder().encode(request) }.value
        try Task.checkCancellation()
        let bytes = try await runtime.perform(data)
        try Task.checkCancellation()
        return try JSONDecoder().decode(RustSemanticEnvelope.self, from: bytes).validated()
    }
    private func preview(_ changes: [RustSemanticFileChange], files: [String: String]) async throws -> RustSemanticProposal {
        let proposal = try await Task.detached { try RustSemanticProposal(files: files, changes: changes) }.value
        try Task.checkCancellation()
        return proposal
    }
}

struct RustSemanticPresentation: ViewModifier {
    @ObservedObject var model: CompilerViewModel
    @Binding var invocation: RustSemanticInvocation?
    @Binding var selectedTab: BuildDockTab
    @Binding var navigation: EditorNavigationTarget?
    let keyboard: RustEditorKeyboardBridge
    func body(content: Content) -> some View {
        content.sheet(item: $invocation) { item in
            RustSemanticInspector(model: model, invocation: item, keyboard: keyboard) { file, location in
                model.selectFile(file)
                navigation = EditorNavigationTarget(filePath: file, line: location.line, column: location.column)
                selectedTab = .code
            }.presentationDetents([.large]).presentationDragIndicator(.visible)
        }
    }
}

struct RustSemanticInspector: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var model: CompilerViewModel
    let invocation: RustSemanticInvocation
    let keyboard: RustEditorKeyboardBridge
    let navigate: (String, (line: Int, column: Int)) -> Void
    @StateObject private var controller = RustSemanticInspectorController()
    @State private var action: RustSemanticAction = .definition
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Label("Local Rust analysis", systemImage: "curlybraces").font(.title2.bold())
                    Text(invocation.file).font(.caption.monospaced()).foregroundStyle(CrabrixTheme.muted)
                    if let position = controller.sourcePosition { Text(position).font(.caption.monospaced()).foregroundStyle(CrabrixTheme.muted) }
                    if let library = controller.library {
                        Button("Back to results", systemImage: "chevron.left") { controller.backFromLibrary() }
                        Text(library.file).font(.headline.monospaced())
                        Text("Read-only library source · around line \(library.line)").foregroundStyle(CrabrixTheme.muted)
                        codeWindow(library.text, line: library.line)
                    } else {
                        Picker("Rust operation", selection: $action) {
                            ForEach(RustSemanticAction.allCases) { value in Text(value.title).tag(value) }
                        }.pickerStyle(.menu).tint(CrabrixTheme.blue).disabled(controller.working || controller.context == nil)
                            .accessibilityIdentifier("semantic-operation")
                        if action == .rename {
                            TextField("New Rust identifier", text: $newName).textInputAutocapitalization(.never).autocorrectionDisabled()
                                .textFieldStyle(.roundedBorder).accessibilityIdentifier("semantic-new-name")
                            Button("Preview rename") { controller.query(.rename, model: model, name: newName) }
                                .buttonStyle(.borderedProminent).tint(CrabrixTheme.blue).foregroundStyle(CrabrixTheme.onAccent)
                                .disabled(newName.isEmpty || newName.utf8.count > 128 || controller.context == nil || controller.working || model.playgroundIsReadOnly)
                                .accessibilityIdentifier("semantic-preview-rename")
                        }
                        if controller.working {
                            HStack { ProgressView(); Text("Analyzing this snapshot…"); Spacer()
                                Button("Stop") { controller.stop() }.accessibilityIdentifier("semantic-stop")
                            }
                        }
                        if let message = controller.message { Text(message).foregroundStyle(CrabrixTheme.muted).accessibilityIdentifier("semantic-message") }
                        if let proposal = controller.proposal { preview(proposal) }
                        else if let result = controller.result { results(result) }
                    }
                    Text("Uses the bundled WASI target and prepared source graph. External procedural macros and generated-source graphs are outside this profile. Compiler Check remains authoritative.")
                        .font(.caption).foregroundStyle(CrabrixTheme.muted)
                }.padding(20).frame(maxWidth: 760, alignment: .leading).frame(maxWidth: .infinity)
            }.background(CrabrixTheme.background.ignoresSafeArea()).foregroundStyle(CrabrixTheme.primary)
                .navigationTitle("Rust symbols").navigationBarTitleDisplayMode(.inline)
                .toolbar { CrabrixModalCloseAction(label: "Close Rust symbols") { dismiss() } }
                .task { action = invocation.action; await controller.prepare(model: model, invocation: invocation) }
                .onChange(of: action) { old, value in
                    guard old != value, controller.context != nil else { return }
                    controller.clearPreview()
                    if value != .rename { controller.query(value, model: model) }
                }
                .onChange(of: newName) { _, _ in controller.clearPreview() }
                .onChange(of: model.semanticGeneration) { _, _ in controller.invalidate() }
                .onChange(of: model.projectID) { _, _ in controller.invalidate() }
                .onChange(of: model.isBusy) { _, busy in if busy { controller.stop() } }
                .onChange(of: scenePhase) { _, phase in if phase != .active { controller.stop() } }
                .onDisappear { controller.stop() }
        }
    }

    @ViewBuilder private func results(_ result: RustSemanticResult) -> some View {
        let targets = result.targets ?? result.references ?? []
        if !targets.isEmpty {
            Text("\(targets.count) \(action == .references ? "project locations" : "definitions")").font(.headline)
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(targets.indices, id: \.self) { index in
                    let target = targets[index]
                    Button { open(target) } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(target.name ?? (target.declaration == true ? "Declaration" : "Reference")).font(.headline)
                            Text(target.file).font(.caption.monospaced()).foregroundStyle(CrabrixTheme.muted)
                            if let text = controller.context?.project.files[target.file], let location = RustSemanticText.location(offset: target.range.start, in: text) {
                                Text("Line \(location.line), column \(location.column)").font(.caption)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(12).crabrixPanel().contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier("semantic-location-\(index)")
                }
            }
        } else if let hover = result.hover {
            Text(String(hover.text.prefix(16_384))).font(.body.monospaced()).textSelection(.enabled).accessibilityIdentifier("semantic-type")
        } else if let signature = result.signature {
            Text(signature.text).font(.body.monospaced()).textSelection(.enabled)
            if let parameter = signature.activeParameter { Text("Argument \(parameter + 1)").foregroundStyle(CrabrixTheme.muted) }
        } else if let items = result.items, !items.isEmpty {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(items) { item in
                    Button { controller.complete(item, model: model) } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(item.label).font(.headline.monospaced())
                            if let detail = item.detail { Text(detail).font(.caption.monospaced()).foregroundStyle(CrabrixTheme.muted) }
                            if !item.imports.isEmpty { Text("Includes import preview").font(.caption).foregroundStyle(CrabrixTheme.blue) }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(12).crabrixPanel().contentShape(Rectangle())
                    }.buttonStyle(.plain).disabled(model.playgroundIsReadOnly)
                }
            }
        } else if action != .rename {
            Text("Information is unavailable at this position. Place the cursor on a linked Rust symbol, or after a receiver’s dot for completion.").foregroundStyle(CrabrixTheme.muted)
        }
    }

    private func preview(_ proposal: RustSemanticProposal) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Review changes in \(proposal.changedPaths.count) \(proposal.changedPaths.count == 1 ? "file" : "files")").font(.headline)
            ForEach(proposal.changedPaths, id: \.self) { path in
                Text(path).font(.headline.monospaced())
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(proposal.reviewed[path] ?? []) { edit in
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Line \(edit.line)").font(.caption).foregroundStyle(CrabrixTheme.muted)
                            if !edit.before.isEmpty { Text("− " + edit.before).font(.body.monospaced()).foregroundStyle(CrabrixTheme.coral).textSelection(.enabled) }
                            if !edit.after.isEmpty { Text("+ " + edit.after).font(.body.monospaced()).foregroundStyle(CrabrixTheme.mint).textSelection(.enabled) }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(12).crabrixPanel()
                    }
                }
                DisclosureGroup("Source context") {
                    Text("Before").foregroundStyle(CrabrixTheme.muted)
                    codeWindow(proposal.before[path] ?? "", line: changedLine(proposal.before[path] ?? "", proposal.after[path] ?? ""))
                    Text("After").foregroundStyle(CrabrixTheme.mint)
                    codeWindow(proposal.after[path] ?? "", line: changedLine(proposal.before[path] ?? "", proposal.after[path] ?? ""))
                }
            }
            Button("Apply reviewed changes") {
                guard let context = controller.context,
                      model.applySemanticProposal(proposal, expected: context.revision, applyToEditor: keyboard.applyFormattedText) else {
                    controller.invalidate(); return
                }
                dismiss()
            }.buttonStyle(.borderedProminent).tint(CrabrixTheme.blue).foregroundStyle(CrabrixTheme.onAccent)
                .disabled(controller.working || model.playgroundIsReadOnly).accessibilityIdentifier("semantic-apply")
        }
    }
    private func open(_ target: RustSemanticTarget) {
        guard let context = controller.context, model.workspaceRevision == context.revision else { controller.invalidate(); return }
        if let text = context.project.files[target.file], let location = RustSemanticText.location(offset: target.range.start, in: text) {
            navigate(target.file, location); dismiss()
        } else { controller.openLibrary(target, model: model) }
    }
    private func changedLine(_ before: String, _ after: String) -> Int {
        let a = before.split(separator: "\n", omittingEmptySubsequences: false), b = after.split(separator: "\n", omittingEmptySubsequences: false)
        return zip(a, b).enumerated().first(where: { $0.element.0 != $0.element.1 }).map { $0.offset + 1 } ?? max(1, min(a.count, b.count))
    }
    private func codeWindow(_ source: String, line: Int) -> some View {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
        let first = max(0, min(line - 4, max(0, lines.count - 1))), last = min(lines.count, first + 24)
        let code = lines[first..<last].map { String($0.prefix(240)) }.joined(separator: "\n")
        return VStack(alignment: .leading, spacing: 5) {
            Text("Lines \(first + 1)–\(last)").font(.caption).foregroundStyle(CrabrixTheme.muted)
            ScrollView(.horizontal) { Text(SyntaxTheme.attributedString(code)).fixedSize(horizontal: true, vertical: true).textSelection(.enabled).padding(12) }
                .background(SyntaxTheme.background).clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
}
