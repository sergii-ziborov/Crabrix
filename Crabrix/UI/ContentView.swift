import SwiftUI
import UIKit
import UniformTypeIdentifiers

private enum CrabrixDestination: Hashable {
    case projects
    case build
    case learn
    case settings

    /// Lets a launch argument open a tab directly, which is how the README and
    /// store screenshots are captured reproducibly.
    static var launchArgument: CrabrixDestination? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-CrabrixTab"),
              index + 1 < arguments.count
        else {
            return nil
        }
        switch arguments[index + 1] {
        case "projects": return .projects
        case "build": return .build
        case "learn": return .learn
        case "settings": return .settings
        default: return nil
        }
    }
}

private struct ArchiveShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

private struct ProjectArchiveShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(
            activityItems: [url],
            applicationActivities: nil
        )
    }

    func updateUIViewController(
        _ uiViewController: UIActivityViewController,
        context: Context
    ) {}
}

struct ContentView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = CompilerViewModel()
    @StateObject private var completion = RustCompletionController()
    @StateObject private var terminal = ProjectTerminalSession()
    @EnvironmentObject private var progress: CrabrixProgressStore
    @EnvironmentObject private var vitals: CrabrixVitalsStore
    /// Lessons already turned into rating, seeded from persisted progress so a
    /// relaunch never re-awards them.
    @State private var scoredLessonIDs: Set<String>?
    @State private var scoredPractice = false
    @State private var isFileImporterPresented = false
    @State private var isFileExporterPresented = false
    @State private var archiveShareItem: ArchiveShareItem?
    @State private var isGitHubImporterPresented = false
    @State private var isNewProjectPresented = false
    @State private var isProjectActionsPresented = false
    @State private var isCargoCatalogPresented = false
    @State private var projectsPath: [ProjectsRoute] =
        ProcessInfo.processInfo.arguments.contains("-CrabrixLibrary") ? [.library] : []
    @State private var projectItemCreation: ProjectItemCreation?
    @State private var githubURL = ""
    @State private var selectedDestination: CrabrixDestination =
        CrabrixDestination.launchArgument ?? .projects
    @State private var projectSidebarWidth: CGFloat = 220
    @State private var inspectorWidth: CGFloat = 390
    @State private var isProjectSidebarCollapsed = false
    @State private var isInspectorCollapsed = false
    @State private var isCompactProjectDrawerPresented = false
    @State private var isCompactInspectorDrawerPresented = false
    @State private var selectedBuildDockTab: BuildDockTab = .code
    @State private var learningPath: [LearningRoute] = LearningRoute.launchArgument
    @State private var editorCursorOffset = 0
    /// Dismissing the running toast hides it for that run only; the next run
    /// shows it again, so a tap is never a setting the reader has to undo.
    @State private var isRunningToastDismissed = false
    /// What the last successful run was scored on, shown in the build dock.
    @State private var lastContribution: CodeContribution?
    @State private var editorNavigationTarget: EditorNavigationTarget?
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
            NavigationStack(path: $projectsPath) {
                ProjectsHomeView(
                projectID: model.projectID,
                projectName: model.projectName,
                fileCount: model.fileNames.count,
                lastBuild: model.lastBuild,
                activity: model.activity,
                isCompilerDraining: model.isCompilerDraining,
                recentProjects: model.recentProjects,
                allProjects: model.allProjects,
                onOpenCurrentProject: { selectedDestination = .build },
                onNewProject: { isNewProjectPresented = true },
                onOpenGitHub: { isGitHubImporterPresented = true },
                onOpenFiles: { isFileImporterPresented = true },
                onOpenRecent: { id in
                    Task {
                        if await model.openRecentProject(id: id) {
                            selectedDestination = .build
                        }
                    }
                },
                onOpenShowcase: { id in
                    model.loadShowcaseProject(id: id)
                    selectedDestination = .build
                },
                onOpenLibrary: { projectsPath = [.library] },
                onOpenMyProjects: { projectsPath = [.myProjects] },
                onOpenProgress: { selectedDestination = .learn }
                )
                .navigationDestination(for: ProjectsRoute.self) { route in
                    switch route {
                    case .myProjects:
                        MyProjectsView(
                            items: model.allProjects,
                            onOpen: { id in
                                Task {
                                    if await model.openRecentProject(id: id) {
                                        projectsPath = []
                                        selectedDestination = .build
                                    }
                                }
                            },
                            onToggleFavorite: { id in
                                Task { await model.toggleFavorite(projectID: id) }
                            },
                            onDelete: { id in
                                Task { _ = await model.deleteProject(projectID: id) }
                            },
                            onUpdate: { id, draft in
                                await model.updateProjectDetails(
                                    projectID: id,
                                    name: draft.name,
                                    description: draft.projectDescription,
                                    tags: draft.tags,
                                    folder: draft.optionalFolder,
                                    kind: draft.kind,
                                    isFavorite: draft.isFavorite
                                )
                            }
                        )
                    case .library:
                        ProjectLibraryView { id in
                            model.loadShowcaseProject(id: id)
                            projectsPath = []
                            selectedDestination = .build
                        }
                    }
                }
            }
            .tabItem { Label("Projects", systemImage: "folder.fill") }
            .tag(CrabrixDestination.projects)

            ZStack {
                CrabrixTheme.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    AppHeader(
                        toolchain: model.toolchain,
                        transfer: model.projectTransfer,
                        activity: model.activity,
                        canRun: model.canStartBuild && !model.isProjectOperationInProgress,
                        onRun: model.run,
                        onCancelBuild: model.cancelBuild,
                        onOpenProjects: { selectedDestination = .projects },
                        onCloseWorkspace: closeBuildWorkspace,
                        onNewProject: { isNewProjectPresented = true },
                        onOpenFiles: { isFileImporterPresented = true },
                        onOpenGitHub: { isGitHubImporterPresented = true },
                        onProjectActions: {
                            isProjectActionsPresented = true
                        }
                    )
                    if model.projectTransfer.isWorking || model.projectTransfer.isFailure {
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
                                    cargoStage: model.cargoStage,
                                    cargoWorkspace: model.cargoWorkspace,
                                    isBusy: model.isBusy,
                                    onProjectActions: {
                                        isProjectActionsPresented = true
                                    },
                                    onSelect: selectEditorFile,
                                    onNewFile: { projectItemCreation = .rustFile },
                                    onNewFolder: { projectItemCreation = .moduleFolder },
                                    onResolvePackages: model.refreshCargoWorkspace,
                                    onAddPackage: { isCargoCatalogPresented = true }
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
                        compactBuildWorkspace
                    }
                }
            }
            .tabItem { Label("Build", systemImage: "hammer.fill") }
            .tag(CrabrixDestination.build)

            LearningHubView(
                navigationPath: $learningPath,
                completedLessonIDs: model.completedLessonIDs,
                lessonAnswerIndices: model.lessonAnswerIndices,
                onStartLesson: startLesson,
                onCompleteLesson: { lesson in model.completeLesson(lesson.id) },
                onAnswerLesson: { lesson, answer, correct in
                    if correct { model.recordLessonAnswer(answer, for: lesson.id) }
                }
            )
            .tabItem { Label("Learn", systemImage: "graduationcap.fill") }
            .tag(CrabrixDestination.learn)

            SettingsView(
                toolchain: model.toolchain,
                manifest: model.cargoManifest,
                workspace: model.cargoWorkspace,
                storage: model.cargoStorage,
                onAddDependency: model.addCargoDependency,
                onRefreshStorage: model.refreshCargoStorage,
                onClearBuildArtifacts: model.clearCargoBuildArtifacts,
                onClearDownloadedArchives: model.clearCargoDownloadedArchives,
                onClearPackageCache: model.clearCargoPackageCache
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
        .sheet(isPresented: $isCargoCatalogPresented) {
            CargoDependencyCatalogSheet(onAdd: model.addCargoDependency)
        }
        .sheet(isPresented: $isNewProjectPresented) {
            NewProjectSheet { request in
                model.createProject(request)
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
        .sheet(isPresented: $isProjectActionsPresented) {
            ProjectActionsSheet(
                project: model.exportProject(),
                onUpdate: { draft in
                    model.updateCurrentProjectDetails(
                        name: draft.name,
                        description: draft.projectDescription,
                        tags: draft.tags,
                        folder: draft.optionalFolder,
                        kind: draft.kind,
                        isFavorite: draft.isFavorite
                    )
                },
                onSaveToFiles: prepareExport,
                onShareArchive: prepareArchiveShare
            )
            .presentationDetents([.large])
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
        .sheet(item: $archiveShareItem) { item in
            ProjectArchiveShareSheet(url: item.url)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .onDisappear {
                    CrabrixProjectArchive.removeTemporaryArchive(at: item.url)
                }
        }
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: [.folder, .crabrixProject, .zip],
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
            if arguments.contains("--crabrix-auto-borrow") {
                model.loadBorrowDiagnosticSample()
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
                if let lesson = RustCourseCatalog.lesson(id: lessonID),
                   let course = RustCourseCatalog.course(containingLessonID: lesson.id) {
                    selectedDestination = .learn
                    learningPath = [.course(course.id), .lesson(lesson.id)]
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
        .onChange(of: model.projectID) { _, _ in
            terminal.attach(to: model.exportProject())
        }
        .onChange(of: model.activity) { oldValue, newValue in
            terminal.activityChanged(
                from: oldValue,
                to: newValue,
                project: model.exportProject()
            )
            if newValue == .running { isRunningToastDismissed = false }
        }
        .onReceive(model.$result) { result in
            guard let result else { return }
            completion.dismiss()
            terminal.record(result, project: model.exportProject())
            recordBuildProgress(result)
            withAnimation(.easeOut(duration: 0.18)) {
                if !result.succeeded {
                    selectedBuildDockTab = .problems
                } else if result.phase == .run {
                    selectedBuildDockTab = .output
                }
            }
        }
        .onReceive(model.$completedLessonIDs) { ids in
            guard let scored = scoredLessonIDs else {
                scoredLessonIDs = ids
                for lessonID in ids {
                    if let pattern = AlgorithmCourseCatalog.pattern(forChallengeLessonID: lessonID) {
                        progress.recordAlgorithmSolved(patternID: pattern.id)
                    }
                }
                return
            }
            let fresh = ids.subtracting(scored)
            guard !fresh.isEmpty else { return }
            scoredLessonIDs = ids
            for lessonID in fresh {
                progress.record(
                    .lessonCompleted,
                    eventKey: "lesson:\(lessonID):first-completion"
                )
                if let pattern = AlgorithmCourseCatalog.pattern(forChallengeLessonID: lessonID) {
                    progress.recordAlgorithmSolved(patternID: pattern.id)
                }
            }
        }
        .onReceive(model.$practiceCompleted) { passed in
            guard passed, !scoredPractice else { return }
            scoredPractice = true
            progress.record(.practicePassed)
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

    private func prepareArchiveShare() {
        cleanupSharedArchive()
        do {
            archiveShareItem = ArchiveShareItem(
                url: try CrabrixProjectArchive.create(project: model.exportProject())
            )
        } catch {
            model.reportProjectFailure(error)
        }
    }

    private func cleanupSharedArchive() {
        guard let url = archiveShareItem?.url else { return }
        CrabrixProjectArchive.removeTemporaryArchive(at: url)
        archiveShareItem = nil
    }

    private func closeBuildWorkspace() {
        if let lessonID = model.activeLessonID,
           let course = RustCourseCatalog.course(containingLessonID: lessonID) {
            selectedDestination = .learn
            learningPath = [.course(course.id), .lesson(lessonID)]
        } else {
            selectedDestination = .projects
        }
    }

    private func startLesson(_ lesson: RustLesson) {
        let isReview = model.completedLessonIDs.contains(lesson.id)
        let reviewProjectName = "review-\(lesson.id)"
        switch lesson.exercise {
        case .runnable:
            model.loadHelloLessonSample(
                projectName: isReview ? reviewProjectName : "hello-crabrix"
            )
        case .borrowDiagnostic:
            model.loadBorrowDiagnosticSample(
                projectName: isReview ? reviewProjectName : "borrow-lab"
            )
        case .multiFile:
            model.loadMultiFileSample(
                projectName: isReview ? reviewProjectName : "modules-lab"
            )
        case .algorithmChallenge:
            guard let challenge = AlgorithmCourseCatalog.challenge(for: lesson.id) else {
                return
            }
            model.loadAlgorithmLessonSample(
                projectName: isReview ? reviewProjectName : challenge.projectName,
                source: challenge.source
            )
        case .planned:
            return
        }
        model.beginLesson(lesson.id, isReview: isReview)
        selectedDestination = .build
    }

    private var editorPane: some View {
        VStack(spacing: 0) {
            EditorToolbar(
                activity: model.activity,
                cargoStage: model.cargoStage,
                result: model.result,
                files: model.fileNames,
                selectedFile: model.selectedFile,
                isProjectSidebarCollapsed: horizontalSizeClass == .regular
                    ? isProjectSidebarCollapsed
                    : !isCompactProjectDrawerPresented,
                isInspectorCollapsed: horizontalSizeClass == .regular
                    ? isInspectorCollapsed
                    : !isCompactInspectorDrawerPresented,
                onSelectFile: selectEditorFile,
                onToggleProjectSidebar: {
                    if horizontalSizeClass == .regular {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isProjectSidebarCollapsed.toggle()
                        }
                    } else {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            isCompactProjectDrawerPresented.toggle()
                            isCompactInspectorDrawerPresented = false
                        }
                    }
                },
                onToggleInspector: {
                    let inspectorIsCollapsed = horizontalSizeClass == .regular
                        ? isInspectorCollapsed
                        : !isCompactInspectorDrawerPresented
                    if inspectorIsCollapsed, model.primaryDiagnostic != nil {
                        presentDiagnosticAdvisor()
                        return
                    }
                    if horizontalSizeClass == .regular {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isInspectorCollapsed.toggle()
                        }
                    } else {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            isCompactInspectorDrawerPresented.toggle()
                            isCompactProjectDrawerPresented = false
                        }
                    }
                }
            )

            BuildDockView(
                selectedTab: $selectedBuildDockTab,
                terminal: terminal,
                project: model.exportProject(),
                result: model.result,
                activity: model.activity,
                canStartBuild: model.canStartBuild && !model.isProjectOperationInProgress,
                onCheck: model.check,
                onRun: model.run,
                onReplaceFiles: model.replaceProjectFilesFromTerminal,
                workspace: model.cargoWorkspace,
                onFetch: model.downloadDependenciesForOffline,
                onCancel: model.cancelBuild,
                canContinueLearning: model.canContinueFromLessonResult,
                lessonEvidenceMessage: model.lessonEvidenceMessage,
                contribution: lastContribution,
                onOpenDiagnostic: openDiagnostic,
                diagnosticAdviceState: model.diagnosticAdviceState,
                onOpenDiagnosticAdvisor: presentDiagnosticAdvisor,
                onContinueLearning: continueLearning
            ) {
                codeWorkspace
            }
        }
        .background(CrabrixTheme.background)
    }

    private var codeWorkspace: some View {
        ZStack(alignment: .topLeading) {
            SyntaxCodeEditor(
                text: $model.source,
                cursorOffset: $editorCursorOffset,
                projectID: model.projectID,
                filePath: model.selectedFile,
                isEditable: !model.isProjectOperationInProgress,
                tracksTyping: !model.activeLessonIsReview,
                diagnostics: model.result?.diagnostics ?? [],
                navigationTarget: editorNavigationTarget,
                onRequestCompletion: requestEditorAssistant
            )

            if model.activity == .running, !isRunningToastDismissed {
                HStack(spacing: 9) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(CrabrixTheme.coral)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Running locally…")
                            .font(.caption.monospaced().bold())
                        Text("Tap to hide · the run keeps going")
                            .font(.caption2)
                            .foregroundStyle(CrabrixTheme.muted)
                    }
                    Image(systemName: "xmark")
                        .font(.caption2.bold())
                        .foregroundStyle(CrabrixTheme.muted)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(CrabrixTheme.border)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .transition(.move(edge: .top).combined(with: .opacity))
                // Hiding the toast only hides the toast; the build is untouched.
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeOut(duration: 0.18)) {
                        isRunningToastDismissed = true
                    }
                }
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Hides this notice. The run continues.")
            }

            if let diagnostic = model.primaryDiagnostic,
               completion.suggestion == nil,
               completion.message == nil {
                VStack {
                    Spacer()
                    DiagnosticAdvisorQuickButton(
                        diagnostic: diagnostic,
                        state: model.diagnosticAdviceState,
                        action: presentDiagnosticAdvisor
                    )
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .trailing)
            } else if let suggestion = completion.suggestion {
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
    }

    private func selectEditorFile(_ file: String) {
        model.selectFile(file)
        editorNavigationTarget = nil
        selectedBuildDockTab = .code
        if horizontalSizeClass != .regular {
            withAnimation(.easeOut(duration: 0.18)) {
                isCompactProjectDrawerPresented = false
            }
        }
    }

    private var compactBuildWorkspace: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                editorPane
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if !isCompactProjectDrawerPresented && !isCompactInspectorDrawerPresented {
                    HStack(spacing: 0) {
                        CompactEdgeSwipeZone(edge: .leading) {
                            withAnimation(.easeOut(duration: 0.22)) {
                                isCompactProjectDrawerPresented = true
                            }
                        }
                        Spacer(minLength: 0)
                        CompactEdgeSwipeZone(edge: .trailing) {
                            withAnimation(.easeOut(duration: 0.22)) {
                                isCompactInspectorDrawerPresented = true
                            }
                        }
                    }
                    .padding(.top, 52)
                    .zIndex(0.5)
                }

                if isCompactProjectDrawerPresented || isCompactInspectorDrawerPresented {
                    Color.black.opacity(0.46)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.easeOut(duration: 0.2)) {
                                isCompactProjectDrawerPresented = false
                                isCompactInspectorDrawerPresented = false
                            }
                        }
                        .transition(.opacity)
                        .zIndex(1)
                }

                if isCompactProjectDrawerPresented {
                    VStack(spacing: 0) {
                        CompactDrawerHeader(title: "Project files", systemImage: "sidebar.left") {
                            withAnimation(.easeOut(duration: 0.2)) {
                                isCompactProjectDrawerPresented = false
                            }
                        }
                        Divider().overlay(CrabrixTheme.border)
                        ProjectSidebar(
                            projectName: model.projectName,
                            files: model.fileNames,
                            selectedFile: model.selectedFile,
                            manifest: model.cargoManifest,
                            report: model.compatibilityReport,
                            provenance: model.provenance,
                            cargoStage: model.cargoStage,
                            cargoWorkspace: model.cargoWorkspace,
                            isBusy: model.isBusy,
                            onProjectActions: {
                                isProjectActionsPresented = true
                            },
                            onSelect: selectEditorFile,
                            onNewFile: { projectItemCreation = .rustFile },
                            onNewFolder: { projectItemCreation = .moduleFolder },
                            onResolvePackages: model.refreshCargoWorkspace,
                            onAddPackage: { isCargoCatalogPresented = true }
                        )
                    }
                    .frame(width: min(geometry.size.width * 0.86, 340))
                    .frame(maxHeight: .infinity)
                    .background(CrabrixTheme.panel)
                    .overlay(alignment: .trailing) {
                        Rectangle().fill(CrabrixTheme.border).frame(width: 1)
                    }
                    .transition(.move(edge: .leading).combined(with: .opacity))
                    .zIndex(2)
                }

                if isCompactInspectorDrawerPresented {
                    VStack(spacing: 0) {
                        CompactDrawerHeader(title: "Build inspector", systemImage: "sidebar.right") {
                            withAnimation(.easeOut(duration: 0.2)) {
                                isCompactInspectorDrawerPresented = false
                            }
                        }
                        Divider().overlay(CrabrixTheme.border)
                        inspectorPane
                    }
                    .frame(width: min(geometry.size.width * 0.88, 360))
                    .frame(maxHeight: .infinity)
                    .background(CrabrixTheme.panel)
                    .overlay(alignment: .leading) {
                        Rectangle().fill(CrabrixTheme.border).frame(width: 1)
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    .zIndex(2)
                }
            }
            .clipped()
            .contentShape(Rectangle())
            .simultaneousGesture(compactDrawerGesture(width: geometry.size.width))
        }
    }

    private func compactDrawerGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 16)
            .onEnded { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height
                guard abs(horizontal) > abs(vertical), abs(horizontal) > 55 else { return }

                if isCompactProjectDrawerPresented, horizontal < 0 {
                    withAnimation(.easeOut(duration: 0.2)) {
                        isCompactProjectDrawerPresented = false
                    }
                } else if isCompactInspectorDrawerPresented, horizontal > 0 {
                    withAnimation(.easeOut(duration: 0.2)) {
                        isCompactInspectorDrawerPresented = false
                    }
                } else if !isCompactProjectDrawerPresented,
                          !isCompactInspectorDrawerPresented,
                          value.startLocation.x <= 30,
                          horizontal > 0 {
                    withAnimation(.easeOut(duration: 0.22)) {
                        isCompactProjectDrawerPresented = true
                    }
                } else if !isCompactProjectDrawerPresented,
                          !isCompactInspectorDrawerPresented,
                          value.startLocation.x >= width - 30,
                          horizontal < 0 {
                    withAnimation(.easeOut(duration: 0.22)) {
                        isCompactInspectorDrawerPresented = true
                    }
                }
            }
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

    /// The keyboard sparkle is one contextual assistant action. With a current
    /// compiler error it opens diagnostic help; otherwise it completes code.
    private func requestEditorAssistant() {
        if model.primaryDiagnostic != nil {
            presentDiagnosticAdvisor()
        } else {
            requestCompletion()
        }
    }

    private func presentDiagnosticAdvisor() {
        guard model.primaryDiagnostic != nil else { return }
        completion.dismiss()
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )

        if case .idle = model.diagnosticAdviceState {
            model.requestAppleIntelligenceAdvice()
        }

        withAnimation(.easeOut(duration: 0.22)) {
            if horizontalSizeClass == .regular {
                isInspectorCollapsed = false
            } else {
                isCompactProjectDrawerPresented = false
                isCompactInspectorDrawerPresented = true
            }
        }
    }

    private func openDiagnostic(_ diagnostic: RustDiagnostic) {
        guard let span = diagnostic.primarySpan else { return }
        let diagnosticPath = span.fileName
        let targetFile = model.fileNames.first(where: { $0 == diagnosticPath })
            ?? model.fileNames.first(where: {
                diagnosticPath.hasSuffix("/\($0)") || $0.hasSuffix("/\(diagnosticPath)")
            })
            ?? model.selectedFile

        if targetFile != model.selectedFile {
            model.selectFile(targetFile)
        }
        editorNavigationTarget = EditorNavigationTarget(
            filePath: targetFile,
            line: span.lineStart,
            column: span.columnStart
        )
        withAnimation(.easeOut(duration: 0.18)) {
            selectedBuildDockTab = .code
        }
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
                // One place in the workspace starts, reports, and stops a build,
                // and it stays put as the panel below it changes.
                BuildWorkflowControls(
                    activity: model.activity,
                    cargoStage: model.cargoStage,
                    result: model.result,
                    canRun: model.canStartBuild && !model.isProjectOperationInProgress,
                    onCheck: model.check,
                    onRun: model.run,
                    onCancel: model.cancelBuild
                )

                if let result = model.result, result.succeeded {
                    SuccessInspector(
                        result: result,
                        practiceCompleted: model.practiceCompleted,
                        canContinueLearning: model.canContinueFromLessonResult,
                        lessonEvidenceMessage: model.lessonEvidenceMessage,
                        contribution: lastContribution,
                        onRunNext: model.run,
                        onContinueLearning: continueLearning
                    )
                } else if let diagnostic = model.primaryDiagnostic {
                    DiagnosticInspector(
                        diagnostic: diagnostic,
                        canRepair: BorrowRepair.apply(to: model.source, diagnostic: diagnostic) != nil,
                        practiceCompleted: model.practiceCompleted,
                        adviceState: model.diagnosticAdviceState,
                        onRepair: model.applyRepair,
                        onRequestAdvice: model.requestAppleIntelligenceAdvice,
                        onCancelAdvice: model.cancelAppleIntelligenceAdvice,
                        onApplyAdvice: model.applyAppleIntelligenceAdvice,
                        onPractice: model.presentPractice
                    )
                } else {
                    RuntimeInspector(
                        toolchain: model.toolchain,
                        activity: model.activity
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

    /// Turns a finished build into rating, once per result.
    private func recordBuildProgress(_ result: CompilationResult) {
        guard result.succeeded, result.phase == .run else { return }
        // A completed lesson is review-only. The editor does not add its typing
        // to the ledger, and the run neither changes vitals nor earns rating.
        if !model.earnsProgressForCurrentRun {
            lastContribution = nil
            _ = vitals.spendOnBuild(isReview: true)
            return
        }
        // Rating follows the diff, so re-running an untouched sample earns a
        // token amount and real editing earns real points.
        var contribution = CodeContributionLedger.shared.record(
            projectID: model.projectID,
            files: model.exportProject().files
        )
        contribution.typedShare = TypingLedger.shared.typedShare(projectID: model.projectID)
        contribution.isFirstRunToday = progress.isFirstRunToday()
        let buildRecorded = progress.record(
            .buildSucceeded(contribution),
            eventKey: "build:\(model.projectID.uuidString):\(model.workspaceRevision.sourceTreeHash)"
        )
        lastContribution = buildRecorded ? contribution : nil

        // A run costs a little energy, so a loop of builds is not free.
        // It never blocks the build itself: this is a developer tool, and
        // being unable to run your own code would be the wrong trade.
        vitals.spendOnBuild()

        // Typing is where most of the rating comes from now.
        let typed = TypingLedger.shared.drainPendingTyped(projectID: model.projectID)
        if typed > 0 { progress.record(.codeTyped(characters: typed)) }
        if let repairEventKey = model.repairRewardEventKey {
            progress.record(.diagnosticRepaired, eventKey: repairEventKey)
        }
        let verifiedPackages = Set(
            model.cargoWorkspace.packages.compactMap { status in
                status.compatibility == .verified ? status.package : nil
            }
        )
        for unit in model.cargoWorkspace.plan.units where verifiedPackages.contains(unit.package) {
            progress.record(
                .packagesCompiled(1),
                eventKey: "crate:\(CargoToolchain.bundledVersion):\(unit.fingerprint):first-build"
            )
        }
    }

    private func continueLearning() {
        selectedDestination = .learn
        if let lessonID = model.activeLessonID,
           AlgorithmCourseCatalog.pattern(forLessonID: lessonID) != nil {
            if let next = AlgorithmCourseCatalog.nextLessonInSameMethod(after: lessonID) {
                learningPath = [.course("algorithms"), .lesson(next.id)]
            } else {
                learningPath = [.course("algorithms")]
            }
            return
        }
        // Land on the next lesson itself, not on the course list: after finishing
        // something, "what is next" is a specific screen.
        guard let step = RustLessonProgression.nextStep(
            after: model.activeLessonID,
            completedLessonIDs: model.completedLessonIDs
        ) else {
            learningPath = []
            return
        }
        learningPath = [.course(step.courseID), .lesson(step.lessonID)]
    }
}

private struct CompactEdgeSwipeZone: View {
    enum Edge {
        case leading
        case trailing
    }

    let edge: Edge
    let onOpen: () -> Void

    var body: some View {
        Color.clear
            .frame(width: 28)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 12)
                    .onEnded { value in
                        let horizontal = value.translation.width
                        let vertical = value.translation.height
                        guard abs(horizontal) > abs(vertical), abs(horizontal) > 48 else { return }
                        if edge == .leading, horizontal > 0 { onOpen() }
                        if edge == .trailing, horizontal < 0 { onOpen() }
                    }
            )
            .accessibilityHidden(true)
    }
}

