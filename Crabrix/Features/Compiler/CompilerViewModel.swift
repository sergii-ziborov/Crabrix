import Foundation
import SwiftUI
import CrabrixGit

struct GitRestorePreview: Identifiable {
    let id = UUID()
    let projectID: UUID
    let generation: UInt64
    let commit: String
    let path: String
    let original: String?
    let replacement: String
}

struct GitConsoleEvent {
    let id = UUID()
    let projectID: UUID
    let text: String
    let isError: Bool
}

enum RustProjectTemplate: String, CaseIterable, Identifiable, Sendable {
    case hello
    case empty
    case modules
    case cli
    case packages
    case visual
    case webPage
    case rustWeb

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hello: "Hello Rust"
        case .empty: "Empty Binary"
        case .modules: "Cargo Modules"
        case .cli: "CLI Starter"
        case .packages: "Cargo Packages"
        case .visual: "Visual Canvas"
        case .webPage: "Web Page"
        case .rustWeb: "Rust Web Generator"
        }
    }

    var detail: String {
        switch self {
        case .hello: "A runnable Cargo project with stdout"
        case .empty: "Cargo.toml and a minimal main.rs"
        case .modules: "A multi-file project with a reusable Rust module"
        case .cli: "Read command-line arguments with the standard library"
        case .packages: "Two real crates.io packages · the first build downloads and compiles them"
        case .visual: "Draw a native pixel canvas from an editable Rust program"
        case .webPage: "HTML, CSS and JavaScript · live offline preview"
        case .rustWeb: "Generate a static site with Rust, then run its JavaScript locally"
        }
    }

    var systemImage: String {
        switch self {
        case .hello: "play.rectangle.fill"
        case .empty: "doc.badge.plus"
        case .modules: "square.stack.3d.up.fill"
        case .cli: "apple.terminal.fill"
        case .packages: "shippingbox.fill"
        case .visual: "paintpalette.fill"
        case .webPage, .rustWeb: "globe"
        }
    }

    var defaultProjectKind: CrabrixProject.Kind {
        switch self {
        case .hello, .modules: .learning
        case .empty: .general
        case .cli: .commandLine
        case .packages: .application
        case .visual: .visual
        case .webPage, .rustWeb: .application
        }
    }
}

struct NewRustProjectRequest: Sendable {
    let name: String
    let template: RustProjectTemplate
    let projectDescription: String
    let folder: String?
    let tags: [String]
    let kind: CrabrixProject.Kind
}

@MainActor
final class CompilerViewModel: ObservableObject {
    enum SaveState: Equatable {
        case unsaved, saving, saved, failed(String)
        var label: String {
            switch self {
            case .unsaved: "Unsaved changes"
            case .saving: "Saving…"
            case .saved: "Saved on this device"
            case .failed: "Save failed"
            }
        }
        var message: String {
            if case let .failed(message) = self { return message + "\nYour current text is still in memory. Retry, save the project to Files, or export the current file." }
            return label
        }
        var symbol: String {
            switch self {
            case .unsaved: "circle.dotted"
            case .saving: "arrow.trianglehead.2.clockwise"
            case .saved: "checkmark.circle"
            case .failed: "exclamationmark.triangle"
            }
        }
    }
    enum ProjectTransfer: Equatable {
        case idle
        case openingFiles
        case importingGitHub(String)
        case ready(String)
        case failed(String)

        var isWorking: Bool {
            switch self {
            case .openingFiles, .importingGitHub: true
            default: false
            }
        }

        /// Only failures still deserve a row above the editor.
        var isFailure: Bool {
            if case .failed = self { return true }
            return false
        }
    }

    enum Activity: Equatable {
        case idle
        case checking
        case building
        case running
        case testing
        case formatting

        var label: String {
            switch self {
            case .idle: "Ready"
            case .checking: "Checking the current project…"
            case .building: "Compiling locally · main is not run…"
            case .running: "Compiling and running locally…"
            case .testing: "Testing the selected Rust entry locally…"
            case .formatting: "Formatting Rust locally…"
            }
        }
    }

