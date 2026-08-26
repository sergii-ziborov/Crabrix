import SwiftUI
import UniformTypeIdentifiers

private enum CrabrixDestination: Hashable {
    case projects
    case build
    case learn
}

struct ContentView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = CompilerViewModel()
    @State private var isFileImporterPresented = false
    @State private var isFileExporterPresented = false
    @State private var isGitHubImporterPresented = false
    @State private var githubURL = ""
    @State private var selectedDestination: CrabrixDestination = .projects
    @State private var exportDocument = CrabrixProjectDocument(
        project: CrabrixProject(
            name: "hello-crabrix",
            files: ["main.rs": RustSamples.runnable],
            entryFile: "main.rs",
            provenance: nil
        )
    )

    var body: some View {
        TabView(selection: $selectedDestination) {
            ProjectsHomeView(
                projectName: model.projectName,
                fileCount: model.fileNames.count,
                lastBuild: model.lastBuild,
                recentProjects: model.recentProjects,
                onNewProject: {
                    model.loadRunnableSample()
                    selectedDestination = .build
                },
                onOpenGitHub: { isGitHubImporterPresented = true },
                onOpenFiles: { isFileImporterPresented = true },
                onSaveProject: prepareExport,
                onOpenRecent: { id in
                    Task {
                        await model.openRecentProject(id: id)
                        selectedDestination = .build
                    }
                },
                onOpenRunnableSample: {
                    model.loadRunnableSample()
                    selectedDestination = .build
                },
                onOpenBorrowSample: {
                    model.loadBorrowDiagnosticSample()
                    selectedDestination = .build
                },
                onOpenModulesSample: {
                    model.loadMultiFileSample()
                    selectedDestination = .build
                }
            )
            .tabItem { Label("Projects", systemImage: "folder.fill") }
            .tag(CrabrixDestination.projects)

            ZStack {
                CrabrixTheme.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    AppHeader(
                        toolchain: model.toolchain,
                        transfer: model.projectTransfer,
                        onNewProject: model.loadRunnableSample,
                        onOpenFiles: { isFileImporterPresented = true },
                        onSaveFiles: prepareExport,
                        onOpenGitHub: { isGitHubImporterPresented = true }
                    )
                    StageStrip(completed: model.completedStages)
                    if model.projectTransfer != .idle {
                        ProjectTransferStrip(transfer: model.projectTransfer)
                    }
                    Divider().overlay(CrabrixTheme.border)

                    if horizontalSizeClass == .regular {
                        HStack(spacing: 0) {
                            ProjectSidebar(
                                projectName: model.projectName,
                                files: model.fileNames,
                                selectedFile: model.selectedFile,
                                manifest: model.cargoManifest,
                                report: model.compatibilityReport,
                                provenance: model.provenance,
                                onSelect: model.selectFile
                            )
                            .frame(width: 210)
                            Divider().overlay(CrabrixTheme.border)
                            editorPane
                                .frame(minWidth: 420)
                            Divider().overlay(CrabrixTheme.border)
                            inspectorPane
                                .frame(minWidth: 350, idealWidth: 410, maxWidth: 470)
                        }
                    } else {
                        ScrollView {
                            VStack(spacing: 0) {
                                editorPane
                                    .frame(minHeight: 590)
                                Divider().overlay(CrabrixTheme.border)
                                inspectorPane
                                    .frame(minHeight: 500)
                            }
                        }
                    }
                }
            }
            .tabItem { Label("Build", systemImage: "hammer.fill") }
            .tag(CrabrixDestination.build)

            LearnPathView(
                completedStages: model.completedStages,
                practiceCompleted: model.practiceCompleted,
                onOpenLesson: openLesson
            )
            .tabItem { Label("Learn", systemImage: "graduationcap.fill") }
            .tag(CrabrixDestination.learn)
        }
        .tabViewStyle(.sidebarAdaptable)
        .tint(CrabrixTheme.coral)
        .foregroundStyle(.white)
        .sheet(isPresented: $model.isPracticePresented) {
            PracticeSheet(
                initialSource: RustSamples.practice,
                validate: model.validatePractice
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isGitHubImporterPresented) {
            GitHubImportSheet(
                url: $githubURL,
                transfer: model.projectTransfer,
                onImport: { rawURL in
                    let imported = await model.importGitHub(rawURL)
                    if imported {
                        isGitHubImporterPresented = false
                        selectedDestination = .build
                    }
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: [.folder, .crabrixProject],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case let .success(urls):
                guard let url = urls.first else { return }
                Task {
                    await model.openProject(from: url)
                    if case .ready = model.projectTransfer {
                        selectedDestination = .build
                    }
                }
            case let .failure(error):
                model.reportProjectFailure(error)
            }
        }
        .fileExporter(
            isPresented: $isFileExporterPresented,
            document: exportDocument,
            contentType: .crabrixProject,
            defaultFilename: model.projectName
        ) { result in
            switch result {
            case .success: model.markProjectSaved()
            case let .failure(error): model.reportProjectFailure(error)
            }
        }
        .task {
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("--crabrix-auto-multifile") {
                model.loadMultiFileSample()
                selectedDestination = .build
            }
            if let githubArgument = arguments.first(where: { $0.hasPrefix("--crabrix-auto-github=") }) {
                let rawURL = String(githubArgument.dropFirst("--crabrix-auto-github=".count))
                if await model.importGitHub(rawURL) {
                    selectedDestination = .build
                }
            }
            if arguments.contains("--crabrix-auto-learn") {
                selectedDestination = .learn
            }
            if arguments.contains("--crabrix-auto-run") {
                model.run()
            } else if arguments.contains("--crabrix-auto-check") {
                model.check()
            }
            if !arguments.contains(where: { $0.hasPrefix("--crabrix-auto-") }) {
                await model.consumePendingSharedImport()
                if case .ready = model.projectTransfer {
                    selectedDestination = .build
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await model.consumePendingSharedImport() }
        }
    }

    private func prepareExport() {
        exportDocument = CrabrixProjectDocument(project: model.exportProject())
        isFileExporterPresented = true
    }

    private func openLesson(_ lesson: RustLesson) {
        switch lesson.exercise {
        case .runnable:
            model.loadRunnableSample()
        case .borrowDiagnostic:
            model.loadBorrowDiagnosticSample()
        case .multiFile:
            model.loadMultiFileSample()
        case .planned:
            return
        }
        selectedDestination = .build
    }

    private var editorPane: some View {
        VStack(spacing: 0) {
            EditorToolbar(
                activity: model.activity,
                files: model.fileNames,
                selectedFile: model.selectedFile,
                canRun: model.toolchain.isReady && !model.isBusy && !model.isProjectOperationInProgress,
                onSelectFile: model.selectFile,
                onLoadRunnable: model.loadRunnableSample,
                onLoadDiagnostic: model.loadBorrowDiagnosticSample,
                onLoadMultiFile: model.loadMultiFileSample,
                onCheck: model.check,
                onRun: model.run
            )

            ZStack(alignment: .topLeading) {
                SyntaxCodeEditor(
                    text: $model.source,
                    filePath: model.selectedFile,
                    isEditable: !model.isBusy && !model.isProjectOperationInProgress
                )

                if model.isBusy {
                    HStack(alignment: .top, spacing: 10) {
                        ProgressView()
                            .tint(CrabrixTheme.coral)
                            .padding(.top, 2)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(model.activity.label)
                                .font(.caption.monospaced())
                            Text(model.activity == .running
                                 ? CrabrixBuildInfo.runTiming
                                 : CrabrixBuildInfo.checkTiming)
                                .font(.caption2)
                                .foregroundStyle(CrabrixTheme.muted)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }

            ResultConsole(result: model.result)
                .frame(minHeight: 150, idealHeight: 190, maxHeight: 230)
        }
        .background(CrabrixTheme.background)
    }

    @ViewBuilder
    private var inspectorPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let result = model.result, result.succeeded {
                    SuccessInspector(result: result, practiceCompleted: model.practiceCompleted)
                } else if let diagnostic = model.primaryDiagnostic {
                    DiagnosticInspector(
                        diagnostic: diagnostic,
                        canRepair: BorrowRepair.apply(to: model.source, diagnostic: diagnostic) != nil,
                        practiceCompleted: model.practiceCompleted,
                        onRepair: model.applyRepair,
                        onPractice: model.presentPractice
                    )
                } else {
                    RuntimeInspector(toolchain: model.toolchain)
                }
            }
            .padding(22)
        }
        .background(
            LinearGradient(
                colors: [CrabrixTheme.panel, CrabrixTheme.background],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }
}

private struct AppHeader: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let toolchain: ToolchainStatus
    let transfer: CompilerViewModel.ProjectTransfer
    let onNewProject: () -> Void
    let onOpenFiles: () -> Void
    let onSaveFiles: () -> Void
    let onOpenGitHub: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image("CrabrixMark")
                .resizable()
                .scaledToFit()
                .frame(width: 30, height: 30)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .accessibilityLabel("Crabrix crab")
            Text("crabrix")
                .font(.system(size: 21, weight: .bold, design: .rounded))
            if horizontalSizeClass == .regular {
                Text("NATIVE PHASE 0")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(CrabrixTheme.muted)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 5)
                    .overlay(Capsule().stroke(CrabrixTheme.border))
            }

            Spacer()

            Menu {
                Button(action: onNewProject) {
                    Label("New Rust Project", systemImage: "plus")
                }
                Button(action: onOpenGitHub) {
                    Label("Open from GitHub", systemImage: "arrow.down.circle")
                }
                Button(action: onOpenFiles) {
                    Label("Open from Files", systemImage: "folder")
                }
                Button(action: onSaveFiles) {
                    Label("Save Project to Files", systemImage: "square.and.arrow.down")
                }
            } label: {
                if transfer.isWorking {
                    ProgressView().tint(CrabrixTheme.coral)
                } else {
                    Label(horizontalSizeClass == .regular ? "PROJECT" : "", systemImage: "folder.fill")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white)
                }
            }
            .disabled(transfer.isWorking)

            Label(horizontalSizeClass == .regular ? "NO WEBVIEW" : "NATIVE", systemImage: "swift")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(CrabrixTheme.mint)
            Label(toolchain.isReady ? (horizontalSizeClass == .regular ? "OFFLINE READY" : "OFFLINE") : "MISSING", systemImage: toolchain.isReady ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(toolchain.isReady ? CrabrixTheme.mint : CrabrixTheme.amber)
        }
        .padding(.horizontal, 18)
        .frame(height: 58)
        .background(CrabrixTheme.background.opacity(0.97))
    }
}

