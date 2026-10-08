import SwiftUI
import UIKit
import UniformTypeIdentifiers

private enum CrabrixDestination: Hashable {
    case projects
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
        case "build": return .projects
        case "learn": return .learn
        case "settings": return .settings
        default: return nil
        }
    }

    static var launchesWorkspace: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-CrabrixTab"),
              index + 1 < arguments.count else { return false }
        return arguments[index + 1] == "build"
    }
}

private enum ProjectImportSource {
    case github
    case files
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

private struct PersistentTabBar: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.tabBarMinimizeBehavior(.never)
        } else {
            content
        }
    }
}

struct ContentView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = CompilerViewModel()
    @StateObject private var completion = RustCompletionController()
    @StateObject private var terminal = ProjectTerminalSession()
    @StateObject private var editorKeyboard = RustEditorKeyboardBridge()
    @EnvironmentObject private var progress: CrabrixProgressStore
    @EnvironmentObject private var academy: AcademyContentStore
    /// Lessons already turned into rating, seeded from persisted progress so a
    /// relaunch never re-awards them.
    @State private var scoredLessonIDs: Set<String>?
    @State private var scoredPractice = false
    @State private var isFileImporterPresented = false
    @State private var isFileExporterPresented = false
    @State private var archiveShareItem: ArchiveShareItem?
    @State private var isGitHubImporterPresented = false
    @State private var isNewProjectPresented = false
    @State private var pendingNewProjectImport: ProjectImportSource?
    @State private var isProjectActionsPresented = false
    @State private var isCargoCatalogPresented = false
    @State private var isPackageStoragePresented = false
    @State private var projectsPath: [ProjectsRoute] = []
    @State private var projectItemCreation: ProjectItemCreation?
    @State private var projectItemParentPath = ""
    @State private var githubURL = ""
    @State private var selectedDestination: CrabrixDestination =
        CrabrixDestination.launchArgument ?? .projects
    @State private var isWorkspaceOpen = CrabrixDestination.launchesWorkspace
    @State private var projectSidebarWidth: CGFloat = 220
    @State private var isProjectSidebarCollapsed = false
    @State private var isCompactProjectDrawerPresented = false
    @State private var isDiagnosticHelpPresented = false
    @State private var selectedBuildDockTab: BuildDockTab = {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--crabrix-auto-terminal") { return .terminal }
        if arguments.contains("--crabrix-auto-problems") { return .problems }
        if arguments.contains("--crabrix-auto-output") { return .output }
        return .code
    }()
    @State private var tabletopTabsGlobalY: CGFloat?
    @State private var learningPath: [LearningRoute] = []
    @State private var editorCursorOffset = 0
    /// What the last successful run was scored on, shown in the build dock.
    @State private var lastContribution: CodeContribution?
    @State private var editorNavigationTarget: EditorNavigationTarget?
    @State private var editorSearchQuery = ""
    @AppStorage("crabrix.appearance") private var appearanceRaw = CrabrixAppearance.system.rawValue
    @AppStorage("crabrix.keepAwakeDuringBuild") private var keepAwakeDuringBuild = true
    @AppStorage("crabrix.appleIntelligenceCompletion") private var appleIntelligenceCompletion = true
    @AppStorage("crabrix.appleIntelligenceDiagnostics") private var appleIntelligenceDiagnostics = true
    @State private var exportDocument = CrabrixProjectDocument(
        project: CrabrixProject(
            name: "hello-crabrix",
            files: ["main.rs": RustSamples.runnable],
            entryFile: "main.rs",
            provenance: nil
        )
    )

    var body: some View {
        GeometryReader { geometry in
            let tabletop = AdaptiveFold.horizontal(in: geometry) != nil
                || tabletopTabsGlobalY != nil
            tabContent(tabletop: tabletop)
                .toolbar(tabletop && isWorkspaceOpen ? .hidden : .visible, for: .tabBar)
        }
    }

    private func tabContent(tabletop: Bool) -> some View {
        TabView(selection: $selectedDestination) {
            Group {
                if isWorkspaceOpen {
                    buildWorkspace
                        .toolbar(tabletop ? .hidden : .visible, for: .tabBar)
                        .ignoresSafeArea(tabletop ? .container : [], edges: .top)
                        .ignoresSafeArea(
                            tabletop && (selectedBuildDockTab == .problems || selectedBuildDockTab == .output)
                                ? .container : [],
                            edges: .bottom
                        )
                        .ignoresSafeArea(
                            tabletopTabsGlobalY == nil ? [] : .keyboard,
                            edges: .bottom
                        )
                } else {
            NavigationStack(path: $projectsPath) {
                ProjectsHomeView(
                    projectName: model.projectName,
                    fileCount: model.fileNames.count,
                    lastBuild: model.lastBuild,
                    activity: model.activity,
                    isCompilerDraining: model.isCompilerDraining,
                    projectCount: model.allProjects.count,
                onOpenCurrentProject: openCodeWorkspace,
                onNewProject: { isNewProjectPresented = true },
                onOpenMyProjects: { projectsPath = [.myProjects] }
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
                                        openCodeWorkspace()
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
                        .toolbar(.visible, for: .navigationBar)
                    }
                }
            }
                }
            }
            .tabItem { Label("Projects", systemImage: "folder.fill") }
            .tag(CrabrixDestination.projects)

            LearningHubView(
                navigationPath: $learningPath,
                completedLessonIDs: model.completedLessonIDs,
                lessonAnswerIndices: model.lessonAnswerIndices,
                onStartLesson: startLesson,
                onCompleteLesson: { lesson in model.completeLesson(lesson.id) },
                onResetCourseProgress: model.resetCourseProgress,
                onAnswerLesson: { lesson, answer, correct in
                    if correct { model.recordLessonAnswer(answer, for: lesson.id) }
                },
                onOpenExample: { project, courseID, contentVersion in
                    model.openAcademyExample(
                        project, courseID: courseID, contentVersion: contentVersion
                    )
                    openCodeWorkspace()
                }
            )
            .tabItem { Label("Learn", systemImage: "graduationcap.fill") }
            .tag(CrabrixDestination.learn)

            SettingsView(
                toolchain: model.toolchain
            )
            .tabItem { Label("Settings", systemImage: "gearshape.fill") }
            .tag(CrabrixDestination.settings)
        }
        .tabViewStyle(.tabBarOnly)
        .modifier(PersistentTabBar())
        .toolbar(tabletop && isWorkspaceOpen ? .hidden : .visible, for: .tabBar)
        .toolbarBackground(CrabrixTheme.panel, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .id(appearanceRaw)
        .tint(CrabrixTheme.coral)
        .foregroundStyle(CrabrixTheme.primary)
        .preferredColorScheme(
            CrabrixAppearance(rawValue: appearanceRaw)?.colorScheme
        )
        .sheet(isPresented: $isCargoCatalogPresented) {
            CargoDependencyCatalogSheet(onAdd: model.addCargoDependency)
        }
        .sheet(isPresented: $isPackageStoragePresented) {
            ProjectPackageStorageSheet(
                storage: model.cargoStorage,
                onRefreshStorage: model.refreshCargoStorage,
                onClearBuildArtifacts: model.clearCargoBuildArtifacts,
                onClearDownloadedArchives: model.clearCargoDownloadedArchives,
                onClearOfflinePins: model.clearCargoOfflinePins,
                onClearPackageCache: model.clearCargoPackageCache
            )
        }
        .sheet(isPresented: $isNewProjectPresented, onDismiss: presentPendingProjectImport) {
            NewProjectSheet(
                onCreate: { request in
                    model.createProject(request)
                    openCodeWorkspace()
                },
                onOpenGitHub: {
                    pendingNewProjectImport = .github
                    isNewProjectPresented = false
                },
                onOpenFiles: {
                    pendingNewProjectImport = .files
                    isNewProjectPresented = false
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $projectItemCreation) { mode in
            NewProjectItemSheet(mode: mode, initialPath: projectItemParentPath) { path in
                switch mode {
                case .rustFile: model.createRustFile(at: path)
                case .textFile: model.createTextFile(at: path)
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
        .sheet(isPresented: $isDiagnosticHelpPresented) {
            NavigationStack {
                ScrollView {
                    if let diagnostic = model.primaryDiagnostic {
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
                        .padding(20)
                    }
                }
                .background(CrabrixTheme.background)
                .navigationTitle("Compiler help")
                .toolbar { Button("Done") { isDiagnosticHelpPresented = false } }
            }
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
                        openCodeWorkspace()
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
                        openCodeWorkspace()
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
            await academy.prepare()
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("-CrabrixLibrary") || arguments.contains("-CrabrixCanvasGallery") {
                selectedDestination = .learn
            }
            if arguments.contains("--crabrix-auto-multifile") {
                model.loadMultiFileSample()
                openCodeWorkspace()
            }
            if arguments.contains("--crabrix-auto-borrow") {
                model.loadBorrowDiagnosticSample()
                openCodeWorkspace()
            }
            if let githubArgument = arguments.first(where: { $0.hasPrefix("--crabrix-auto-github=") }) {
                let rawURL = String(githubArgument.dropFirst("--crabrix-auto-github=".count))
                if await model.importGitHub(rawURL) {
                    openCodeWorkspace()
                }
            }
            if arguments.contains("--crabrix-auto-learn") {
                selectedDestination = .learn
            }
            if arguments.contains(where: { $0.hasPrefix("--crabrix-auto-lesson=") }) {
                selectedDestination = .learn
            }
            if arguments.contains("--crabrix-auto-settings") {
                selectedDestination = .settings
            }
            if let dockArgument = arguments.first(where: { $0.hasPrefix("--crabrix-auto-dock=") }) {
                let tab = String(dockArgument.dropFirst("--crabrix-auto-dock=".count))
                if let dockTab = BuildDockTab(rawValue: tab) {
                    openCodeWorkspace()
                    selectedBuildDockTab = dockTab
                }
            }
            if let showcaseArgument = arguments.first(where: { $0.hasPrefix("--crabrix-auto-showcase=") }) {
                let id = String(showcaseArgument.dropFirst("--crabrix-auto-showcase=".count))
                if let installed = academy.repository?.loaded["examples"]
                    ?? academy.repository?.loaded["projects"],
                   let project = installed.showcases.first(where: { $0.id == id }) {
                    model.openAcademyExample(
                        project, courseID: installed.course.id,
                        contentVersion: installed.contentVersion
                    )
                    openCodeWorkspace()
                } else {
                    selectedDestination = .learn
                }
            }
            if arguments.contains("--crabrix-auto-run") {
                model.run()
            } else if arguments.contains("--crabrix-auto-check") {
                model.check()
            }
            if !arguments.contains(where: { $0.hasPrefix("--crabrix-auto-") }) {
                await model.consumePendingSharedImport()
                if case .ready = model.projectTransfer {
                    openCodeWorkspace()
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
            selectedBuildDockTab = ProcessInfo.processInfo.arguments.contains("--crabrix-auto-terminal")
                ? .terminal : .code
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
                    if let challenge = academy.repository?.challenge(for: lessonID) {
                        progress.recordAlgorithmSolved(challenge: challenge)
                    }
                }
                return
            }
            let fresh = ids.subtracting(scored)
            scoredLessonIDs = ids
            guard !fresh.isEmpty else { return }
            for lessonID in fresh {
                progress.record(
                    progressEvent(forLessonID: lessonID),
                    eventKey: "lesson:\(lessonID):first-completion"
                )
                if let challenge = academy.repository?.challenge(for: lessonID) {
                    progress.recordAlgorithmSolved(challenge: challenge)
                }
            }
        }
        .onReceive(academy.$repository) { repository in
            // Progress may load before the offline transition packs finish
            // activating. Backfill their verified Atlas identities once the
            // repository arrives; the store deduplicates every pattern.
            guard let repository else { return }
            progress.configureAcademy(repository: repository)
            for lessonID in model.completedLessonIDs {
                if let challenge = repository.challenge(for: lessonID) {
                    progress.recordAlgorithmSolved(challenge: challenge)
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
        isWorkspaceOpen = false
        if let lessonID = model.activeLessonID,
           let course = academy.repository?.course(containing: lessonID) {
            selectedDestination = .learn
            learningPath = [.course(course.id), .lesson(lessonID)]
        } else {
            selectedDestination = .projects
        }
    }

    private func openCodeWorkspace() {
        projectsPath = []
        isWorkspaceOpen = true
        selectedBuildDockTab = ProcessInfo.processInfo.arguments.contains("--crabrix-auto-terminal")
            ? .terminal : .code
        selectedDestination = .projects
    }

    private func presentPendingProjectImport() {
        guard let source = pendingNewProjectImport else { return }
        pendingNewProjectImport = nil
        switch source {
        case .github: isGitHubImporterPresented = true
        case .files: isFileImporterPresented = true
        }
    }

    private func startLesson(_ lesson: RustLesson, session: CourseSession) {
        guard let content = CourseLessonExecution(lesson: lesson, session: session) else { return }
        let isReview = model.completedLessonIDs.contains(lesson.id)
        let reviewProjectName = "review-\(lesson.id)"
        if let template = session.repository.starterProject(for: lesson.id) {
            model.loadCourseStarter(
                template, session: session,
                projectName: isReview ? reviewProjectName : nil
            )
        } else { switch lesson.exercise {
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
            guard let challenge = content.challenge else {
                return
            }
            model.loadAlgorithmLessonSample(
                projectName: isReview ? reviewProjectName : challenge.projectName,
                source: challenge.source
            )
        case .planned:
            return
        } }
        model.beginLesson(lesson.id, isReview: isReview, content: content)
        openCodeWorkspace()
    }

    private func editorPane(fixedSidebar: Bool) -> some View {
        VStack(spacing: 0) {
            EditorToolbar(
                activity: model.activity,
                cargoStage: model.cargoStage,
                files: model.fileNames,
                selectedFile: model.selectedFile,
                isProjectSidebarCollapsed: fixedSidebar ? false : !isCompactProjectDrawerPresented,
                showsProjectSidebarToggle: !fixedSidebar,
                showsEnvironmentBar: tabletopTabsGlobalY == nil,
                onSelectFile: selectEditorFile,
                onToggleProjectSidebar: {
                    if fixedSidebar {
                        // The files panel does not hide on iPad.
                    } else {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            isCompactProjectDrawerPresented.toggle()
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
                lessonHint: model.activeLessonHint,
                contribution: lastContribution,
                onOpenDiagnostic: openDiagnostic,
                diagnosticAdviceState: model.diagnosticAdviceState,
                onOpenDiagnosticAdvisor: presentDiagnosticAdvisor,
                onContinueLearning: continueLearning,
                keyboardBridge: editorKeyboard,
                assistantUsesAppleIntelligence: appleIntelligenceCompletion
                    && RustCompletionSupport.isAppleIntelligenceAvailable,
                onRequestCompletion: requestEditorAssistant
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
                assistantUsesAppleIntelligence: appleIntelligenceCompletion
                    && RustCompletionSupport.isAppleIntelligenceAvailable,
                tabletopCodeTabActive: tabletopTabsGlobalY == nil
                    ? nil : selectedBuildDockTab == .code,
                keyboardBridge: editorKeyboard,
                onRequestCompletion: requestEditorAssistant,
                onEditorFocus: {
                    if tabletopTabsGlobalY != nil {
                        selectedBuildDockTab = .code
                    }
                }
            )

            if let diagnostic = model.primaryDiagnostic,
               completion.suggestion == nil,
               completion.message == nil {
                VStack {
                    Spacer()
                    DiagnosticAdvisorQuickButton(
                        diagnostic: diagnostic,
                        state: model.diagnosticAdviceState,
                        usesAppleIntelligence: diagnosticAdviceUsesAppleIntelligence,
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

    private var buildWorkspace: some View {
        GeometryReader { workspace in
        let fixedSidebar = horizontalSizeClass == .regular && workspace.size.width >= 570
        let bookFold = AdaptiveFold.vertical(in: workspace)
        let tabletopFold = AdaptiveFold.horizontal(in: workspace)
        ZStack {
            CrabrixTheme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                AppHeader(
                    isPhone: UIDevice.current.userInterfaceIdiom == .phone,
                    regularTablet: horizontalSizeClass == .regular && UIDevice.current.userInterfaceIdiom != .phone,
                    dense: tabletopFold != nil || tabletopTabsGlobalY != nil,
                    showsTopNavigation: tabletopFold != nil || tabletopTabsGlobalY != nil,
                    headerWidth: workspace.size.width,
                    projectName: model.projectName,
                    searchQuery: $editorSearchQuery,
                    transfer: model.projectTransfer,
                    activity: model.activity,
                    canRun: model.canStartBuild && !model.isProjectOperationInProgress,
                    onCheck: model.check,
                    onRun: model.run,
                    onCancelBuild: model.cancelBuild,
                    onOpenProjects: {
                        isWorkspaceOpen = false
                        selectedDestination = .projects
                    },
                    onCloseWorkspace: closeBuildWorkspace,
                    onFindNext: findNextInCurrentFile,
                    onNewProject: { isNewProjectPresented = true },
                    onProjectActions: {
                        isProjectActionsPresented = true
                    }
                )
                if model.projectTransfer.isWorking || model.projectTransfer.isFailure {
                    ProjectTransferStrip(transfer: model.projectTransfer)
                }
                Rectangle()
                    .fill(CrabrixTheme.border)
                    .frame(height: 1 / UIScreen.main.scale)

                if fixedSidebar && tabletopFold == nil && tabletopTabsGlobalY == nil {
                    HStack(spacing: 0) {
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
                                onNewFile: { path in
                                    projectItemParentPath = path
                                    projectItemCreation = .rustFile
                                },
                                onNewTextFile: { path in
                                    projectItemParentPath = path
                                    projectItemCreation = .textFile
                                },
                                onNewFolder: { path in
                                    projectItemParentPath = path
                                    projectItemCreation = .moduleFolder
                                },
                                onResolvePackages: model.refreshCargoWorkspace,
                                onPinPackages: model.pinDependenciesForOffline,
                                onAddPackage: { isCargoCatalogPresented = true },
                                onManagePackageStorage: { isPackageStoragePresented = true },
                                onRemovePackage: model.removeCargoDependency,
                                onUseSynParserFeatures: model.useSynParserFeatures,
                                vendoredFiles: model.vendoredFiles,
                                onVendor: model.vendorCrate,
                                onOpenVendor: model.openVendoredCrate,
                                onResetVendor: model.resetVendoredCrate
                            )
                        .frame(width: bookFold.map { max(170, min($0.minX, workspace.size.width - 280)) }
                            ?? min(projectSidebarWidth, workspace.size.width - 360))

                        if let bookFold {
                            Color.clear.frame(width: bookFold.width)
                        } else {
                            ResizablePanelDivider(
                                edge: .leading,
                                width: $projectSidebarWidth,
                                isCollapsed: $isProjectSidebarCollapsed,
                                minimumWidth: 170,
                                maximumWidth: 360,
                                canCollapse: false
                            )
                        }

                        editorPane(fixedSidebar: true)
                            .frame(minWidth: bookFold == nil ? 340 : 0)
                    }
                } else {
                    compactBuildWorkspace(tabletopTabsGlobalY: tabletopTabsGlobalY)
                }
            }
            // Keep the workspace toolbar level with the native My Projects
            // navigation bar; the status glyphs remain in the trailing space.
            .padding(.top, tabletopFold == nil ? 0 : 30)
            .background(CrabrixTheme.background)
        }
        .onPreferenceChange(TabletopTabsGlobalYPreferenceKey.self) { globalY in
            let enteringTabletop = tabletopTabsGlobalY == nil && globalY != nil
            tabletopTabsGlobalY = globalY
            if enteringTabletop && selectedBuildDockTab == .code {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    if selectedBuildDockTab == .code {
                        editorKeyboard.focusEditor()
                    }
                }
            }
        }
        }
    }

    private func selectEditorFile(_ file: String) {
        model.selectFile(file)
        editorNavigationTarget = nil
        editorSearchQuery = ""
        selectedBuildDockTab = .code
        withAnimation(.easeOut(duration: 0.18)) {
            isCompactProjectDrawerPresented = false
        }
    }

    private func compactBuildWorkspace(tabletopTabsGlobalY: CGFloat?) -> some View {
        GeometryReader { geometry in
            // In tabletop pose the drawer fills the upper display down to the
            // Code, Problems, Output and Terminal tabs, without a dead strip.
            let drawerHeight = tabletopTabsGlobalY.map {
                max(160, min($0 - geometry.frame(in: .global).minY, geometry.size.height))
            } ?? geometry.size.height
            ZStack(alignment: .topLeading) {
                editorPane(fixedSidebar: false)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if !isCompactProjectDrawerPresented {
                    HStack(spacing: 0) {
                        CompactEdgeSwipeZone(edge: .leading) {
                            withAnimation(.easeOut(duration: 0.22)) {
                                isCompactProjectDrawerPresented = true
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.top, 52)
                    .zIndex(0.5)
                }

                if isCompactProjectDrawerPresented {
                    Color.black.opacity(0.46)
                        .frame(height: drawerHeight)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.easeOut(duration: 0.2)) {
                                isCompactProjectDrawerPresented = false
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
                            onNewFile: { path in
                                projectItemParentPath = path
                                projectItemCreation = .rustFile
                            },
                            onNewTextFile: { path in
                                projectItemParentPath = path
                                projectItemCreation = .textFile
                            },
                            onNewFolder: { path in
                                projectItemParentPath = path
                                projectItemCreation = .moduleFolder
                            },
                            onResolvePackages: model.refreshCargoWorkspace,
                            onPinPackages: model.pinDependenciesForOffline,
                            onAddPackage: { isCargoCatalogPresented = true },
                            onManagePackageStorage: { isPackageStoragePresented = true },
                            onRemovePackage: model.removeCargoDependency,
                            onUseSynParserFeatures: model.useSynParserFeatures,
                            vendoredFiles: model.vendoredFiles,
                            onVendor: model.vendorCrate,
                            onOpenVendor: model.openVendoredCrate,
                            onResetVendor: model.resetVendoredCrate
                        )
                    }
                    .frame(width: min(geometry.size.width * 0.86, 340))
                    .frame(height: drawerHeight)
                    .background(CrabrixTheme.panel)
                    .overlay(alignment: .trailing) {
                        Rectangle().fill(CrabrixTheme.border).frame(width: 1)
                    }
                    .clipped()
                    .frame(maxHeight: .infinity, alignment: .top)
                    .transition(.move(edge: .leading).combined(with: .opacity))
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
                } else if !isCompactProjectDrawerPresented,
                          value.startLocation.x <= 30,
                          horizontal > 0 {
                    withAnimation(.easeOut(duration: 0.22)) {
                        isCompactProjectDrawerPresented = true
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
    /// Whether the diagnostic helper will really reach Apple Intelligence.
    private var diagnosticAdviceUsesAppleIntelligence: Bool {
        appleIntelligenceDiagnostics && RustCompletionSupport.isAppleIntelligenceAvailable
    }

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

        // The Settings switch has to mean something: with it off, the advisor
        // opens on Crabrix's own explanation and repair rather than quietly
        // calling Apple Intelligence anyway.
        if case .idle = model.diagnosticAdviceState, diagnosticAdviceUsesAppleIntelligence {
            model.requestAppleIntelligenceAdvice()
        }

        withAnimation(.easeOut(duration: 0.22)) {
            isCompactProjectDrawerPresented = false
            isDiagnosticHelpPresented = true
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

    private func findNextInCurrentFile() {
        let needle = editorSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return }
        let source = model.source as NSString
        let start = min(max(editorCursorOffset + 1, 0), source.length)
        var match = source.range(
            of: needle,
            options: .caseInsensitive,
            range: NSRange(location: start, length: source.length - start)
        )
        if match.location == NSNotFound {
            match = source.range(of: needle, options: .caseInsensitive)
        }
        guard match.location != NSNotFound else { return }

        let prefix = source.substring(to: match.location) as NSString
        let lastNewline = prefix.range(of: "\n", options: .backwards).location
        let line = prefix.components(separatedBy: "\n").count
        let column = match.location - (lastNewline == NSNotFound ? 0 : lastNewline + 1) + 1
        selectedBuildDockTab = .code
        editorNavigationTarget = EditorNavigationTarget(
            filePath: model.selectedFile,
            line: line,
            column: column
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

    /// What finishing this step is worth.
    ///
    /// The Atlas is three times the size of the language path, so paying each
    /// of its 600 steps like a Rust lesson would have made the rank ladder a
    /// formality. Reading a pattern is a quarter of a lesson; proving one to
    /// the compiler is worth more than either.
    private func progressEvent(forLessonID lessonID: String) -> CrabrixProgressEvent {
        guard academy.repository?.course(containing: lessonID)?.id == "algorithms" else {
            return .lessonCompleted
        }
        return academy.repository?.challenge(for: lessonID) == nil
            ? .algorithmStudyStepCompleted : .algorithmChallengeSolved
    }

    /// Turns a finished build into rating, once per result.
    private func recordBuildProgress(_ result: CompilationResult) {
        guard result.succeeded, result.phase == .run else { return }
        // A completed lesson is review-only. The editor does not add its typing
        // to the ledger, and this run earns no additional rating.
        if !model.earnsProgressForCurrentRun {
            lastContribution = nil
            return
        }
        // Rating follows the diff, so re-running an untouched sample earns a
        // token amount and real editing earns real points.
        var contribution = CodeContributionLedger.shared.record(
            projectID: model.projectID,
            files: model.exportProject().files
        )
        contribution.typedShare = TypingLedger.shared.typedShare(projectID: model.projectID)
        // Two separate rewards, because they answer different questions. The
        // diff is paid once per exact source revision, so a loop of identical
        // builds earns nothing; showing up is paid once a day, so coming back
        // to a finished project tomorrow still counts.
        let revisionKey = CrabrixProgressState.buildRevisionKeyPrefix
            + "\(model.projectID.uuidString):\(model.workspaceRevision.sourceTreeHash)"
        let buildRecorded = progress.record(.buildSucceeded(contribution), eventKey: revisionKey)
        if progress.isFirstRunToday() { progress.record(.dailyRunBonus) }
        lastContribution = buildRecorded ? contribution : nil

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
           let course = academy.repository?.course(containing: lessonID),
           course.id == "algorithms" {
            let methodLessons = course.units.first { $0.lessons.contains { $0.id == lessonID } }?.lessons ?? []
            if let position = methodLessons.firstIndex(where: { $0.id == lessonID }),
               methodLessons.indices.contains(position + 1) {
                let next = methodLessons[position + 1]
                learningPath = [.course("algorithms"), .lesson(next.id)]
            } else {
                learningPath = [.course("algorithms")]
            }
            return
        }
        // Land on the next lesson itself, not on the course list: after finishing
        // something, "what is next" is a specific screen.
        guard let courses = academy.repository?.courses,
              let step = RustLessonProgression.nextStep(
                after: model.activeLessonID,
                completedLessonIDs: model.completedLessonIDs,
                courses: courses
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
    let isPhone: Bool
    let regularTablet: Bool
    let dense: Bool
    let showsTopNavigation: Bool
    let headerWidth: CGFloat
    let projectName: String
    @Binding var searchQuery: String
    let transfer: CompilerViewModel.ProjectTransfer
    let activity: CompilerViewModel.Activity
    let canRun: Bool
    let onCheck: () -> Void
    let onRun: () -> Void
    let onCancelBuild: () -> Void
    let onOpenProjects: () -> Void
    let onCloseWorkspace: () -> Void
    let onFindNext: () -> Void
    let onNewProject: () -> Void
    let onProjectActions: () -> Void

    var body: some View {
        HStack(spacing: isPhone ? 7 : 12) {
            if showsTopNavigation {
                Button(action: onCloseWorkspace) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 38, height: 38)
                        .background(CrabrixTheme.raised, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back to Projects")

                Text(projectName)
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: max(110, min(190, headerWidth * 0.2)), alignment: .leading)

                Spacer(minLength: 4)
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(CrabrixTheme.muted)
                    TextField("Find in file", text: $searchQuery)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .onSubmit(onFindNext)
                        .accessibilityLabel("Find in current file")
                    if !searchQuery.isEmpty {
                        Button(action: onFindNext) {
                            Image(systemName: "arrow.down")
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Find next in file")
                    }
                }
                .font(.system(size: 13))
                .padding(.horizontal, 12)
                .frame(width: max(120, min(190, headerWidth * 0.2)), height: 36)
                .background(CrabrixTheme.raised, in: Capsule())

                tabletopProjectMenu
                checkButton
                runButton
            } else {
                Image("CrabrixMark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 30, height: 30)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .accessibilityLabel("Crabrix crab")
                Text("crabrix")
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                Spacer()

                if regularTablet {
                    Button(action: onOpenProjects) {
                        Label("Projects", systemImage: "square.grid.2x2.fill")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .frame(minWidth: 88, minHeight: 34)
                            .background(CrabrixTheme.raised, in: CrabrixCardShape(cornerRadius: 9))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open Projects home")

                    Menu {
                        Button(action: onNewProject) {
                            Label("New Project", systemImage: "plus")
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
                } else {
                    if isPhone {
                        Button(action: onProjectActions) {
                            Image(systemName: "ellipsis.circle")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundStyle(CrabrixTheme.primary)
                                .frame(width: 40, height: 40)
                                .background(CrabrixTheme.raised, in: CrabrixControlShape(classic: .circle))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Project settings and share")
                        checkButton
                        runButton
                    }
                    closeButton
                }
            }
        }
        .padding(.horizontal, isPhone ? 14 : 18)
        // The status glyphs share the header row in laptop posture.
        .padding(.trailing, showsTopNavigation ? 112 : 0)
        .frame(height: dense ? 44 : 58)
        .background(CrabrixTheme.background)
    }

    private var tabletopProjectMenu: some View {
        Menu {
            Button("Project settings and share", systemImage: "gearshape", action: onProjectActions)
            Button("New project", systemImage: "plus", action: onNewProject)
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(CrabrixTheme.primary)
                .frame(width: 40, height: 40)
                .background(CrabrixTheme.raised, in: Circle())
        }
        .disabled(transfer.isWorking)
        .accessibilityLabel("Project menu")
    }

    private var checkButton: some View {
        Button(action: onCheck) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(CrabrixTheme.blue)
                .frame(width: 40, height: 40)
                .background {
                    if showsTopNavigation {
                        Circle().fill(CrabrixTheme.blue.opacity(0.1))
                    } else {
                        CrabrixControlShape(classic: .capsule)
                            .fill(CrabrixTheme.blue.opacity(0.1))
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(activity != .idle || !canRun)
        .accessibilityLabel("Check project")
    }

    private var runButton: some View {
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
            .background {
                if showsTopNavigation {
                    Capsule().fill(CrabrixTheme.coral.opacity(0.12))
                } else {
                    CrabrixControlShape(classic: .capsule)
                        .fill(CrabrixTheme.coral.opacity(0.12))
                }
            }
            .overlay {
                if showsTopNavigation {
                    Capsule().stroke(CrabrixTheme.coral.opacity(0.3))
                } else {
                    CrabrixControlShape(classic: .capsule)
                        .stroke(CrabrixTheme.coral.opacity(0.3))
                }
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

    private var closeButton: some View {
        Button(action: onCloseWorkspace) {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .bold))
                .frame(width: 38, height: 38)
                .background(CrabrixTheme.raised, in: CrabrixControlShape(classic: .circle))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close editor")
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
    /// A panel that has to stay on screen still resizes, it just cannot be
    /// hidden. The iPad file sidebar is one: keeping it visible is what holds
    /// the editor's share of the window under the programming-environment
    /// limit Apple's developer agreement sets.
    var canCollapse = true
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

            if canCollapse {
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
    let onNewFile: (String) -> Void
    let onNewTextFile: (String) -> Void
    let onNewFolder: (String) -> Void
    let onResolvePackages: () -> Void
    let onPinPackages: () -> Void
    let onAddPackage: () -> Void
    let onManagePackageStorage: () -> Void
    let onRemovePackage: (String) -> Bool
    let onUseSynParserFeatures: () -> Bool
    let vendoredFiles: (String, SemanticVersion) -> [String: String]
    let onVendor: (String, SemanticVersion) -> Bool
    let onOpenVendor: (String, SemanticVersion) -> Bool
    let onResetVendor: (String, SemanticVersion) -> Bool

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
                            Button { onNewFile("") } label: {
                                Label("New Rust File", systemImage: "doc.badge.plus")
                            }
                            Button { onNewTextFile("") } label: {
                                Label("New File", systemImage: "doc.badge.plus")
                            }
                            Button { onNewFolder("") } label: {
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
                        onSelect: onSelect,
                        onNewRustFileIn: onNewFile,
                        onNewTextFileIn: onNewTextFile,
                        onNewFolderIn: onNewFolder
                    )

                    if let manifest {
                        Divider().overlay(CrabrixTheme.border).padding(.vertical, 8)
                        Button {
                            onSelect("Cargo.toml")
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("PROJECT MANIFEST")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundStyle(CrabrixTheme.muted)
                                HStack {
                                    Text("\(manifest.name) \(manifest.version ?? "")")
                                        .font(.caption.weight(.semibold))
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption.bold())
                                }
                                Text("Open Cargo.toml · edition \(manifest.edition ?? "unspecified")")
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(CrabrixTheme.mint)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Open Cargo.toml for \(manifest.name)")
                    }

                    Divider().overlay(CrabrixTheme.border).padding(.vertical, 8)
                    CargoPackagesPanel(
                        stage: cargoStage,
                        workspace: cargoWorkspace,
                        manifest: manifest,
                        isBusy: isBusy,
                        onRefresh: onResolvePackages,
                        onPinForOffline: onPinPackages,
                        onAddDependency: onAddPackage,
                        onManageStorage: onManagePackageStorage,
                        onRemoveDependency: onRemovePackage,
                        onUseSynParserFeatures: onUseSynParserFeatures,
                        vendoredFiles: vendoredFiles,
                        onVendor: onVendor,
                        onOpenVendor: onOpenVendor,
                        onResetVendor: onResetVendor
                    )

                    Divider().overlay(CrabrixTheme.border).padding(.vertical, 6)
                    Text("COMPATIBILITY")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(CrabrixTheme.muted)
                    Label(
                        !cargoWorkspace.blockingPackages.isEmpty
                            ? "Package build blocked"
                            : (report.status == .ready ? "Ready for local inspection" : "Review required"),
                        systemImage: report.status == .ready && cargoWorkspace.blockingPackages.isEmpty
                            ? "checkmark.seal.fill" : "exclamationmark.triangle.fill"
                    )
                    .font(.caption2.monospaced())
                    .foregroundStyle(
                        report.status == .ready && cargoWorkspace.blockingPackages.isEmpty
                            ? CrabrixTheme.mint : CrabrixTheme.amber
                    )
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

/// A persistent statement of what this screen is.
///
/// Crabrix is a programming environment, and Apple's Developer Program License
/// Agreement asks such an app to say so conspicuously rather than leaving the
/// user to infer it from an editor. It doubles as the honest toolchain label:
/// the compiler is pinned and bundled, and its exact version is not hidden.
struct ProgrammingEnvironmentBar: View {
    private var toolchainDetail: String {
        "rustc \(CargoToolchain.semanticVersionLabel) · \(RustTargetSpec.wasm32WasiP1.triple)"
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(CrabrixTheme.coral)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    label
                    Spacer(minLength: 8)
                    Text(toolchainDetail)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(CrabrixTheme.muted)
                        .lineLimit(1)
                }
                label
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CrabrixTheme.panel)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Rust programming environment. Bundled \(toolchainDetail)."
        )
    }

    private var label: some View {
        Text("RUST PROGRAMMING ENVIRONMENT")
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundStyle(CrabrixTheme.primary)
            .lineLimit(1)
    }
}

private struct EditorToolbar: View {
    let activity: CompilerViewModel.Activity
    let cargoStage: CargoPreparationStage
    let files: [String]
    let selectedFile: String
    let isProjectSidebarCollapsed: Bool
    /// iPad keeps the files panel on screen, so it offers no button to hide it.
    var showsProjectSidebarToggle = true
    var showsEnvironmentBar = true
    let onSelectFile: (String) -> Void
    let onToggleProjectSidebar: () -> Void

    /// The running state stays visible above the editor on both device sizes.
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
            if showsEnvironmentBar {
                ProgrammingEnvironmentBar()
                Divider().overlay(CrabrixTheme.border)
            }

            HStack(spacing: 8) {
                if showsProjectSidebarToggle {
                    PanelToolbarButton(
                        title: isProjectSidebarCollapsed ? "Show files" : "Hide files",
                        systemImage: "sidebar.left",
                        isCollapsed: isProjectSidebarCollapsed,
                        visibleTitle: isProjectSidebarCollapsed ? "Files" : nil,
                        action: onToggleProjectSidebar
                    )
                }

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
    /// False when Apple Intelligence is switched off in Settings or the device
    /// is not eligible. The button still opens the advisor — Crabrix explains
    /// the diagnostic and can often repair it on its own — but it stops
    /// wearing a name that will not answer.
    let usesAppleIntelligence: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if state.isWorking {
                    ProgressView()
                        .controlSize(.small)
                        .tint(CrabrixTheme.blue)
                } else {
                    Image(systemName: usesAppleIntelligence ? "apple.intelligence" : "bandage.fill")
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
        .accessibilityHint(
            usesAppleIntelligence
                ? "Opens Apple Intelligence analysis for this compiler error"
                : "Opens Crabrix's explanation of this compiler error"
        )
    }

    private var title: String {
        guard usesAppleIntelligence else {
            return "Explain " + (diagnostic.code ?? "this error")
        }
        switch state {
        case .idle:
            return "Fix " + (diagnostic.code ?? "error") + " with Apple Intelligence"
        case .generating:
            return "Apple Intelligence is analyzing…"
        case .verifying:
            return "Verifying the suggested fix…"
        case let .ready(advice):
            return advice.canApply ? "Review verified fix" : "Review Apple Intelligence advice"
        case .unavailable:
            return "Apple Intelligence needs attention"
        }
    }

    private var detail: String {
        guard usesAppleIntelligence else {
            return "Open the diagnostic advisor"
        }
        switch state {
        case .idle:
            return "Tap to analyze this rustc error"
        case .generating, .verifying:
            return "Tap to view progress"
        case let .ready(advice):
            return advice.canApply
                ? "The edit passed the bundled rustc"
                : "Open the diagnostic advisor"
        case let .unavailable(message):
            return message
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
