import Foundation
import SwiftUI

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
    @Published private(set) var result: CompilationResult?
    @Published private(set) var toolchain: ToolchainStatus
    @Published private(set) var completedStages: Set<Stage> = []
    @Published private(set) var practiceCompleted = false
    @Published private(set) var projectTransfer: ProjectTransfer = .idle
    @Published private(set) var compatibilityReport: ProjectCompatibilityReport
    @Published private(set) var provenance: CrabrixProject.Provenance?
    @Published private(set) var recentProjects: [ProjectLibraryItem] = []
    @Published private(set) var lastBuild: ProjectBuildRecord?
    @Published var isPracticePresented = false

    private let compiler: WasmRustCompiler
    private let githubImporter: GitHubProjectImporter
    private let projectLibrary: ProjectLibrary
    private var lastDiagnostic: RustDiagnostic?
    private var fileContents = ["main.rs": RustSamples.runnable]
    private var entryFile = "main.rs"

    init(
        compiler: WasmRustCompiler = WasmRustCompiler(),
        githubImporter: GitHubProjectImporter = GitHubProjectImporter(),
        projectLibrary: ProjectLibrary = ProjectLibrary()
    ) {
        self.compiler = compiler
        self.githubImporter = githubImporter
        self.projectLibrary = projectLibrary
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
    var primaryDiagnostic: RustDiagnostic? { result?.diagnostics.first ?? lastDiagnostic }
    var cargoManifest: CargoManifest? {
        var files = fileContents
        files[selectedFile] = source
        return files["Cargo.toml"].flatMap(CargoManifest.parse)
    }

    var isProjectOperationInProgress: Bool { projectTransfer.isWorking }

    func exportProject() -> CrabrixProject {
        currentProject()
    }

    func openProject(from url: URL) async {
        guard !isBusy, !isProjectOperationInProgress else { return }
        projectTransfer = .openingFiles
        do {
            let project = try await Task.detached {
                try LocalProjectLoader.load(from: url, provenance: .files())
            }.value
            loadProject(project)
            projectTransfer = .ready("Opened \(project.files.count) files from Files.")
        } catch {
            projectTransfer = .failed(error.localizedDescription)
        }
    }

    @discardableResult
    func importGitHub(_ rawURL: String) async -> Bool {
        guard !isBusy, !isProjectOperationInProgress else { return false }
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

    func openRecentProject(id: UUID) async {
        guard !isBusy, !isProjectOperationInProgress else { return }
        do {
            guard let item = try await projectLibrary.project(id: id) else { return }
            loadProject(item.project, lastBuild: item.lastBuild)
            projectTransfer = .ready("Opened recent project \(item.project.name).")
        } catch {
            projectTransfer = .failed(error.localizedDescription)
        }
    }

    func check() {
        guard !isBusy, toolchain.isReady else { return }
        activity = .checking
        result = nil
        let project = projectSnapshot()
        Task {
            let value = await compiler.check(
                source: project.main,
                sourcePath: project.entryPath,
                supportingFiles: project.supporting
            )
            finish(value)
        }
    }

    func run() {
        guard !isBusy, toolchain.isReady else { return }
        activity = .running
        result = nil
        let project = projectSnapshot()
        Task {
            let value = await compiler.run(
                source: project.main,
                sourcePath: project.entryPath,
                supportingFiles: project.supporting
            )
            finish(value)
        }
    }

    func loadRunnableSample() {
        loadProject(name: "hello-crabrix", files: ["main.rs": RustSamples.runnable])
    }

    func loadBorrowDiagnosticSample() {
        loadProject(name: "borrow-lab", files: ["main.rs": RustSamples.broken])
    }

    func loadMultiFileSample() {
        loadProject(
            name: "modules-lab",
            files: [
                "Cargo.toml": RustSamples.cargoManifest,
                "src/main.rs": RustSamples.multiFileMain,
                "src/greeter.rs": RustSamples.multiFileGreeter,
            ]
        )
    }

    func selectFile(_ name: String) {
        guard !isBusy, name != selectedFile, fileContents[name] != nil else { return }
        fileContents[selectedFile] = source
        selectedFile = name
        source = fileContents[name] ?? ""
    }

    private func loadProject(
        name: String,
        files: [String: String],
        entryFile requestedEntry: String? = nil,
        provenance: CrabrixProject.Provenance? = nil
    ) {
        guard !isBusy else { return }
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
        let project = currentProject()
        Task { await remember(project, lastBuild: nil) }
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

    func applyRepair() {
        guard selectedFile == entryFile,
              let diagnostic = primaryDiagnostic,
              let repaired = BorrowRepair.apply(to: source, diagnostic: diagnostic)
        else {
            return
        }
        source = repaired
        result = nil
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
            case entryFile: 1
            default: 2
            }
        }
        let lhsRank = rank(lhs)
        let rhsRank = rank(rhs)
        return lhsRank == rhsRank
            ? lhs.localizedStandardCompare(rhs) == .orderedAscending
            : lhsRank < rhsRank
    }

    private func finish(_ value: CompilationResult) {
        result = value
        activity = .idle
        lastBuild = ProjectBuildRecord(result: value)

        if let diagnostic = value.diagnostics.first {
            lastDiagnostic = diagnostic
            completedStages.insert(.diagnostic)
            completedStages.insert(.explanation)
        } else if value.succeeded, lastDiagnostic != nil {
            completedStages.insert(.repair)
        }
        Task { await remember(currentProject(), lastBuild: lastBuild) }
    }

    private func remember(_ project: CrabrixProject, lastBuild: ProjectBuildRecord?) async {
        if let items = try? await projectLibrary.record(project: project, lastBuild: lastBuild) {
            recentProjects = items
        }
    }
}