private struct ProjectTransferStrip: View {
    let transfer: CompilerViewModel.ProjectTransfer

    var body: some View {
        HStack(spacing: 8) {
            switch transfer {
            case .idle:
                EmptyView()
            case .openingFiles:
                ProgressView().tint(CrabrixTheme.blue)
                Text("Opening project from Files…")
            case let .importingGitHub(repository):
                ProgressView().tint(CrabrixTheme.blue)
                Text("Importing \(repository) from GitHub…")
            case let .ready(message):
                Image(systemName: "checkmark.circle.fill").foregroundStyle(CrabrixTheme.mint)
                Text(message)
            case let .failed(message):
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(CrabrixTheme.amber)
                Text(message)
            }
            Spacer()
        }
        .font(.caption.monospaced())
        .foregroundStyle(CrabrixTheme.muted)
        .padding(.horizontal, 18)
        .frame(minHeight: 34)
        .background(CrabrixTheme.background)
    }
}

private struct StageStrip: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let completed: Set<CompilerViewModel.Stage>

    var body: some View {
        HStack(spacing: 8) {
            Text(horizontalSizeClass == .regular ? "DEVICE HYPOTHESIS" : "PHASE 0")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(CrabrixTheme.coral)
            if horizontalSizeClass == .regular {
                Text("bundled rustc → diagnostic → repair → local run")
                    .font(.caption)
                    .foregroundStyle(CrabrixTheme.muted)
            }
            Spacer()

            ForEach(CompilerViewModel.Stage.allCases) { stage in
                let done = completed.contains(stage)
                HStack(spacing: 5) {
                    Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    Text(stage.title)
                }
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(done ? CrabrixTheme.mint : CrabrixTheme.muted)
                .lineLimit(1)
            }
        }
        .padding(.horizontal, 18)
        .frame(minHeight: 52)
        .background(CrabrixTheme.panel)
    }
}