    enum Stage: Int, CaseIterable, Identifiable {
        case diagnostic
        case explanation
        case practice
        case repair

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .diagnostic: "Diagnostic"
            case .explanation: "Understand"
            case .practice: "Practice"
            case .repair: "Repair"
            }
        }
    }

    @Published var source = RustSamples.runnable {
        didSet { workspaceDidChange() }
    }
    @Published private(set) var projectID: UUID
    @Published private(set) var projectName = "hello-crabrix"
    @Published private(set) var projectDescription = ""
    @Published private(set) var projectTags: [String] = []
    @Published private(set) var projectFolder: String?
    @Published private(set) var projectKind: CrabrixProject.Kind = .general
    @Published private(set) var projectIsFavorite = false
    @Published private(set) var fileNames = ["main.rs"]
    @Published private(set) var selectedFile = "main.rs"
    @Published private(set) var activity: Activity = .idle
    @Published private(set) var isCompilerDraining = false
    @Published private(set) var result: CompilationResult?
    @Published private(set) var unitTestReport: RustUnitTestReport?
    @Published private(set) var toolchain: ToolchainStatus
    @Published private(set) var completedStages: Set<Stage> = []
    @Published private(set) var practiceCompleted = false
    @Published private(set) var completedLessonIDs: Set<String>
    @Published private(set) var lessonAnswerIndices: [String: Int]
    @Published private(set) var activeLessonID: String?
    private var activeLessonContent: CourseLessonExecution?
    var activeLessonHint: CourseHintSnapshot? {
        guard let content = activeLessonContent,
              let hint = content.hint,
              !hint.isEmpty else { return nil }
        return CourseHintSnapshot(sessionToken: content.sessionToken, text: hint)
    }
    @Published private(set) var activeLessonIsReview = false
    @Published private(set) var projectTransfer: ProjectTransfer = .idle
    @Published private(set) var gitState: GitState?
    @Published private(set) var gitAvailable = false
    @Published private(set) var gitIsWorking = false
    @Published private(set) var gitLocksWorkspace = false
    @Published private(set) var gitActivity = ""
    @Published private(set) var gitMessage = ""
    @Published private(set) var gitHistory: [GitCommit] = []
    @Published private(set) var gitBranches: [String] = []
    @Published private(set) var gitDiff: GitDiff?
    @Published private(set) var gitRemote: GitRemoteState?
    @Published private(set) var gitCredentialUsername: String?
    @Published private(set) var gitArchiveURL: URL?
    private var gitArchiveRevision: WorkspaceRevision?
    @Published private(set) var gitRevisionTree: GitTreeSnapshot?
    @Published var gitViewingCommit: GitCommit?
    @Published var gitRestorePreview: GitRestorePreview?
    @Published private(set) var gitConsoleEvent: GitConsoleEvent?
    private var gitObservedGeneration: UInt64?
    private var gitJob: Task<Void, Never>?
    private var gitJobProjectID: UUID?
    private lazy var gitStore = GitRepositoryStore(root: projectLibrary.gitStorageURL)
    private let gitCredentialVault = GitCredentialVault()
    private var projectResourceDigest: String?
    private enum PendingGitURL { case project(URL), playground(PlaygroundLink) }
    private var pendingGitURL: PendingGitURL?

    var gitNeedsRefresh: Bool { gitState != nil && gitObservedGeneration != workspaceGeneration }
    var gitArchiveIsCurrent: Bool { gitArchiveURL != nil && gitArchiveRevision.map(isCurrent) == true }
    var gitCanSwitchBranch: Bool { gitState?.head != nil && gitState?.changes.isEmpty == true && !gitNeedsRefresh && playgroundSession == nil }
    @Published private(set) var compatibilityReport: ProjectCompatibilityReport
    @Published private(set) var provenance: CrabrixProject.Provenance?
    @Published private(set) var recentProjects: [ProjectLibraryItem] = []
    @Published private(set) var allProjects: [ProjectLibraryItem] = []
    @Published private(set) var projectReadFailures: [ProjectReadFailure] = []
    @Published private(set) var lastBuild: ProjectBuildRecord?
    @Published private(set) var saveState: SaveState = .unsaved
    @Published private(set) var cargoStage: CargoPreparationStage = .idle
    @Published private(set) var packageTransfers: [PackageTransferRow] = []
    @Published var isPackageProgressPresented = false
    @Published private(set) var buildEvents: [BuildStageEvent] = []
    @Published private(set) var debugActive = false
    @Published private(set) var debugPause: RustDebugPause?
    @Published private(set) var debugSites: [RustDebugSite] = []
    @Published private(set) var debugBreakpoints: Set<RustDebugBreakpoint> = []
    private var debugSession: RustDebugSession?
    private let typeScriptChecker = BrowserTypeScriptChecker()
    private var typeScriptCheckPending = false
    private var debugSessionID: UUID?

    func toggleDebugBreakpoint(file: String, line: Int) {
        guard line > 0 else { return }
        let value = RustDebugBreakpoint(file: file, line: line)
        if debugBreakpoints.contains(value) { debugBreakpoints.remove(value) } else { debugBreakpoints.insert(value) }
        debugSession?.updateBreakpoints(debugBreakpoints)
    }
    func resumeDebug(_ command: RustDebugSession.Command) { debugPause = nil; if playgroundRuntime?.working == true { playgroundRuntime?.resumeLocal(command) } else { debugSession?.resume(command) } }
    func pauseDebug() { debugSession?.requestPause() }
    func debug() {
        guard compilerProjectSnapshot(from: projectSnapshot()).entryPath.hasSuffix(".rs") else { result = .failure(phase: .setup, detail: "Debug is available for Rust source projects. Browser projects use normal Run and their Web Preview console."); return }
        startBuild(.running, debugging: true)
    }
    private var packageProgressWasPresented = false
    private var packageTransferID: UUID?

    private func appendBuildStage(_ label: String) {
        guard buildEvents.last?.label != label else { return }
        buildEvents.append(BuildStageEvent(label: label))
        if buildEvents.count > 200 { buildEvents.removeFirst(buildEvents.count - 200) }
    }
    @Published private(set) var cargoWorkspace: CargoWorkspaceSnapshot = .empty
    @Published var cargoFeatureProposal: CargoFeatureProposal?
    @Published private(set) var cargoStorage: CrateStorageUsage = CrateStorageUsage()
    @Published private(set) var diagnosticAdviceState: RustDiagnosticAdviceState = .idle
    @Published private(set) var lessonEvidenceMessage: String?
    @Published private(set) var lessonAttemptEvidence: [LessonAttemptEvidence] = []
    @Published var isPracticePresented = false
    private(set) var repairRewardEventKey: String?

    private let compiler: WasmRustCompiler
    private let githubImporter: GitHubProjectImporter
    private let projectLibrary: ProjectLibrary
    private let packageManager: CargoPackageManager
    /// The manifest text the current `cargoWorkspace` was resolved from.
    private var resolvedManifestSource: String?
    private var resolvedWorkspaceRevision: WorkspaceRevision?
    private var cargoTask: Task<Void, Never>?
    private var unresolvedDiagnosticEvidence: (signature: String, beforeHash: String)?
    private var activeLessonInitialSourceTreeHash: String?
    private var activeLessonObservedDiagnosticCodes: Set<String> = []
    @Published private(set) var playgroundSession: PlaygroundLiveSession?
    @Published private(set) var playgroundRuntime: PlaygroundRuntimeHost?
    @Published private(set) var playgroundStatus = ""
    @Published private(set) var playgroundLocalSelection: PlaygroundRemoteSelection?
    @Published private(set) var playgroundSelections: [PlaygroundRemoteSelection] = []
    private var isApplyingPlayground = false
    var playgroundIsReadOnly: Bool { playgroundSession.map { $0.link.isReadOnly || $0.expired } ?? false }
    private var fileContents = ["main.rs": RustSamples.runnable]
    private var entryFile = "main.rs"
    private var compilationTask: Task<Void, Never>?
    private var activeCompilationID: UUID?
    private var diagnosticAdviceTask: Task<Void, Never>?
    private var diagnosticAdviceRevision: WorkspaceRevision?
    private var autosaveTask: Task<Void, Never>?
    private var autosaveRequestID: UUID?
    private var saveQueue: Task<Void, Never>?
    private var latestProjectSnapshots: [UUID: CrabrixProject] = [:]
    private let formatter = RustFormatter()
    private struct FormatUndo {
        let projectID: UUID
        let files: [String: String]
        let generation: UInt64
    }
    private var formatUndo: FormatUndo?
    private var semanticUndo: FormatUndo?

    var canUndoSymbolChanges: Bool {
        !isBusy && !isCompilerDraining && !isProjectOperationInProgress && !playgroundIsReadOnly
            && semanticUndo?.projectID == projectID && semanticUndo?.generation == workspaceGeneration
    }

    var canUndoFormatting: Bool {
        !isBusy && !isCompilerDraining && !playgroundIsReadOnly
            && formatUndo?.projectID == projectID && formatUndo?.generation == workspaceGeneration
    }
    private var suppressAutosave = false
    private(set) var workspaceGeneration: UInt64 = 0
    private let userDefaults: UserDefaults

    private static let completedLessonsKey = "crabrix.learn.completedLessonIDs"
    private static let lessonAnswersKey = "crabrix.learn.lessonAnswerIndices"
    private static let lessonEvidenceKey = "crabrix.learn.attemptEvidence.v1"
    private static let appleIntelligenceDiagnosticsKey = "crabrix.appleIntelligenceDiagnostics"

    init(
        compiler: WasmRustCompiler = WasmRustCompiler(),
        githubImporter: GitHubProjectImporter = GitHubProjectImporter(),
        projectLibrary: ProjectLibrary = ProjectLibrary(),
        packageManager: CargoPackageManager = CargoPackageManager(),
        userDefaults: UserDefaults = .standard
    ) {
        self.compiler = compiler
        self.githubImporter = githubImporter
        #if DEBUG || CRABRIX_LEGACY_FIXTURES
        if ProcessInfo.processInfo.arguments.contains("--crabrix-auto-save-failure-fixture") {
            let blocker = FileManager.default.temporaryDirectory.appending(path: "CrabrixSaveFailure-\(UUID().uuidString)")
            try? Data("injected storage failure".utf8).write(to: blocker)
            self.projectLibrary = ProjectLibrary(storageURL: blocker.appending(path: "recent.json"))
        } else { self.projectLibrary = projectLibrary }
        #else
        self.projectLibrary = projectLibrary
        #endif
        self.packageManager = packageManager
        self.userDefaults = userDefaults
        completedLessonIDs = Set(userDefaults.stringArray(forKey: Self.completedLessonsKey) ?? [])
        lessonAnswerIndices = (userDefaults.dictionary(forKey: Self.lessonAnswersKey) ?? [:])
            .compactMapValues { ($0 as? NSNumber)?.intValue }
        lessonAttemptEvidence = userDefaults.data(forKey: Self.lessonEvidenceKey)
            .flatMap { try? JSONDecoder().decode([LessonAttemptEvidence].self, from: $0) }
            ?? []
        toolchain = compiler.probe()
        let initialProjectID = UUID()
        projectID = initialProjectID
        let initialProject = CrabrixProject(
            id: initialProjectID,
            name: "hello-crabrix",
            files: ["main.rs": RustSamples.runnable],
            entryFile: "main.rs",
            provenance: nil
        )
        compatibilityReport = ProjectCompatibilityReport.scan(initialProject)
        provenance = nil
        lastBuild = nil
        Task {
            await reloadProjectLists()
        }
    }

    var isBusy: Bool { activity != .idle || playgroundRuntime?.working == true }
    var earnsProgressForCurrentRun: Bool { !activeLessonIsReview && result?.isSharedSourceExecution != true }
    var canContinueFromLessonResult: Bool {
        guard let activeLessonID else { return false }
        return completedLessonIDs.contains(activeLessonID)
    }
    var canStartBuild: Bool {
        !isBusy && !gitIsWorking
            && !isProjectOperationInProgress
            && !isCompilerDraining
            && !diagnosticAdviceState.isWorking
            && (toolchain.isReady || BrowserProjectConfiguration.isBrowserEntry(entryFile))
    }
    var primaryDiagnostic: RustDiagnostic? {
        result?.diagnostics.first(where: { $0.level == "error" })
            ?? result?.diagnostics.first
    }
    var cargoManifest: CargoManifest? {
        var files = fileContents
        files[selectedFile] = source
        return files["Cargo.toml"].flatMap(CargoManifest.parse)
    }

    var isProjectOperationInProgress: Bool { projectTransfer.isWorking || gitLocksWorkspace }
    var isBrowserProject: Bool { BrowserProjectConfiguration.isBrowserEntry(entryFile) }
    var browserManifestPath: String? {
        guard isBrowserProject else { return nil }
        let path = BrowserProjectConfiguration.manifestPath(files: fileContents, entry: entryFile)
        return fileContents[path] == nil ? nil : path
    }

    var workspaceRevision: WorkspaceRevision {
        WorkspaceRevision.capture(
            project: currentProject(),
            generation: workspaceGeneration,
            toolchainID: ProjectExecutionProfile.identity,
            resourceTreeHash: projectResourceDigest
        )
    }

    /// True only while the workspace is running a lesson's project. A personal
    /// project is not part of the course, so it gets no "continue learning" step.
    var isLessonContext: Bool { activeLessonID != nil }

    func exportProject() -> CrabrixProject {
        currentProject()
    }

    var semanticGeneration: UInt64 { workspaceGeneration }

    var preflightRefreshKey: String {
        "\(projectID):\(workspaceGeneration):\(lastBuild?.finishedAt.timeIntervalSince1970 ?? 0):\(cargoStage.label)"
    }

    func preflightInput(browserDirectory: String? = nil) -> ProjectPreflight.Input {
        let project = currentProject(), revision = workspaceRevision
        return .init(project: project, revision: revision, workspace: cargoWorkspace,
                     graphIsCurrent: resolvedWorkspaceRevision == revision && resolvedManifestSource == project.files["Cargo.toml"],
                     lastBuild: lastBuild, browserDirectory: browserDirectory)
    }

    func semanticContext() throws -> RustSemanticContext {
        guard !isBusy, !isCompilerDraining, !isProjectOperationInProgress, !cargoStage.isWorking else {
            throw RustSemanticError.unavailable("Wait for the current project operation before requesting Rust analysis.")
        }
        let project = currentProject()
        var plan = CargoBuildPlan.empty
        if let manifest = project.files["Cargo.toml"] {
            let parsed = try CratePackageManifest.parse(manifest)
            guard !parsed.isVirtualWorkspace else { throw RustSemanticError.unavailable("Select a prepared package before requesting semantic analysis of a workspace.") }
            guard !parsed.isProcMacro, parsed.buildScriptPath == nil,
                  parsed.buildScriptDisabled || project.files["build.rs"] == nil else {
                throw RustSemanticError.unavailable("This package uses a procedural-macro target or generated-source build graph outside semantic analysis. Compiler Check remains separate.")
            }
            if resolvedManifestSource == manifest, cargoWorkspace.lockfile == project.files["Cargo.lock"] {
                plan = cargoWorkspace.plan
            } else if !parsed.dependencies.isEmpty || !parsed.features.isEmpty {
                throw RustSemanticError.unavailable("Prepare the current Cargo graph first so analysis uses its exact features and dependencies. Analysis never downloads packages.")
            }
        }
        return RustSemanticContext(project: project, revision: workspaceRevision,
                                   edition: rootEdition(from: project.files["Cargo.toml"]), plan: plan)
    }

    @discardableResult
    func applySemanticProposal(_ proposal: RustSemanticProposal, expected: WorkspaceRevision,
                               applyToEditor: ((UUID, String, String, String) -> Bool)? = nil) -> Bool {
        guard isCurrent(expected), !isBusy, !isCompilerDraining, !isProjectOperationInProgress, !playgroundIsReadOnly,
              currentProject().files == proposal.before else { return false }
        do {
            try ProjectFilePolicy.validate(proposal.after, entryFile: entryFile)
            if playgroundSession != nil {
                _ = try playgroundDocument(files: proposal.after)
            }
            applyFormattedFiles(proposal.after, applyToEditor: applyToEditor)
            semanticUndo = FormatUndo(projectID: projectID, files: proposal.before, generation: workspaceGeneration)
            return true
        } catch { return false }
    }

    @discardableResult
    func undoSymbolChanges() -> Bool {
        guard canUndoSymbolChanges, let undo = semanticUndo else { return false }
        do {
            try ProjectFilePolicy.validate(undo.files, entryFile: entryFile)
            if playgroundSession != nil {
                _ = try playgroundDocument(files: undo.files)
            }
            applyFormattedFiles(undo.files, applyToEditor: nil)
            semanticUndo = nil
            return true
        } catch { return false }
    }

    func openProject(from url: URL) async {
        if gitLocksWorkspace { pendingGitURL = .project(url); return }
        if url.pathExtension.lowercased() == "crabrixrepo" { await importGitRepository(from: url); return }
        guard prepareForProjectSwitch() else { return }
        let revision = workspaceRevision
        projectTransfer = .openingFiles
        do {
            let project = try await Task.detached {
                if url.pathExtension.lowercased() == "zip" {
                    try CrabrixProjectArchive.load(from: url)
                } else {
                    try LocalProjectLoader.load(from: url, provenance: .files())
                }
            }.value
            guard isCurrent(revision) else { return }
            loadProject(project)
            projectTransfer = .ready("Opened \(project.files.count) files from Files.")
        } catch {
            guard isCurrent(revision) else { return }
            projectTransfer = .failed(error.localizedDescription)
        }
    }

    @discardableResult
    func importGitHub(_ rawURL: String) async -> Bool {
        guard prepareForProjectSwitch() else { return false }
        let revision = workspaceRevision
        let label = (try? GitHubRepositoryReference.parse(rawURL))
            .map { "\($0.owner)/\($0.repository)" } ?? "repository"
        projectTransfer = .importingGitHub(label)
        do {
            let project = try await githubImporter.importProject(from: rawURL)
            guard isCurrent(revision) else { return false }
            loadProject(project)
            projectTransfer = .ready("Imported \(project.files.count) files from GitHub.")
            return true
        } catch {
            guard isCurrent(revision) else { return false }
            projectTransfer = .failed(error.localizedDescription)
            return false
        }
    }

    func consumePendingSharedImport() async {
        guard !isProjectOperationInProgress else { return }
        guard let rawURL = SharedImportQueue.dequeue() else { return }
        if let link = try? PlaygroundLink.parse(rawURL) { await openPlayground(link) }
        else { await importGitHub(rawURL) }
    }

    private func playgroundDocument(files proposedFiles: [String: String]? = nil) throws -> PlaygroundDocument {
        let project = currentProject()
        // Packages and generated outputs are never uploaded. Unsupported source
        // types fail explicitly instead of silently sharing an incomplete project.
        var files = PlaygroundLocalFiles.sharedFiles(in: proposedFiles ?? project.files)
        let shared = playgroundSession?.document
        if let shared, shared.files["Cargo.toml"] == nil,
           let generated = shared.nativeFiles["Cargo.toml"], files["Cargo.toml"] == generated {
            files.removeValue(forKey: "Cargo.toml")
        }
        let edition = files["Cargo.toml"] == nil ? (shared?.edition ?? "2024") : (cargoManifest?.edition ?? shared?.edition ?? "2024")
        return try PlaygroundDocument(name: shared?.name ?? project.name, entryFile: project.entryFile, files: files, edition: edition, origin: shared?.origin).validated()
    }

    func createPlayground(lifetimeSeconds: Int) async throws {
        if playgroundSession != nil { return }
        let revision = projectID
        let connection = try await PlaygroundLiveSession.create(document: playgroundDocument(), lifetimeSeconds: lifetimeSeconds)
        guard revision == projectID else { connection.stop(); throw PlaygroundFailure("The active project changed. Share it again from its settings.") }
        attachPlayground(connection, needsInitialProject: false)
        try connection.replace(playgroundDocument())
        connection.start()
    }

    func openPlayground(_ link: PlaygroundLink) async {
        if gitLocksWorkspace { pendingGitURL = .playground(link); return }
        if playgroundSession?.link == link, playgroundSession?.expired == false { return }
        guard prepareForProjectSwitch() else { return }
        guard link.expiresAt > Date() else { projectTransfer = .failed("This temporary Playground has expired."); return }
        do {
            let connection = try PlaygroundLiveSession(link: link)
            projectTransfer = .openingFiles
            attachPlayground(connection, needsInitialProject: true)
            connection.start()
        } catch { projectTransfer = .failed(error.localizedDescription) }
    }

    private func attachPlayground(_ connection: PlaygroundLiveSession, needsInitialProject: Bool) {
        playgroundRuntime?.stop(); playgroundRuntime = nil
        playgroundSession?.stop()
        playgroundSession = connection
        playgroundStatus = connection.status
        var initial = needsInitialProject
        var sharedName = connection.document?.name
        connection.onDocument = { [weak self, weak connection] value in
            guard let self, let connection, playgroundSession === connection else { return }
            let sharedNameChanged = sharedName != nil && sharedName != value.name
            sharedName = value.name
            isApplyingPlayground = true
            defer { isApplyingPlayground = false }
            if initial {
                initial = false
                loadProject(name: value.name, files: value.nativeFiles, entryFile: value.entryFile, projectDescription: "Local copy of a temporary Crabrix Playground. The link expires; this device copy remains available.")
                projectTransfer = .ready("Decrypted Playground · saved a local source copy. Run when ready.")
            } else {
                var existing = fileContents; existing[selectedFile] = source
                let incoming: [String: String]
                do { incoming = try PlaygroundLocalFiles.merging(value, into: existing) }
                catch {
                    leavePlayground()
                    playgroundStatus = "Disconnected · existing local files retained"
                    projectTransfer = .failed("The shared update could not fit this local project: \(error.localizedDescription) Existing local files are unchanged.")
                    return
                }
                guard existing != incoming || sharedNameChanged || entryFile != value.entryFile else { return }
                if debugActive { cancelBuild() }
                let oldSelection = selectedFile
                suppressAutosave = true
                fileContents = incoming; fileNames = incoming.keys.sorted(by: projectFileOrder)
                if sharedNameChanged { projectName = value.name }; entryFile = value.entryFile
                selectedFile = incoming[oldSelection] == nil ? value.entryFile : oldSelection
                source = incoming[selectedFile] ?? ""
                suppressAutosave = false
                workspaceGeneration &+= 1
                scheduleAutosave()
            }
        }
        connection.onSelections = { [weak self, weak connection] values in
            guard let self, playgroundSession === connection else { return }
            playgroundSelections = values
        }
        connection.onLocalSelection = { [weak self] value in self?.playgroundLocalSelection = value }
        connection.onStatus = { [weak self, weak connection] value in
            guard let self, playgroundSession === connection else { return }
            playgroundStatus = value
            if case .openingFiles = projectTransfer, !value.hasPrefix("Connected") {
                // A failing join remains recoverable; the existing project is intact.
                if value.contains("expired") || value.hasPrefix("Reconnecting") { projectTransfer = .failed(value) }
            }
        }
        let runtime = PlaygroundRuntimeHost(session: connection, compiler: compiler, localState: { [weak self] in
            guard let self else { return ("detached", false, true) }
            return (projectID.uuidString, toolchain.isReady, compiler.hasPendingInvocations || activity != .idle || gitIsWorking || isProjectOperationInProgress || isCompilerDraining || diagnosticAdviceState.isWorking)
        }, onResult: { [weak self, weak connection] value in
            guard let self, playgroundSession === connection else { return }
            receiveSharedRuntimeResult(value)
        })
        runtime.onDebug = { [weak self, weak connection] session, sites, pause in
            guard let self, playgroundSession === connection else { return }
            debugSession = session; debugActive = session != nil; debugPause = pause
            if let sites { debugSites = sites }
        }
        runtime.onStage = { [weak self, weak connection] label in
            guard let self, playgroundSession === connection else { return }
            if label.hasPrefix("Shared ") { buildEvents = []; result = nil; unitTestReport = nil }
            appendBuildStage(label)
        }
        runtime.onChange = { [weak self] in self?.objectWillChange.send() }
        playgroundRuntime = runtime
    }

    func receiveSharedRuntimeResult(_ value: CompilationResult) {
        result = CompilationResult(succeeded: value.succeeded, phase: value.phase, exitCode: value.exitCode, diagnostics: value.diagnostics,
            stdout: value.stdout, stderr: value.stderr, duration: value.duration, detail: value.detail + "\nShared source only · local execution · no saved-project build evidence", isSharedSourceExecution: true)
    }

    func leavePlayground() {
        playgroundRuntime?.stop(); playgroundRuntime = nil
        playgroundSession?.stop(); playgroundSession = nil; playgroundSelections = []; playgroundLocalSelection = nil; playgroundStatus = ""
    }

    func sharePlaygroundSelection(file: String, range: NSRange) {
        guard file == selectedFile else { return }
        playgroundSession?.select(file: file, range: range)
    }


    func markProjectSaved(_ exported: CrabrixProject? = nil) {
        // Export completion must never save an older exported copy over newer
        // edits, or mark a different workspace as durably saved.
        let exported = exported ?? currentProject()
        guard exported == currentProject() else { return }
        projectTransfer = .ready("Saved \(exported.name) to Files.")
    }

    func retryProjectSave() async {
        autosaveTask?.cancel()
        await remember(currentProject(), lastBuild: lastBuild)
    }

    func recoveryArchive(projectID: UUID) async throws -> URL { try await projectLibrary.recoveryArchive(projectID: projectID) }

    @discardableResult
    func updateCurrentProjectDetails(
        name rawName: String,
        description: String,
        tags: [String],
        folder: String?,
        kind: CrabrixProject.Kind,
        isFavorite: Bool
    ) async -> Bool {
        let name = Self.normalizedProjectName(rawName)
        guard !name.isEmpty else {
            projectTransfer = .failed("Enter a project name.")
            return false
        }
        autosaveTask?.cancel()
        var project = currentProject()
        project.name = name
        project.projectDescription = description
            .trimmingCharacters(in: .whitespacesAndNewlines)
        project.tags = CrabrixProject.normalizedTags(tags)
        project.folder = CrabrixProject.normalizedFolder(folder)
        project.kind = kind
        project.isFavorite = isFavorite
        projectName = project.name
        projectDescription = project.projectDescription
        projectTags = project.tags
        projectFolder = project.folder
        projectKind = project.kind
        projectIsFavorite = project.isFavorite
        workspaceGeneration &+= 1
        latestProjectSnapshots[projectID] = currentProject()
        saveState = .unsaved
        await remember(currentProject(), lastBuild: lastBuild)
        if case .saved = saveState { projectTransfer = .ready("Updated project details."); return true }
        return false
    }

    func toggleFavorite(projectID: UUID) async {
        if projectID == self.projectID {
            projectIsFavorite.toggle()
            workspaceDidChange()
            await retryProjectSave()
            return
        }
        guard let item = allProjects.first(where: { $0.id == projectID }) else { return }
        var project = item.project
        project.isFavorite.toggle()
        _ = try? await projectLibrary.update(
            project: project,
            lastBuild: item.lastBuild
        )
        if projectID == self.projectID {
            projectIsFavorite = project.isFavorite
        }
        await reloadProjectLists()
    }

    /// Updates organization metadata for any saved project without opening it
    /// or moving it to the top of Recent. ProjectID remains unchanged even when
    /// the display name or folder changes.
    @discardableResult
    func updateProjectDetails(
        projectID: UUID,
        name rawName: String,
        description: String,
        tags: [String],
        folder: String?,
        kind: CrabrixProject.Kind,
        isFavorite: Bool
    ) async -> Bool {
        if projectID == self.projectID {
            return await updateCurrentProjectDetails(name: rawName, description: description, tags: tags,
                folder: folder, kind: kind, isFavorite: isFavorite)
        }
        guard let item = allProjects.first(where: { $0.id == projectID }) else {
            projectTransfer = .failed("That project is no longer available.")
            return false
        }
        let name = Self.normalizedProjectName(rawName)
        guard !name.isEmpty else {
            projectTransfer = .failed("Enter a project name.")
            return false
        }

        var project = item.project
        project.name = name
        project.projectDescription = description
            .trimmingCharacters(in: .whitespacesAndNewlines)
        project.tags = CrabrixProject.normalizedTags(tags)
        project.folder = CrabrixProject.normalizedFolder(folder)
        project.kind = kind
        project.isFavorite = isFavorite

        do {
            let saved = try await projectLibrary.update(
                project: project,
                lastBuild: item.lastBuild
            )
            project = saved.project
            if projectID == self.projectID {
                projectName = project.name
                projectDescription = project.projectDescription
                projectTags = project.tags
                projectFolder = project.folder
                projectKind = project.kind
                projectIsFavorite = project.isFavorite
            }
            projectTransfer = .ready("Updated project details.")
            await reloadProjectLists()
            return true
        } catch {
            projectTransfer = .failed(error.localizedDescription)
            return false
        }
    }

    @discardableResult
    func deleteProject(projectID: UUID) async -> Bool {
        if gitJobProjectID == projectID, let job = gitJob { job.cancel(); await job.value }
        if projectID == self.projectID { autosaveTask?.cancel(); autosaveTask = nil }
        if let saveQueue { await saveQueue.value }
        latestProjectSnapshots.removeValue(forKey: projectID)
        do {
            try await projectLibrary.delete(projectID: projectID)
            await reloadProjectLists()
            if projectID == self.projectID {
                loadProject(
                    name: "hello-crabrix",
                    files: ["main.rs": RustSamples.runnable],
                    entryFile: "main.rs"
                )
            }
            return true
        } catch {
            projectTransfer = .failed(error.localizedDescription)
            return false
        }
    }

    func reportProjectFailure(_ error: Error) {
        projectTransfer = .failed(error.localizedDescription)
    }

    @discardableResult
    func openRecentProject(id: UUID) async -> Bool {
        let stoppedBuild = isBusy
        guard prepareForProjectSwitch() else { return false }
        let revision = workspaceRevision
        do {
            guard let item = try await projectLibrary.project(id: id) else { return false }
            guard isCurrent(revision) else { return false }
            loadProject(item.project, lastBuild: item.lastBuild, resourceTreeHash: item.resourceTreeHash)
            projectTransfer = .ready(
                stoppedBuild
                    ? "Stopped the previous build and opened \(item.project.name)."
                    : "Opened recent project \(item.project.name)."
            )
            if let message = item.recoveryMessage { projectTransfer = .failed(message) }
            return true
        } catch {
            guard isCurrent(revision) else { return false }
            projectTransfer = .failed(error.localizedDescription)
            return false
        }
    }

    func check() { startBuild(.checking) }

    func run() { startBuild(.running) }
    func build() { startBuild(.building) }

    func performBrowserCommand(_ command: BrowserProjectCommand) {
        switch command {
        case let .install(frozen, directory): startBuild(.checking, browserDirectory: directory, prepareBrowserPackages: true, frozenBrowserPackages: frozen)
        case let .build(run, directory): startBuild(run ? .running : .building, browserDirectory: directory)
        case let .check(directory): startBuild(.checking, browserDirectory: directory)
        }
    }

    func runUnitTests(_ request: RustUnitTestRequest = .init()) {
        guard canStartBuild else { return }
        unitTestReport = nil
        do { _ = try request.entry(in: currentProject()) }
        catch { result = .failure(phase: .setup, detail: error.localizedDescription); return }
        startBuild(.testing, unitTestRequest: request)
    }

    func formatRust(_ request: RustFormatRequest,
                    applyToEditor: ((UUID, String, String, String) -> Bool)? = nil) {
        guard canStartBuild, !playgroundIsReadOnly else { return }
        unitTestReport = nil
        let snapshot = currentProject()
        let revision = workspaceRevision
        let paths: [String]
        let configuration: String?
        do {
            try ProjectFilePolicy.validate(snapshot.files, entryFile: snapshot.entryFile)
            paths = try request.paths(in: snapshot)
            guard !paths.isEmpty else { throw RustFormatter.Failure.rejected("no project-owned Rust files were selected") }
            let configurations = [".rustfmt.toml", "rustfmt.toml"].compactMap { snapshot.files[$0] }
            guard configurations.count <= 1 else { throw RustFormatter.Failure.configuration("keep one root .rustfmt.toml or rustfmt.toml") }
            configuration = configurations.first
        } catch { result = .failure(phase: .format, detail: error.localizedDescription); return }
        activity = .formatting
        result = nil; unitTestReport = nil; buildEvents = []
        let id = UUID(); activeCompilationID = id
        appendBuildStage(request.checkOnly ? "Checking Rust formatting locally" : "Formatting project-owned Rust source locally")
        let edition = rootEdition(from: snapshot.files["Cargo.toml"])
        compilationTask = Task { [weak self] in
            guard let self else { return }
            let started = ContinuousClock.now
            do {
                var proposed = snapshot.files
                for path in paths {
                    guard !Task.isCancelled, isCurrent(revision), activeCompilationID == id else { discardCompilationIfActive(id); return }
                    appendBuildStage("Rustfmt · \(path)")
                    proposed[path] = try await formatter.format(source: snapshot.files[path]!, edition: edition, configuration: configuration)
                }
                guard !Task.isCancelled, isCurrent(revision), activeCompilationID == id else { discardCompilationIfActive(id); return }
                guard !playgroundIsReadOnly else { throw RustFormatter.Failure.rejected("the shared source became read-only") }
                try ProjectFilePolicy.validate(proposed, entryFile: snapshot.entryFile)
                if playgroundSession != nil {
                    _ = try playgroundDocument(files: proposed)
                }
                let changed = paths.filter { Data(proposed[$0]!.utf8) != Data(snapshot.files[$0]!.utf8) }
                if !request.checkOnly, !changed.isEmpty {
                    applyFormattedFiles(proposed, applyToEditor: applyToEditor)
                    formatUndo = FormatUndo(projectID: projectID, files: snapshot.files, generation: workspaceGeneration)
                }
                let message = request.checkOnly
                    ? (changed.isEmpty ? "Rust formatting check passed." : "\(changed.count) Rust file(s) need formatting; source was kept unchanged.")
                    : (changed.isEmpty ? "Rust source is already formatted." : "Formatted \(changed.count) Rust file(s). Native editor Undo and Undo formatting are available.")
                let breakpoints = debugBreakpoints.filter { changed.contains($0.file) }.count
                let note = breakpoints > 0 && !request.checkOnly ? "\nReview \(breakpoints) existing breakpoint position(s), because formatting can move source lines." : ""
                result = CompilationResult(succeeded: !request.checkOnly || changed.isEmpty, phase: .format,
                    exitCode: request.checkOnly && !changed.isEmpty ? 1 : 0, diagnostics: [],
                    stdout: message + "\n" + RustFormatter.version + note, stderr: "",
                    duration: started.duration(to: .now), detail: message)
                appendBuildStage(message)
                activity = .idle; isCompilerDraining = false; activeCompilationID = nil; compilationTask = nil
            } catch {
                guard activeCompilationID == id else { return }
                if Task.isCancelled || !isCurrent(revision) { discardCompilationIfActive(id); return }
                result = .failure(phase: .format, detail: error.localizedDescription, duration: started.duration(to: .now))
                appendBuildStage("Formatting failed · original source kept")
                activity = .idle; isCompilerDraining = false; activeCompilationID = nil; compilationTask = nil
            }
        }
    }

    func undoFormatting() {
        guard canUndoFormatting, let undo = formatUndo else { return }
        do {
            try ProjectFilePolicy.validate(undo.files, entryFile: entryFile)
            if playgroundSession != nil {
                _ = try playgroundDocument(files: undo.files)
            }
            applyFormattedFiles(undo.files, applyToEditor: nil)
            formatUndo = nil
            result = CompilationResult(succeeded: true, phase: .format, exitCode: 0, diagnostics: [],
                stdout: "Restored the source from before formatting.", stderr: "", duration: .zero,
                detail: "Formatting undone.")
        } catch { result = .failure(phase: .format, detail: error.localizedDescription) }
    }

    private func applyFormattedFiles(_ files: [String: String],
                                     applyToEditor: ((UUID, String, String, String) -> Bool)?) {
        if let replacement = files[selectedFile], Data(replacement.utf8) != Data(source.utf8) {
            let expected = source
            fileContents = files
            _ = applyToEditor?(projectID, selectedFile, expected, replacement)
            if Data(source.utf8) != Data(replacement.utf8) { source = replacement }
        } else {
            fileContents = files
            workspaceDidChange()
        }
    }

    private func startBuild(_ mode: Activity, browserDirectory: String? = nil,
                            prepareBrowserPackages: Bool = false, frozenBrowserPackages: Bool = false,
                            debugging: Bool = false, unitTestRequest: RustUnitTestRequest? = nil) {
        guard canStartBuild else { return }
        do { try ProjectFilePolicy.validate(currentProject().files, entryFile: entryFile) }
        catch { result = .failure(phase: .setup, detail: error.localizedDescription); return }
        if debugging {
            debugActive = true; debugPause = nil; debugSites = []
            let identity = UUID(); debugSessionID = identity
            let session = RustDebugSession(breakpoints: debugBreakpoints, onPlan: { [weak self] sites in
                Task { @MainActor [weak self] in guard let self, debugSessionID == identity else { return }; debugSites = sites }
            }, onPause: { [weak self] snapshot in
                Task { @MainActor [weak self] in guard let self, debugSessionID == identity else { return }; debugPause = snapshot }
            })
            debugSession = session
        }
        resetDiagnosticAdvice()
        let preparationRevision = workspaceRevision
        activity = mode
        playgroundRuntime?.clearSharedOutput()
        result = nil
        unitTestReport = nil
        buildEvents = []
        appendBuildStage(mode == .testing ? "Selected-entry Unit Test requested · not an Academy validator" : mode == .checking ? "Check requested" : mode == .building ? "Build requested · main will not run" : "Run requested")
        var project = projectSnapshot()
        if let unitTestRequest {
            do {
                let snapshot = currentProject()
                let path = try unitTestRequest.entry(in: snapshot)
                var supporting = snapshot.files
                let main = supporting.removeValue(forKey: path)!
                project = (path, main, supporting)
            } catch { activity = .idle; result = .failure(phase: .setup, detail: error.localizedDescription); return }
        }
        var projectFiles = project.supporting
        projectFiles[project.entryPath] = project.main
        let compilerProject = mode == .testing ? project : compilerProjectSnapshot(from: project)
        let manifestSource = manifestSource(in: project)
        let lockfileSource = project.entryPath == "Cargo.lock"
            ? project.main
            : project.supporting["Cargo.lock"]
        let rootEdition = rootEdition(from: manifestSource)
        let compilationID = UUID()
        let inspectionInput = preflightInput(browserDirectory: browserDirectory)
        activeCompilationID = compilationID
        typeScriptCheckPending = mode == .checking && !prepareBrowserPackages
            && (browserDirectory != nil || BrowserProjectConfiguration.isBrowserEntry(project.entryPath))
        compilationTask = Task { [weak self] in
            guard let self else { return }
            guard !Task.isCancelled, activeCompilationID == compilationID, isCurrent(preparationRevision) else {
                discardCompilationIfActive(compilationID); return
            }
            if mode != .testing {
                appendBuildStage("Inspecting the current local execution profile")
                let inspection = await Task.detached(priority: .userInitiated) { ProjectPreflight.inspect(inspectionInput) }.value
                guard !Task.isCancelled, activeCompilationID == compilationID, isCurrent(preparationRevision) else {
                    discardCompilationIfActive(compilationID); return
                }
                let operation: ProjectVerifiedOperation = debugging ? .debug : mode == .checking ? .check : mode == .building ? .build : .run
                if let reason = inspection.blockingReason(for: operation) {
                    finish(.failure(phase: .setup, detail: reason), revision: preparationRevision, isDebugExecution: debugging)
                    return
                }
            }
            let resourceFiles: [String: Data]
            do {
                let store = GitRepositoryStore(root: projectLibrary.gitStorageURL)
                if try await store.resourceIdentity(preparationRevision.projectID) != nil {
                    appendBuildStage("Reading repository resources into a local build snapshot")
                    resourceFiles = try await store.resources(preparationRevision.projectID, files: projectFiles)
                } else { resourceFiles = [:] }
            } catch {
                guard isCurrent(preparationRevision) else { discardCompilationIfActive(compilationID); return }
                finish(.failure(phase: .setup, detail: error.localizedDescription), revision: preparationRevision, recordsLearningEvidence: mode != .testing)
                return
            }
            let resourceDigest = await Task.detached(priority: .userInitiated) { GitRepositoryStore.resourceFingerprint(resourceFiles) }.value
            guard !Task.isCancelled, activeCompilationID == compilationID, isCurrent(preparationRevision) else {
                discardCompilationIfActive(compilationID); return
            }
            projectResourceDigest = resourceDigest
            let revision = workspaceRevision

            if browserDirectory != nil || BrowserProjectConfiguration.isBrowserEntry(project.entryPath) {
                let began = ContinuousClock.now
                let entry = BrowserProjectConfiguration.entry(files: projectFiles, preferred: project.entryPath, directory: browserDirectory)
                let transferID = UUID()
                packageTransferID = transferID
                packageTransfers = []
                packageProgressWasPresented = false
                let stageHandler: @Sendable (String) -> Void = { [weak self] label in
                    Task { @MainActor [weak self] in
                        guard let self, activeCompilationID == compilationID, isCurrent(revision) else { return }
                        appendBuildStage(label)
                    }
                }
                let transferHandler: @Sendable (PackageTransferEvent) -> Void = { [weak self] event in
                    Task { @MainActor [weak self] in
                        guard let self, activeCompilationID == compilationID, isCurrent(revision), packageTransferID == transferID else { return }
                        switch event {
                        case let .planned(rows): packageTransfers = rows
                        case let .updated(id, state):
                            if let index = packageTransfers.firstIndex(where: { $0.package == id }) { packageTransfers[index].state = state }
                            if state == .downloading, !packageProgressWasPresented {
                                packageProgressWasPresented = true
                                isPackageProgressPresented = true
                            }
                        }
                    }
                }
                if prepareBrowserPackages { cargoStage = .resolving }
                do {
                    let built = try await BrowserProjectBuilder.shared.build(files: projectFiles, preferredEntry: entry,
                        preparePackages: prepareBrowserPackages, frozen: frozenBrowserPackages,
                        onStage: stageHandler, onTransfer: transferHandler)
                    guard !Task.isCancelled, activeCompilationID == compilationID, isCurrent(revision) else {
                        discardCompilationIfActive(compilationID); return
                    }
                    if prepareBrowserPackages {
                        // Installation is transactional. A changed project discards the result;
                        // no in-flight download may overwrite a newer editor snapshot.
                        let installedFiles = projectFiles.filter { !$0.key.hasPrefix(built.sourceRemovalPrefix) }
                            .merging(built.sourceAdditions) { _, new in new }
                        try ProjectFilePolicy.validate(installedFiles, entryFile: entryFile)
                        suppressAutosave = true
                        fileContents = installedFiles
                        fileNames = fileContents.keys.sorted(by: projectFileOrder)
                        if fileContents[selectedFile] == nil {
                            selectedFile = fileContents[entryFile] != nil ? entryFile : entry
                        }
                        source = fileContents[selectedFile] ?? ""
                        suppressAutosave = false
                        workspaceGeneration &+= 1
                        cargoStage = .ready
                        // Final edges include shared packages that were already
                        // resolved before another importer reached them.
                        packageTransfers = built.transfers
                        packageTransferID = nil
                    }
                    let preview: WebPreviewSnapshot
                    if resourceFiles.isEmpty { preview = built.preview }
                    else {
                        guard let combined = WebPreviewSnapshot(files: resourceFiles.filter { WebPreviewSnapshot.mimeType(for: $0.key) != nil }.merging(built.preview.assets) { _, built in built }, preferredEntry: built.preview.entryPath) else { throw BrowserBuildError(message: "The browser preview exceeds its asset budget.") }
                        preview = combined
                    }
                    var checkedTypeScript: BrowserTypeScriptResult?
                    if mode == .checking && !prepareBrowserPackages {
                        let directory = BrowserTypeScriptProfile.directory(files: projectFiles, entry: entry)
                        if BrowserTypeScriptProfile.applies(files: projectFiles, directory: directory) {
                            appendBuildStage("Checking TypeScript types locally · \(BrowserTypeScriptProfile.version)")
                        }
                        checkedTypeScript = try await typeScriptChecker.check(files: projectFiles, directory: directory)
                        guard activeCompilationID == compilationID, !Task.isCancelled, isCurrent(revision) else { discardCompilationIfActive(compilationID); return }
                        if let checked = checkedTypeScript, !checked.succeeded {
                            finish(CompilationResult(succeeded: false, phase: .check, exitCode: 1,
                                diagnostics: checked.diagnostics.map { $0.rustDiagnostic(files: projectFiles) }, stdout: "", stderr: "",
                                duration: began.duration(to: .now), detail: "TypeScript \(checked.version) reported type/configuration errors. Missing dependency declarations require explicit package preparation.\(checked.omittedDiagnostics > 0 ? " Additional diagnostics omitted: \(checked.omittedDiagnostics)." : "")"), revision: revision,
                                executionKind: .browser, compilerEntryFile: entry)
                            return
                        }
                    }
                    finish(CompilationResult(succeeded: true, phase: mode == .running ? .run : (mode == .building ? .compile : .check),
                        exitCode: nil, diagnostics: checkedTypeScript?.diagnostics.map { $0.rustDiagnostic(files: projectFiles) } ?? [], stdout: "", stderr: "", duration: began.duration(to: .now),
                        detail: prepareBrowserPackages
                            ? "Prepared \(built.packageCount) browser npm packages as editable local source. Run now builds offline."
                            : checkedTypeScript?.checked == true
                            ? "TypeScript \(BrowserTypeScriptProfile.version) checked \(checkedTypeScript!.roots) source entries locally; bundled \(built.moduleCount) browser modules. Browser runtime errors remain separate in the Web Preview console."
                            : "Built \(built.moduleCount) browser modules locally. TypeScript syntax is transpiled; this is not TypeScript type checking. Browser errors appear in the web console.",
                        webPreview: mode == .running ? preview : nil), revision: workspaceRevision,
                        browserTypeCheckVersion: checkedTypeScript?.checked == true ? BrowserTypeScriptProfile.version : nil,
                        executionKind: .browser, compilerEntryFile: entry)
                    if prepareBrowserPackages { await remember(currentProject(), lastBuild: lastBuild) }
                } catch {
                    guard activeCompilationID == compilationID, isCurrent(revision) else { discardCompilationIfActive(compilationID); return }
                    if Task.isCancelled || error is CancellationError { discardCompilationIfActive(compilationID); return }
                    cargoStage = .failed(error.localizedDescription)
                    let browserError = error as? BrowserBuildError
                    let path = browserError?.file ?? ""
                    let line = max(1, browserError?.line ?? 1), column = max(1, browserError?.column ?? 1)
                    let lines = (projectFiles[path] ?? "").components(separatedBy: "\n")
                    let span: [RustDiagnostic.Span] = path.isEmpty ? [] : [.init(fileName: path, lineStart: line, lineEnd: line,
                        columnStart: column, columnEnd: column + 1, isPrimary: true, label: nil,
                        sourceLine: line <= lines.count ? lines[line - 1] : "")]
                    finish(CompilationResult(succeeded: false, phase: .compile, exitCode: nil,
                        diagnostics: [.init(level: "error", message: browserError?.message ?? error.localizedDescription,
                            code: nil, rendered: error.localizedDescription, spans: span)],
                        stdout: "", stderr: "", duration: began.duration(to: .now), detail: error.localizedDescription), revision: revision,
                        executionKind: .browser, compilerEntryFile: entry)
                }
                return
            }

            var plan = CargoBuildPlan.empty
            if let manifestSource {
                do {
                    let snapshot = try await resolveWorkspace(
                        manifestSource: manifestSource,
                        lockfileSource: lockfileSource,
                        projectFiles: projectFiles, resourceFiles: resourceFiles,
                        revision: revision
                    )
                    guard activeCompilationID == compilationID, isCurrent(revision) else {
                        discardCompilationIfActive(compilationID)
                        return
                    }
                    if let blocked = snapshot.blockingPackages.first {
                        finish(
                            .failure(
                                phase: .setup,
                                detail: "\(blocked.name) \(blocked.version) cannot be built locally: "
                                    + (blocked.compatibility.detail ?? "unsupported package")
                            ),
                            revision: revision, recordsLearningEvidence: mode != .testing
                        )
                        return
                    }
                    plan = snapshot.plan
                } catch {
                    guard activeCompilationID == compilationID, isCurrent(revision) else {
                        discardCompilationIfActive(compilationID)
                        return
                    }
                    cargoStage = .failed(error.localizedDescription)
                    finish(
                        .failure(
                            phase: .setup,
                            detail: "Dependency resolution failed: \(error.localizedDescription)"
                        ),
                        revision: revision, recordsLearningEvidence: mode != .testing
                    )
                    return
                }
            }

            let progress: @Sendable (CargoBuildProgress) -> Void = { [weak self] update in
                Task { @MainActor [weak self] in
                    guard let self,
                          activeCompilationID == compilationID,
                          isCurrent(revision)
                    else { return }
                    cargoStage = update.wasCached
                        ? .building(
                            name: "\(update.package.name) (cached)",
                            index: update.index,
                            total: update.total
                        )
                        : .building(
                            name: update.package.name,
                            index: update.index,
                            total: update.total
                        )
                    appendBuildStage("\(update.wasCached ? "Cached" : "Compiling") \(update.package) · \(update.index)/\(update.total)")
                }
            }

            let stageHandler: @Sendable (String) -> Void = { [weak self] label in
                Task { @MainActor [weak self] in
                    guard let self, activeCompilationID == compilationID, isCurrent(revision) else { return }
                    appendBuildStage(label)
                }
            }

            var value = switch mode {
            case .testing:
                await testSnapshot(compilerProject, resourceFiles: resourceFiles, request: unitTestRequest ?? .init(), edition: rootEdition,
                    plan: plan, revision: revision, compilationID: compilationID, onStage: stageHandler)
            case .building:
                await compiler.build(source: compilerProject.main, sourcePath: compilerProject.entryPath,
                    supportingFiles: compilerProject.supporting, resourceFiles: resourceFiles, edition: rootEdition, plan: plan,
                    onDependencyProgress: plan.isEmpty ? nil : progress, onStage: stageHandler)
            case .checking:
                await compiler.check(
                    source: compilerProject.main,
                    sourcePath: compilerProject.entryPath,
                    supportingFiles: compilerProject.supporting, resourceFiles: resourceFiles,
                    edition: rootEdition,
                    plan: plan,
                    onDependencyProgress: plan.isEmpty ? nil : progress,
                    onStage: stageHandler
                )
            default:
                if let debugSession {
                    await compiler.debug(source: compilerProject.main, sourcePath: compilerProject.entryPath,
                        supportingFiles: compilerProject.supporting, resourceFiles: resourceFiles, edition: rootEdition, plan: plan, session: debugSession,
                        onDependencyProgress: plan.isEmpty ? nil : progress, onStage: stageHandler)
                } else { await compiler.run(
                    source: compilerProject.main,
                    sourcePath: compilerProject.entryPath,
                    supportingFiles: compilerProject.supporting, resourceFiles: resourceFiles,
                    edition: rootEdition,
                    plan: plan,
                    onDependencyProgress: plan.isEmpty ? nil : progress,
                    onStage: stageHandler
                ) }
            }

            guard !Task.isCancelled,
                  activeCompilationID == compilationID,
                  isCurrent(revision)
            else {
                discardCompilationIfActive(compilationID)
                return
            }
            if value.succeeded, let preview = value.webPreview {
                var browserFiles = projectFiles
                for (path, data) in preview.assets {
                    if let text = String(data: data, encoding: .utf8) { browserFiles[path] = text }
                }
                do {
                    let built = try await BrowserProjectBuilder.shared.build(files: browserFiles, preferredEntry: preview.entryPath,
                        onStage: stageHandler)
                    guard !Task.isCancelled, activeCompilationID == compilationID, isCurrent(revision) else { discardCompilationIfActive(compilationID); return }
                    // Keep binary assets captured by the Rust generator too.
                    guard let combined = WebPreviewSnapshot(files: preview.assets.merging(built.preview.assets) { _, compiled in compiled }, preferredEntry: built.preview.entryPath) else {
                        throw BrowserBuildError(message: "The generated browser preview exceeds its asset budget.")
                    }
                    value.webPreview = combined
                } catch {
                    guard activeCompilationID == compilationID, isCurrent(revision) else { discardCompilationIfActive(compilationID); return }
                    value = .failure(phase: .compile, detail: error.localizedDescription, duration: value.duration)
                }
            }
            if !plan.isEmpty { cargoStage = .ready }
            finish(value, revision: revision, recordsLearningEvidence: mode != .testing, isDebugExecution: debugging)
            if mode == .running, plan.isEmpty, resourceFiles.isEmpty {
                var sharedFiles = compilerProject.supporting; sharedFiles[compilerProject.entryPath] = compilerProject.main
                playgroundRuntime?.reportLocalResult(value, entry: compilerProject.entryPath, files: sharedFiles, edition: rootEdition)
            }
            // A build is the only source of verified compatibility, so refresh
            // the package list with whatever the compiler just learned.
            if !plan.isEmpty, let manifestSource {
                resolvedManifestSource = nil
                resolvedWorkspaceRevision = nil
                _ = try? await resolveWorkspace(
                    manifestSource: manifestSource,
                    lockfileSource: lockfileSource,
                    projectFiles: projectFiles,
                    revision: revision
                )
            }
        }
    }

    // MARK: - Cargo

    /// The active project's manifest text, if it has one.
    private func manifestSource(
        in project: (entryPath: String, main: String, supporting: [String: String])
    ) -> String? {
        project.entryPath == "Cargo.toml" ? project.main : project.supporting["Cargo.toml"]
    }

    private func rootEdition(from manifestSource: String?) -> String {
        guard let manifestSource,
              let manifest = try? CratePackageManifest.parse(manifestSource)
        else { return "2024" }
        return manifest.edition
    }

    /// Algorithm learners edit only `solution.rs`. Inputs and expected values
    /// are inserted as an app-private main module for this compilation, so the
    /// editable project cannot pass by copying a literal from its own harness.
    private func compilerProjectSnapshot(
        from project: (entryPath: String, main: String, supporting: [String: String])
    ) -> (entryPath: String, main: String, supporting: [String: String]) {
        guard activeLessonID != nil,
              let challenge = activeLessonContent?.challenge
        else { return project }

        var supporting = project.supporting
        supporting["solution.rs"] = project.main
        supporting.removeValue(forKey: "main.rs")
        return ("main.rs", challenge.verificationSource, supporting)
    }

    var cargoManifestSource: String? {
        var files = fileContents
        files[selectedFile] = source
        return files["Cargo.toml"]
    }

    /// Resolves and downloads, reusing the last snapshot when the manifest text
    /// has not changed.
    @discardableResult
    private func resolveWorkspace(
        manifestSource: String,
        lockfileSource: String?,
        mode: CargoResolutionMode = .normal,
        projectFiles: [String: String],
        resourceFiles providedResources: [String: Data]? = nil,
        revision: WorkspaceRevision
    ) async throws -> CargoWorkspaceSnapshot {
        guard isCurrent(revision) else { throw CancellationError() }
        if resolvedManifestSource == manifestSource,
           resolvedWorkspaceRevision == revision,
           !cargoWorkspace.isEmpty {
            return cargoWorkspace
        }
        let resources: [String: Data]
        if let providedResources { resources = providedResources }
        else {
            let store = GitRepositoryStore(root: projectLibrary.gitStorageURL)
            if try await store.resourceIdentity(revision.projectID) != nil { resources = try await store.resources(revision.projectID, files: projectFiles) }
            else { resources = [:] }
        }
        guard isCurrent(revision), !Task.isCancelled else { throw CancellationError() }
        let transferID = UUID()
        packageTransferID = transferID
        let handler: @Sendable (CargoPreparationStage) -> Void = { [weak self] stage in
            Task { @MainActor [weak self] in
                guard let self, isCurrent(revision), packageTransferID == transferID else { return }
                cargoStage = stage
                if stage.isWorking { appendBuildStage(stage.label) }
            }
        }
        packageProgressWasPresented = false
        packageTransfers = []
        let transferHandler: @Sendable (PackageTransferEvent) -> Void = { [weak self] event in
            Task { @MainActor [weak self] in
                guard let self, isCurrent(revision), packageTransferID == transferID else { return }
                switch event {
                case let .planned(rows): packageTransfers = rows
                case let .updated(id, state):
                    guard let index = packageTransfers.firstIndex(where: { $0.package == id }) else { return }
                    packageTransfers[index].state = state
                    if state == .downloading, !packageProgressWasPresented {
                        packageProgressWasPresented = true
                        isPackageProgressPresented = true
                    }
                }
            }
        }
        let snapshot: CargoWorkspaceSnapshot
        if mode == .normal, lockfileSource != nil {
            // Reopening an already prepared project must not wait for a registry
            // request to time out in airplane mode. Explicit Update still uses
            // the network; only an exact, locally available lock can take this path.
            do {
                snapshot = try await packageManager.prepare(
                    manifestSource: manifestSource, lockfileSource: lockfileSource,
                    mode: .frozen, projectFiles: projectFiles, resourceFiles: resources, onStage: handler, onTransfer: transferHandler)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                snapshot = try await packageManager.prepare(
                    manifestSource: manifestSource, lockfileSource: lockfileSource,
                    mode: mode, projectFiles: projectFiles, resourceFiles: resources, onStage: handler, onTransfer: transferHandler)
            }
        } else {
            snapshot = try await packageManager.prepare(
                manifestSource: manifestSource, lockfileSource: lockfileSource,
                mode: mode, projectFiles: projectFiles, resourceFiles: resources, onStage: handler, onTransfer: transferHandler)
        }
        guard !Task.isCancelled, isCurrent(revision) else { throw CancellationError() }
        cargoWorkspace = snapshot
        resolvedManifestSource = manifestSource
        resolvedWorkspaceRevision = revision
        if let blocked = snapshot.blockingPackages.first {
            cargoStage = .failed("\(blocked.name) \(blocked.version) cannot build with this toolchain")
        } else {
            cargoStage = snapshot.isEmpty ? .idle : .ready
        }
        return snapshot
    }

    /// Explicitly re-resolves the project's dependencies and writes Cargo.lock.
    func refreshCargoWorkspace() {
        guard let manifestSource = cargoManifestSource else {
            cargoWorkspace = .empty
            cargoStage = .idle
            resolvedManifestSource = nil
            resolvedWorkspaceRevision = nil
            return
        }
        let revision = workspaceRevision
        let projectFiles = currentProject().files
        // The editor buffer is authoritative for the selected file. Do not
        // resolve against an older in-memory Cargo.lock while the user is
        // actively editing it.
        let lockfileSource = selectedFile == "Cargo.lock"
            ? source
            : fileContents["Cargo.lock"]
        cargoTask?.cancel()
        cargoTask = Task { [weak self] in
            guard let self else { return }
            do {
                let snapshot = try await resolveWorkspace(
                    manifestSource: manifestSource,
                    lockfileSource: lockfileSource,
                    projectFiles: projectFiles,
                    revision: revision
                )
                if let lockfile = snapshot.lockfile, !snapshot.packages.isEmpty || lockfileSource != nil {
                    writeLockfile(lockfile, expectedRevision: revision)
                }
            } catch is CancellationError {
                return
            } catch {
                guard isCurrent(revision) else { return }
                cargoStage = .failed(error.localizedDescription)
            }
            await refreshCargoStorage()
        }
    }

    /// Records the resolved graph in the project, exactly as `cargo fetch` does,
    /// so the same versions rebuild later and travel with the project.
    private func writeLockfile(
        _ contents: String,
        expectedRevision: WorkspaceRevision
    ) {
        guard !isBusy, isCurrent(expectedRevision) else { return }
        // Sync the editor buffer first so an in-progress edit is not lost.
        fileContents[selectedFile] = source
        guard fileContents["Cargo.lock"] != contents else { return }
        fileContents["Cargo.lock"] = contents
        if selectedFile == "Cargo.lock" {
            source = contents
        } else {
            workspaceDidChange()
        }
        fileNames = fileContents.keys.sorted(by: projectFileOrder)
        let project = currentProject()
        Task { await remember(project, lastBuild: lastBuild) }
    }

    /// Downloads every resolved package so the project builds with no network.
    func downloadDependenciesForOffline() {
        if BrowserProjectConfiguration.isBrowserEntry(entryFile) {
            performBrowserCommand(.install(frozen: false, directory: (BrowserProjectConfiguration.manifestPath(files: currentProject().files, entry: entryFile) as NSString).deletingLastPathComponent))
            return
        }
        resolvedManifestSource = nil
        resolvedWorkspaceRevision = nil
        refreshCargoWorkspace()
    }

    /// Explicitly moves the exact verified archives for the current lock graph
    /// out of purgeable Caches. Builds may still regenerate source/artifacts,
    /// but they no longer need the network after iOS cache eviction.
    func pinDependenciesForOffline() {
        guard !isBusy, !cargoWorkspace.packages.isEmpty else { return }
        let revision = workspaceRevision
        let packages = cargoWorkspace.packages
        cargoTask?.cancel()
        cargoStage = .downloading(name: "offline archive set", index: 0, total: packages.count)
        cargoTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await packageManager.pinForOffline(packages)
                guard !Task.isCancelled, isCurrent(revision) else { return }
                cargoWorkspace.isOfflinePinned = true
                cargoStage = .ready
                projectTransfer = .ready(
                    "Offline pinned. Cargo.lock and \(packages.count) verified package archives can survive cache eviction."
                )
            } catch is CancellationError {
                return
            } catch {
                guard isCurrent(revision) else { return }
                cargoStage = .failed(error.localizedDescription)
                projectTransfer = .failed(error.localizedDescription)
            }
            await refreshCargoStorage()
        }
    }

    /// Copies every editable source file from the verified registry tree into
    /// `vendor/<name>-<version>` in the current project. The registry cache is
    /// never changed; Cargo planning notices this exact directory and gives the
    /// edited tree a new content fingerprint.
    @discardableResult
    func vendorCrate(name: String, version: SemanticVersion) -> Bool {
        guard !isBusy, !isProjectOperationInProgress else { return false }
        let root = "vendor/\(name)-\(version)"
        let prefix = root + "/"
        fileContents[selectedFile] = source

        if fileContents.keys.contains(where: { $0.hasPrefix(prefix) }) {
            return openVendoredCrate(name: name, version: version)
        }

        do {
            let editable = try CrateSourceBrowser.vendorableFiles(name: name, version: version)
            guard fileContents.count + editable.count <= LocalProjectLoader.maximumFileCount else {
                throw CrateSourceBrowser.VendorError.tooManyEditableFiles
            }
            let existingBytes = fileContents.values.reduce(0) { $0 + $1.utf8.count }
            let patchBytes = editable.values.reduce(0) { $0 + $1.utf8.count }
            guard existingBytes + patchBytes <= LocalProjectLoader.maximumProjectBytes else {
                throw CrateSourceBrowser.VendorError.editableTreeTooLarge
            }

            suppressAutosave = true
            for (path, contents) in editable {
                fileContents["\(root)/\(path)"] = contents
            }
            let selection = preferredVendoredFile(root: root, files: fileContents)
            fileNames = fileContents.keys.sorted(by: projectFileOrder)
            selectedFile = selection
            source = fileContents[selection] ?? ""
            suppressAutosave = false

            workspaceGeneration &+= 1
            result = nil
            lastBuild = nil
            completedStages = []
            compatibilityReport = ProjectCompatibilityReport.scan(currentProject())
            resetCargoWorkspace()
            projectTransfer = .ready(
                "Vendored \(name) \(version). Registry source remains immutable; edits now build as a local patch."
            )
            let project = currentProject()
            Task { await remember(project, lastBuild: nil) }
            refreshCargoWorkspace()
            return true
        } catch {
            suppressAutosave = false
            projectTransfer = .failed(error.localizedDescription)
            return false
        }
    }

    @discardableResult
    func openVendoredCrate(name: String, version: SemanticVersion) -> Bool {
        guard !isBusy else { return false }
        fileContents[selectedFile] = source
        let root = "vendor/\(name)-\(version)"
        let selection = preferredVendoredFile(root: root, files: fileContents)
        guard fileContents[selection] != nil else { return false }
        selectedFile = selection
        source = fileContents[selection] ?? ""
        return true
    }

    @discardableResult
    func resetVendoredCrate(name: String, version: SemanticVersion) -> Bool {
        guard !isBusy, !isProjectOperationInProgress else { return false }
        fileContents[selectedFile] = source
        let root = "vendor/\(name)-\(version)"
        let prefix = root + "/"
        let removed = fileContents.keys.filter { $0.hasPrefix(prefix) }
        guard !removed.isEmpty else { return false }

        suppressAutosave = true
        for path in removed { fileContents.removeValue(forKey: path) }
        if removed.contains(selectedFile) {
            selectedFile = fileContents[entryFile] != nil
                ? entryFile
                : fileContents.keys.sorted(by: projectFileOrder).first ?? entryFile
            source = fileContents[selectedFile] ?? ""
        }
        fileNames = fileContents.keys.sorted(by: projectFileOrder)
        suppressAutosave = false

        workspaceGeneration &+= 1
        result = nil
        lastBuild = nil
        completedStages = []
        compatibilityReport = ProjectCompatibilityReport.scan(currentProject())
        resetCargoWorkspace()
        projectTransfer = .ready(
            "Reset \(name) \(version) to its checksum-verified registry source."
        )
        let project = currentProject()
        Task { await remember(project, lastBuild: nil) }
        refreshCargoWorkspace()
        return true
    }

    func vendoredFiles(name: String, version: SemanticVersion) -> [String: String] {
        var files = fileContents
        files[selectedFile] = source
        let prefix = "vendor/\(name)-\(version)/"
        return Dictionary<String, String>(
            uniqueKeysWithValues: files.compactMap { path, contents in
                guard path.hasPrefix(prefix) else { return nil }
                return (String(path.dropFirst(prefix.count)), contents)
            }
        )
    }

    private func preferredVendoredFile(root: String, files: [String: String]) -> String {
        for candidate in ["src/lib.rs", "src/main.rs", "Cargo.toml"] {
            let path = "\(root)/\(candidate)"
            if files[path] != nil { return path }
        }
        return files.keys
            .filter { $0.hasPrefix(root + "/") && $0.hasSuffix(".rs") }
            .sorted()
            .first ?? "\(root)/Cargo.toml"
    }

    func refreshCargoStorage() async {
        cargoStorage = await packageManager.storageUsage()
    }

    func clearCargoBuildArtifacts() async {
        let revision = workspaceRevision
        try? await packageManager.clearBuildArtifacts()
        await compiler.clearProjectArtifacts()
        guard isCurrent(revision) else { return }
        resolvedManifestSource = nil
        resolvedWorkspaceRevision = nil
        await refreshCargoStorage()
        refreshCargoWorkspace()
    }

    func clearCargoPackageCache() async {
        let revision = workspaceRevision
        try? await packageManager.clearPackageCache()
        await compiler.clearProjectArtifacts()
        guard isCurrent(revision) else { return }
        resolvedManifestSource = nil
        resolvedWorkspaceRevision = nil
        cargoWorkspace = .empty
        cargoStage = .idle
        await refreshCargoStorage()
    }

    func clearCargoDownloadedArchives() async {
        let revision = workspaceRevision
        try? await packageManager.clearDownloadedArchives()
        guard isCurrent(revision) else { return }
        await refreshCargoStorage()
    }

    func clearCargoOfflinePins() async {
        let revision = workspaceRevision
        try? await packageManager.clearOfflinePins()
        guard isCurrent(revision) else { return }
        cargoWorkspace.isOfflinePinned = false
        await refreshCargoStorage()
    }

    func cancelBuild() {
        if playgroundRuntime?.working == true { playgroundRuntime?.stopOwned(); return }
        guard isBusy, activeCompilationID != nil else { return }
        debugSession?.stop(); debugSession = nil; debugSessionID = nil; debugActive = false; debugPause = nil
        // Interrupt the guest itself; the task cancellation below only detaches
        // the UI from a worker that would otherwise run to completion.
        compiler.cancel()
        formatter.cancel()
        typeScriptChecker.cancel()
        typeScriptCheckPending = false
        compilationTask?.cancel()
        // Keep the active identity until the queue callback returns. Clearing it
        // here made `discardCompilationIfActive` reject that callback, leaving
        // `isCompilerDraining` true forever and permanently disabling Run.
        activity = .idle
        isCompilerDraining = true
        if cargoStage.isWorking { cargoStage = .idle }
        result = .failure(
            phase: .setup,
            detail: "Build stopped. The active worker is being interrupted and its snapshot released."
        )
    }

    func stopTypeScriptForBackground() {
        if typeScriptCheckPending || typeScriptChecker.isWorking { cancelBuild() }
    }

    func loadRunnableSample(projectName: String = "hello-crabrix") {
        loadProject(name: projectName, files: ["main.rs": RustSamples.runnable])
    }

    func loadHelloLessonSample(projectName: String = "hello-crabrix") {
        loadProject(name: projectName, files: ["main.rs": RustSamples.helloLesson])
    }

    func loadBorrowDiagnosticSample(projectName: String = "borrow-lab") {
        loadProject(name: projectName, files: ["main.rs": RustSamples.broken])
    }

    func loadMultiFileSample(projectName: String = "modules-lab") {
        loadProject(
            name: projectName,
            files: [
                "Cargo.toml": RustSamples.cargoManifest,
                "src/main.rs": RustSamples.multiFileMain,
                "src/greeter.rs": RustSamples.multiFileGreeter,
            ]
        )
    }

    func loadAlgorithmLessonSample(projectName: String, source: String) {
        loadProject(
            name: projectName,
            files: ["solution.rs": source],
            entryFile: "solution.rs",
            kind: .learning
        )
    }

    func loadCourseStarter(_ template: CourseProjectTemplate, session: CourseSession,
                           projectName: String? = nil) {
        loadProject(
            name: projectName ?? template.name,
            files: template.files,
            entryFile: template.entryFile,
            provenance: .academy(session: session, templateHash: template.templateHash),
            kind: .learning
        )
    }

    @discardableResult
    func openAtlasRecording(_ recording: AtlasRecording, session: CourseSession) -> Bool {
        let replay = recording.replay
        guard session.courseID == "algorithms", session.lessonID == recording.lessonID,
              session.repository.writing(for: recording.lessonID)?.exampleCode == replay.source,
              AtlasReplay.digest(Data(replay.source.utf8)) == replay.sourceHash else { return false }
        let template = CourseProjectTemplate(name: "atlas-\(replay.pattern)", entryFile: "main.rs",
                                             files: ["main.rs": replay.source])
        var origin = CrabrixProject.Provenance.academy(session: session, templateHash: template.templateHash)
        origin.course?.recording = .init(key: replay.key, sourceHash: replay.sourceHash, input: replay.input,
            packVersion: recording.packVersion, packDigest: recording.packDigest,
            courseContentVersion: recording.courseContentVersion)
        loadProject(name: template.name, files: template.files, entryFile: template.entryFile,
                    provenance: origin, kind: .learning)
        return true
    }

    func beginLesson(_ id: String, isReview: Bool = false,
                     content: CourseLessonExecution? = nil) {
        activeLessonID = id
        activeLessonContent = content
        activeLessonIsReview = isReview
        activeLessonInitialSourceTreeHash = workspaceRevision.sourceTreeHash
        activeLessonObservedDiagnosticCodes = []
        lessonEvidenceMessage = isReview
            ? "Review mode — evidence may be rerun, but rewards stay unchanged."
            : nil
    }

    func completeLesson(_ id: String) {
        completedLessonIDs.insert(id)
        persistCompletedLessons()
    }

    /// Restarts only this course's lesson path. Earned rating, achievements,
    /// attempt evidence and editable projects remain intact.
    func resetCourseProgress(lessonIDs: Set<String>) {
        guard !lessonIDs.isEmpty else { return }
        completedLessonIDs.subtract(lessonIDs)
        lessonAnswerIndices = lessonAnswerIndices.filter { !lessonIDs.contains($0.key) }
        persistCompletedLessons()
        userDefaults.set(lessonAnswerIndices, forKey: Self.lessonAnswersKey)
        if let activeLessonID, lessonIDs.contains(activeLessonID) {
            self.activeLessonID = nil
            activeLessonContent = nil
            activeLessonIsReview = false
            lessonEvidenceMessage = nil
        }
    }

    /// Keeps the first committed quick-check answer so reopening a lesson is
    /// review, not a second attempt that can spend or earn resources again.
    func recordLessonAnswer(_ index: Int, for lessonID: String) {
        guard index >= 0, lessonAnswerIndices[lessonID] == nil else { return }
        lessonAnswerIndices[lessonID] = index
        userDefaults.set(lessonAnswerIndices, forKey: Self.lessonAnswersKey)
    }

    func openAcademyExample(_ showcase: RustShowcaseProject,
                            courseID: String = "projects", contentVersion: String) {
        let template = showcase.project
        let copy = CrabrixProject(
            name: template.name,
            files: template.files,
            entryFile: template.entryFile,
            provenance: .academyExample(
                id: showcase.id, courseID: courseID, contentVersion: contentVersion,
                templateHash: CourseProjectTemplate(
                    name: template.name, entryFile: template.entryFile,
                    files: template.files
                ).templateHash
            ),
            projectDescription: showcase.detail,
            tags: showcase.concepts,
            folder: template.folder,
            kind: template.kind
        )
        loadProject(copy)
        projectTransfer = .ready("Created \(showcase.title) in My Projects.")
    }

    func createProject(name: String, template: RustProjectTemplate) {
        createProject(
            NewRustProjectRequest(
                name: name,
                template: template,
                projectDescription: "",
                folder: nil,
                tags: [],
                kind: template.defaultProjectKind
            )
        )
    }

    func createProject(_ request: NewRustProjectRequest) {
        guard prepareForProjectSwitch() else { return }
        let name = Self.normalizedProjectName(request.name)
        guard !name.isEmpty else {
            projectTransfer = .failed("Enter a project name.")
            return
        }

        let files: [String: String]
        switch request.template {
        case .hello:
            files = [
                "src/main.rs": """
                fn main() {
                    println!("Hello from \(name)!");
                }
                """,
            ]
        case .empty:
            files = [
                "src/main.rs": """
                fn main() {
                    // Start building here.
                }
                """,
            ]
        case .modules:
            files = [
                "src/main.rs": """
                mod greeter;

                fn main() {
                    println!("{}", greeter::message());
                }
                """,
                "src/greeter.rs": """
                pub fn message() -> &'static str {
                    "Hello from a Rust module!"
                }
                """,
            ]
        case .cli:
            files = [
                "src/main.rs": """
                use std::env;

                fn main() {
                    let name = env::args()
                        .nth(1)
                        .unwrap_or_else(|| "crabrix".to_string());
                    println!("Hello, {name}!");
                }
                """,
            ]
        case .packages:
            files = [
                "src/main.rs": """
                use smallvec::SmallVec;

                fn main() {
                    // SmallVec keeps the first eight values inline, with no heap
                    // allocation, and spills to a Vec only when it has to.
                    let mut squares: SmallVec<[u32; 8]> = SmallVec::new();
                    for value in 1..=6 {
                        squares.push(value * value);
                    }

                    println!("squares      {squares:?}");
                    println!("spilled      {}", squares.spilled());
                    println!("log level    {}", log::max_level());
                }
                """,
            ]
        case .visual:
            files = [
                "src/main.rs": """
                const HEX: &[u8] = b"0123456789abcdef";

                fn main() {
                    let (width, height) = (24, 16);
                    let mut pixels = String::new();
                    for y in 0..height {
                        for x in 0..width {
                            let band = (x / 4 + y / 3) % 6;
                            pixels.push(HEX[band] as char);
                        }
                    }
                    println!(
                        r##"CRABRIX_CANVAS:{{\"title\":\"My Rust Canvas\",\"width\":24,\"height\":16,\"palette\":[\"#172554\",\"#2563EB\",\"#06B6D4\",\"#34D399\",\"#FACC15\",\"#FB7185\"],\"pixels\":\"{}\"}}"##,
                        pixels
                    );
                    println!("Change the algorithm, then Run again.");
                }
                """,
            ]
        case .webPage:
            files = WebProjectSamples.files
        case .rustWeb:
            var site = Dictionary(uniqueKeysWithValues: WebProjectSamples.files.map { ("web/" + $0.key, $0.value) })
            site["src/main.rs"] = WebProjectSamples.rustGenerator
            files = site
        }

        let dependencies = switch request.template {
        case .packages:
            """
            smallvec = "1"
            log = "0.4"
            """
        default:
            ""
        }
        let manifest = """
        [package]
        name = "\(name)"
        version = "0.1.0"
        edition = "2024"

        [dependencies]
        \(dependencies)
        """
        var projectFiles = files
        if request.template != .webPage { projectFiles["Cargo.toml"] = manifest }
        loadProject(
            name: name,
            files: projectFiles,
            entryFile: request.template == .webPage ? "index.html" : "src/main.rs",
            projectDescription: request.projectDescription,
            tags: request.tags,
            folder: request.folder,
            kind: request.kind
        )
        projectTransfer = .ready("Created \(name) with \(projectFiles.count) editable files.")
    }

    @discardableResult
    func createRustFile(at rawPath: String) -> Bool {
        guard !isBusy, !isProjectOperationInProgress,
              var path = normalizedProjectPath(rawPath, defaultRoot: "src")
        else { return false }
        if (path as NSString).pathExtension.isEmpty { path += ".rs" }
        guard canCreateProjectFile(at: path) else {
            projectTransfer = .failed("\(path) already exists.")
            return false
        }

        guard addProjectFile(path: path, source: "// \(path)\n") else { return false }
        projectTransfer = .ready("Created \(path).")
        return true
    }

    @discardableResult
    func createTextFile(at rawPath: String) -> Bool {
        guard !isBusy, !isProjectOperationInProgress,
              let path = normalizedProjectPath(rawPath, defaultRoot: "src")
        else { return false }
        guard canCreateProjectFile(at: path) else {
            projectTransfer = .failed("\(path) conflicts with an existing file or folder.")
            return false
        }

        guard addProjectFile(path: path, source: "") else { return false }
        projectTransfer = .ready("Created \(path).")
        return true
    }

    @discardableResult
    func createModuleFolder(at rawPath: String) -> Bool {
        guard !isBusy, !isProjectOperationInProgress,
              let folder = normalizedProjectPath(rawPath, defaultRoot: "src")
        else { return false }
        let path = "\(folder)/mod.rs"
        guard canCreateProjectFile(at: path) else {
            projectTransfer = .failed("\(folder) already contains mod.rs.")
            return false
        }

        let moduleName = folder.split(separator: "/").last.map(String.init) ?? "module"
        guard addProjectFile(path: path, source: "// \(moduleName) module\n") else { return false }
        projectTransfer = .ready("Created \(folder) with mod.rs.")
        return true
    }

    private func canCreateProjectFile(at path: String) -> Bool {
        let folded = path.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        return !fileContents.keys.contains { existing in
            let current = existing.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            return current == folded || current.hasPrefix(folded + "/")
                || folded.hasPrefix(current + "/")
        }
    }

    @discardableResult
    func addCargoDependency(name rawName: String, requirement rawRequirement: String) -> Bool {
        guard !isBusy, !isProjectOperationInProgress else { return false }
        resetDiagnosticAdvice()
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let requirement = rawRequirement.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowedNameCharacters = CharacterSet.alphanumerics
            .union(CharacterSet(charactersIn: "-_"))
        guard !name.isEmpty,
              !requirement.isEmpty,
              name.unicodeScalars.allSatisfy(allowedNameCharacters.contains),
              !requirement.contains("\"")
        else {
            projectTransfer = .failed("Enter a valid crate name and version requirement.")
            return false
        }

        fileContents[selectedFile] = source
        guard let manifest = fileContents["Cargo.toml"] else {
            projectTransfer = .failed("This project does not contain Cargo.toml.")
            return false
        }

        let updated = Self.updatingManifest(
            manifest,
            dependency: name,
            requirement: requirement
        )
        fileContents["Cargo.toml"] = updated
        if selectedFile == "Cargo.toml" {
            source = updated
        } else {
            workspaceDidChange()
        }
        fileNames = fileContents.keys.sorted(by: projectFileOrder)
        result = nil
        lastBuild = nil
        compatibilityReport = ProjectCompatibilityReport.scan(currentProject())
        projectTransfer = .ready("Added \(name) \(requirement) to Cargo.toml.")
        let project = currentProject()
        Task { await remember(project, lastBuild: nil) }
        refreshCargoWorkspace()
        return true
    }

    @discardableResult
    func useSynParserFeatures() -> Bool {
        guard !isBusy, !isCompilerDraining, !isProjectOperationInProgress, !playgroundIsReadOnly else { return false }
        do {
            cargoFeatureProposal = try CargoFeatureProposal(project: currentProject(), revision: workspaceRevision)
            return true
        } catch {
            projectTransfer = .failed(error.localizedDescription)
            return false
        }
    }

    @discardableResult
    func applyCargoFeatureProposal(_ proposal: CargoFeatureProposal) -> Bool {
        guard !isBusy, !isCompilerDraining, !isProjectOperationInProgress, !playgroundIsReadOnly,
              isCurrent(proposal.revision), currentProject().files == proposal.before else {
            projectTransfer = .failed("Project changed. Reopen the feature preview before applying it."); return false
        }
        do {
            try ProjectFilePolicy.validate(proposal.after, entryFile: entryFile)
            if playgroundSession != nil {
                _ = try playgroundDocument(files: proposal.after)
            }
            applyFormattedFiles(proposal.after, applyToEditor: nil)
            cargoFeatureProposal = nil
            projectTransfer = .ready("Feature profile updated. Original Cargo.toml kept at \(proposal.backupPath). Prepare dependencies explicitly to refresh this graph.")
            let project = currentProject(); Task { await remember(project, lastBuild: nil) }
            return true
        } catch { projectTransfer = .failed(error.localizedDescription); return false }
    }

    @discardableResult
    func removeCargoDependency(name: String) -> Bool {
        guard !isBusy, !isProjectOperationInProgress,
              let manifest = cargoManifestSource,
              cargoManifest?.dependencies.contains(where: { $0.name == name }) == true
        else { return false }

        do {
            let updated = try CargoManifestEditor.removingDependency(name, from: manifest)
            guard updated != manifest,
                  CargoManifest.parse(updated)?.dependencies.contains(where: { $0.name == name }) == false
            else {
                projectTransfer = .failed("Open Cargo.toml to remove this dependency declaration.")
                return false
            }
            resetDiagnosticAdvice()
            fileContents[selectedFile] = source
            fileContents["Cargo.toml"] = updated
            if (try? CratePackageManifest.parse(updated))?.dependencies.isEmpty == true {
                // No pins remain to preserve. Otherwise a frozen refresh can
                // retain the removed crate as an inactive old lockfile entry.
                fileContents.removeValue(forKey: "Cargo.lock")
                if selectedFile == "Cargo.lock" { selectedFile = "Cargo.toml" }
                fileNames = fileContents.keys.sorted(by: projectFileOrder)
            }
            if selectedFile == "Cargo.toml" {
                source = updated
            } else {
                workspaceDidChange()
            }
            result = nil
            lastBuild = nil
            resetCargoWorkspace()
            compatibilityReport = ProjectCompatibilityReport.scan(currentProject())
            projectTransfer = .ready("Removed \(name) from Cargo.toml. Update any code that imports it.")
            refreshCargoWorkspace()
            return true
        } catch {
            projectTransfer = .failed("Could not update Cargo.toml: \(error.localizedDescription)")
            return false
        }
    }

    func selectFile(_ name: String) {
        guard !isProjectOperationInProgress, name != selectedFile, fileContents[name] != nil else { return }
        fileContents[selectedFile] = source
        selectedFile = name
        // Navigation does not change the source tree. In particular it must
        // not invalidate the immutable revision of an in-flight compilation.
        let wasSuppressed = suppressAutosave
        suppressAutosave = true
        source = fileContents[name] ?? ""
        suppressAutosave = wasSuppressed
    }

    @discardableResult
    func replaceProjectFilesFromTerminal(
        _ files: [String: String],
        selecting requestedSelection: String? = nil
    ) -> Bool {
        guard !isBusy, !isProjectOperationInProgress, !files.isEmpty else { return false }
        do { try ProjectFilePolicy.validate(files) }
        catch { projectTransfer = .failed(error.localizedDescription); return false }

        resetDiagnosticAdvice()
        fileContents = files
        if let requestedSelection, files[requestedSelection] != nil {
            selectedFile = requestedSelection
        } else if files[selectedFile] == nil {
            selectedFile = files[entryFile] != nil
                ? entryFile
                : files.keys.sorted(by: projectFileOrder).first ?? entryFile
        }
        if files[entryFile] == nil {
            entryFile = ["src/main.rs", "main.rs", "src/lib.rs", "lib.rs"]
                .first(where: { files[$0] != nil })
                ?? selectedFile
        }
        fileNames = files.keys.sorted(by: projectFileOrder)
        source = files[selectedFile] ?? ""
        result = nil
        lastBuild = nil
        completedStages = []
        compatibilityReport = ProjectCompatibilityReport.scan(currentProject())
        resetCargoWorkspace()
        let project = currentProject()
        Task { await remember(project, lastBuild: nil) }
        return true
    }

    private func loadProject(
        name: String,
        id: UUID = UUID(),
        files: [String: String],
        entryFile requestedEntry: String? = nil,
        provenance: CrabrixProject.Provenance? = nil,
        projectDescription: String = "",
        tags: [String] = [],
        folder: String? = nil,
        kind: CrabrixProject.Kind = .general,
        isFavorite: Bool = false,
        lastBuild: ProjectBuildRecord? = nil,
        resourceTreeHash: String? = nil
    ) {
        latestProjectSnapshots[projectID] = currentProject()
        if !isApplyingPlayground { leavePlayground() }
        if isBusy { cancelBuild() }
        resetDiagnosticAdvice()
        autosaveTask?.cancel()
        suppressAutosave = true
        projectID = id
        projectResourceDigest = resourceTreeHash
        gitState = nil; gitAvailable = false; gitHistory = []; gitBranches = []
        gitDiff = nil; gitRevisionTree = nil; gitViewingCommit = nil; gitRestorePreview = nil
        gitObservedGeneration = nil; gitMessage = ""
        gitRemote = nil; gitCredentialUsername = nil
        gitArchiveURL = nil; gitArchiveRevision = nil
        projectName = name
        self.projectDescription = projectDescription
        projectTags = CrabrixProject.normalizedTags(tags)
        projectFolder = CrabrixProject.normalizedFolder(folder)
        projectKind = kind
        projectIsFavorite = isFavorite
        fileContents = files
        entryFile = requestedEntry
            ?? (files["src/main.rs"] != nil ? "src/main.rs" : "main.rs")
        fileNames = files.keys.sorted(by: projectFileOrder)
        selectedFile = entryFile
        source = files[entryFile] ?? ""
        self.provenance = provenance
        let expectedKind: ProjectExecutionKind = BrowserProjectConfiguration.isBrowserEntry(entryFile) ? .browser : .rust
        let expectedCompilerEntry = expectedKind == .browser ? BrowserProjectConfiguration.entry(files: files, preferred: entryFile) : entryFile
        self.lastBuild = lastBuild?.sourceTreeHash == workspaceRevision.sourceTreeHash && lastBuild?.toolchainID == ProjectExecutionProfile.identity && lastBuild?.resourceTreeHash == projectResourceDigest
            && lastBuild?.workspaceEntryFile == entryFile && lastBuild?.compilerEntryFile == expectedCompilerEntry && lastBuild?.executionKind == expectedKind ? lastBuild : nil
        compatibilityReport = ProjectCompatibilityReport.scan(
            CrabrixProject(
                id: id,
                name: name,
                files: files,
                entryFile: entryFile,
                provenance: provenance,
                projectDescription: projectDescription,
                tags: tags,
                folder: folder,
                kind: kind,
                isFavorite: isFavorite
            )
        )
        result = nil
        unresolvedDiagnosticEvidence = nil
        repairRewardEventKey = nil
        completedStages = []
        practiceCompleted = false
        activeLessonID = nil
        activeLessonContent = nil
        activeLessonIsReview = false
        activeLessonInitialSourceTreeHash = nil
        activeLessonObservedDiagnosticCodes = []
        lessonEvidenceMessage = nil
        resetCargoWorkspace()
        suppressAutosave = false
        workspaceGeneration &+= 1
        latestProjectSnapshots[projectID] = currentProject()
        saveState = .unsaved
        let project = currentProject()
        Task { await remember(project, lastBuild: lastBuild) }
    }

    /// Drops the resolved graph so the next build resolves the new manifest.
    private func resetCargoWorkspace() {
        cargoTask?.cancel()
        cargoTask = nil
        resolvedManifestSource = nil
        resolvedWorkspaceRevision = nil
        cargoWorkspace = .empty
        cargoStage = .idle
    }

    private func loadProject(_ project: CrabrixProject, lastBuild: ProjectBuildRecord? = nil, resourceTreeHash: String? = nil) {
        loadProject(
            name: project.name,
            id: project.id,
            files: project.files,
            entryFile: project.entryFile,
            provenance: project.provenance,
            projectDescription: project.projectDescription,
            tags: project.tags,
            folder: project.folder,
            kind: project.kind,
            isFavorite: project.isFavorite,
            lastBuild: lastBuild,
            resourceTreeHash: resourceTreeHash
        )
    }

    private func prepareForProjectSwitch() -> Bool {
        guard !isProjectOperationInProgress else { return false }
        if !isApplyingPlayground { leavePlayground() }
        if isBusy { cancelBuild() }
        resetDiagnosticAdvice()
        return true
    }

    func applyRepair() {
        guard selectedFile == entryFile,
              let diagnostic = primaryDiagnostic,
              let repaired = BorrowRepair.apply(to: source, diagnostic: diagnostic)
        else {
            return
        }
        resetDiagnosticAdvice()
        source = repaired
        result = nil
    }

    func recordWebPreviewFailure(snapshotID: String, failure: WebPreviewFailure) {
        guard !isBusy, let preview = result?.webPreview, preview.id == snapshotID,
              (result?.diagnostics.count ?? 0) < 128 else { return }
        let path = failure.file ?? preview.entryPath
        let source = fileContents[path]
        let isCurrentSource = source.map { preview.assets[path] == Data($0.utf8) } == true
        let lines = source?.components(separatedBy: "\n") ?? []
        let span: [RustDiagnostic.Span] = isCurrentSource ? [RustDiagnostic.Span(
            fileName: path, lineStart: failure.line, lineEnd: failure.line,
            columnStart: failure.column, columnEnd: failure.column + 1,
            isPrimary: true, label: "Web preview",
            sourceLine: lines.indices.contains(failure.line - 1) ? lines[failure.line - 1] : "")] : []
        let diagnostic = RustDiagnostic(level: "error", message: failure.message, code: "WEB",
            rendered: "\(path):\(failure.line):\(failure.column): \(failure.message)", spans: span)
        guard result?.diagnostics.contains(where: { $0.code == "WEB" && $0.rendered == diagnostic.rendered }) != true else { return }
        result?.diagnostics.append(diagnostic)
    }

    func requestAppleIntelligenceAdvice() {
        guard !isBusy,
              !diagnosticAdviceState.isWorking,
              let diagnostic = primaryDiagnostic
        else { return }

        let project = currentProject()
        guard let targetFile = diagnosticTargetFile(for: diagnostic, in: project.files),
              SourceLanguage(filePath: targetFile).supportsCompletion,
              let originalSource = project.files[targetFile]
        else {
            diagnosticAdviceState = .unavailable(
                "The diagnostic did not identify an editable source file for this issue."
            )
            return
        }

        diagnosticAdviceTask?.cancel()
        diagnosticAdviceState = .generating
        diagnosticAdviceRevision = nil
        let revision = workspaceRevision
        let plan = resolvedWorkspaceRevision == revision ? cargoWorkspace.plan : .empty
        diagnosticAdviceTask = Task { [weak self] in
            guard let self else { return }
            do {
                let draft = try await AppleIntelligenceDiagnosticAdvisor.generate(
                    diagnostic: diagnostic,
                    project: project,
                    targetFile: targetFile
                )
                try Task.checkCancellation()

                guard isCurrent(revision) else { return }

                guard targetFile.lowercased().hasSuffix(".rs"), !draft.edits.isEmpty else {
                    diagnosticAdviceRevision = revision
                    diagnosticAdviceState = .ready(
                        RustDiagnosticAdvice(
                            filePath: targetFile,
                            originalSource: originalSource,
                            proposedSource: nil,
                            explanation: draft.explanation,
                            changeSummary: draft.changeSummary,
                            edits: [],
                            verification: .explanationOnly
                        )
                    )
                    diagnosticAdviceTask = nil
                    return
                }

                let proposedSource = try RustSourcePatch.applying(
                    draft.edits,
                    to: originalSource
                )
                guard proposedSource != originalSource else {
                    diagnosticAdviceRevision = revision
                    diagnosticAdviceState = .ready(
                        RustDiagnosticAdvice(
                            filePath: targetFile,
                            originalSource: originalSource,
                            proposedSource: nil,
                            explanation: draft.explanation,
                            changeSummary: draft.changeSummary,
                            edits: [],
                            verification: .explanationOnly
                        )
                    )
                    diagnosticAdviceTask = nil
                    return
                }

                diagnosticAdviceState = .verifying
                var candidateFiles = project.files
                candidateFiles[targetFile] = proposedSource
                let entryPath = project.entryFile
                guard let main = candidateFiles.removeValue(forKey: entryPath) else {
                    diagnosticAdviceState = .unavailable(
                        "The project entry file is unavailable for verification."
                    )
                    diagnosticAdviceTask = nil
                    return
                }
                let verificationResult = await compiler.check(
                    source: main,
                    sourcePath: entryPath,
                    supportingFiles: candidateFiles,
                    edition: rootEdition(from: candidateFiles["Cargo.toml"]),
                    plan: plan
                )
                guard !Task.isCancelled, isCurrent(revision) else { return }

                let verification: RustDiagnosticAdvice.Verification
                if verificationResult.succeeded {
                    verification = .verified
                } else {
                    let reason = verificationResult.diagnostics.first?.message
                        ?? verificationResult.detail
                    verification = .rejected(reason)
                }
                diagnosticAdviceRevision = revision
                diagnosticAdviceState = .ready(
                    RustDiagnosticAdvice(
                        filePath: targetFile,
                        originalSource: originalSource,
                        proposedSource: proposedSource,
                        explanation: draft.explanation,
                        changeSummary: draft.changeSummary,
                        edits: draft.edits,
                        verification: verification
                    )
                )
                diagnosticAdviceTask = nil
            } catch is CancellationError {
                guard isCurrent(revision) else { return }
                if diagnosticAdviceState.isWorking {
                    diagnosticAdviceState = .idle
                }
                diagnosticAdviceTask = nil
            } catch {
                guard isCurrent(revision) else { return }
                diagnosticAdviceState = .unavailable(error.localizedDescription)
                diagnosticAdviceTask = nil
            }
        }
    }

    func cancelAppleIntelligenceAdvice() {
        guard diagnosticAdviceState.isWorking else { return }
        resetDiagnosticAdvice()
    }

    private func resetDiagnosticAdvice() {
        diagnosticAdviceTask?.cancel()
        diagnosticAdviceTask = nil
        diagnosticAdviceRevision = nil
        if diagnosticAdviceState == .verifying {
            compiler.cancel()
        }
        diagnosticAdviceState = .idle
    }

    func applyAppleIntelligenceAdvice() {
        guard case let .ready(advice) = diagnosticAdviceState,
              advice.canApply,
              let proposedSource = advice.proposedSource,
              let revision = diagnosticAdviceRevision,
              isCurrent(revision)
        else { return }

        fileContents[selectedFile] = source
        guard fileContents[advice.filePath] == advice.originalSource else {
            diagnosticAdviceState = .unavailable(
                "The source changed after verification. Run Check again before applying a fix."
            )
            return
        }

        fileContents[advice.filePath] = proposedSource
        selectedFile = advice.filePath
        source = proposedSource
        result = nil
        lastBuild = nil
        diagnosticAdviceState = .idle
        compatibilityReport = ProjectCompatibilityReport.scan(currentProject())
        startBuild(.checking)
    }

    private func diagnosticTargetFile(
        for diagnostic: RustDiagnostic,
        in files: [String: String]
    ) -> String? {
        guard let diagnosticPath = diagnostic.primarySpan?.fileName else { return nil }
        return files.keys.first(where: { $0 == diagnosticPath })
            ?? files.keys.first(where: {
                diagnosticPath.hasSuffix("/\($0)") || $0.hasSuffix("/\(diagnosticPath)")
            })
    }

    func presentPractice() {
        guard primaryDiagnostic?.code == "E0502" else { return }
        completedStages.insert(.explanation)
        isPracticePresented = true
    }

    func validatePractice(source: String) async -> CompilationResult {
        let value = await compiler.run(source: source)
        if value.succeeded, value.stdout.contains("Ada") {
            practiceCompleted = true
            completedStages.insert(.practice)
        }
        return value
    }

    private func projectSnapshot() -> (entryPath: String, main: String, supporting: [String: String]) {
        var files = fileContents
        files[selectedFile] = source
        let main = files.removeValue(forKey: entryFile) ?? ""
        return (entryFile, main, files)
    }

    private func currentProject() -> CrabrixProject {
        var files = fileContents
        files[selectedFile] = source
        return CrabrixProject(
            id: projectID,
            name: projectName,
            files: files,
            entryFile: entryFile,
            provenance: provenance,
            projectDescription: projectDescription,
            tags: projectTags,
            folder: projectFolder,
            kind: projectKind,
            isFavorite: projectIsFavorite
        )
    }

    private func projectFileOrder(_ lhs: String, _ rhs: String) -> Bool {
        func rank(_ path: String) -> Int {
            switch path {
            case "Cargo.toml": 0
            case "Cargo.lock": 1
            case entryFile: 2
            default: 3
            }
        }
        let lhsRank = rank(lhs)
        let rhsRank = rank(rhs)
        return lhsRank == rhsRank
            ? lhs.localizedStandardCompare(rhs) == .orderedAscending
            : lhsRank < rhsRank
    }

    private func addProjectFile(path: String, source newSource: String) -> Bool {
        var proposed = currentProject().files
        proposed[path] = newSource
        do { try ProjectFilePolicy.validate(proposed, entryFile: entryFile) }
        catch { projectTransfer = .failed(error.localizedDescription); return false }
        fileContents = proposed
        fileNames = fileContents.keys.sorted(by: projectFileOrder)
        selectedFile = path
        source = newSource
        result = nil
        unresolvedDiagnosticEvidence = nil
        repairRewardEventKey = nil
        lastBuild = nil
        completedStages = []
        compatibilityReport = ProjectCompatibilityReport.scan(currentProject())
        let project = currentProject()
        Task { await remember(project, lastBuild: nil) }
        return true
    }

    private func normalizedProjectPath(_ rawPath: String, defaultRoot: String) -> String? {
        var raw = rawPath
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\", with: "/")
        guard !raw.isEmpty, !raw.hasPrefix("/") else {
            projectTransfer = .failed("Enter a relative path inside the project.")
            return nil
        }
        if !raw.contains("/") { raw = "\(defaultRoot)/\(raw)" }
        let components = raw.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard !components.isEmpty,
              components.count <= 16,
              !components.contains(where: { $0 == "." || $0 == ".." || $0 == ".crabrix" })
        else {
            projectTransfer = .failed("That project path is not allowed.")
            return nil
        }
        return components.joined(separator: "/")
    }

    private static func normalizedProjectName(_ rawName: String) -> String {
        let lowered = rawName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var result = ""
        var lastWasSeparator = false
        for scalar in lowered.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) || scalar == "_" {
                result.unicodeScalars.append(scalar)
                lastWasSeparator = false
            } else if !lastWasSeparator, !result.isEmpty {
                result.append("-")
                lastWasSeparator = true
            }
        }
        return result.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private static func updatingManifest(
        _ manifest: String,
        dependency name: String,
        requirement: String
    ) -> String {
        var lines = manifest.components(separatedBy: "\n")
        let dependencyLine = CargoManifestEditor.localCompilerDeclaration(
            name: name, requirement: requirement
        )

        guard let sectionStart = lines.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces) == "[dependencies]"
        }) else {
            if lines.last?.isEmpty == false { lines.append("") }
            lines.append("[dependencies]")
            lines.append(dependencyLine)
            return lines.joined(separator: "\n")
        }

        let sectionEnd = lines.indices.first(where: { index in
            index > sectionStart
                && lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("[")
        }) ?? lines.endIndex
        if let existing = lines.indices.first(where: { index in
            guard index > sectionStart, index < sectionEnd else { return false }
            let key = lines[index].split(separator: "=", maxSplits: 1).first?
                .trimmingCharacters(in: .whitespaces)
            return key == name
        }) {
            lines[existing] = dependencyLine
        } else {
            lines.insert(dependencyLine, at: sectionEnd)
        }
        return lines.joined(separator: "\n")
    }

    private func testSnapshot(_ project: (entryPath: String, main: String, supporting: [String: String]),
                              resourceFiles: [String: Data], request: RustUnitTestRequest, edition: String, plan: CargoBuildPlan,
                              revision: WorkspaceRevision, compilationID: UUID,
                              onStage: @escaping @Sendable (String) -> Void) async -> CompilationResult {
        let report = await RustUnitTestRunner().run(compiler: compiler, source: project.main,
            sourcePath: project.entryPath, supportingFiles: project.supporting, resourceFiles: resourceFiles, edition: edition,
            plan: plan, filter: request.filter, listOnly: request.listOnly, onStage: onStage)
        if isCurrent(revision), activeCompilationID == compilationID { unitTestReport = report }
        return report.rendered
    }

    private func finish(_ value: CompilationResult, revision: WorkspaceRevision, recordsLearningEvidence: Bool = true, isDebugExecution: Bool = false, browserTypeCheckVersion: String? = nil, executionKind: ProjectExecutionKind = .rust, compilerEntryFile: String? = nil) {
        guard isCurrent(revision) else { return }
        typeScriptCheckPending = false
        debugSession = nil; debugSessionID = nil; debugActive = false; debugPause = nil
        appendBuildStage(value.succeeded ? "Finished successfully" : "Stopped · see Problems for details")
        result = value
        activity = .idle
        isCompilerDraining = false
        compilationTask = nil
        activeCompilationID = nil
        // User tests and formatter tools must not complete Academy lessons,
        // mint repair rewards or replace the last ordinary Build/Run record.
        guard recordsLearningEvidence else { return }
        lastBuild = ProjectBuildRecord(result: value, sourceTreeHash: revision.sourceTreeHash, toolchainID: revision.toolchainID, resourceTreeHash: revision.resourceTreeHash, isDebugExecution: isDebugExecution, browserTypeCheckVersion: browserTypeCheckVersion,
            workspaceEntryFile: revision.entryFile, compilerEntryFile: compilerEntryFile ?? revision.entryFile, executionKind: executionKind)

        let errorDiagnostic = value.diagnostics.first(where: { $0.level == "error" })
        activeLessonObservedDiagnosticCodes.formUnion(value.diagnostics.compactMap(\.code))
        if !value.diagnostics.isEmpty {
            completedStages.insert(.diagnostic)
            completedStages.insert(.explanation)
        }
        if !value.succeeded, let diagnostic = errorDiagnostic {
            let signatureMaterial = [
                diagnostic.code ?? "unknown",
                diagnostic.message,
                diagnostic.spans.map {
                    "\($0.fileName):\($0.lineStart):\($0.columnStart):\($0.label ?? "")"
                }.joined(separator: "|"),
            ].joined(separator: "\n")
            unresolvedDiagnosticEvidence = (
                WorkspaceRevision.contentHash(signatureMaterial),
                revision.sourceTreeHash
            )
            repairRewardEventKey = nil
            completedStages.remove(.repair)
            let diagnosticsSetting = userDefaults.object(
                forKey: Self.appleIntelligenceDiagnosticsKey
            ) as? Bool ?? true
            // Web/type diagnostics keep independent Run immediately usable.
            // Optional web advice remains an explicit, explanation-only action.
            if diagnosticsSetting, executionKind == .rust { requestAppleIntelligenceAdvice() }
        } else if value.succeeded, let evidence = unresolvedDiagnosticEvidence {
            completedStages.insert(.repair)
            // Check proves the original compiler error is gone. Rating waits
            // for Run so the repaired program also produces runtime evidence.
            if value.phase == .run {
                repairRewardEventKey = [
                    "repair",
                    evidence.signature,
                    evidence.beforeHash,
                    revision.sourceTreeHash,
                ].joined(separator: ":")
                unresolvedDiagnosticEvidence = nil
            }
        }
        if value.phase == .run,
           let activeLessonID,
           let content = activeLessonContent {
            let validation = LessonEvidenceValidator.validateCompilerAttempt(
                evidence: content.evidence,
                result: value,
                project: currentProject(),
                initialSourceTreeHash: activeLessonInitialSourceTreeHash,
                currentSourceTreeHash: revision.sourceTreeHash,
                observedDiagnosticCodes: activeLessonObservedDiagnosticCodes
            )
            lessonEvidenceMessage = validation.detail
            appendLessonAttemptEvidence(
                lessonID: activeLessonID,
                content: content,
                revision: revision,
                result: value,
                passed: validation.passed
            )
            if validation.passed { completeLesson(activeLessonID) }
        }
        Task {
            await remember(currentProject(), lastBuild: lastBuild)
            await refreshCargoStorage()
        }
    }

    private func persistCompletedLessons() {
        userDefaults.set(completedLessonIDs.sorted(), forKey: Self.completedLessonsKey)
    }

    private func appendLessonAttemptEvidence(
        lessonID: String,
        content: CourseLessonExecution,
        revision: WorkspaceRevision,
        result: CompilationResult,
        passed: Bool
    ) {
        lessonAttemptEvidence.append(
            LessonAttemptEvidence(
                lessonID: lessonID,
                projectRevision: revision.sourceTreeHash,
                validatorVersion: LessonAttemptEvidence.validatorVersion,
                compilerVersion: CargoToolchain.semanticVersionLabel,
                result: passed ? .passed : .failed,
                diagnosticCodes: result.diagnostics.compactMap(\.code).sorted(),
                stdoutHash: result.stdout.isEmpty
                    ? nil
                    : WorkspaceRevision.contentHash(result.stdout),
                completedAt: Date(),
                identity: LessonAttemptIdentity(
                    courseID: content.courseID,
                    language: content.language,
                    contentVersion: content.contentVersion,
                    lessonID: lessonID,
                    exerciseID: lessonID,
                    validatorVersion: LessonAttemptEvidence.validatorVersion,
                    toolchainID: revision.toolchainID,
                    projectID: revision.projectID,
                    projectRevision: revision.sourceTreeHash
                )
            )
        )
        if lessonAttemptEvidence.count > 500 {
            lessonAttemptEvidence.removeFirst(lessonAttemptEvidence.count - 500)
        }
        if let data = try? JSONEncoder().encode(lessonAttemptEvidence) {
            userDefaults.set(data, forKey: Self.lessonEvidenceKey)
        }
    }

    private func remember(_ project: CrabrixProject, lastBuild: ProjectBuildRecord?) async {
        let revision = project.id == projectID ? workspaceRevision : nil
        let previous = saveQueue
        let task = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            let latest = project.id == projectID ? currentProject() : latestProjectSnapshots[project.id]
            guard latest == nil || latest == project else { return }
            if let revision, isCurrentSource(revision) { saveState = .saving }
            do {
                try ProjectFilePolicy.validate(project.files, entryFile: project.entryFile)
                recentProjects = try await projectLibrary.record(project: project, lastBuild: lastBuild)
                if let revision, isCurrentSource(revision) {
                    saveState = .saved
                    if projectName == project.name, let saved = recentProjects.first(where: { $0.id == project.id }) { projectName = saved.project.name }
                    if case let .failed(message) = projectTransfer, message.hasPrefix("Autosave failed:") { projectTransfer = .ready("Saved on this device.") }
                }
                await reloadProjectLists()
            } catch {
                if let revision, isCurrentSource(revision) {
                    saveState = .failed(error.localizedDescription)
                    projectTransfer = .failed("Autosave failed: " + error.localizedDescription)
                }
            }
        }
        saveQueue = task
        await task.value
    }

    private func reloadProjectLists() async {
        do {
            recentProjects = try await projectLibrary.items()
            allProjects = try await projectLibrary.allItems()
            projectReadFailures = await projectLibrary.readFailures()
        } catch { projectTransfer = .failed("Cannot read the saved project library: " + error.localizedDescription) }
    }

    private func isCurrentSource(_ revision: WorkspaceRevision) -> Bool {
        let current = workspaceRevision
        return current.projectID == revision.projectID && current.generation == revision.generation
            && current.entryFile == revision.entryFile
            && current.sourceTreeHash == revision.sourceTreeHash && current.toolchainID == revision.toolchainID
    }

    private func isCurrent(_ revision: WorkspaceRevision) -> Bool {
        workspaceRevision == revision
    }

    private func discardCompilationIfActive(_ compilationID: UUID) {
        guard activeCompilationID == compilationID else { return }
        typeScriptCheckPending = false
        debugSession?.stop(); debugSession = nil; debugSessionID = nil; debugActive = false; debugPause = nil
        activity = .idle
        isCompilerDraining = false
        compilationTask = nil
        activeCompilationID = nil
        if cargoStage.isWorking { cargoStage = .idle }
    }

    private func workspaceDidChange() {
        guard !suppressAutosave else { return }
        semanticUndo = nil
        if debugActive || typeScriptCheckPending { cancelBuild() }
        if !isApplyingPlayground, let connection = playgroundSession {
            do { try connection.replace(playgroundDocument()) }
            catch {
                leavePlayground()
                projectTransfer = .failed("Playground sharing stopped; your local source is kept. " + error.localizedDescription)
            }
        }
        workspaceGeneration &+= 1
        latestProjectSnapshots[projectID] = currentProject()
        saveState = .unsaved
        // A successful result belongs to the exact tree which produced it.
        // Editing invalidates its diagnostics instead of showing them as current.
        result = nil
        unitTestReport = nil
        lastBuild = nil
        if diagnosticAdviceState != .idle {
            resetDiagnosticAdvice()
        }
        scheduleAutosave()
    }

    /// Source edits are persisted after a short quiet period. The durable
    /// ProjectStore writes an atomic snapshot, so editing does not depend on a
    /// later Build or explicit export to survive relaunch.
    private func scheduleAutosave() {
        guard !suppressAutosave else { return }
        autosaveTask?.cancel()
        let requestID = UUID()
        autosaveRequestID = requestID
        autosaveTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(500))
            } catch {
                return
            }
            guard let self, !Task.isCancelled else { return }
            await remember(currentProject(), lastBuild: lastBuild)
            if autosaveRequestID == requestID { autosaveTask = nil }
        }
    }
}

