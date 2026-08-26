import Foundation
import SwiftUI

enum RustProjectTemplate: String, CaseIterable, Identifiable, Sendable {
    case hello
    case empty

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hello: "Hello Rust"
        case .empty: "Empty Binary"
        }
    }

    var detail: String {
        switch self {
        case .hello: "A runnable Cargo project with stdout"
        case .empty: "Cargo.toml and a minimal main.rs"
        }
    }

    var systemImage: String {
        switch self {
        case .hello: "play.rectangle.fill"
        case .empty: "doc.badge.plus"
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
    @Published var isPracticePresented = false

    private let compiler: WasmRustCompiler
    private let githubImporter: GitHubProjectImporter
    private let projectLibrary: ProjectLibrary
    private var lastDiagnostic: RustDiagnostic?
    private var fileContents = ["main.rs": RustSamples.runnable]
    private var entryFile = "main.rs"
    private var compilationTask: Task<Void, Never>?
    private var activeCompilationID: UUID?
    private let userDefaults: UserDefaults

    private static let completedLessonsKey = "crabrix.learn.completedLessonIDs"

    init(
        compiler: WasmRustCompiler = WasmRustCompiler(),
        githubImporter: GitHubProjectImporter = GitHubProjectImporter(),
        projectLibrary: ProjectLibrary = ProjectLibrary(),
        userDefaults: UserDefaults = .standard
    ) {
        self.compiler = compiler
        self.githubImporter = githubImporter
        self.projectLibrary = projectLibrary
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
    var canStartBuild: Bool { !isBusy && !isCompilerDraining && toolchain.isReady }
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
        guard prepareForProjectSwitch() else { return }
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

    func check() {
        guard canStartBuild else { return }
        activity = .checking
        result = nil
        let project = projectSnapshot()
        let compilationID = UUID()
        activeCompilationID = compilationID
        compilationTask = Task { [weak self] in
            guard let self else { return }
            let value = await compiler.check(
                source: project.main,
                sourcePath: project.entryPath,
                supportingFiles: project.supporting
            )
            guard !Task.isCancelled, activeCompilationID == compilationID else {
                isCompilerDraining = false
                return
            }
            finish(value)
        }
    }

    func run() {
        guard canStartBuild else { return }
        activity = .running
        result = nil
        let project = projectSnapshot()
        let compilationID = UUID()
        activeCompilationID = compilationID
        compilationTask = Task { [weak self] in
            guard let self else { return }
            let value = await compiler.run(
                source: project.main,
                sourcePath: project.entryPath,
                supportingFiles: project.supporting
            )
            guard !Task.isCancelled, activeCompilationID == compilationID else {
                isCompilerDraining = false
                return
            }
            finish(value)
        }
    }

    func cancelBuild() {
        guard isBusy else { return }
        compilationTask?.cancel()
        compilationTask = nil
        activeCompilationID = nil
        activity = .idle
        isCompilerDraining = true
        result = .failure(
            phase: .setup,
            detail: "Build cancelled. The Wasm worker is finishing sandbox cleanup in the background."
        )
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

        let source: String
        switch template {
        case .hello:
            source = """
            fn main() {
                println!("Hello from \(name)!");
            }
            """
        case .empty:
            source = """
            fn main() {
                // Start building here.
            }
            """
        }

        let manifest = """
        [package]
        name = "\(name)"
        version = "0.1.0"
        edition = "2024"

        [dependencies]
        """
        loadProject(
            name: name,
            files: ["Cargo.toml": manifest, "src/main.rs": source],
            entryFile: "src/main.rs"
        )
        projectTransfer = .ready("Created \(name) with 2 editable files.")
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
        return true
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
        if isBusy { cancelBuild() }
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

    private func prepareForProjectSwitch() -> Bool {
        guard !isProjectOperationInProgress else { return false }
        if isBusy { cancelBuild() }
        return true
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

        if let diagnostic = value.diagnostics.first {
            lastDiagnostic = diagnostic
            completedStages.insert(.diagnostic)
            completedStages.insert(.explanation)
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
