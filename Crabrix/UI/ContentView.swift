import SwiftUI
import UIKit
import UniformTypeIdentifiers

private enum CrabrixDestination: Hashable {
    case projects
    case build
    case learn
    case settings
}

struct ContentView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = CompilerViewModel()
    @StateObject private var completion = RustCompletionController()
    @StateObject private var terminal = ProjectTerminalSession()
    @State private var isFileImporterPresented = false
    @State private var isFileExporterPresented = false
    @State private var isGitHubImporterPresented = false
    @State private var isNewProjectPresented = false
    @State private var projectItemCreation: ProjectItemCreation?
    @State private var githubURL = ""
    @State private var selectedDestination: CrabrixDestination = .projects
    @State private var projectSidebarWidth: CGFloat = 220
    @State private var inspectorWidth: CGFloat = 390
    @State private var isProjectSidebarCollapsed = false
    @State private var isInspectorCollapsed = false
    @State private var buildDockHeight: CGFloat = 210
    @State private var isBuildDockCollapsed = false
    @State private var selectedBuildDockTab: BuildDockTab = .output
    @State private var selectedLesson: RustLesson?
    @State private var editorCursorOffset = 0
    @AppStorage("crabrix.appearance") private var appearanceRaw = CrabrixAppearance.system.rawValue
    @AppStorage("crabrix.keepAwakeDuringBuild") private var keepAwakeDuringBuild = true
    @AppStorage("crabrix.appleIntelligenceCompletion") private var appleIntelligenceCompletion = true
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
                activity: model.activity,
                isCompilerDraining: model.isCompilerDraining,
                recentProjects: model.recentProjects,
                onNewProject: { isNewProjectPresented = true },
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
                },
                onOpenShowcase: { id in
                    model.loadShowcaseProject(id: id)
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
                        onNewProject: { isNewProjectPresented = true },
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
                            if !isProjectSidebarCollapsed {
                                ProjectSidebar(
                                    projectName: model.projectName,
                                    files: model.fileNames,
                                    selectedFile: model.selectedFile,
                                    manifest: model.cargoManifest,
                                    report: model.compatibilityReport,
                                    provenance: model.provenance,
                                    onSelect: model.selectFile,
                                    onNewFile: { projectItemCreation = .rustFile },
                                    onNewFolder: { projectItemCreation = .moduleFolder }
                                )
                                .frame(width: projectSidebarWidth)
                                .transition(.move(edge: .leading).combined(with: .opacity))
                            }

                            ResizablePanelDivider(
                                edge: .leading,
                                width: $projectSidebarWidth,
                                isCollapsed: $isProjectSidebarCollapsed,
                                minimumWidth: 170,
                                maximumWidth: 360
                            )

                            editorPane
                                .frame(minWidth: 340)

                            ResizablePanelDivider(
                                edge: .trailing,
                                width: $inspectorWidth,
                                isCollapsed: $isInspectorCollapsed,
                                minimumWidth: 320,
                                maximumWidth: 560
                            )

                            if !isInspectorCollapsed {
                                inspectorPane
                                    .frame(width: inspectorWidth)
                                    .transition(.move(edge: .trailing).combined(with: .opacity))
                            }
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

            LearningHubView(
                completedStages: model.completedStages,
                practiceCompleted: model.practiceCompleted,
                onOpenLesson: openLesson
            )
            .tabItem { Label("Learn", systemImage: "graduationcap.fill") }
            .tag(CrabrixDestination.learn)

            SettingsView(
                toolchain: model.toolchain,
                manifest: model.cargoManifest,
                onAddDependency: model.addCargoDependency
            )
            .tabItem { Label("Settings", systemImage: "gearshape.fill") }
            .tag(CrabrixDestination.settings)
        }
        .tabViewStyle(.sidebarAdaptable)
        .tint(CrabrixTheme.coral)
        .foregroundStyle(CrabrixTheme.primary)
        .preferredColorScheme(
            CrabrixAppearance(rawValue: appearanceRaw)?.colorScheme
        )
        .sheet(isPresented: $isNewProjectPresented) {
            NewProjectSheet { name, template in
                model.createProject(name: name, template: template)
                selectedDestination = .build
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $projectItemCreation) { mode in
            NewProjectItemSheet(mode: mode) { path in
                switch mode {
                case .rustFile: model.createRustFile(at: path)
                case .moduleFolder: model.createModuleFolder(at: path)
                }
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $model.isPracticePresented) {
            PracticeSheet(
                initialSource: RustSamples.practice,
                validate: model.validatePractice
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $selectedLesson) { lesson in
            LessonDetailView(lesson: lesson) {
                startLesson(lesson)
                selectedLesson = nil
            }
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
            if let lessonArgument = arguments.first(where: { $0.hasPrefix("--crabrix-auto-lesson=") }) {
                let lessonID = String(lessonArgument.dropFirst("--crabrix-auto-lesson=".count))
                let lessons = RustCourseCatalog.courses.flatMap(\.units).flatMap(\.lessons)
                if let lesson = lessons.first(where: { $0.id == lessonID }) {
                    selectedDestination = .learn
                    selectedLesson = lesson
                }
            }
            if arguments.contains("--crabrix-auto-settings") {
                selectedDestination = .settings
            }
            if let dockArgument = arguments.first(where: { $0.hasPrefix("--crabrix-auto-dock=") }) {
                let tab = String(dockArgument.dropFirst("--crabrix-auto-dock=".count))
                if let dockTab = BuildDockTab(rawValue: tab) {
                    selectedDestination = .build
                    selectedBuildDockTab = dockTab
                    isBuildDockCollapsed = false
                    buildDockHeight = 260
                }
            }
            if let showcaseArgument = arguments.first(where: { $0.hasPrefix("--crabrix-auto-showcase=") }) {
                let id = String(showcaseArgument.dropFirst("--crabrix-auto-showcase=".count))
                model.loadShowcaseProject(id: id)
                selectedDestination = .build
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
        .onChange(of: model.isBusy) { _, isBusy in
            UIApplication.shared.isIdleTimerDisabled = isBusy && keepAwakeDuringBuild
        }
        .onChange(of: model.projectName) { _, _ in
            terminal.attach(to: model.exportProject())
        }
        .onChange(of: model.activity) { oldValue, newValue in
            terminal.activityChanged(
                from: oldValue,
                to: newValue,
                project: model.exportProject()
            )
        }
        .onReceive(model.$result) { result in
            guard let result else { return }
            terminal.record(result, project: model.exportProject())
        }
        .onChange(of: keepAwakeDuringBuild) { _, keepAwake in
            UIApplication.shared.isIdleTimerDisabled = model.isBusy && keepAwake
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    private func prepareExport() {
        exportDocument = CrabrixProjectDocument(project: model.exportProject())
        isFileExporterPresented = true
    }

    private func openLesson(_ lesson: RustLesson) {
        selectedLesson = lesson
    }

    private func startLesson(_ lesson: RustLesson) {
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
                result: model.result,
                files: model.fileNames,
                selectedFile: model.selectedFile,
                canRun: model.canStartBuild && !model.isProjectOperationInProgress,
                isCompletionLoading: completion.isLoading,
                onSelectFile: model.selectFile,
                onLoadRunnable: model.loadRunnableSample,
                onLoadDiagnostic: model.loadBorrowDiagnosticSample,
                onLoadMultiFile: model.loadMultiFileSample,
                onCheck: model.check,
                onRun: model.run,
                onComplete: requestCompletion
            )

            ZStack(alignment: .topLeading) {
                SyntaxCodeEditor(
                    text: $model.source,
                    cursorOffset: $editorCursorOffset,
                    filePath: model.selectedFile,
                    isEditable: !model.isProjectOperationInProgress
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
                            Label("Background snapshot · keep editing or open another tab", systemImage: "arrow.triangle.2.circlepath")
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .foregroundStyle(CrabrixTheme.blue)
                        }
                        Button {
                            model.cancelBuild()
                        } label: {
                            Label("Stop", systemImage: "stop.fill")
                                .font(.caption.bold())
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(CrabrixTheme.coral)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }

                if let suggestion = completion.suggestion {
                    VStack {
                        Spacer()
                        CompletionSuggestionCard(
                            suggestion: suggestion,
                            onAccept: acceptCompletion,
                            onDismiss: completion.dismiss
                        )
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                } else if let message = completion.message {
                    VStack {
                        Spacer()
                        CompletionMessageCard(message: message, onDismiss: completion.dismiss)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }

            BuildDockView(
                selectedTab: $selectedBuildDockTab,
                height: $buildDockHeight,
                isCollapsed: $isBuildDockCollapsed,
                terminal: terminal,
                project: model.exportProject(),
                result: model.result,
                activity: model.activity,
                canStartBuild: model.canStartBuild && !model.isProjectOperationInProgress,
                onCheck: model.check,
                onRun: model.run
            )
            .frame(height: isBuildDockCollapsed ? 38 : buildDockHeight)
        }
        .background(CrabrixTheme.background)
    }

    private func requestCompletion() {
        guard !model.isBusy && !model.isProjectOperationInProgress else { return }
        completion.request(
            source: model.source,
            cursorOffset: editorCursorOffset,
            filePath: model.selectedFile,
            useAppleIntelligence: appleIntelligenceCompletion
        )
    }

    private func acceptCompletion() {
        guard let suggestion = completion.suggestion else { return }
        let source = model.source as NSString
        let offset = min(max(editorCursorOffset, 0), source.length)
        model.source = source.replacingCharacters(
            in: NSRange(location: offset, length: 0),
            with: suggestion.insertion
        )
        editorCursorOffset = offset + (suggestion.insertion as NSString).length
        completion.dismiss()
    }

    @ViewBuilder
    private var inspectorPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let result = model.result, result.succeeded {
                    SuccessInspector(
                        result: result,
                        practiceCompleted: model.practiceCompleted,
                        onRunNext: model.run,
                        onContinueLearning: { selectedDestination = .learn }
                    )
                } else if let diagnostic = model.primaryDiagnostic {
                    DiagnosticInspector(
                        diagnostic: diagnostic,
                        canRepair: BorrowRepair.apply(to: model.source, diagnostic: diagnostic) != nil,
                        practiceCompleted: model.practiceCompleted,
                        onRepair: model.applyRepair,
                        onPractice: model.presentPractice
                    )
                } else {
                    RuntimeInspector(
                        toolchain: model.toolchain,
                        onCheck: model.check,
                        onRun: model.run
                    )
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
                        .foregroundStyle(CrabrixTheme.primary)
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

private struct ResizablePanelDivider: View {
    enum Edge {
        case leading
        case trailing
    }

    let edge: Edge
    @Binding var width: CGFloat
    @Binding var isCollapsed: Bool
    let minimumWidth: CGFloat
    let maximumWidth: CGFloat
    @State private var dragStartWidth: CGFloat?

    private var collapseIcon: String {
        switch (edge, isCollapsed) {
        case (.leading, false): "chevron.left"
        case (.leading, true): "chevron.right"
        case (.trailing, false): "chevron.right"
        case (.trailing, true): "chevron.left"
        }
    }

    private var accessibilityTitle: String {
        if isCollapsed { return "Show panel" }
        return "Hide panel"
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(CrabrixTheme.border)
                .frame(width: 1)

            Capsule()
                .fill(CrabrixTheme.muted.opacity(isCollapsed ? 0 : 0.45))
                .frame(width: 3, height: 34)

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isCollapsed.toggle()
                }
            } label: {
                Image(systemName: collapseIcon)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(CrabrixTheme.primary)
                    .frame(width: 22, height: 22)
                    .background(CrabrixTheme.raised, in: Circle())
                    .overlay { Circle().stroke(CrabrixTheme.border) }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityTitle)
        }
        .frame(width: 28)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 2)
                .onChanged { value in
                    guard !isCollapsed else { return }
                    if dragStartWidth == nil { dragStartWidth = width }
                    let direction: CGFloat = edge == .leading ? 1 : -1
                    let candidate = (dragStartWidth ?? width) + value.translation.width * direction
                    width = min(max(candidate, minimumWidth), maximumWidth)
                }
                .onEnded { _ in dragStartWidth = nil }
        )
        .hoverEffect(.highlight)
        .accessibilityHint("Drag to resize the panel")
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
    let onNewFile: () -> Void
    let onNewFolder: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text("PROJECT")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(CrabrixTheme.muted)
                        .padding(.bottom, 6)
                    HStack(spacing: 8) {
                        Image(systemName: "shippingbox.fill")
                            .foregroundStyle(CrabrixTheme.coral)
                        Text(projectName)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Menu {
                            Button(action: onNewFile) {
                                Label("New Rust File", systemImage: "doc.badge.plus")
                            }
                            Button(action: onNewFolder) {
                                Label("New Module Folder", systemImage: "folder.badge.plus")
                            }
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(CrabrixTheme.mint)
                        }
                    }
                    .padding(.bottom, 4)

                    ProjectFileTree(
                        paths: files,
                        selectedPath: selectedFile,
                        onSelect: onSelect
                    )

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
            .foregroundStyle(CrabrixTheme.primary)
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

private struct EditorToolbar: View {
    let activity: CompilerViewModel.Activity
    let result: CompilationResult?
    let files: [String]
    let selectedFile: String
    let canRun: Bool
    let isCompletionLoading: Bool
    let onSelectFile: (String) -> Void
    let onLoadRunnable: () -> Void
    let onLoadDiagnostic: () -> Void
    let onLoadMultiFile: () -> Void
    let onCheck: () -> Void
    let onRun: () -> Void
    let onComplete: () -> Void

    private var checkPassed: Bool {
        result?.succeeded == true && result?.phase == .check
    }

    private var runPassed: Bool {
        result?.succeeded == true && result?.phase == .run
    }

    private var checkNeedsAttention: Bool {
        guard let result else { return false }
        return !result.succeeded || !result.diagnostics.isEmpty
    }

    private var connectorLabel: String {
        if activity == .checking { return "Checking…" }
        if activity == .running { return "Running…" }
        if runPassed { return "Done" }
        if checkPassed { return "Run next" }
        if checkNeedsAttention { return "Fix, then retry" }
        return "then"
    }

    var body: some View {
        VStack(spacing: 0) {
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
                        .foregroundStyle(CrabrixTheme.primary)
                }
                .disabled(activity != .idle)
                Spacer()
                Button(action: onComplete) {
                    if isCompletionLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Complete", systemImage: "sparkles")
                    }
                }
                .buttonStyle(.plain)
                .font(.caption.bold())
                .foregroundStyle(CrabrixTheme.blue)
                .disabled(activity != .idle || isCompletionLoading)
                .accessibilityHint("Suggest Rust code at the cursor")
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
            }

            Divider().overlay(CrabrixTheme.border)

            ViewThatFits(in: .horizontal) {
                fullWorkflow
                    .frame(minWidth: 520)
                compactWorkflow
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
        }
        .background(CrabrixTheme.panel)
    }

    private var fullWorkflow: some View {
        HStack(spacing: 10) {
            WorkflowActionButton(
                step: 1,
                title: checkPassed ? "Checked" : "Check code",
                subtitle: checkNeedsAttention ? "Fix errors and retry" : "Find errors, don't run",
                systemImage: checkPassed ? "checkmark.circle.fill" : "checkmark.shield.fill",
                tint: checkPassed ? CrabrixTheme.mint : (checkNeedsAttention ? CrabrixTheme.coral : CrabrixTheme.blue),
                isWorking: activity == .checking,
                isEmphasized: !checkPassed && !runPassed,
                action: onCheck
            )
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!canRun)

            workflowConnector

            WorkflowActionButton(
                step: 2,
                title: runPassed ? "Ran successfully" : "Run project",
                subtitle: runPassed ? "Output is ready" : "Compile and show output",
                systemImage: runPassed ? "checkmark.circle.fill" : "play.fill",
                tint: runPassed ? CrabrixTheme.mint : CrabrixTheme.coral,
                isWorking: activity == .running,
                isEmphasized: checkPassed || !runPassed,
                action: onRun
            )
            .keyboardShortcut("r", modifiers: .command)
            .disabled(!canRun)
        }
    }

    private var compactWorkflow: some View {
        HStack(spacing: 8) {
            CompactWorkflowButton(
                step: 1,
                title: checkPassed ? "Checked" : "Check",
                systemImage: checkPassed ? "checkmark.circle.fill" : "checkmark.shield.fill",
                tint: checkPassed ? CrabrixTheme.mint : CrabrixTheme.blue,
                isWorking: activity == .checking,
                action: onCheck
            )
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!canRun)

            Image(systemName: runPassed ? "checkmark" : "arrow.right")
                .font(.caption.bold())
                .foregroundStyle(runPassed || checkPassed ? CrabrixTheme.mint : CrabrixTheme.muted)

            CompactWorkflowButton(
                step: 2,
                title: runPassed ? "Done" : "Run",
                systemImage: runPassed ? "checkmark.circle.fill" : "play.fill",
                tint: runPassed ? CrabrixTheme.mint : CrabrixTheme.coral,
                isWorking: activity == .running,
                action: onRun
            )
            .keyboardShortcut("r", modifiers: .command)
            .disabled(!canRun)
        }
    }

    private var workflowConnector: some View {
        VStack(spacing: 3) {
            Image(systemName: runPassed ? "checkmark" : "arrow.right")
                .font(.caption.bold())
            Text(connectorLabel)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .lineLimit(1)
        }
        .foregroundStyle(runPassed || checkPassed ? CrabrixTheme.mint : CrabrixTheme.muted)
        .frame(width: 54)
    }
}

private struct CompactWorkflowButton: View {
    let step: Int
    let title: String
    let systemImage: String
    let tint: Color
    let isWorking: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text("\(step)")
                    .font(.caption.monospaced().bold())
                    .frame(width: 22, height: 22)
                    .background(tint.opacity(0.16), in: Circle())
                if isWorking {
                    ProgressView().controlSize(.small).tint(tint)
                } else {
                    Image(systemName: systemImage)
                }
                Text(title)
                    .lineLimit(1)
            }
            .font(.caption.bold())
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .padding(.horizontal, 8)
            .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 11))
            .overlay { RoundedRectangle(cornerRadius: 11).stroke(tint.opacity(0.45)) }
        }
        .buttonStyle(.plain)
    }
}