extension CompilerViewModel {
    func closeGitRevision() { gitViewingCommit = nil; gitRevisionTree = nil; gitRestorePreview = nil }
    func closeGitRestorePreview() { gitRestorePreview = nil }
    func performGitCommand(_ command: ProjectGitCommand) {
        guard !gitIsWorking else {
            gitConsoleEvent = GitConsoleEvent(projectID: projectID, text: "A Git operation is still running. Stop it in Local Git or wait for its result.", isError: true)
            return
        }
        let previousEvent = gitConsoleEvent?.id
        switch command {
        case .initialize: initializeGit()
        case .fetch: fetchGit()
        case .pull: pullGit()
        case .push: pushGit()
        case let .clone(url): cloneGit(url)
        case let .connectRemote(url): connectGitRemote(url)
        case .remote:
            runGit("Reading origin") { store, project, _ in
                guard let remote = try await store.remoteState(project.id) else { return "No origin configured." }
                let ahead = remote.ahead.map { "\($0) ahead" } ?? "fetch to compare"
                let behind = remote.behind.map { "\($0) behind last fetch" } ?? "unknown remote branch"
                return "\(remote.url)\n\(remote.branch) · \(ahead) · \(behind)"
            }
        case .status: refreshGit()
        case let .diff(path): showGitDiff(path)
        case let .branch(name): createGitBranch(name)
        case let .checkout(name): switchGitBranch(name)
        case let .restore(commit, path): previewGitFile(commit: commit, path: path)
        case let .commit(message, paths):
            commitGit(paths: paths, author: userDefaults.string(forKey: "crabrix.git.author.name") ?? "",
                email: userDefaults.string(forKey: "crabrix.git.author.email") ?? "", message: message)
        case let .identity(key, value):
            let preference = key == "user.name" ? "crabrix.git.author.name" : "crabrix.git.author.email"
            if let value {
                guard !value.isEmpty, value.utf8.count <= 320, !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
                    gitConsoleEvent = GitConsoleEvent(projectID: projectID, text: "Enter a bounded single-line commit identity.", isError: true); return
                }
                userDefaults.set(value, forKey: preference)
            }
            gitConsoleEvent = GitConsoleEvent(projectID: projectID, text: "This device's commit identity: \(key)=\(userDefaults.string(forKey: preference) ?? "not set")", isError: false)
        case .log:
            runGit("Reading local history") { store, project, _ in
                let commits = try await store.history(project.id)
                return commits.isEmpty ? "No local commits." : commits.map { "\($0.id.prefix(8))  \($0.author)\n\($0.message)" }.joined(separator: "\n\n")
            }
        case .branches:
            runGit("Reading local branches") { store, project, _ in
                let state = try await store.inspect(project.id), branches = try await store.branches(project.id)
                return branches.isEmpty ? "No local branch commits." : branches.map { ($0 == state.branch ? "* " : "  ") + $0 }.joined(separator: "\n")
            }
        case let .show(commit, path):
            runGit("Reading historical source") { store, project, _ in
                let data = try await store.file(project.id, commit: commit, path: path)
                guard !data.contains(0), String(data: data, encoding: .utf8) != nil else { throw GitRepositoryFailure("This is opaque repository data, not text.") }
                return String(decoding: data.prefix(64 * 1024), as: UTF8.self) + (data.count > 64 * 1024 ? "\n[Terminal preview limited to 64 KiB; repository bytes are unchanged.]" : "")
            }
        }
        if !gitIsWorking, gitConsoleEvent?.id == previousEvent, !gitMessage.isEmpty {
            gitConsoleEvent = GitConsoleEvent(projectID: projectID, text: gitMessage, isError: true)
        }
    }
    private func runGit(_ label: String, exclusive: Bool = false, destinationProject: UUID? = nil,
                        operation: @escaping @MainActor (GitRepositoryStore, CrabrixProject, WorkspaceRevision) async throws -> String) {
        guard !isBusy, !isCompilerDraining, !isProjectOperationInProgress, !gitIsWorking else {
            gitMessage = "Wait for the active compiler/project operation to finish, or stop it before starting Git."
            gitConsoleEvent = GitConsoleEvent(projectID: projectID, text: gitMessage, isError: true)
            return
        }
        let snapshot = currentProject(), revision = workspaceRevision
        gitIsWorking = true; gitJobProjectID = snapshot.id; gitLocksWorkspace = exclusive; gitActivity = label; gitMessage = ""
        resetDiagnosticAdvice()
        gitJob = Task { [weak self] in
            guard let self else { return }
            defer {
                gitIsWorking = false; gitLocksWorkspace = false; gitActivity = ""; gitJob = nil; gitJobProjectID = nil
                if let pending = pendingGitURL {
                    pendingGitURL = nil
                    Task { [weak self] in
                        guard let self else { return }
                        switch pending {
                        case let .project(url): await openProject(from: url)
                        case let .playground(link): await openPlayground(link)
                        }
                    }
                }
            }
            do {
                let text = try await operation(gitStore, snapshot, revision)
                guard projectID == snapshot.id || projectID == destinationProject else { return }
                gitMessage = text
                gitConsoleEvent = GitConsoleEvent(projectID: projectID, text: text, isError: false)
            } catch {
                guard projectID == snapshot.id || projectID == destinationProject else { return }
                gitMessage = error is CancellationError ? "Git operation stopped. Refresh to read the current state." : error.localizedDescription
                gitConsoleEvent = GitConsoleEvent(projectID: projectID, text: gitMessage, isError: true)
            }
        }
    }

    func stopGit() { gitJob?.cancel() }

    private func acceptGit(_ state: GitState, revision: WorkspaceRevision) {
        guard projectID == revision.projectID else { return }
        gitState = state; gitAvailable = true; gitObservedGeneration = revision.generation
    }

    func refreshGit() {
        runGit("Reading local Git changes") { [self] store, project, revision in
            guard try await store.exists(project.id) else {
                gitAvailable = false; gitState = nil; gitHistory = []; gitBranches = []
                gitRemote = nil; gitCredentialUsername = nil
                return "No local Git history. Initialize it to start recording explicit commits."
            }
            let observed = try await store.inspect(project.id)
            let state = try await store.status(project.id, files: project.files, expectedRevision: observed.revision)
            let history = try await store.history(project.id)
            let branches = try await store.branches(project.id)
            let remote = try await store.remoteState(project.id)
            let username: String?
            if let remote { username = try? await gitCredentialVault.username(url: remote.url) }
            else { username = nil }
            guard projectID == project.id else { return "Project changed." }
            acceptGit(state, revision: revision); gitHistory = history; gitBranches = branches
            gitRemote = remote; gitCredentialUsername = username
            return "\(state.branch) · \(state.head.map { String($0.prefix(8)) } ?? "no commits")\n" +
                (state.changes.isEmpty ? "Working tree is clean." : state.changes.map { "\($0.kind)  \($0.path)" }.joined(separator: "\n"))
        }
    }

    func initializeGit() {
        runGit("Starting local Git history") { [self] store, project, revision in
            let state = try await store.initialize(project.id, files: project.files)
            acceptGit(state, revision: revision)
            return "Initialized a new local Git repository. Previous snapshot imports have no invented parent commit. Select files and create your first commit."
        }
    }

    func showGitDiff(_ path: String) {
        guard let state = gitState, !gitNeedsRefresh else { gitMessage = "Refresh Changes before opening this diff."; return }
        runGit("Reading diff · \(path)") { [self] store, project, revision in
            let result = try await store.diff(project.id, files: project.files, path: path, expectedRevision: state.revision)
            guard projectID == project.id else { return "Diff prepared for the captured project." }
            acceptGit(result.state, revision: revision); gitDiff = result
            return result.text.isEmpty ? "No text changes in \(path)." : result.text
        }
    }

    func commitGit(paths: [String], author: String, email: String, message: String) {
        guard let state = gitState, !gitNeedsRefresh else { gitMessage = "Refresh Changes before committing this editor revision."; return }
        runGit("Committing selected files") { [self] store, project, revision in
            let receipt = try await store.commit(project.id, files: project.files, selected: paths,
                author: author, email: email, message: message, expectedHead: state.head, expectedRevision: state.revision)
            let history = try await store.history(project.id), branches = try await store.branches(project.id)
            guard projectID == project.id else { return "Committed the captured project snapshot." }
            acceptGit(receipt.state, revision: revision); gitHistory = history; gitBranches = branches; gitDiff = nil
            gitRemote = try await store.remoteState(project.id)
            userDefaults.set(author, forKey: "crabrix.git.author.name")
            userDefaults.set(email, forKey: "crabrix.git.author.email")
            return "Committed \(receipt.commit.id.prefix(8)): \(message)" +
                (isCurrent(revision) ? "" : "\nThe captured source was committed; newer editor/room edits remain uncommitted. Refresh Changes.")
        }
    }

    func createGitBranch(_ name: String) {
        guard let state = gitState, let head = state.head, !gitNeedsRefresh else { gitMessage = "Refresh Changes and create a first commit before creating a branch."; return }
        runGit("Creating local branch") { [self] store, project, revision in
            let result = try await store.createBranch(project.id, name: name, expectedHead: head, expectedRevision: state.revision)
            let branches = try await store.branches(project.id)
            guard projectID == project.id else { return "Created the branch in the captured project." }
            acceptGit(result, revision: revision); gitBranches = branches
            return "Created branch \(name). Your current branch is still \(result.branch)."
        }
    }

    func switchGitBranch(_ branch: String) {
        guard gitCanSwitchBranch, let state = gitState, let head = state.head else {
            gitMessage = playgroundSession != nil ? "Leave the live Playground before switching local Git branches." : "Refresh, then commit or restore local changes before switching branches."
            return
        }
        runGit("Switching local branch", exclusive: true) { [self] store, project, revision in
            await retryProjectSave()
            guard isCurrent(revision), playgroundSession == nil else { throw GitRepositoryFailure("The editor changed before checkout. Refresh and retry.") }
            let checkout = try await store.checkout(project.id, branch: branch, files: project.files,
                expectedHead: head, expectedRevision: state.revision)
            guard isCurrent(revision), playgroundSession == nil else { throw GitRepositoryFailure("Git completed checkout, but the editor changed. Your editor source was kept; refresh Git before continuing.") }
            guard !checkout.snapshot.files.isEmpty else { throw GitRepositoryFailure("This branch has no editable source files. Its opaque files remain in local Git storage.") }
            try ProjectFilePolicy.validate(checkout.snapshot.files)
            gitLocksWorkspace = false
            let applied = replaceProjectFilesFromTerminal(checkout.snapshot.files)
            gitLocksWorkspace = true
            guard applied else { throw GitRepositoryFailure("The checked-out tree could not be applied to the editor; existing source is kept.") }
            await retryProjectSave()
            projectResourceDigest = checkout.state.resourceTreeHash
            acceptGit(checkout.state, revision: workspaceRevision)
            gitHistory = try await store.history(project.id); gitDiff = nil
            gitRemote = try await store.remoteState(project.id)
            return "Switched to \(branch). Kept \(checkout.snapshot.opaquePaths.count) opaque files in repository storage. Diagnostics and dependency state were refreshed."
        }
    }

    func viewGitCommit(_ commit: GitCommit) {
        runGit("Reading commit \(commit.id.prefix(8))") { [self] store, project, _ in
            let tree = try await store.tree(project.id, commit: commit.id)
            guard projectID == project.id else { return "Project changed." }
            gitViewingCommit = commit; gitRevisionTree = tree; gitRestorePreview = nil
            return "\(commit.id.prefix(8)) · \(tree.files.count) editable files · \(tree.opaquePaths.count) opaque files."
        }
    }

    func previewGitFile(commit: String, path: String) {
        runGit("Reading file from history") { [self] store, project, revision in
            let data = try await store.file(project.id, commit: commit, path: path)
            guard data.count <= ProjectFilePolicy.maximumFileBytes, !data.contains(0),
                  let replacement = String(data: data, encoding: .utf8) else {
                throw GitRepositoryFailure("This file is preserved as opaque repository data and cannot be restored into the text editor.")
            }
            guard isCurrent(revision) else { throw GitRepositoryFailure("The editor changed. Open the history preview again.") }
            gitRestorePreview = GitRestorePreview(projectID: project.id, generation: revision.generation,
                commit: commit, path: path, original: project.files[path], replacement: replacement)
            return "Previewing \(path) from \(commit.prefix(8)). Restore is an explicit action."
        }
    }

    func restoreGitPreview() {
        guard let preview = gitRestorePreview, preview.projectID == projectID,
              preview.generation == workspaceGeneration, !playgroundIsReadOnly else {
            gitMessage = "The source changed or is read-only. Open the history preview again."; return
        }
        runGit("Restoring one source file", exclusive: true) { [self] _, _, _ in
            await retryProjectSave()
            guard preview.projectID == projectID, preview.generation == workspaceGeneration,
                  currentProject().files[preview.path] == preview.original else { throw GitRepositoryFailure("Newer source was kept; reopen the preview before restoring.") }
            var files = currentProject().files; files[preview.path] = preview.replacement
            try ProjectFilePolicy.validate(files)
            if playgroundSession != nil { _ = try playgroundDocument(files: files) }
            gitLocksWorkspace = false
            let applied = replaceProjectFilesFromTerminal(files, selecting: preview.path)
            gitLocksWorkspace = true
            guard applied else { throw GitRepositoryFailure("The source file could not be restored.") }
            gitRestorePreview = nil; gitDiff = nil
            await retryProjectSave()
            return "Restored \(preview.path) from \(preview.commit.prefix(8)). This is a working-tree edit; refresh and commit it when ready."
        }
    }
}