private struct ProjectSidebar: View {
    let projectName: String
    let files: [String]
    let selectedFile: String
    let manifest: CargoManifest?
    let report: ProjectCompatibilityReport
    let provenance: CrabrixProject.Provenance?
    let onSelect: (String) -> Void

    private var rootFiles: [String] {
        files.filter { !$0.hasPrefix("src/") && $0 != "main.rs" }
    }

    private var sourceFiles: [String] {
        files.filter { $0.hasPrefix("src/") || $0 == "main.rs" }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text("PROJECT")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(CrabrixTheme.muted)
                        .padding(.bottom, 6)
                    Label(projectName, systemImage: "chevron.down")
                        .font(.subheadline.weight(.semibold))
                    ForEach(rootFiles, id: \.self) { file in
                        ProjectFileButton(
                            file: file,
                            selectedFile: selectedFile,
                            indentation: 12,
                            onSelect: onSelect
                        )
                    }
                    Label("src", systemImage: "chevron.down")
                        .font(.caption)
                        .padding(.leading, 12)
                    ForEach(sourceFiles, id: \.self) { file in
                        ProjectFileButton(
                            file: file,
                            selectedFile: selectedFile,
                            indentation: 24,
                            onSelect: onSelect
                        )
                    }

                    if let manifest {
                        Divider().overlay(CrabrixTheme.border).padding(.vertical, 8)
                        Text("PACKAGE")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(CrabrixTheme.muted)
                        Text("\(manifest.name) \(manifest.version ?? "")")
                            .font(.caption.weight(.semibold))
                        Text("edition \(manifest.edition ?? "unspecified") · manifest parsed")
                            .font(.caption2.monospaced())
                            .foregroundStyle(CrabrixTheme.mint)
                        if !manifest.dependencies.isEmpty {
                            Text("DEPENDENCIES")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(CrabrixTheme.muted)
                                .padding(.top, 6)
                            ForEach(manifest.dependencies) { dependency in
                                Text("\(dependency.name)  \(dependency.requirement ?? dependency.source.rawValue)")
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(CrabrixTheme.amber)
                            }
                            Text("resolver pending")
                                .font(.caption2)
                                .foregroundStyle(CrabrixTheme.muted)
                        }
                    }

                    Divider().overlay(CrabrixTheme.border).padding(.vertical, 6)
                    Text("COMPATIBILITY")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(CrabrixTheme.muted)
                    Label(
                        report.status == .ready ? "Ready for local inspection" : "Review required",
                        systemImage: report.status == .ready ? "checkmark.seal.fill" : "exclamationmark.triangle.fill"
                    )
                    .font(.caption2.monospaced())
                    .foregroundStyle(report.status == .ready ? CrabrixTheme.mint : CrabrixTheme.amber)
                    Text("\(report.rustFiles) Rust files · \(report.dependencies) dependencies")
                        .font(.caption2.monospaced())
                        .foregroundStyle(CrabrixTheme.muted)
                    if let provenance, provenance.source == .github {
                        Label(
                            "\(provenance.owner ?? "")/\(provenance.repository ?? "") @ \(provenance.reference ?? "HEAD")",
                            systemImage: "arrow.triangle.branch"
                        )
                        .font(.caption2.monospaced())
                        .foregroundStyle(CrabrixTheme.blue)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                Label("Physical device gate", systemImage: "iphone.gen3")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(CrabrixTheme.amber)
                Text("Simulator proves integration, not memory, thermal behavior, or airplane-mode operation.")
                    .font(.caption2)
                    .foregroundStyle(CrabrixTheme.muted)
            }
            .padding(11)
            .crabrixPanel(cornerRadius: 9)
        }
        .padding(14)
        .background(CrabrixTheme.panel)
    }
}