private struct CompletionSuggestionCard: View {
    let suggestion: RustCodeCompletion
    let onAccept: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: suggestion.provider == .appleIntelligence
                      ? "apple.intelligence" : "bolt.fill")
                    .foregroundStyle(
                        suggestion.provider == .appleIntelligence
                            ? CrabrixTheme.blue : CrabrixTheme.amber
                    )
                VStack(alignment: .leading, spacing: 1) {
                    Text(suggestion.provider.rawValue)
                        .font(.caption.bold())
                    Text(suggestion.detail)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(CrabrixTheme.muted)
                }
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                Text(suggestion.insertion)
                    .font(.caption.monospaced())
                    .foregroundStyle(CrabrixTheme.primary)
                    .textSelection(.enabled)
            }
            .padding(10)
            .background(CrabrixTheme.editor, in: RoundedRectangle(cornerRadius: 9))

            Button(action: onAccept) {
                Label("Insert at cursor", systemImage: "return")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(CrabrixTheme.mint)
            .keyboardShortcut(.tab, modifiers: [])
        }
        .padding(12)
        .frame(maxWidth: 430)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(CrabrixTheme.border)
        }
        .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
    }
}

private struct CompletionMessageCard: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .foregroundStyle(CrabrixTheme.blue)
            Text(message)
                .font(.caption)
                .foregroundStyle(CrabrixTheme.muted)
            Button("Dismiss", action: onDismiss)
                .font(.caption.bold())
        }
        .padding(12)
        .frame(maxWidth: 430)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).stroke(CrabrixTheme.border) }
    }
}

private struct WorkflowActionButton: View {
    let step: Int
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    let isWorking: Bool
    let isEmphasized: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                ZStack {
                    Circle()
                        .fill(tint.opacity(isEmphasized ? 0.24 : 0.14))
                    if isWorking {
                        ProgressView().tint(tint).controlSize(.small)
                    } else {
                        Text("\(step)")
                            .font(.caption.monospaced().bold())
                            .foregroundStyle(tint)
                    }
                }
                .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.bold())
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(CrabrixTheme.muted)
                        .lineLimit(1)
                }

                Spacer(minLength: 2)

                Image(systemName: systemImage)
                    .font(.subheadline.bold())
                    .foregroundStyle(tint)
            }
            .padding(.horizontal, 11)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(tint.opacity(isEmphasized ? 0.13 : 0.06))
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(tint.opacity(isEmphasized ? 0.52 : 0.18), lineWidth: isEmphasized ? 1.5 : 1)
            }
        }
        .buttonStyle(.plain)
        .opacity(isWorking ? 0.85 : 1)
    }
}