extension CompilerViewModel {
    func connectGitRemote(_ url: String) {
        guard let state = gitState else { gitMessage = "Start local Git history first."; return }
        runGit("Connecting HTTPS origin") { [self] store, project, revision in
            let updated = try await store.connectRemote(project.id, url: url, expectedRevision: state.revision)
            let remote = try await store.remoteState(project.id)
            guard projectID == project.id else { return "Origin connected." }
            acceptGit(updated, revision: revision); gitRemote = remote
            if let remote { gitCredentialUsername = try? await gitCredentialVault.username(url: remote.url) }
            return "Connected origin. Fetch and push are explicit actions."
        }
    }

    func saveGitCredential(url: String, username: String, token: String) {
        runGit("Saving HTTPS access in Keychain") { [self] _, project, _ in
            try await gitCredentialVault.save(url: url, username: username, token: token)
            if projectID == project.id { gitCredentialUsername = username }
            return "HTTPS access saved in this device's Keychain."
        }
    }

    func removeGitCredential(url: String) {
        runGit("Removing saved HTTPS access") { [self] _, project, _ in
            try await gitCredentialVault.remove(url: url)
            if projectID == project.id { gitCredentialUsername = nil }
            return "Removed this repository's saved access token. Local source and commits are unchanged."
        }
    }