private struct AppHeader: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let toolchain: ToolchainStatus
    let transfer: CompilerViewModel.ProjectTransfer
    let activity: CompilerViewModel.Activity
    let canRun: Bool
    let onRun: () -> Void
    let onCancelBuild: () -> Void
    let onOpenProjects: () -> Void
    let onCloseWorkspace: () -> Void
    let onNewProject: () -> Void
    let onOpenFiles: () -> Void
    let onOpenGitHub: () -> Void
    let onProjectActions: () -> Void

    private var isPhone: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }

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
            Spacer()

            if horizontalSizeClass == .regular, !isPhone {
                Button(action: onOpenProjects) {
                    Label("Projects", systemImage: "square.grid.2x2.fill")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .frame(minWidth: 88, minHeight: 34)
                        .background(CrabrixTheme.raised, in: RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open Projects home")

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
                    Button(action: onProjectActions) {
                        Label("Project Details & Share", systemImage: "ellipsis.circle")
                    }
                } label: {
                    if transfer.isWorking {
                        ProgressView().tint(CrabrixTheme.coral)
                    } else {
                        Label("PROJECT", systemImage: "folder.fill")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(CrabrixTheme.primary)
                    }
                }
                .disabled(transfer.isWorking)

                Label("NO WEBVIEW", systemImage: "swift")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(CrabrixTheme.mint)
                    .accessibilityLabel("Native SwiftUI")
                Label(toolchain.isReady ? "OFFLINE READY" : "MISSING", systemImage: toolchain.isReady ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(toolchain.isReady ? CrabrixTheme.mint : CrabrixTheme.amber)
                    .accessibilityLabel(toolchain.isReady ? "Offline compiler ready" : "Compiler missing")
            } else {
                if isPhone {
                    Button(action: onProjectActions) {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 18, weight: .semibold))
                            .frame(width: 34, height: 38)
                            .background(
                                CrabrixTheme.raised,
                                in: Circle()
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(transfer.isWorking)
                    .accessibilityLabel("Project details, save, and share")

                    Button(action: activity == .idle ? onRun : onCancelBuild) {
                        HStack(spacing: 6) {
                            if activity == .idle {
                                Image(systemName: "play.fill")
                            } else {
                                ProgressView()
                                    .controlSize(.mini)
                                    .tint(CrabrixTheme.coral)
                            }
                            Text(activity == .idle ? "Run" : "Stop")
                                .font(.caption.bold())
                        }
                        .foregroundStyle(CrabrixTheme.coral)
                        .padding(.horizontal, 11)
                        .frame(minHeight: 38)
                        .background(CrabrixTheme.coral.opacity(0.12), in: Capsule())
                        .overlay {
                            Capsule().stroke(CrabrixTheme.coral.opacity(0.3))
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(activity == .idle && !canRun)
                    .opacity(activity == .idle && !canRun ? 0.46 : 1)
                    .accessibilityLabel(activity == .idle ? "Run project" : "Stop build")
                    .accessibilityHint(
                        activity == .idle
                            ? "Compiles and runs the project locally"
                            : "Cancels the current compiler operation"
                    )
                }

                Button(action: onCloseWorkspace) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 38, height: 38)
                        .background(CrabrixTheme.raised, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close editor")
            }
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
            case .ready:
                // Success is already visible in the workspace itself, so it does
                // not get a permanent row above the editor.
                EmptyView()
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
    let cargoStage: CargoPreparationStage
    let cargoWorkspace: CargoWorkspaceSnapshot
    let isBusy: Bool
    let onProjectActions: () -> Void
    let onSelect: (String) -> Void
    let onNewFile: () -> Void
    let onNewFolder: () -> Void
    let onResolvePackages: () -> Void
    let onAddPackage: () -> Void

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
                        Button(action: onProjectActions) {
                            Image(systemName: "ellipsis.circle")
                                .foregroundStyle(CrabrixTheme.blue)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(
                            "Project details, save, and share"
                        )
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
                    }

                    Divider().overlay(CrabrixTheme.border).padding(.vertical, 8)
                    CargoPackagesPanel(
                        stage: cargoStage,
                        workspace: cargoWorkspace,
                        manifest: manifest,
                        isBusy: isBusy,
                        onRefresh: onResolvePackages,
                        onAddDependency: onAddPackage
                    )

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
    let cargoStage: CargoPreparationStage
    let result: CompilationResult?
    let files: [String]
    let selectedFile: String
    let isProjectSidebarCollapsed: Bool
    let isInspectorCollapsed: Bool
    let onSelectFile: (String) -> Void
    let onToggleProjectSidebar: () -> Void
    let onToggleInspector: () -> Void

    private var hasCompilerError: Bool {
        result?.diagnostics.contains(where: { $0.level == "error" }) == true
    }

    /// Build controls live in the Build inspector. What stays above the editor
    /// is a read-only line, so a multi-minute build is never silent while the
    /// inspector is closed.
    private var buildStatus: some View {
        HStack(spacing: 7) {
            ProgressView().controlSize(.mini).tint(CrabrixTheme.amber)
            Text(cargoStage.isWorking ? cargoStage.label : activity.label)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(CrabrixTheme.muted)
                .lineLimit(1)
            Spacer(minLength: 0)
            Text(activity == .checking ? "CHECK" : "RUN")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(activity == .checking ? CrabrixTheme.blue : CrabrixTheme.coral)
        }
        .accessibilityElement(children: .combine)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                PanelToolbarButton(
                    title: isProjectSidebarCollapsed ? "Show files" : "Hide files",
                    systemImage: "sidebar.left",
                    isCollapsed: isProjectSidebarCollapsed,
                    visibleTitle: isProjectSidebarCollapsed ? "Files" : nil,
                    action: onToggleProjectSidebar
                )

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

                PanelToolbarButton(
                    title: isInspectorCollapsed
                        ? (hasCompilerError ? "Show Apple Intelligence error help" : "Show inspector")
                        : "Hide inspector",
                    systemImage: hasCompilerError && isInspectorCollapsed
                        ? "apple.intelligence"
                        : "sidebar.right",
                    isCollapsed: isInspectorCollapsed,
                    visibleTitle: isInspectorCollapsed
                        ? (hasCompilerError ? "Fix" : "Build")
                        : nil,
                    action: onToggleInspector
                )
            }

            Divider().overlay(CrabrixTheme.border)

            if activity != .idle {
                buildStatus
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
            }
        }
        .background(CrabrixTheme.panel)
    }
}

private struct PanelToolbarButton: View {
    let title: String
    let systemImage: String
    let isCollapsed: Bool
    let visibleTitle: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .bold))
                if let visibleTitle {
                    Text(visibleTitle)
                        .font(.caption.bold())
                        .lineLimit(1)
                }
            }
            .foregroundStyle(isCollapsed ? CrabrixTheme.mint : CrabrixTheme.blue)
            .padding(.horizontal, visibleTitle == nil ? 0 : 10)
            .frame(minWidth: 42, minHeight: 34)
            .background(
                (isCollapsed ? CrabrixTheme.mint : CrabrixTheme.blue).opacity(0.11),
                in: RoundedRectangle(cornerRadius: 10)
            )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityLabel(title)
        .accessibilityHint("Toggle this editor panel")
    }
}