private struct GitHubImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var url: String
    let transfer: CompilerViewModel.ProjectTransfer
    let onImport: (String) async -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Label("Public repository snapshot", systemImage: "arrow.down.circle.fill")
                    .font(.title2.bold())
                    .foregroundStyle(CrabrixTheme.blue)
                Text("Paste a public GitHub repository or branch URL. No GitHub login is required. Crabrix downloads a bounded ZIP snapshot, discovers Cargo.toml, and opens it locally.")
                    .foregroundStyle(CrabrixTheme.muted)
                TextField("https://github.com/owner/repository", text: $url)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.go)
                    .onSubmit(importRepository)
                if case let .failed(message) = transfer {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(CrabrixTheme.amber)
                }
                Button(action: importRepository) {
                    HStack {
                        if transfer.isWorking { ProgressView().tint(.white) }
                        Text(transfer.isWorking ? "Importing…" : "Import Repository")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(CrabrixTheme.coral)
                .disabled(url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || transfer.isWorking)
                Spacer()
            }
            .padding(22)
            .background(CrabrixTheme.background.ignoresSafeArea())
            .foregroundStyle(.white)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func importRepository() {
        guard !transfer.isWorking else { return }
        Task { await onImport(url) }
    }
}

private struct ProjectFileButton: View {
    let file: String
    let selectedFile: String
    let indentation: CGFloat
    let onSelect: (String) -> Void