    func cloneGit(_ rawURL: String) {
        let id = UUID()
        runGit("Cloning GitHub repository", destinationProject: id) { [self] store, _, revision in
            let address = try GitHTTPSAddress.canonical(rawURL)
            let credential = try await gitCredentialVault.load(url: address)
            var persisted = false
            do {
                let clone = try await store.clone(id, url: address, credential: credential)
                try Task.checkCancellation()
                try ProjectFilePolicy.validate(clone.snapshot.files)
                let parts = URL(string: address)!.path.split(separator: "/").map(String.init)
                let name = String(parts.last!.dropLast(4))
                let project = CrabrixProject(id: id, name: name, files: clone.snapshot.files,
                    entryFile: LocalProjectLoader.preferredEntryFile(in: clone.snapshot.files),
                    provenance: .init(source: .github, owner: parts[0], repository: name,
                        reference: clone.state.branch, commit: clone.state.head, importedAt: Date()))
                let saved = try await projectLibrary.update(project: project, lastBuild: nil)
                persisted = true
                await reloadProjectLists()
                guard isCurrent(revision), playgroundSession == nil, !Task.isCancelled else {
                    return "Cloned \(saved.project.name) with its real Git history. Open it from My Projects; newer editor/room work was kept."
                }
                await retryProjectSave()
                guard isCurrent(revision), playgroundSession == nil, !Task.isCancelled else {
                    return "Cloned \(saved.project.name). Open it from My Projects; your current editor was kept."
                }
                loadProject(saved.project, resourceTreeHash: clone.state.resourceTreeHash)
                acceptGit(clone.state, revision: workspaceRevision)
                let history = try await store.history(id), branches = try await store.branches(id)
                let remote = try await store.remoteState(id)
                let username = try? await gitCredentialVault.username(url: address)
                guard projectID == id else { return "Cloned the repository. Open it in My Projects." }
                gitHistory = history; gitBranches = branches; gitRemote = remote; gitCredentialUsername = username
                return "Cloned \(saved.project.name) · \(clone.state.branch) · \(clone.state.head.map { String($0.prefix(8)) } ?? "no commits"). Preserved \(clone.snapshot.opaquePaths.count) opaque files in repository storage. Nothing was executed."
            } catch {
                if !persisted { try? await store.delete(id) }
                throw error
            }
        }
    }

