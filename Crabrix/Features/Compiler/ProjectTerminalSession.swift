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
    @Published private(set) var projectID: UUID?

    private var buffers: [UUID: [Line]] = [:]
    private var resultSignatures: [UUID: String] = [:]
    private var workingDirectories: [UUID: String] = [:]
    private var directoryBuffers: [UUID: Set<String>] = [:]
    private var commandHistories: [UUID: [String]] = [:]
    private var historyPositions: [UUID: Int] = [:]
    private var historyDrafts: [UUID: String] = [:]

    var promptDirectory: String { currentDirectory.isEmpty ? "~" : "~/\(currentDirectory)" }
    var canRecallPrevious: Bool { !(projectID.flatMap { commandHistories[$0] } ?? []).isEmpty }
    var canRecallNext: Bool { projectID.flatMap { historyPositions[$0] } != nil }

    func recallPrevious() {
        guard let projectID, let history = commandHistories[projectID], !history.isEmpty else { return }
        if historyPositions[projectID] == nil {
            historyDrafts[projectID] = command
            historyPositions[projectID] = history.count
        }
        let position = max(0, (historyPositions[projectID] ?? history.count) - 1)
        historyPositions[projectID] = position
        command = history[position]
    }

    func recallNext() {
        guard let projectID, let history = commandHistories[projectID],
              let position = historyPositions[projectID] else { return }
        let next = position + 1
        if next < history.count {
            historyPositions[projectID] = next
            command = history[next]
        } else {
            historyPositions[projectID] = nil
            command = historyDrafts.removeValue(forKey: projectID) ?? ""
        }
    }

    func attach(to project: CrabrixProject) {
        guard projectID != project.id else {
            projectName = project.name
            return
        }
        if let projectID { buffers[projectID] = lines }
        projectID = project.id
        projectName = project.name
        workingDirectories[project.id, default: ""] = workingDirectories[project.id] ?? ""
        directoryBuffers[project.id, default: []].formUnion(Self.directories(in: project.files))
        if let stored = buffers[project.id] {
            lines = stored
        } else {
            lines = [
                Line(
                    text: "Crabrix project terminal · /workspace/\(project.name)",
                    kind: .info
                ),
                Line(text: "Type help to see available commands.", kind: .info),
            ]
            buffers[project.id] = lines
        }
        command = ""
    }

    func submit(
        project: CrabrixProject,
        isBusy: Bool,
        workspace: CargoWorkspaceSnapshot = .empty,
        onCheck: () -> Void,
        onRun: () -> Void,
        onBuild: (() -> Void)? = nil,
        onTest: ((RustUnitTestRequest) -> Void)? = nil,
        onFormat: ((RustFormatRequest) -> Void)? = nil,
        onGitCommand: ((ProjectGitCommand) -> Void)? = nil,
        onFetch: (() -> Void)? = nil,
        onBrowserCommand: ((BrowserProjectCommand) -> Void)? = nil,
        onReplaceFiles: (([String: String], String?) -> Bool)? = nil
    ) {
        let raw = command.trimmingCharacters(in: .whitespacesAndNewlines)
        attach(to: project)
        command = ""
        guard !raw.isEmpty else { return }
        let visibleCommand = Self.redactedCommand(raw)
        commandHistories[project.id, default: []].append(visibleCommand)
        if commandHistories[project.id, default: []].count > 100 {
            commandHistories[project.id]?.removeFirst()
        }
        historyPositions[project.id] = nil
        historyDrafts[project.id] = nil
        append("$ \(visibleCommand)", kind: .command)

        guard let components = Self.shellWords(raw), !components.isEmpty else {
            append("shell: unmatched quote", kind: .error)
            return
        }
        let normalized = components.map { $0.lowercased() }
        guard let executable = normalized.first else { return }

        switch executable {
        case "help":
            append(
                "Project shell commands\n" +
                "  ls [-laR] [path]        List files and directories\n" +
                "  pwd · cd [path] · tree  Navigate the project\n" +
                "  cat [-n] · head · tail  Read project files\n" +
                "  grep [-inr] · find · wc Search and inspect text\n" +
                "  touch · mkdir · rm      Edit the project snapshot\n" +
                "  cp · mv · echo          Copy, move, and write files\n" +
                "  cargo check|run|build   Use the bundled Rust toolchain\n" +
                "  cargo test [filter]     Selected-entry unit tests; --lib or --bin NAME\n" +
                "  cargo test -- --list    Discover unit tests without running them\n" +
                "  cargo fmt [--check]     Format owned Rust files; check keeps source\n" +
                "  rustfmt path.rs         Format one file; Undo in project settings\n" +
                "  cargo tree|fetch        Inspect and download packages\n" +
                "  cargo metadata          Inspect this package manifest\n" +
                "  git init|status|log     Local history without an account\n" +
                "  git diff <path>          Inspect one changed file\n" +
                "  git branch|switch       Local branches; clean checkout only\n" +
                "  git commit -m msg -- paths  Commit selected paths\n" +
                "  git clone <HTTPS URL>   New GitHub project with real history\n" +
                "  git remote add origin URL  Connect this local repository\n" +
                "  git fetch|pull --ff-only|push  Explicit HTTPS operations\n" +
                "  npm install|ci          Prepare browser imports for offline use\n" +
                "  npm run dev|preview     Build and open the local web preview\n" +
                "  npm run build|check     Build browser JS/TS/JSX locally\n" +
                "  npm --prefix web …      Target a nested browser project\n" +
                "  history                 Recall recent commands\n" +
                "  env · date · uname      Sandbox information\n" +
                "  clear                    Clear this terminal\n\n" +
                "Commands run inside /workspace/\(project.name); iOS does not expose host processes.",
                kind: .info
            )
        case "pwd":
            let cwd = currentDirectory
            append("/workspace/\(project.name)\(cwd.isEmpty ? "" : "/\(cwd)")", kind: .info)
        case "ls":
            runLS(arguments: Array(components.dropFirst()), project: project)
        case "cd":
            runCD(arguments: Array(components.dropFirst()), project: project)
        case "tree":
            runTree(arguments: Array(components.dropFirst()), project: project)
        case "cat":
            runCat(arguments: Array(components.dropFirst()), project: project)
        case "head", "tail":
            runHeadOrTail(executable, arguments: Array(components.dropFirst()), project: project)
        case "wc":
            runWC(arguments: Array(components.dropFirst()), project: project)
        case "grep":
            runGrep(arguments: Array(components.dropFirst()), project: project)
        case "find":
            runFind(arguments: Array(components.dropFirst()), project: project)
        case "touch", "mkdir", "rm", "cp", "mv", "echo":
            runMutation(
                executable,
                arguments: Array(components.dropFirst()),
                project: project,
                onReplaceFiles: onReplaceFiles
            )
        case "whoami":
            append("crabrix", kind: .info)
        case "uname":
            append("Crabrix iOS sandbox · arm64 · bundled WASI Rust toolchain", kind: .info)
        case "env":
            append(
                "HOME=/workspace/\(project.name)\nPWD=/workspace/\(project.name)\(currentDirectory.isEmpty ? "" : "/\(currentDirectory)")\nSHELL=crabrix-project-shell\nTERM=xterm-256color\nNETWORK=preview-disabled; explicit package preparation only",
                kind: .info
            )
        case "date":
            append(Date().formatted(date: .abbreviated, time: .standard), kind: .info)
        case "history":
            let history = commandHistories[project.id] ?? []
            append(history.enumerated().map { "\($0.offset + 1)  \($0.element)" }
                .joined(separator: "\n"), kind: .info)
        case "which":
            guard components.count == 2 else {
                append("usage: which <command>", kind: .error)
                return
            }
            let available = Self.availableCommands.contains(components[1].lowercased())
            append(
                available ? "/app/bin/\(components[1])" : "\(components[1]) not found",
                kind: available ? .info : .error
            )
        case "npm":
            runNpm(arguments: Array(components.dropFirst()), project: project, isBusy: isBusy, onCommand: onBrowserCommand)
        case "git":
            guard !isBusy else { append("Wait for the current exclusive project/build operation to finish.", kind: .error); return }
            do {
                let command = try ProjectGitCommand.parse(Array(components.dropFirst()))
                guard let onGitCommand else { append("Local Git is unavailable in this view.", kind: .error); return }
                onGitCommand(command)
            } catch { append(error.localizedDescription, kind: .error) }
        case "cargo":
            runCargo(
                arguments: Array(components.dropFirst()),
                project: project,
                workspace: workspace,
                isBusy: isBusy,
                onCheck: onCheck,
                onRun: onRun,
                onBuild: onBuild,
                onTest: onTest,
                onFormat: onFormat,
                onFetch: onFetch
            )
        case "rustfmt":
            guard !isBusy else { append("Wait for the current operation to finish.", kind: .error); return }
            guard components.count == 2, let path = normalizedPath(components[1], project: project),
                  !components[1].hasPrefix("-"), let onFormat else {
                append("usage: rustfmt <project/path.rs>; use cargo fmt --check for a project formatting check.", kind: .error); return
            }
            onFormat(.init(scope: .file(path)))
        case "clear":
            lines = []
            buffers[project.id] = []
        default:
            append("\(components[0]): command is not available in the iOS project sandbox", kind: .error)
            append("Type help for Crabrix project commands.", kind: .info)
        }
    }

    private func runNpm(arguments: [String], project: CrabrixProject, isBusy: Bool,
                        onCommand: ((BrowserProjectCommand) -> Void)?) {
        var arguments = arguments
        var explicitDirectory: String?
        var index = 0
        while index < arguments.count, arguments[index] != "--" {
            let argument = arguments[index]
            if argument == "--prefix" || argument.hasPrefix("--prefix=") {
                let rawDirectory: String
                if argument == "--prefix" {
                    guard index + 1 < arguments.count else {
                        append("npm: --prefix requires a project directory.", kind: .error); return
                    }
                    rawDirectory = arguments.remove(at: index + 1)
                } else {
                    rawDirectory = String(argument.dropFirst("--prefix=".count))
                }
                guard explicitDirectory == nil, !rawDirectory.isEmpty,
                      let directory = normalizedPath(rawDirectory, project: project) else {
                    append("npm: use one --prefix directory inside this project.", kind: .error); return
                }
                explicitDirectory = directory
                arguments.remove(at: index)
            } else { index += 1 }
        }
        let directory = explicitDirectory ?? currentDirectory
        let reference = directory.isEmpty ? "package.json" : directory + "/package.json"
        let path = BrowserProjectConfiguration.manifestPath(files: project.files, entry: reference)
        if explicitDirectory != nil, path != reference {
            append("npm: no package.json in \(displayPath(directory, project: project)).", kind: .error); return
        }
        guard let text = project.files[path],
              let manifest = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else {
            append("npm: add a valid package.json and an HTML entry to this browser project.", kind: .error); return
        }
        let scripts = manifest["scripts"] as? [String: String] ?? [:]
        if arguments.isEmpty || arguments == ["--version"] || arguments == ["run"] {
            append("Crabrix browser package tools · local JS/TS/JSX bundler, not a Node process.\n" +
                "npm install (or npm i) · npm ci · npm run dev|start|preview|build|check|typecheck\n" +
                "Use npm --prefix web <command> for a nested app.\n" +
                scripts.keys.sorted().map { "  \($0): \(scripts[$0]!)" }.joined(separator: "\n"), kind: .info)
            return
        }
        guard !isBusy else { append("Wait for the current build or package preparation to finish.", kind: .error); return }
        guard let onCommand else { append("Browser package tools are unavailable in this view.", kind: .error); return }
        let packageDirectory = (path as NSString).deletingLastPathComponent
        if arguments == ["install"] || arguments == ["i"] || arguments == ["ci"] {
            append("Preparing imported browser dependencies only; npm lifecycle scripts and host build plugins are not executed.", kind: .info)
            onCommand(.install(frozen: arguments == ["ci"], directory: packageDirectory)); return
        }
        let name = arguments.count == 2 && ["run", "run-script"].contains(arguments[0]) ? arguments[1] : arguments == ["start"] ? "start" : ""
        guard ["dev", "start", "preview", "build", "check", "typecheck"].contains(name) else {
            append("Supported: npm install (or npm i), npm ci, npm start, npm run dev|start|preview|build|check, npm --prefix <directory> <command>. Declare dependencies in package.json; shell scripts, extra script arguments and package executables are not available.", kind: .error); return
        }
        if let script = scripts[name], script.range(of: #"(?:^|[;&|]\s*)(?:node|next|nuxt|astro|bun|deno|webpack|rollup)\b"#, options: .regularExpression) != nil {
            append("This script needs a host/server build tool. Import its static browser export, or use an HTML entry with browser imports; this command does not execute Node or arbitrary package scripts.", kind: .error); return
        }
        if ["check", "typecheck"].contains(name) {
            append("Using Crabrix's bundled TypeScript checker and browser bundler. No package script or plugin is executed and no package is downloaded.", kind: .info)
            onCommand(.check(directory: packageDirectory)); return
        }
        append("Using Crabrix's browser bundler for \(name); package scripts/plugins are not executed and no dev server is started.", kind: .info)
        onCommand(.build(run: ["dev", "start", "preview"].contains(name), directory: packageDirectory))
    }

    func activityChanged(
        from oldValue: CompilerViewModel.Activity,
        to newValue: CompilerViewModel.Activity,
        project: CrabrixProject
    ) {
        attach(to: project)
        guard oldValue == .idle, newValue != .idle else { return }
        let web = BrowserProjectConfiguration.isBrowserEntry(project.entryFile)
        let command: String
        switch newValue {
        case .testing: command = "selected-entry unit tests"
        case .formatting: command = "rustfmt · source formatting"
        default: command = web ? "browser build" : (newValue == .checking ? "cargo check" : newValue == .building ? "cargo build · compile only" : "cargo run")
        }
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
        guard resultSignatures[project.id] != signature else { return }
        resultSignatures[project.id] = signature

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

    func recordGit(_ text: String, isError: Bool, project: CrabrixProject) {
        attach(to: project)
        append("[git] " + text, kind: isError ? .error : .info)
    }

    private func runCargo(
        arguments: [String],
        project: CrabrixProject,
        workspace: CargoWorkspaceSnapshot,
        isBusy: Bool,
        onCheck: () -> Void,
        onRun: () -> Void,
        onBuild: (() -> Void)?,
        onTest: ((RustUnitTestRequest) -> Void)?,
        onFormat: ((RustFormatRequest) -> Void)?,
        onFetch: (() -> Void)?
    ) {
        guard let command = arguments.first else {
            append("usage: cargo <check|run|build|test|fmt|tree|fetch|metadata>", kind: .error)
            return
        }
        switch command {
        case "test":
            guard !isBusy else { append("Wait for the current operation to finish.", kind: .error); return }
            guard let onTest else { append("Unit Test is unavailable in this workspace.", kind: .error); return }
            var request = RustUnitTestRequest()
            let options = Array(arguments.dropFirst())
            var index = 0
            var hasTarget = false
            while index < options.count {
                let option = options[index]
                if option == "--", Array(options.dropFirst(index + 1)) == ["--list"] {
                    request.listOnly = true; index = options.count; break
                } else if option == "--lib", !hasTarget {
                    request.target = .library; hasTarget = true
                } else if option == "--bin", !hasTarget, index + 1 < options.count,
                          !options[index + 1].hasPrefix("-"), !options[index + 1].isEmpty {
                    index += 1; request.target = .binary(options[index]); hasTarget = true
                } else if !option.hasPrefix("-"), request.filter == nil {
                    request.filter = option
                } else {
                    append("Supported: cargo test [name-filter] [--lib | --bin NAME] [-- --list]. This profile tests one entry, not integration targets or doctests; ignored/should_panic and extra harness options are not enabled.", kind: .error); return
                }
                index += 1
            }
            append("Unit Test uses the selected entry (or explicit --lib/--bin), with real local libtest. Integration targets, dev-dependencies and doctests are not covered.", kind: .info)
            onTest(request)
        case "fmt":
            guard !isBusy else { append("Wait for the current operation to finish.", kind: .error); return }
            guard arguments.count == 1 || Array(arguments.dropFirst()) == ["--check"] else {
                append("Supported: cargo fmt or cargo fmt --check. Root rustfmt.toml is validated; external/vendor trees are excluded.", kind: .error); return
            }
            guard let onFormat else { append("Rustfmt is unavailable in this workspace.", kind: .error); return }
            onFormat(.init(scope: .project, checkOnly: arguments.count > 1))
        case "check":
            guard arguments.count == 1 else { append("cargo check options are not supported; use the project manifest profile.", kind: .error); return }
            guard !isBusy else {
                append("A build is already running.", kind: .error)
                return
            }
            onCheck()
        case "build":
            guard !isBusy else { append("A build is already running.", kind: .error); return }
            guard arguments.count == 1 else { append("cargo build options are not supported; set the profile in your project manifest.", kind: .error); return }
            guard let onBuild else { append("Compile-only Build is unavailable in this workspace.", kind: .error); return }
            onBuild()
        case "run":
            guard arguments.count == 1 else { append("cargo run options and extra program arguments are not supported in this terminal profile.", kind: .error); return }
            guard !isBusy else {
                append("A build is already running.", kind: .error)
                return
            }
            onRun()
        case "fetch":
            guard let onFetch else {
                append("cargo fetch is unavailable right now.", kind: .error)
                return
            }
            append("Resolving and downloading registry packages…", kind: .info)
            onFetch()
        case "tree":
            append(Self.renderTree(project: project, workspace: workspace), kind: .info)
        case "metadata":
            let manifest = project.manifest
            append(
                "Package: \(manifest?.name ?? project.name) \(manifest?.version ?? "0.1.0")\n" +
                "Edition: \(manifest?.edition ?? "2024")\n" +
                "Entry: \(project.entryFile)\n" +
                "Files: \(project.files.count)\n" +
                "Dependencies: \(manifest?.dependencies.count ?? 0)\n" +
                workspace.summary,
                kind: .info
            )
        default:
            append("cargo \(command) is not available in the Crabrix project shell", kind: .error)
        }
    }

    /// Renders the resolved graph the way `cargo tree` does, falling back to the
    /// manifest's declared dependencies before anything has been resolved.
    nonisolated static func renderTree(
        project: CrabrixProject,
        workspace: CargoWorkspaceSnapshot
    ) -> String {
        let manifest = project.manifest
        let rootLabel = "\(manifest?.name ?? project.name) v\(manifest?.version ?? "0.1.0")"

        guard !workspace.packages.isEmpty else {
            let declared = manifest?.dependencies ?? []
            guard !declared.isEmpty else { return "\(rootLabel)\n└── no dependencies" }
            var lines = [rootLabel]
            for (offset, dependency) in declared.enumerated() {
                let isLast = offset == declared.count - 1
                lines.append(
                    "\(isLast ? "└── " : "├── ")\(dependency.name) \(dependency.requirement ?? dependency.source.rawValue) (unresolved)"
                )
            }
            lines.append("")
            lines.append("Run cargo fetch to resolve and download these packages.")
            return lines.joined(separator: "\n")
        }

        var lines = [rootLabel]
        let direct = workspace.packages.filter(\.isDirect)
        let transitive = workspace.packages.filter { !$0.isDirect }
        for (offset, package) in direct.enumerated() {
            let isLast = offset == direct.count - 1 && transitive.isEmpty
            lines.append("\(isLast ? "└── " : "├── ")\(package.name) v\(package.version) \(marker(for: package))")
        }
        for (offset, package) in transitive.enumerated() {
            let isLast = offset == transitive.count - 1
            lines.append("\(isLast ? "└── " : "├── ")\(package.name) v\(package.version) \(marker(for: package)) (transitive)")
        }
        lines.append("")
        let offline = workspace.isOfflinePinned
            ? " · offline pinned"
            : (workspace.isOfflineReady ? " · offline while cached" : " · download pending")
        lines.append(workspace.summary + offline)
        return lines.joined(separator: "\n")
    }

    private nonisolated static func marker(for package: CratePackageStatus) -> String {
        switch package.compatibility {
        case .verified: "[link-verified]"
        case .checkVerified: "[check-verified]"
        case .expected: "[ready]"
        case .review: "[review]"
        case .buildFailed: "[build-failed]"
        case .unsupported: "[unsupported]"
        }
    }

    private var currentDirectory: String {
        projectID.flatMap { workingDirectories[$0] } ?? ""
    }

    private static let availableCommands: Set<String> = [
        "help", "pwd", "ls", "cd", "tree", "cat", "head", "tail", "wc",
        "grep", "find", "touch", "mkdir", "rm", "cp", "mv", "echo",
        "whoami", "uname", "env", "date", "which", "cargo", "rustfmt", "git", "npm", "history", "clear",
    ]

    private static func shellWords(_ input: String) -> [String]? {
        var words: [String] = []
        var word = ""
        var quote: Character?
        var escaped = false

        func flush() {
            guard !word.isEmpty else { return }
            words.append(word)
            word = ""
        }

        var index = input.startIndex
        while index < input.endIndex {
            let character = input[index]
            if escaped {
                word.append(character)
                escaped = false
            } else if character == "\\" && quote != "'" {
                escaped = true
            } else if let activeQuote = quote {
                if character == activeQuote {
                    quote = nil
                } else {
                    word.append(character)
                }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character.isWhitespace {
                flush()
            } else if character == ">" {
                flush()
                let next = input.index(after: index)
                if next < input.endIndex, input[next] == ">" {
                    words.append(">>")
                    index = next
                } else {
                    words.append(">")
                }
            } else {
                word.append(character)
            }
            index = input.index(after: index)
        }
        guard quote == nil, !escaped else { return nil }
        flush()
        return words
    }

    private static func directories(in files: [String: String]) -> Set<String> {
        var result: Set<String> = [""]
        for path in files.keys {
            let components = path.split(separator: "/").map(String.init)
            guard components.count > 1 else { continue }
            for count in 1..<components.count {
                result.insert(components.prefix(count).joined(separator: "/"))
            }
        }
        return result
    }

    private func normalizedPath(_ rawPath: String, project: CrabrixProject) -> String? {
        var path = rawPath
        let root = "/workspace/\(project.name)"
        if path == "~" || path == root || path == "/" { return "" }
        if path.hasPrefix("~/") { path = String(path.dropFirst(2)) }
        if path.hasPrefix(root + "/") { path = String(path.dropFirst(root.count + 1)) }
        else if path.hasPrefix("/") { return nil }

        let initial = rawPath.hasPrefix("/") || rawPath.hasPrefix("~")
            ? []
            : currentDirectory.split(separator: "/").map(String.init)
        var components = initial
        for component in path.split(separator: "/").map(String.init) {
            switch component {
            case "", ".": continue
            case "..":
                guard !components.isEmpty else { return nil }
                components.removeLast()
            default:
                components.append(component)
            }
        }
        return components.joined(separator: "/")
    }

    private func allDirectories(project: CrabrixProject) -> Set<String> {
        Self.directories(in: project.files).union(directoryBuffers[project.id] ?? [])
    }

    private func displayPath(_ path: String, project: CrabrixProject) -> String {
        "/workspace/\(project.name)\(path.isEmpty ? "" : "/\(path)")"
    }

    private func immediateEntries(at directory: String, project: CrabrixProject) -> [(name: String, path: String, isDirectory: Bool)] {
        let prefix = directory.isEmpty ? "" : directory + "/"
        var found: [String: Bool] = [:]
        for path in project.files.keys where path.hasPrefix(prefix) {
            let remainder = String(path.dropFirst(prefix.count))
            guard let first = remainder.split(separator: "/").first.map(String.init), !first.isEmpty else { continue }
            found[first] = remainder.contains("/")
        }
        for path in allDirectories(project: project) where path.hasPrefix(prefix) && path != directory {
            let remainder = String(path.dropFirst(prefix.count))
            guard let first = remainder.split(separator: "/").first.map(String.init), !first.isEmpty else { continue }
            found[first] = true
        }
        return found.map { name, isDirectory in
            (name, prefix + name, isDirectory)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func runLS(arguments: [String], project: CrabrixProject) {
        var showAll = false
        var long = false
        var recursive = false
        var paths: [String] = []
        for argument in arguments {
            if argument.hasPrefix("-") && argument != "-" {
                showAll = showAll || argument.contains("a")
                long = long || argument.contains("l")
                recursive = recursive || argument.contains("R")
                let known = Set("-alR")
                if argument.contains(where: { !known.contains($0) }) {
                    append("ls: unsupported option \(argument)", kind: .error)
                    return
                }
            } else {
                paths.append(argument)
            }
        }
        if paths.isEmpty { paths = ["."] }

        var blocks: [String] = []
        for rawPath in paths {
            guard let path = normalizedPath(rawPath, project: project) else {
                append("ls: \(rawPath): outside the project sandbox", kind: .error)
                continue
            }
            if let content = project.files[path] {
                blocks.append(long ? longListing(name: path.split(separator: "/").last.map(String.init) ?? path, content: content) : path)
                continue
            }
            guard allDirectories(project: project).contains(path) else {
                append("ls: \(rawPath): No such file or directory", kind: .error)
                continue
            }
            let directories = recursive
                ? [path] + allDirectories(project: project).filter { $0.hasPrefix(path.isEmpty ? "" : path + "/") }.sorted()
                : [path]
            for directory in directories {
                var entries = immediateEntries(at: directory, project: project)
                if !showAll { entries.removeAll { $0.name.hasPrefix(".") } }
                var output: [String] = []
                if showAll { output.append(long ? "drwxr-xr-x          .\ndrwxr-xr-x          .." : ".  ..") }
                output.append(contentsOf: entries.map { entry in
                    if long {
                        return entry.isDirectory
                            ? "drwxr-xr-x          \(entry.name)/"
                            : longListing(name: entry.name, content: project.files[entry.path] ?? "")
                    }
                    return entry.name + (entry.isDirectory ? "/" : "")
                })
                let heading = recursive || paths.count > 1 ? "\(displayPath(directory, project: project)):\n" : ""
                blocks.append(heading + (long ? output.joined(separator: "\n") : output.joined(separator: "  ")))
            }
        }
        if !blocks.isEmpty { append(blocks.joined(separator: "\n\n"), kind: .info) }
    }

    private func longListing(name: String, content: String) -> String {
        "-rw-r--r-- \(String(format: "%8d", content.utf8.count)) \(name)"
    }

    private func runCD(arguments: [String], project: CrabrixProject) {
        guard arguments.count <= 1 else {
            append("cd: too many arguments", kind: .error)
            return
        }
        let rawPath = arguments.first ?? "~"
        guard let path = normalizedPath(rawPath, project: project) else {
            append("cd: \(rawPath): outside the project sandbox", kind: .error)
            return
        }
        guard allDirectories(project: project).contains(path) else {
            append("cd: \(rawPath): No such directory", kind: .error)
            return
        }
        workingDirectories[project.id] = path
    }

    private func runTree(arguments: [String], project: CrabrixProject) {
        guard arguments.count <= 1 else {
            append("usage: tree [path]", kind: .error)
            return
        }
        let rawPath = arguments.first ?? "."
        guard let root = normalizedPath(rawPath, project: project), allDirectories(project: project).contains(root) else {
            append("tree: \(rawPath): No such directory", kind: .error)
            return
        }
        var output = [root.isEmpty ? project.name : (root.split(separator: "/").last.map(String.init) ?? root)]
        func visit(_ directory: String, prefix: String) {
            let entries = immediateEntries(at: directory, project: project)
            for (index, entry) in entries.enumerated() {
                let last = index == entries.count - 1
                output.append(prefix + (last ? "└── " : "├── ") + entry.name + (entry.isDirectory ? "/" : ""))
                if entry.isDirectory { visit(entry.path, prefix: prefix + (last ? "    " : "│   ")) }
            }
        }
        visit(root, prefix: "")
        append(output.joined(separator: "\n"), kind: .info)
    }

    private func runCat(arguments: [String], project: CrabrixProject) {
        var showNumbers = false
        var paths: [String] = []
        for argument in arguments {
            if argument == "-n" { showNumbers = true }
            else if argument.hasPrefix("-") {
                append("cat: unsupported option \(argument)", kind: .error)
                return
            } else { paths.append(argument) }
        }
        guard !paths.isEmpty else {
            append("usage: cat [-n] <file>…", kind: .error)
            return
        }
        for rawPath in paths {
            guard let path = normalizedPath(rawPath, project: project), let content = project.files[path] else {
                append("cat: \(rawPath): No such file", kind: .error)
                continue
            }
            if showNumbers {
                let numbered = content.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
                    .map { String(format: "%4d  %@", $0.offset + 1, String($0.element)) }
                    .joined(separator: "\n")
                append(numbered, kind: .info)
            } else {
                append(content, kind: .info)
            }
        }
    }

    private func runHeadOrTail(_ command: String, arguments: [String], project: CrabrixProject) {
        var lineCount = 10
        var path: String?
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            if argument == "-n", index + 1 < arguments.count, let count = Int(arguments[index + 1]) {
                lineCount = max(0, count)
                index += 2
            } else if argument.hasPrefix("-"), let count = Int(argument.dropFirst()) {
                lineCount = max(0, count)
                index += 1
            } else {
                path = argument
                index += 1
            }
        }
        guard let rawPath = path,
              let resolved = normalizedPath(rawPath, project: project),
              let content = project.files[resolved] else {
            append("usage: \(command) [-n count] <file>", kind: .error)
            return
        }
        let rows = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let selection = command == "head" ? Array(rows.prefix(lineCount)) : Array(rows.suffix(lineCount))
        append(selection.joined(separator: "\n"), kind: .info)
    }

    private func runWC(arguments: [String], project: CrabrixProject) {
        var showLines = false
        var showWords = false
        var showBytes = false
        var paths: [String] = []
        for argument in arguments {
            if argument.hasPrefix("-") {
                showLines = showLines || argument.contains("l")
                showWords = showWords || argument.contains("w")
                showBytes = showBytes || argument.contains("c")
            } else { paths.append(argument) }
        }
        if !showLines && !showWords && !showBytes { showLines = true; showWords = true; showBytes = true }
        guard !paths.isEmpty else { append("usage: wc [-lwc] <file>…", kind: .error); return }
        for rawPath in paths {
            guard let path = normalizedPath(rawPath, project: project), let content = project.files[path] else {
                append("wc: \(rawPath): No such file", kind: .error)
                continue
            }
            let values = [
                showLines ? String(content.split(separator: "\n", omittingEmptySubsequences: false).count) : nil,
                showWords ? String(content.split(whereSeparator: \Character.isWhitespace).count) : nil,
                showBytes ? String(content.utf8.count) : nil,
            ].compactMap { $0 }
            append(values.joined(separator: "  ") + "  \(rawPath)", kind: .info)
        }
    }

    private func runGrep(arguments: [String], project: CrabrixProject) {
        var ignoreCase = false
        var showNumbers = false
        var recursive = false
        var operands: [String] = []
        for argument in arguments {
            if argument.hasPrefix("-") {
                ignoreCase = ignoreCase || argument.contains("i")
                showNumbers = showNumbers || argument.contains("n")
                recursive = recursive || argument.contains("r") || argument.contains("R")
            } else { operands.append(argument) }
        }
        guard let pattern = operands.first else { append("usage: grep [-inr] pattern <path>…", kind: .error); return }
        let requested = Array(operands.dropFirst())
        let paths = requested.isEmpty ? ["."] : requested
        var matches: [String] = []
        for rawPath in paths {
            guard let path = normalizedPath(rawPath, project: project) else { continue }
            let files: [(String, String)]
            if let content = project.files[path] {
                files = [(path, content)]
            } else if allDirectories(project: project).contains(path), recursive {
                let prefix = path.isEmpty ? "" : path + "/"
                files = project.files.filter { $0.key.hasPrefix(prefix) }.sorted { $0.key < $1.key }
            } else {
                append("grep: \(rawPath): use -r to search a directory", kind: .error)
                continue
            }
            for (file, content) in files {
                for (offset, line) in content.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                    let haystack = ignoreCase ? line.lowercased() : String(line)
                    let needle = ignoreCase ? pattern.lowercased() : pattern
                    if haystack.contains(needle) {
                        matches.append("\(file)\(showNumbers ? ":\(offset + 1)" : ""):\(line)")
                    }
                }
            }
        }
        if !matches.isEmpty { append(matches.joined(separator: "\n"), kind: .info) }
    }

    private func runFind(arguments: [String], project: CrabrixProject) {
        var rootArgument = "."
        var pattern: String?
        var index = 0
        if let first = arguments.first, !first.hasPrefix("-") { rootArgument = first; index = 1 }
        while index < arguments.count {
            guard arguments[index] == "-name", index + 1 < arguments.count else {
                append("usage: find [path] [-name pattern]", kind: .error)
                return
            }
            pattern = arguments[index + 1]
            index += 2
        }
        guard let root = normalizedPath(rootArgument, project: project), allDirectories(project: project).contains(root) else {
            append("find: \(rootArgument): No such directory", kind: .error)
            return
        }
        let prefix = root.isEmpty ? "" : root + "/"
        var paths = Array(allDirectories(project: project).filter { $0 == root || $0.hasPrefix(prefix) })
        paths += project.files.keys.filter { $0.hasPrefix(prefix) }
        let filtered = Set(paths).sorted().filter { path in
            guard let pattern else { return true }
            let name = path.split(separator: "/").last.map(String.init) ?? path
            return Self.globMatches(name, pattern: pattern)
        }
        append(filtered.map { $0.isEmpty ? "." : "./\($0)" }.joined(separator: "\n"), kind: .info)
    }

    private static func globMatches(_ value: String, pattern: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: pattern)
            .replacingOccurrences(of: "\\*", with: ".*")
            .replacingOccurrences(of: "\\?", with: ".")
        return value.range(of: "^\(escaped)$", options: .regularExpression) != nil
    }

    private func runMutation(
        _ command: String,
        arguments: [String],
        project: CrabrixProject,
        onReplaceFiles: (([String: String], String?) -> Bool)?
    ) {
        guard let onReplaceFiles else {
            append("\(command): project editing is unavailable here", kind: .error)
            return
        }
        var files = project.files
        var directories = allDirectories(project: project)
        var selectedFile: String?

        func resolve(_ rawPath: String) -> String? { normalizedPath(rawPath, project: project) }
        func parentDirectory(of path: String) -> String {
            path.split(separator: "/").dropLast().joined(separator: "/")
        }
        func ensureParent(_ path: String) -> Bool { directories.contains(parentDirectory(of: path)) }
        func fail(_ text: String) { append("\(command): \(text)", kind: .error) }

        switch command {
        case "touch":
            guard !arguments.isEmpty else { fail("missing file operand"); return }
            for rawPath in arguments {
                guard let path = resolve(rawPath), !path.isEmpty, ensureParent(path) else { fail("\(rawPath): invalid path"); return }
                files[path] = files[path] ?? ""
                selectedFile = path
            }
        case "mkdir":
            let recursive = arguments.contains("-p")
            let operands = arguments.filter { $0 != "-p" }
            guard !operands.isEmpty else { fail("missing directory operand"); return }
            for rawPath in operands {
                guard let path = resolve(rawPath), !path.isEmpty else { fail("\(rawPath): invalid path"); return }
                let components = path.split(separator: "/").map(String.init)
                if recursive {
                    for count in 1...components.count { directories.insert(components.prefix(count).joined(separator: "/")) }
                } else {
                    guard directories.contains(parentDirectory(of: path)) else { fail("\(rawPath): parent does not exist"); return }
                    directories.insert(path)
                }
            }
        case "rm":
            let recursive = arguments.contains { $0.contains("r") || $0.contains("R") }
            let operands = arguments.filter { !$0.hasPrefix("-") }
            guard !operands.isEmpty else { fail("missing operand"); return }
            for rawPath in operands {
                guard let path = resolve(rawPath), !path.isEmpty else { fail("refusing to remove project root"); return }
                if files.removeValue(forKey: path) != nil { continue }
                guard directories.contains(path) else { fail("\(rawPath): No such file or directory"); return }
                guard recursive else { fail("\(rawPath): is a directory; use -r"); return }
                let prefix = path + "/"
                files = files.filter { !$0.key.hasPrefix(prefix) }
                directories = directories.filter { $0 != path && !$0.hasPrefix(prefix) }
            }
        case "cp", "mv":
            guard arguments.count == 2,
                  let source = resolve(arguments[0]), let content = files[source],
                  let rawDestination = resolve(arguments[1]) else { fail("usage: \(command) <source> <destination>"); return }
            let destination = directories.contains(rawDestination)
                ? rawDestination + "/" + (source.split(separator: "/").last.map(String.init) ?? source)
                : rawDestination
            guard !destination.isEmpty, ensureParent(destination) else { fail("destination parent does not exist"); return }
            files[destination] = content
            if command == "mv" { files.removeValue(forKey: source) }
            selectedFile = destination
        case "echo":
            let redirectIndex = arguments.firstIndex(where: { $0 == ">" || $0 == ">>" })
            guard let redirectIndex else {
                append(arguments.joined(separator: " "), kind: .info)
                return
            }
            guard redirectIndex + 1 < arguments.count,
                  let path = resolve(arguments[redirectIndex + 1]), !path.isEmpty, ensureParent(path) else {
                fail("invalid redirection")
                return
            }
            let text = arguments[..<redirectIndex].joined(separator: " ") + "\n"
            files[path] = arguments[redirectIndex] == ">>" ? (files[path] ?? "") + text : text
            selectedFile = path
        default:
            return
        }

        directoryBuffers[project.id] = directories.union(Self.directories(in: files))
        if onReplaceFiles(files, selectedFile) {
            append("Project snapshot updated.", kind: .success)
        } else {
            append("\(command): project is busy; no files were changed", kind: .error)
        }
    }

    private static func redactedCommand(_ raw: String) -> String {
        var result = raw
        if let expression = try? NSRegularExpression(pattern: #"(?:https?|ssh)://[^\s"']+"#) {
            for match in expression.matches(in: raw, range: NSRange(raw.startIndex..., in: raw)).reversed() {
                guard let range = Range(match.range, in: raw), let url = URLComponents(string: String(raw[range])) else { continue }
                if url.user != nil || url.password != nil || url.query != nil || url.fragment != nil,
                   let target = Range(match.range, in: result) {
                    result.replaceSubrange(target, with: "<redacted URL>")
                }
            }
        }
        if let pattern = try? NSRegularExpression(pattern: #"(?:gh[pousr]_[A-Za-z0-9_]{10,}|github_pat_[A-Za-z0-9_]{10,})"#) {
            result = pattern.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "<redacted token>")
        }
        return result
    }

    private func append(_ text: String, kind: Line.Kind) {
        lines.append(Line(text: text, kind: kind))
        if let projectID { buffers[projectID] = lines }
    }
}
