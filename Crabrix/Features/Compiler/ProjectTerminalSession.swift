import Foundation

@MainActor
final class ProjectTerminalSession: ObservableObject {
    struct Line: Identifiable, Equatable {
        enum Kind: Equatable {
            case command
            case info
            case success
            case error
        }

        let id = UUID()
        let text: String
        let kind: Kind
    }

    @Published var command = ""
    @Published private(set) var lines: [Line] = []
    @Published private(set) var projectName = ""

    private var buffers: [String: [Line]] = [:]
    private var resultSignatures: [String: String] = [:]

    func attach(to project: CrabrixProject) {
        guard projectName != project.name else { return }
        if !projectName.isEmpty { buffers[projectName] = lines }
        projectName = project.name
        if let stored = buffers[project.name] {
            lines = stored
        } else {
            lines = [
                Line(
                    text: "Crabrix project terminal · /workspace/\(project.name)",
                    kind: .info
                ),
                Line(text: "Type help to see available commands.", kind: .info),
            ]
            buffers[project.name] = lines
        }
        command = ""
    }

    func submit(
        project: CrabrixProject,
        isBusy: Bool,
        onCheck: () -> Void,
        onRun: () -> Void
    ) {
        let raw = command.trimmingCharacters(in: .whitespacesAndNewlines)
        attach(to: project)
        command = ""
        guard !raw.isEmpty else { return }
        append("$ \(raw)", kind: .command)

        let components = raw.split(whereSeparator: \.isWhitespace).map(String.init)
        let normalized = components.map { $0.lowercased() }
        guard let executable = normalized.first else { return }

        switch executable {
        case "help":
            append(
                "help            Show this command list\n" +
                "pwd             Print the project workspace\n" +
                "ls              List project files\n" +
                "cat <path>      Print an editable project file\n" +
                "cargo check     Type-check the current snapshot\n" +
                "cargo run       Compile and run the current snapshot\n" +
                "cargo tree      Show recorded dependencies\n" +
                "clear           Clear this project's terminal",
                kind: .info
            )
        case "pwd":
            append("/workspace/\(project.name)", kind: .info)
        case "ls":
            append(project.files.keys.sorted().joined(separator: "\n"), kind: .info)
        case "cat":
            guard components.count > 1 else {
                append("usage: cat <project-relative path>", kind: .error)
                return
            }
            var path = components.dropFirst().joined(separator: " ")
            while path.hasPrefix("./") { path.removeFirst(2) }
            if let contents = project.files[path] {
                append(contents, kind: .info)
            } else {
                append("cat: \(path): no such project file", kind: .error)
            }
        case "cargo":
            runCargo(
                arguments: Array(normalized.dropFirst()),
                project: project,
                isBusy: isBusy,
                onCheck: onCheck,
                onRun: onRun
            )
        case "clear":
            lines = []
            buffers[projectName] = []
        default:
            append("\(components[0]): command is not available in the iOS project sandbox", kind: .error)
            append("Type help for Crabrix project commands.", kind: .info)
        }
    }

    func activityChanged(
        from oldValue: CompilerViewModel.Activity,
        to newValue: CompilerViewModel.Activity,
        project: CrabrixProject
    ) {
        attach(to: project)
        guard oldValue == .idle, newValue != .idle else { return }
        let command = newValue == .checking ? "cargo check" : "cargo run"
        append("[build] \(command) · background snapshot started", kind: .info)
    }

    func record(_ result: CompilationResult, project: CrabrixProject) {
        attach(to: project)
        let parts = result.duration.components
        let signature = [
            result.phase.rawValue,
            result.succeeded.description,
            String(parts.seconds),
            result.stdout,
            result.stderr,
            result.detail,
        ].joined(separator: "|")
        guard resultSignatures[project.name] != signature else { return }
        resultSignatures[project.name] = signature

        let status = result.succeeded ? "finished successfully" : "failed"
        append(
            "[build] \(result.phase.rawValue) \(status) in \(result.duration.crabrixDescription)",
            kind: result.succeeded ? .success : .error
        )
        if !result.stdout.isEmpty { append(result.stdout, kind: .success) }
        if !result.stderr.isEmpty { append(result.stderr, kind: .error) }
        if !result.succeeded, result.stderr.isEmpty {
            append(result.detail, kind: .error)
        }
    }

    private func runCargo(
        arguments: [String],
        project: CrabrixProject,
        isBusy: Bool,
        onCheck: () -> Void,
        onRun: () -> Void
    ) {
        guard let command = arguments.first else {
            append("usage: cargo <check|run|tree>", kind: .error)
            return
        }
        switch command {
        case "check":
            guard !isBusy else {
                append("A build is already running.", kind: .error)
                return
            }
            onCheck()
        case "run":
            guard !isBusy else {
                append("A build is already running.", kind: .error)
                return
            }
            onRun()
        case "tree":
            let dependencies = project.manifest?.dependencies ?? []
            guard !dependencies.isEmpty else {
                append("\(project.name) v0.1.0\n└── no dependencies", kind: .info)
                return
            }
            let tree = dependencies.map {
                "├── \($0.name) \($0.requirement ?? $0.source.rawValue)"
            }.joined(separator: "\n")
            append("\(project.name) v0.1.0\n\(tree)", kind: .info)
        default:
            append("cargo \(command) is not available in the Phase 0 sandbox", kind: .error)
        }
    }

    private func append(_ text: String, kind: Line.Kind) {
        lines.append(Line(text: text, kind: kind))
        buffers[projectName] = lines
    }
}