    func fetchGit() {
        guard let state = gitState, let remote = gitRemote else { gitMessage = "Connect an HTTPS origin first."; return }
        runGit("Fetching origin") { [self] store, project, revision in
            let credential = try await gitCredentialVault.load(url: remote.url)
            let fetched = try await store.fetch(project.id, credential: credential, expectedRevision: state.revision)
            let updated = try await store.status(project.id, files: project.files, expectedRevision: fetched.revision)
            let remote = try await store.remoteState(project.id)
            guard projectID == project.id else { return "Fetch completed for the captured project." }
            acceptGit(updated, revision: revision); gitRemote = remote
            return "Fetched origin. Your local branch and editor source were kept."
        }
    }

    func pullGit() {
        guard gitCanSwitchBranch, let state = gitState, let head = state.head, let remote = gitRemote else {
            gitMessage = "Fast-forward pull requires a fresh, clean local branch outside a live Playground."; return
        }
        runGit("Fetching before fast-forward") { [self] store, project, revision in
            let credential = try await gitCredentialVault.load(url: remote.url)
            let fetched = try await store.fetch(project.id, credential: credential, expectedRevision: state.revision)
            guard isCurrent(revision), playgroundSession == nil else {
                throw GitRepositoryFailure("Fetched origin; newer editor/room work was kept. Refresh before trying a fast-forward.")
            }
            gitRemote = try await store.remoteState(project.id)
            acceptGit(fetched, revision: revision)
            gitLocksWorkspace = true; gitActivity = "Applying clean fast-forward"
            await retryProjectSave()
            guard isCurrent(revision), playgroundSession == nil else { throw GitRepositoryFailure("The editor changed before fast-forward. Refresh and retry.") }
            let checkout = try await store.fastForward(project.id, files: project.files, expectedHead: head, expectedRevision: fetched.revision)
            guard isCurrent(revision), playgroundSession == nil else { throw GitRepositoryFailure("Newer editor work was kept. Refresh Git to inspect its completed branch state.") }
            gitLocksWorkspace = false
            let applied = replaceProjectFilesFromTerminal(checkout.snapshot.files)
            gitLocksWorkspace = true
            guard applied else { throw GitRepositoryFailure("The fetched tree could not be applied to the editor; existing editor source was kept.") }
            await retryProjectSave()
            projectResourceDigest = checkout.state.resourceTreeHash
            acceptGit(checkout.state, revision: workspaceRevision)
            gitHistory = try await store.history(project.id); gitRemote = try await store.remoteState(project.id)
            gitDiff = nil
            return checkout.state.head == head ? "Already up to date; your local branch was kept." : "Fast-forwarded to \(checkout.state.head.map { String($0.prefix(8)) } ?? "HEAD"). No merge or rebase was performed."
        }
    }

