import Foundation
import SwiftUI

enum RustProjectTemplate: String, CaseIterable, Identifiable, Sendable {
    case hello
    case empty
    case modules
    case cli
    case packages

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hello: "Hello Rust"
        case .empty: "Empty Binary"
        case .modules: "Cargo Modules"
        case .cli: "CLI Starter"
        case .packages: "Cargo Packages"
        }
    }

    var detail: String {
        switch self {
        case .hello: "A runnable Cargo project with stdout"
        case .empty: "Cargo.toml and a minimal main.rs"
        case .modules: "A multi-file project with a reusable Rust module"
        case .cli: "Read command-line arguments with the standard library"
        case .packages: "Two real crates.io packages · the first build downloads and compiles them"
        }
    }

    var systemImage: String {
        switch self {
        case .hello: "play.rectangle.fill"
        case .empty: "doc.badge.plus"
        case .modules: "square.stack.3d.up.fill"
        case .cli: "apple.terminal.fill"
        case .packages: "shippingbox.fill"
        }
    }
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

    @Published var source = RustSamples.runnable
    @Published private(set) var projectName = "hello-crabrix"
    @Published private(set) var fileNames = ["main.rs"]
    @Published private(set) var selectedFile = "main.rs"
    @Published private(set) var activity: Activity = .idle
    @Published private(set) var isCompilerDraining = false
    @Published private(set) var result: CompilationResult?
    @Published private(set) var toolchain: ToolchainStatus
    @Published private(set) var completedStages: Set<Stage> = []
    @Published private(set) var practiceCompleted = false
    @Published private(set) var completedLessonIDs: Set<String>
    @Published private(set) var activeLessonID: String?
    @Published private(set) var projectTransfer: ProjectTransfer = .idle
    @Published private(set) var compatibilityReport: ProjectCompatibilityReport
    @Published private(set) var provenance: CrabrixProject.Provenance?
    @Published private(set) var recentProjects: [ProjectLibraryItem] = []
    @Published private(set) var lastBuild: ProjectBuildRecord?
    @Published private(set) var cargoStage: CargoPreparationStage = .idle
    @Published private(set) var cargoWorkspace: CargoWorkspaceSnapshot = .empty
    @Published private(set) var cargoStorage: CrateStorageUsage = CrateStorageUsage()
    @Published private(set) var diagnosticAdviceState: RustDiagnosticAdviceState = .idle
    @Published var isPracticePresented = false

    private let compiler: WasmRustCompiler
    private let githubImporter: GitHubProjectImporter
    private let projectLibrary: ProjectLibrary
    private let packageManager: CargoPackageManager
    /// The manifest text the current `cargoWorkspace` was resolved from.
    private var resolvedManifestSource: String?
    private var cargoTask: Task<Void, Never>?
    private var lastDiagnostic: RustDiagnostic?
    private var fileContents = ["main.rs": RustSamples.runnable]
    private var entryFile = "main.rs"
    private var compilationTask: Task<Void, Never>?
    private var activeCompilationID: UUID?
    private var diagnosticAdviceTask: Task<Void, Never>?
    private let userDefaults: UserDefaults

    private static let completedLessonsKey = "crabrix.learn.completedLessonIDs"
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
        toolchain = compiler.probe()
        let initialProject = CrabrixProject(
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
        }
    }

    var isBusy: Bool { activity != .idle }
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

    /// True only while the workspace is running a lesson's project. A personal
    /// project is not part of the course, so it gets no "continue learning" step.
    var isLessonContext: Bool { activeLessonID != nil }

    func exportProject() -> CrabrixProject {
        currentProject()
    }

    func openProject(from url: URL) async {
        guard prepareForProjectSwitch() else { return }
        projectTransfer = .openingFiles
        do {
            let project = try await Task.detached {
                if url.pathExtension.lowercased() == "zip" {
                    try CrabrixProjectArchive.load(from: url)
                } else {
                    try LocalProjectLoader.load(from: url, provenance: .files())
                }
            }.value
            loadProject(project)
            projectTransfer = .ready("Opened \(project.files.count) files from Files.")
        } catch {
            projectTransfer = .failed(error.localizedDescription)
        }
    }

    @discardableResult
    func importGitHub(_ rawURL: String) async -> Bool {
        guard prepareForProjectSwitch() else { return false }
        let label = (try? GitHubRepositoryReference.parse(rawURL))
            .map { "\($0.owner)/\($0.repository)" } ?? "repository"
        projectTransfer = .importingGitHub(label)
        do {
            let project = try await githubImporter.importProject(from: rawURL)
            loadProject(project)
            projectTransfer = .ready("Imported \(project.files.count) files from GitHub.")
            return true
        } catch {
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

    func reportProjectFailure(_ error: Error) {
        projectTransfer = .failed(error.localizedDescription)
    }

    @discardableResult
    func openRecentProject(id: UUID) async -> Bool {
        let stoppedBuild = isBusy
        guard prepareForProjectSwitch() else { return false }
        do {
            guard let item = try await projectLibrary.project(id: id) else { return false }
            loadProject(item.project, lastBuild: item.lastBuild)
            projectTransfer = .ready(
                stoppedBuild
                    ? "Stopped the previous build and opened \(item.project.name)."
                    : "Opened recent project \(item.project.name)."
            )
            return true
        } catch {
            projectTransfer = .failed(error.localizedDescription)
            return false
        }
    }

    func check() { startBuild(.checking) }

    func run() { startBuild(.running) }

    private func startBuild(_ mode: Activity) {
        guard canStartBuild else { return }
        resetDiagnosticAdvice()
        activity = mode
        result = nil
        let project = projectSnapshot()
        let manifestSource = manifestSource(in: project)
        let compilationID = UUID()
        activeCompilationID = compilationID
        compilationTask = Task { [weak self] in
            guard let self else { return }

            var plan = CargoBuildPlan.empty
            if let manifestSource {
                do {
                    let snapshot = try await resolveWorkspace(manifestSource: manifestSource)
                    guard activeCompilationID == compilationID else { return }
                    if let blocked = snapshot.blockingPackages.first {
                        finish(
                            .failure(
                                phase: .setup,
                                detail: "\(blocked.name) \(blocked.version) cannot be built locally: "
                                    + (blocked.compatibility.detail ?? "unsupported package")
                            )
                        )
                        return
                    }
                    plan = snapshot.plan
                } catch {
                    guard activeCompilationID == compilationID else { return }
                    cargoStage = .failed(error.localizedDescription)
                    finish(
                        .failure(
                            phase: .setup,
                            detail: "Dependency resolution failed: \(error.localizedDescription)"
                        )
                    )
                    return
                }
            }

            let progress: @Sendable (CargoBuildProgress) -> Void = { [weak self] update in
                Task { @MainActor [weak self] in
                    guard let self, activeCompilationID == compilationID else { return }
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
                    source: project.main,
                    sourcePath: project.entryPath,
                    supportingFiles: project.supporting,
                    plan: plan,
                    onDependencyProgress: plan.isEmpty ? nil : progress
                )
            default:
                await compiler.run(
                    source: project.main,
                    sourcePath: project.entryPath,
                    supportingFiles: project.supporting,
                    plan: plan,
                    onDependencyProgress: plan.isEmpty ? nil : progress
                )
            }

            guard !Task.isCancelled, activeCompilationID == compilationID else {
                isCompilerDraining = false
                return
            }
            if !plan.isEmpty { cargoStage = .ready }
            finish(value)
            // A build is the only source of verified compatibility, so refresh
            // the package list with whatever the compiler just learned.
            if !plan.isEmpty, let manifestSource {
                resolvedManifestSource = nil
                _ = try? await resolveWorkspace(manifestSource: manifestSource)
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

    var cargoManifestSource: String? {
        var files = fileContents
        files[selectedFile] = source
        return files["Cargo.toml"]
    }

    /// Resolves and downloads, reusing the last snapshot when the manifest text
    /// has not changed.
    @discardableResult
    private func resolveWorkspace(manifestSource: String) async throws -> CargoWorkspaceSnapshot {
        if resolvedManifestSource == manifestSource, !cargoWorkspace.isEmpty {
            return cargoWorkspace
        }
        let handler: @Sendable (CargoPreparationStage) -> Void = { [weak self] stage in
            Task { @MainActor [weak self] in self?.cargoStage = stage }
        }
        let snapshot = try await packageManager.prepare(
            manifestSource: manifestSource,
            onStage: handler
        )
        cargoWorkspace = snapshot
        resolvedManifestSource = manifestSource
        cargoStage = snapshot.isEmpty ? .idle : .ready
        return snapshot
    }

    /// Explicitly re-resolves the project's dependencies and writes Cargo.lock.
    func refreshCargoWorkspace() {
        guard let manifestSource = cargoManifestSource else {
            cargoWorkspace = .empty
            cargoStage = .idle
            resolvedManifestSource = nil
            return
        }
        cargoTask?.cancel()
        cargoTask = Task { [weak self] in
            guard let self else { return }
            do {
                let snapshot = try await resolveWorkspace(manifestSource: manifestSource)
                if let lockfile = snapshot.lockfile, !snapshot.packages.isEmpty {
                    writeLockfile(lockfile)
                }
            } catch is CancellationError {
                return
            } catch {
                cargoStage = .failed(error.localizedDescription)
            }
            await refreshCargoStorage()
        }
    }

    /// Records the resolved graph in the project, exactly as `cargo fetch` does,
    /// so the same versions rebuild later and travel with the project.
    private func writeLockfile(_ contents: String) {
        guard !isBusy else { return }
        // Sync the editor buffer first so an in-progress edit is not lost.
        fileContents[selectedFile] = source
        guard fileContents["Cargo.lock"] != contents else { return }
        fileContents["Cargo.lock"] = contents
        if selectedFile == "Cargo.lock" { source = contents }
        fileNames = fileContents.keys.sorted(by: projectFileOrder)
        let project = currentProject()
        Task { await remember(project, lastBuild: lastBuild) }
    }

    /// Downloads every resolved package so the project builds with no network.
    func downloadDependenciesForOffline() {
        resolvedManifestSource = nil
        refreshCargoWorkspace()
    }

    func refreshCargoStorage() async {
        cargoStorage = await packageManager.storageUsage()
    }

    func clearCargoBuildArtifacts() async {
        try? await packageManager.clearBuildArtifacts()
        resolvedManifestSource = nil
        await refreshCargoStorage()
        refreshCargoWorkspace()
    }

    func clearCargoPackageCache() async {
        try? await packageManager.clearPackageCache()
        resolvedManifestSource = nil
        cargoWorkspace = .empty
        cargoStage = .idle
        await refreshCargoStorage()
    }

    func clearCargoDownloadedArchives() async {
        try? await packageManager.clearDownloadedArchives()
        await refreshCargoStorage()
    }

    func cancelBuild() {
        guard isBusy else { return }
        // Interrupt the guest itself; the task cancellation below only detaches
        // the UI from a worker that would otherwise run to completion.
        compiler.cancel()
        compilationTask?.cancel()
        compilationTask = nil
        activeCompilationID = nil
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

    func beginLesson(_ id: String) {
        activeLessonID = id
    }

    func completeLesson(_ id: String) {
        completedLessonIDs.insert(id)
        persistCompletedLessons()
    }

    func loadShowcaseProject(id: String) {
        guard let showcase = RustShowcaseLibrary.projects.first(where: { $0.id == id }) else {
            projectTransfer = .failed("That library project is unavailable.")
            return
        }
        loadProject(showcase.project)
        projectTransfer = .ready("Opened \(showcase.title) from the project library.")
    }

    func createProject(name rawName: String, template: RustProjectTemplate) {
        guard prepareForProjectSwitch() else { return }
        let name = Self.normalizedProjectName(rawName)
        guard !name.isEmpty else {
            projectTransfer = .failed("Enter a project name.")
            return
        }

        let files: [String: String]
        switch template {
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
        }

        let dependencies = switch template {
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
        loadProject(name: name, files: projectFiles, entryFile: "src/main.rs")
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
        if selectedFile == "Cargo.toml" { source = updated }
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
        files: [String: String],
        entryFile requestedEntry: String? = nil,
        provenance: CrabrixProject.Provenance? = nil
    ) {
        if isBusy { cancelBuild() }
        resetDiagnosticAdvice()
        projectName = name
        fileContents = files
        entryFile = requestedEntry
            ?? (files["src/main.rs"] != nil ? "src/main.rs" : "main.rs")
        fileNames = files.keys.sorted(by: projectFileOrder)
        selectedFile = entryFile
        source = files[entryFile] ?? ""
        self.provenance = provenance
        lastBuild = nil
        compatibilityReport = ProjectCompatibilityReport.scan(
            CrabrixProject(
                name: name,
                files: files,
                entryFile: entryFile,
                provenance: provenance
            )
        )
        result = nil
        lastDiagnostic = nil
        completedStages = []
        practiceCompleted = false
        activeLessonID = nil
        resetCargoWorkspace()
        let project = currentProject()
        Task { await remember(project, lastBuild: nil) }
    }

    /// Drops the resolved graph so the next build resolves the new manifest.
    private func resetCargoWorkspace() {
        cargoTask?.cancel()
        cargoTask = nil
        resolvedManifestSource = nil
        cargoWorkspace = .empty
        cargoStage = .idle
    }

    private func loadProject(_ project: CrabrixProject, lastBuild: ProjectBuildRecord? = nil) {
        loadProject(
            name: project.name,
            files: project.files,
            entryFile: project.entryFile,
            provenance: project.provenance
        )
        self.lastBuild = lastBuild
        Task { await remember(project, lastBuild: lastBuild) }
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
        let plan = cargoWorkspace.plan
        diagnosticAdviceTask = Task { [weak self] in
            guard let self else { return }
            do {
                let draft = try await AppleIntelligenceDiagnosticAdvisor.generate(
                    diagnostic: diagnostic,
                    project: project,
                    targetFile: targetFile
                )
                try Task.checkCancellation()

                guard currentProject().files[targetFile] == originalSource else {
                    diagnosticAdviceState = .unavailable(
                        "The source changed during analysis. Run Check again for a fresh suggestion."
                    )
                    diagnosticAdviceTask = nil
                    return
                }

                guard !draft.edits.isEmpty else {
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
                    plan: plan
                )
                guard !Task.isCancelled else { return }
                guard currentProject().files[targetFile] == originalSource else {
                    diagnosticAdviceState = .unavailable(
                        "The source changed during verification. Run Check again for a fresh suggestion."
                    )
                    diagnosticAdviceTask = nil
                    return
                }

                let verification: RustDiagnosticAdvice.Verification
                if verificationResult.succeeded {
                    verification = .verified
                } else {
                    let reason = verificationResult.diagnostics.first?.message
                        ?? verificationResult.detail
                    verification = .rejected(reason)
                }
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
                if diagnosticAdviceState.isWorking {
                    diagnosticAdviceState = .idle
                }
                diagnosticAdviceTask = nil
            } catch {
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
        if diagnosticAdviceState == .verifying {
            compiler.cancel()
        }
        diagnosticAdviceState = .idle
    }

    func applyAppleIntelligenceAdvice() {
        guard case let .ready(advice) = diagnosticAdviceState,
              advice.canApply,
              let proposedSource = advice.proposedSource
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
        completedStages.insert(.repair)
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
            name: projectName,
            files: files,
            entryFile: entryFile,
            provenance: provenance
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

    private func finish(_ value: CompilationResult) {
        result = value
        activity = .idle
        isCompilerDraining = false
        compilationTask = nil
        activeCompilationID = nil
        lastBuild = ProjectBuildRecord(result: value)

        if let diagnostic = value.diagnostics.first(where: { $0.level == "error" })
            ?? value.diagnostics.first {
            lastDiagnostic = diagnostic
            completedStages.insert(.diagnostic)
            completedStages.insert(.explanation)
            let diagnosticsSetting = userDefaults.object(
                forKey: Self.appleIntelligenceDiagnosticsKey
            ) as? Bool ?? true
            if diagnosticsSetting, !value.succeeded, diagnostic.level == "error" {
                requestAppleIntelligenceAdvice()
            }
        } else if value.succeeded, lastDiagnostic != nil {
            completedStages.insert(.repair)
        }
        if value.succeeded, value.phase == .run, let activeLessonID {
            completeLesson(activeLessonID)
        }
        Task { await remember(currentProject(), lastBuild: lastBuild) }
    }

    private func persistCompletedLessons() {
        userDefaults.set(completedLessonIDs.sorted(), forKey: Self.completedLessonsKey)
    }

    private func remember(_ project: CrabrixProject, lastBuild: ProjectBuildRecord?) async {
        if let items = try? await projectLibrary.record(project: project, lastBuild: lastBuild) {
            recentProjects = items
        }
    }
}
