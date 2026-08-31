import Foundation
import SwiftUI

enum RustProjectTemplate: String, CaseIterable, Identifiable, Sendable {
    case hello
    case empty
    case modules
    case cli
    case packages
    case visual

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hello: "Hello Rust"
        case .empty: "Empty Binary"
        case .modules: "Cargo Modules"
        case .cli: "CLI Starter"
        case .packages: "Cargo Packages"
        case .visual: "Visual Canvas"
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
        }
    }

    var defaultProjectKind: CrabrixProject.Kind {
        switch self {
        case .hello, .modules: .learning
        case .empty: .general
        case .cli: .commandLine
        case .packages: .application
        case .visual: .visual
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
        case running

        var label: String {
            switch self {
            case .idle: "Ready"
            case .checking: "Type-checking with bundled rustc…"
            case .running: "Compiling and running locally…"
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
    @Published private(set) var toolchain: ToolchainStatus
    @Published private(set) var completedStages: Set<Stage> = []
    @Published private(set) var practiceCompleted = false
    @Published private(set) var completedLessonIDs: Set<String>
    @Published private(set) var lessonAnswerIndices: [String: Int]
    @Published private(set) var activeLessonID: String?
    @Published private(set) var activeLessonIsReview = false
    @Published private(set) var projectTransfer: ProjectTransfer = .idle
    @Published private(set) var compatibilityReport: ProjectCompatibilityReport
    @Published private(set) var provenance: CrabrixProject.Provenance?
    @Published private(set) var recentProjects: [ProjectLibraryItem] = []
    @Published private(set) var allProjects: [ProjectLibraryItem] = []
    @Published private(set) var lastBuild: ProjectBuildRecord?
    @Published private(set) var cargoStage: CargoPreparationStage = .idle
    @Published private(set) var cargoWorkspace: CargoWorkspaceSnapshot = .empty
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
    private var lastDiagnostic: RustDiagnostic?
    private var unresolvedDiagnosticEvidence: (signature: String, beforeHash: String)?
    private var activeLessonInitialSourceTreeHash: String?
    private var activeLessonObservedDiagnosticCodes: Set<String> = []
    private var fileContents = ["main.rs": RustSamples.runnable]
    private var entryFile = "main.rs"
    private var compilationTask: Task<Void, Never>?
    private var activeCompilationID: UUID?
    private var diagnosticAdviceTask: Task<Void, Never>?
    private var diagnosticAdviceRevision: WorkspaceRevision?
    private var autosaveTask: Task<Void, Never>?
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
        self.projectLibrary = projectLibrary
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
            recentProjects = (try? await projectLibrary.items()) ?? []
            allProjects = (try? await projectLibrary.allItems()) ?? []
        }
    }

    var isBusy: Bool { activity != .idle }
    var earnsProgressForCurrentRun: Bool { !activeLessonIsReview }
    var canContinueFromLessonResult: Bool {
        guard let activeLessonID else { return false }
        return completedLessonIDs.contains(activeLessonID)
    }
    var canStartBuild: Bool {
        !isBusy
            && !isCompilerDraining
            && !diagnosticAdviceState.isWorking
            && toolchain.isReady
    }
    var primaryDiagnostic: RustDiagnostic? {
        result?.diagnostics.first(where: { $0.level == "error" })
            ?? result?.diagnostics.first
            ?? lastDiagnostic
    }
    var cargoManifest: CargoManifest? {
        var files = fileContents
        files[selectedFile] = source
        return files["Cargo.toml"].flatMap(CargoManifest.parse)
    }

    var isProjectOperationInProgress: Bool { projectTransfer.isWorking }

    var workspaceRevision: WorkspaceRevision {
        WorkspaceRevision.capture(
            project: currentProject(),
            generation: workspaceGeneration,
            toolchainID: WasmRustCompiler.toolchainVersion
        )
    }

    /// True only while the workspace is running a lesson's project. A personal
    /// project is not part of the course, so it gets no "continue learning" step.
    var isLessonContext: Bool { activeLessonID != nil }

    func exportProject() -> CrabrixProject {
        currentProject()
    }

    func openProject(from url: URL) async {
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
        guard let rawURL = SharedImportQueue.dequeue() else { return }
        await importGitHub(rawURL)
    }

    func markProjectSaved() {
        projectTransfer = .ready("Saved \(projectName) to Files.")
        Task { await remember(currentProject(), lastBuild: lastBuild) }
    }

    @discardableResult
    func updateCurrentProjectDetails(
        name rawName: String,
        description: String,
        tags: [String],
        folder: String?,
        kind: CrabrixProject.Kind,
        isFavorite: Bool
    ) -> Bool {
        let name = Self.normalizedProjectName(rawName)
        guard !name.isEmpty else {
            projectTransfer = .failed("Enter a project name.")
            return false
        }
        projectName = name
        projectDescription = description
            .trimmingCharacters(in: .whitespacesAndNewlines)
        projectTags = CrabrixProject.normalizedTags(tags)
        projectFolder = CrabrixProject.normalizedFolder(folder)
        projectKind = kind
        projectIsFavorite = isFavorite
        projectTransfer = .ready("Updated project details.")
        Task { await remember(currentProject(), lastBuild: lastBuild) }
        return true
    }

    func toggleFavorite(projectID: UUID) async {
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
            _ = try await projectLibrary.update(
                project: project,
                lastBuild: item.lastBuild
            )
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
            loadProject(item.project, lastBuild: item.lastBuild)
            projectTransfer = .ready(
                stoppedBuild
                    ? "Stopped the previous build and opened \(item.project.name)."
                    : "Opened recent project \(item.project.name)."
            )
            return true
        } catch {
            guard isCurrent(revision) else { return false }
            projectTransfer = .failed(error.localizedDescription)
            return false
        }
    }

    func check() { startBuild(.checking) }

    func run() { startBuild(.running) }

    private func startBuild(_ mode: Activity) {
        guard canStartBuild else { return }
        resetDiagnosticAdvice()
        let revision = workspaceRevision
        activity = mode
        result = nil
        let project = projectSnapshot()
        var projectFiles = project.supporting
        projectFiles[project.entryPath] = project.main
        let compilerProject = compilerProjectSnapshot(from: project)
        let manifestSource = manifestSource(in: project)
        let lockfileSource = project.entryPath == "Cargo.lock"
            ? project.main
            : project.supporting["Cargo.lock"]
        let rootEdition = rootEdition(from: manifestSource)
        let compilationID = UUID()
        activeCompilationID = compilationID
        compilationTask = Task { [weak self] in
            guard let self else { return }

            var plan = CargoBuildPlan.empty
            if let manifestSource {
                do {
                    let snapshot = try await resolveWorkspace(
                        manifestSource: manifestSource,
                        lockfileSource: lockfileSource,
                        projectFiles: projectFiles,
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
                            revision: revision
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
                        revision: revision
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
                }
            }

            let value = switch mode {
            case .checking:
                await compiler.check(
                    source: compilerProject.main,
                    sourcePath: compilerProject.entryPath,
                    supportingFiles: compilerProject.supporting,
                    edition: rootEdition,
                    plan: plan,
                    onDependencyProgress: plan.isEmpty ? nil : progress
                )
            default:
                await compiler.run(
                    source: compilerProject.main,
                    sourcePath: compilerProject.entryPath,
                    supportingFiles: compilerProject.supporting,
                    edition: rootEdition,
                    plan: plan,
                    onDependencyProgress: plan.isEmpty ? nil : progress
                )
            }

            guard !Task.isCancelled,
                  activeCompilationID == compilationID,
                  isCurrent(revision)
            else {
                discardCompilationIfActive(compilationID)
                return
            }
            if !plan.isEmpty { cargoStage = .ready }
            finish(value, revision: revision)
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
        guard let activeLessonID,
              let challenge = AlgorithmCourseCatalog.challenge(for: activeLessonID)
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
        revision: WorkspaceRevision
    ) async throws -> CargoWorkspaceSnapshot {
        guard isCurrent(revision) else { throw CancellationError() }
        if resolvedManifestSource == manifestSource,
           resolvedWorkspaceRevision == revision,
           !cargoWorkspace.isEmpty {
            return cargoWorkspace
        }
        let handler: @Sendable (CargoPreparationStage) -> Void = { [weak self] stage in
            Task { @MainActor [weak self] in
                guard let self, isCurrent(revision) else { return }
                cargoStage = stage
            }
        }
        let snapshot = try await packageManager.prepare(
            manifestSource: manifestSource,
            lockfileSource: lockfileSource,
            mode: mode,
            projectFiles: projectFiles,
            onStage: handler
        )
        guard !Task.isCancelled, isCurrent(revision) else { throw CancellationError() }
        cargoWorkspace = snapshot
        resolvedManifestSource = manifestSource
        resolvedWorkspaceRevision = revision
        cargoStage = snapshot.isEmpty ? .idle : .ready
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
                if let lockfile = snapshot.lockfile, !snapshot.packages.isEmpty {
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
            lastDiagnostic = nil
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
        lastDiagnostic = nil
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
        guard isBusy, activeCompilationID != nil else { return }
        // Interrupt the guest itself; the task cancellation below only detaches
        // the UI from a worker that would otherwise run to completion.
        compiler.cancel()
        compilationTask?.cancel()
        // Keep the active identity until the queue callback returns. Clearing it
        // here made `discardCompilationIfActive` reject that callback, leaving
        // `isCompilerDraining` true forever and permanently disabling Run.
        activity = .idle
        isCompilerDraining = true
        if cargoStage.isWorking { cargoStage = .idle }
        result = .failure(
            phase: .setup,
            detail: "Build stopped. The Wasm guest is being interrupted and its sandbox released."
        )
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

    func beginLesson(_ id: String, isReview: Bool = false) {
        activeLessonID = id
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

    /// Keeps the first committed quick-check answer so reopening a lesson is
    /// review, not a second attempt that can spend or earn resources again.
    func recordLessonAnswer(_ index: Int, for lessonID: String) {
        guard index >= 0, lessonAnswerIndices[lessonID] == nil else { return }
        lessonAnswerIndices[lessonID] = index
        userDefaults.set(lessonAnswerIndices, forKey: Self.lessonAnswersKey)
    }

    func loadShowcaseProject(id: String) {
        guard let showcase = RustShowcaseLibrary.projects.first(where: { $0.id == id }) else {
            projectTransfer = .failed("That library project is unavailable.")
            return
        }
        loadProject(showcase.project)
        projectTransfer = .ready("Opened \(showcase.title) from the project library.")
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
        projectFiles["Cargo.toml"] = manifest
        loadProject(
            name: name,
            files: projectFiles,
            entryFile: "src/main.rs",
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
        guard fileContents[path] == nil else {
            projectTransfer = .failed("\(path) already exists.")
            return false
        }

        addProjectFile(path: path, source: "// \(path)\n")
        projectTransfer = .ready("Created \(path).")
        return true
    }

    @discardableResult
    func createModuleFolder(at rawPath: String) -> Bool {
        guard !isBusy, !isProjectOperationInProgress,
              let folder = normalizedProjectPath(rawPath, defaultRoot: "src")
        else { return false }
        let path = "\(folder)/mod.rs"
        guard fileContents[path] == nil else {
            projectTransfer = .failed("\(folder) already contains mod.rs.")
            return false
        }

        let moduleName = folder.split(separator: "/").last.map(String.init) ?? "module"
        addProjectFile(path: path, source: "// \(moduleName) module\n")
        projectTransfer = .ready("Created \(folder) with mod.rs.")
        return true
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
        lastDiagnostic = nil
        lastBuild = nil
        compatibilityReport = ProjectCompatibilityReport.scan(currentProject())
        projectTransfer = .ready("Added \(name) \(requirement) to Cargo.toml.")
        let project = currentProject()
        Task { await remember(project, lastBuild: nil) }
        refreshCargoWorkspace()
        return true
    }

    func selectFile(_ name: String) {
        guard !isBusy, name != selectedFile, fileContents[name] != nil else { return }
        fileContents[selectedFile] = source
        selectedFile = name
        source = fileContents[name] ?? ""
    }

    @discardableResult
    func replaceProjectFilesFromTerminal(
        _ files: [String: String],
        selecting requestedSelection: String? = nil
    ) -> Bool {
        guard !isBusy, !isProjectOperationInProgress, !files.isEmpty else { return false }

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
        lastDiagnostic = nil
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
        lastBuild: ProjectBuildRecord? = nil
    ) {
        if isBusy { cancelBuild() }
        resetDiagnosticAdvice()
        autosaveTask?.cancel()
        suppressAutosave = true
        projectID = id
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
        self.lastBuild = lastBuild
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
        lastDiagnostic = nil
        unresolvedDiagnosticEvidence = nil
        repairRewardEventKey = nil
        completedStages = []
        practiceCompleted = false
        activeLessonID = nil
        activeLessonIsReview = false
        activeLessonInitialSourceTreeHash = nil
        activeLessonObservedDiagnosticCodes = []
        lessonEvidenceMessage = nil
        resetCargoWorkspace()
        suppressAutosave = false
        workspaceGeneration &+= 1
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

    private func loadProject(_ project: CrabrixProject, lastBuild: ProjectBuildRecord? = nil) {
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
            lastBuild: lastBuild
        )
    }

    private func prepareForProjectSwitch() -> Bool {
        guard !isProjectOperationInProgress else { return false }
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

    func requestAppleIntelligenceAdvice() {
        guard !isBusy,
              !diagnosticAdviceState.isWorking,
              let diagnostic = primaryDiagnostic
        else { return }

        let project = currentProject()
        guard let targetFile = diagnosticTargetFile(for: diagnostic, in: project.files),
              targetFile.lowercased().hasSuffix(".rs"),
              let originalSource = project.files[targetFile]
        else {
            diagnosticAdviceState = .unavailable(
                "The compiler did not identify an editable Rust source file for this issue."
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

                guard !draft.edits.isEmpty else {
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

    private func addProjectFile(path: String, source newSource: String) {
        fileContents[selectedFile] = source
        fileContents[path] = newSource
        fileNames = fileContents.keys.sorted(by: projectFileOrder)
        selectedFile = path
        source = newSource
        result = nil
        lastDiagnostic = nil
        unresolvedDiagnosticEvidence = nil
        repairRewardEventKey = nil
        lastBuild = nil
        completedStages = []
        compatibilityReport = ProjectCompatibilityReport.scan(currentProject())
        let project = currentProject()
        Task { await remember(project, lastBuild: nil) }
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
        let dependencyLine = "\(name) = \"\(requirement)\""

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

    private func finish(_ value: CompilationResult, revision: WorkspaceRevision) {
        guard isCurrent(revision) else { return }
        result = value
        activity = .idle
        isCompilerDraining = false
        compilationTask = nil
        activeCompilationID = nil
        lastBuild = ProjectBuildRecord(result: value)

        let errorDiagnostic = value.diagnostics.first(where: { $0.level == "error" })
        activeLessonObservedDiagnosticCodes.formUnion(value.diagnostics.compactMap(\.code))
        if let diagnostic = errorDiagnostic ?? value.diagnostics.first {
            lastDiagnostic = diagnostic
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
            if diagnosticsSetting { requestAppleIntelligenceAdvice() }
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
           let lesson = RustCourseCatalog.lesson(id: activeLessonID) {
            let validation = LessonEvidenceValidator.validateCompilerAttempt(
                lesson: lesson,
                result: value,
                project: currentProject(),
                initialSourceTreeHash: activeLessonInitialSourceTreeHash,
                currentSourceTreeHash: revision.sourceTreeHash,
                observedDiagnosticCodes: activeLessonObservedDiagnosticCodes
            )
            lessonEvidenceMessage = validation.detail
            appendLessonAttemptEvidence(
                lessonID: activeLessonID,
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
                completedAt: Date()
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
        if let items = try? await projectLibrary.record(project: project, lastBuild: lastBuild) {
            recentProjects = items
        }
        allProjects = (try? await projectLibrary.allItems()) ?? allProjects
    }

    private func reloadProjectLists() async {
        recentProjects = (try? await projectLibrary.items()) ?? recentProjects
        allProjects = (try? await projectLibrary.allItems()) ?? allProjects
    }

    private func isCurrent(_ revision: WorkspaceRevision) -> Bool {
        workspaceRevision == revision
    }

    private func discardCompilationIfActive(_ compilationID: UUID) {
        guard activeCompilationID == compilationID else { return }
        activity = .idle
        isCompilerDraining = false
        compilationTask = nil
        activeCompilationID = nil
        if cargoStage.isWorking { cargoStage = .idle }
    }

    private func workspaceDidChange() {
        guard !suppressAutosave else { return }
        workspaceGeneration &+= 1
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
        autosaveTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(500))
            } catch {
                return
            }
            guard let self, !Task.isCancelled else { return }
            await remember(currentProject(), lastBuild: lastBuild)
            autosaveTask = nil
        }
    }
}