    func pushGit() {
        guard let state = gitState, let head = state.head, let remote = gitRemote, !gitNeedsRefresh else {
            gitMessage = "Refresh Git and create a commit before pushing."; return
        }
        runGit("Pushing committed branch") { [self] store, project, revision in
            let credential = try await gitCredentialVault.load(url: remote.url)
            let updated = try await store.push(project.id, credential: credential, expectedHead: head, expectedRevision: state.revision)
            let remote = try await store.remoteState(project.id)
            guard projectID == project.id else { return "Push completed for the captured project." }
            acceptGit(updated, revision: revision); gitRemote = remote
            return "Pushed \(state.branch) at \(head.prefix(8)). Uncommitted editor changes were not uploaded."
        }
    }
}

extension CompilerViewModel {
    func exportGitRepository() {
        guard let state = gitState, state.head != nil, !gitNeedsRefresh else { gitMessage = "Refresh and create a first commit before a complete repository export."; return }
        runGit("Preparing complete repository export") { [self] store, project, revision in
            let copy = try await store.exportCopy(project.id, files: project.files, expectedRevision: state.revision)
            defer { try? FileManager.default.removeItem(at: copy.directory) }
            let archive = try await GitRepositoryTransfer.create(copy: copy, project: project)
            guard isCurrent(revision), !Task.isCancelled else {
                try? FileManager.default.removeItem(at: archive.deletingLastPathComponent())
                throw GitRepositoryFailure("The editor changed while the repository export was prepared. Retry for the current snapshot.")
            }
            acceptGit(copy.state, revision: revision)
            gitArchiveURL = archive; gitArchiveRevision = revision
            return "Repository export ready · complete local history and \(copy.snapshot.opaquePaths.count) opaque files."
        }
    }