private struct CompactDrawerHeader: View {
    let title: String
    let systemImage: String
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .frame(width: 38, height: 38)
                    .background(CrabrixTheme.raised, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close \(title.lowercased())")
        }
        .padding(.horizontal, 14)
        .frame(height: 54)
        .background(CrabrixTheme.panel)
    }
}

private struct DiagnosticAdvisorQuickButton: View {
    let diagnostic: RustDiagnostic
    let state: RustDiagnosticAdviceState
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if state.isWorking {
                    ProgressView()
                        .controlSize(.small)
                        .tint(CrabrixTheme.blue)
                } else {
                    Image(systemName: "apple.intelligence")
                        .foregroundStyle(CrabrixTheme.blue)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(CrabrixTheme.primary)
                    Text(detail)
                        .font(.caption2.monospaced())
                        .foregroundStyle(CrabrixTheme.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.caption2.bold())
                    .foregroundStyle(CrabrixTheme.blue)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: 360, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(CrabrixTheme.blue.opacity(0.35))
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens Apple Intelligence analysis for this compiler error")
    }

    private var title: String {
        switch state {
        case .idle:
            "Fix " + (diagnostic.code ?? "error") + " with Apple Intelligence"
        case .generating:
            "Apple Intelligence is analyzing…"
        case .verifying:
            "Verifying the suggested fix…"
        case let .ready(advice):
            advice.canApply ? "Review verified fix" : "Review Apple Intelligence advice"
        case .unavailable:
            "Apple Intelligence needs attention"
        }
    }

    private var detail: String {
        switch state {
        case .idle:
            "Tap to analyze this rustc error"
        case .generating, .verifying:
            "Tap to view progress"
        case let .ready(advice):
            advice.canApply ? "The edit passed the bundled rustc" : "Open the diagnostic advisor"
        case let .unavailable(message):
            message
        }
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
