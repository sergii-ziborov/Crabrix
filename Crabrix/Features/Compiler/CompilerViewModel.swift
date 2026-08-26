import Foundation
import SwiftUI

@MainActor
final class CompilerViewModel: ObservableObject {
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
    @Published var isPracticePresented = false

    private let compiler: WasmRustCompiler
    private var lastDiagnostic: RustDiagnostic?
    private var fileContents = ["main.rs": RustSamples.runnable]

    init(compiler: WasmRustCompiler = WasmRustCompiler()) {
        self.compiler = compiler
        toolchain = compiler.probe()
    }

    var isBusy: Bool { activity != .idle }
    var primaryDiagnostic: RustDiagnostic? { result?.diagnostics.first ?? lastDiagnostic }

    func check() {
        guard !isBusy, toolchain.isReady else { return }
        activity = .checking
        result = nil
        let project = projectSnapshot()
        Task {
            let value = await compiler.check(
                source: project.main,
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
                "main.rs": RustSamples.multiFileMain,
                "greeter.rs": RustSamples.multiFileGreeter,
            ]
        )
    }

    func selectFile(_ name: String) {
        guard !isBusy, name != selectedFile, fileContents[name] != nil else { return }
        fileContents[selectedFile] = source
        selectedFile = name
        source = fileContents[name] ?? ""
    }

    private func loadProject(name: String, files: [String: String]) {
        guard !isBusy else { return }
        projectName = name
        fileContents = files
        fileNames = files.keys.sorted { lhs, rhs in
            lhs == "main.rs" || (rhs != "main.rs" && lhs < rhs)
        }
        selectedFile = "main.rs"
        source = files["main.rs"] ?? ""
        result = nil
        lastDiagnostic = nil
        completedStages = []
        practiceCompleted = false
    }

    func applyRepair() {
        guard selectedFile == "main.rs",
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

    private func projectSnapshot() -> (main: String, supporting: [String: String]) {
        var files = fileContents
        files[selectedFile] = source
        let main = files.removeValue(forKey: "main.rs") ?? ""
        return (main, files)
    }

    private func finish(_ value: CompilationResult) {
        result = value
        activity = .idle

        if let diagnostic = value.diagnostics.first {
            lastDiagnostic = diagnostic
            completedStages.insert(.diagnostic)
            completedStages.insert(.explanation)
        } else if value.succeeded, lastDiagnostic != nil {
            completedStages.insert(.repair)
        }
    }
}