    func importGitRepository(from url: URL) async {
        let id = UUID()
        runGit("Importing complete repository", destinationProject: id) { [self] store, _, revision in
            let prepared = try await GitRepositoryTransfer.unpack(url)
            defer { try? FileManager.default.removeItem(at: prepared.directory) }
            var persisted = false
            do {
                let checkout = try await store.importCopy(id, directory: prepared.directory, origin: prepared.envelope.origin)
                try Task.checkCancellation()
                let metadata = prepared.envelope.project, files = checkout.snapshot.files
                try ProjectFilePolicy.validate(files)
                try ProjectFilePolicy.verify(metadata.fileDigests, files: files)
                let entry = files[metadata.entryFile] == nil ? LocalProjectLoader.preferredEntryFile(in: files) : metadata.entryFile
                let project = CrabrixProject(id: id, name: metadata.name, files: files, entryFile: entry,
                    provenance: metadata.provenance, projectDescription: metadata.projectDescription ?? "",
                    tags: metadata.tags ?? [], folder: metadata.folder, kind: metadata.kind ?? .general, isFavorite: metadata.isFavorite ?? false)
                let saved = try await projectLibrary.update(project: project, lastBuild: nil)
                persisted = true
                await reloadProjectLists()
                guard isCurrent(revision), playgroundSession == nil, !Task.isCancelled else {
                    return "Imported \(saved.project.name) as a new local copy with its Git history. Open it in My Projects; current editor/room work was kept."
                }
                await retryProjectSave()
                guard isCurrent(revision), playgroundSession == nil, !Task.isCancelled else { return "Imported \(saved.project.name). Open the new copy in My Projects." }
                loadProject(saved.project, resourceTreeHash: checkout.state.resourceTreeHash)
                acceptGit(checkout.state, revision: workspaceRevision)
                let history = try await store.history(id), branches = try await store.branches(id)
                let remote = try await store.remoteState(id)
                let username: String?
                if let remote { username = try? await gitCredentialVault.username(url: remote.url) } else { username = nil }
                guard projectID == id else { return "Imported the repository. Open the new copy in My Projects." }
                gitHistory = history; gitBranches = branches; gitRemote = remote; gitCredentialUsername = username
                projectTransfer = .ready("Imported a new local repository copy with complete Git history.")
                return "Imported \(saved.project.name) · preserved commit IDs, refs and \(checkout.snapshot.opaquePaths.count) opaque files."
            } catch {
                if !persisted { try? await store.delete(id) }
                throw error
            }
        }
        await gitJob?.value
    }
}