    var body: some View {
        Button {
            onSelect(file)
        } label: {
            Label(
                file.split(separator: "/").last.map(String.init) ?? file,
                systemImage: "doc.text.fill"
            )
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(.white)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(file == selectedFile ? CrabrixTheme.raised : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .padding(.leading, indentation)
    }
}

private struct EditorToolbar: View {
    let activity: CompilerViewModel.Activity
    let files: [String]
    let selectedFile: String
    let canRun: Bool
    let onSelectFile: (String) -> Void
    let onLoadRunnable: () -> Void
    let onLoadDiagnostic: () -> Void
    let onLoadMultiFile: () -> Void
    let onCheck: () -> Void
    let onRun: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(files, id: \.self) { file in
                    Button {
                        onSelectFile(file)
                    } label: {
                        if file == selectedFile {
                            Label(file, systemImage: "checkmark")
                        } else {
                            Text(file)
                        }
                    }
                }
            } label: {
                Label(selectedFile, systemImage: "doc.plaintext")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white)
            }
            .disabled(activity != .idle)
            Spacer()
            Menu {
                Button(action: onLoadRunnable) {
                    Label("Runnable stdout demo", systemImage: "play.fill")
                }
                Button(action: onLoadDiagnostic) {
                    Label("Borrow error E0502", systemImage: "exclamationmark.triangle.fill")
                }
                Button(action: onLoadMultiFile) {
                    Label("Multi-file modules", systemImage: "square.stack.3d.up.fill")
                }
            } label: {
                Label("Samples", systemImage: "chevron.down")
            }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(CrabrixTheme.muted)
                .disabled(activity != .idle)
            Button(action: onCheck) {
                Label("Check", systemImage: "checkmark")
            }
            .buttonStyle(.bordered)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!canRun)
            Button(action: onRun) {
                Label("Run", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(CrabrixTheme.coral)
            .disabled(!canRun)
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .background(CrabrixTheme.panel)
    }
}

private struct ResultConsole: View {
    let result: CompilationResult?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("PROBLEMS")
                Text("\(result?.diagnostics.count ?? 0)")
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(CrabrixTheme.raised)
                    .clipShape(Capsule())
                Text("OUTPUT")
                    .padding(.leading, 10)
                Spacer()
                if let result {
                    Text(result.duration.crabrixDescription)
                }
            }
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundStyle(CrabrixTheme.muted)
            .padding(.horizontal, 14)
            .frame(height: 36)

            Divider().overlay(CrabrixTheme.border)

            ScrollView {
                if let result {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(
                            !result.succeeded && result.phase == .compile
                                ? "Build failed — the program was not executed."
                                : result.detail,
                            systemImage: result.succeeded ? "checkmark.circle.fill" : "xmark.octagon.fill"
                        )
                        .foregroundStyle(result.succeeded ? CrabrixTheme.mint : CrabrixTheme.coral)

                        if let diagnostic = result.diagnostics.first {
                            Text("\(diagnostic.code ?? "error") · \(diagnostic.message)")
                                .foregroundStyle(.white)
                        }
                        if !result.stdout.isEmpty {
                            Text(result.stdout)
                                .foregroundStyle(CrabrixTheme.mint)
                        }
                        if !result.stderr.isEmpty {
                            Text(result.stderr)
                                .foregroundStyle(CrabrixTheme.coral)
                        }
                    }
                    .font(.system(size: 11, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                } else {
                    ContentUnavailableView(
                        "Ready to run",
                        systemImage: "play.circle.fill",
                        description: Text("Press Run to compile and execute this valid starter program locally.")
                    )
                    .foregroundStyle(CrabrixTheme.muted)
                }
            }
        }
        .background(Color(red: 0.035, green: 0.049, blue: 0.064))
        .overlay(alignment: .top) { Divider().overlay(CrabrixTheme.border) }
    }
}
