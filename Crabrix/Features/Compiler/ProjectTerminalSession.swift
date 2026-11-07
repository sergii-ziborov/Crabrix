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
        var syntaxPath: String? = nil
    }

    @Published var command = ""
    @Published private(set) var lines: [Line] = []
    @Published private(set) var projectName = ""
    @Published private(set) var projectID: UUID?

    private let httpServer = ProjectHTTPServer()
    private var workflowTasks: [UUID: Task<Void, Never>] = [:]
    private var serviceCompiler: WasmRustCompiler?
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
        httpServer.stop(); serviceCompiler?.cancel(); serviceCompiler = nil
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
        onRunWithInput: ((RustProgramInput) -> Void)? = nil,
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

        guard let components = Self.shellWords(raw) else {
            append("shell: unmatched quote", kind: .error)
            return
        }
        guard !components.isEmpty else { return }
        if let words = try? ProjectCommandLexer.words(raw),
           words.contains(where: { $0.isOperator && ["|", "||", "&&", ";", "&", "<<"].contains($0.value) }) {
            append("Shell pipelines and command lists are outside this terminal profile; run each command separately.", kind: .error); return
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
                "  cargo run -- args < file  Run with arguments and stdin\n" +
                "  env KEY=value cargo run -- args  Invocation environment\n" +
                "  sqlite3 name.db SQL      Execute real SQLite; .read path.sql\n" +
                "  cargo serve [--port N] [--database name.db]  Local Rust HTTP\n" +
                "  curl [-i] [-X METHOD] [-H header] [-d body] URL  HTTP request\n" +
                "  http run request.http   Send one editable HTTP request file\n" +
                "  http stop               Stop the loopback service\n" +
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
                "  npm install|ci          Prepare browser source and declared types\n" +
                "  npm run dev|preview     Build and open the local web preview\n" +
                "  npm run build           Bundle browser JS/TS/JSX locally\n" +
                "  npm run check|typecheck Check local TypeScript and browser bundle\n" +
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
        case "env" where components.count > 1:
            guard !isBusy else { append("A build is already running.", kind: .error); return }
            do {
                let input = try ProjectCommandLexer.runInput(ProjectCommandLexer.words(raw), files: project.files, directory: currentDirectory, projectID: project.id)
                guard let onRunWithInput else { throw ProjectWorkflowFailure("CLI input is unavailable in this view.") }
                onRunWithInput(input)
            } catch { append(error.localizedDescription, kind: .error) }
        case "sqlite3", "sql":
            runSQL(arguments: Array(components.dropFirst()), project: project, isBusy: isBusy)
        case "curl":
            runHTTP(arguments: Array(components.dropFirst()), project: project)
        case "http":
            if components.count == 3, components[1] == "run" {
                do {
                    guard let path = normalizedPath(components[2], project: project), let text = project.files[path] else { throw ProjectWorkflowFailure("HTTP request file is missing.") }
                    runHTTP(arguments: try ProjectHTTPRequestFile.curlArguments(text), project: project)
                } catch { append(error.localizedDescription, kind: .error) }
            }
            else if components == ["http", "stop"] { httpServer.stop(); serviceCompiler?.cancel(); serviceCompiler = nil; append("Local HTTP service stopped.", kind: .info) }
            else { append("usage: cargo serve [--port 8080] [--database tasks.db] · curl URL · http run request.http · http stop", kind: .error) }
        case "env":
            append(
                "HOME=/workspace/\(project.name)\nPWD=/workspace/\(project.name)\(currentDirectory.isEmpty ? "" : "/\(currentDirectory)")\nSHELL=crabrix-project-shell\nTERM=xterm-256color\nNETWORK=explicit terminal HTTP; loopback Rust HTTP adapter; preview remains isolated",
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
        case "cargo" where components.dropFirst().first == "serve":
            startHTTP(arguments: Array(components.dropFirst(2)), project: project, isBusy: isBusy)
        case "cargo" where components.dropFirst().first == "run":
            guard !isBusy else { append("A build is already running.", kind: .error); return }
            if components == ["cargo", "run"] { onRun() }
            else {
                do {
                    let input = try ProjectCommandLexer.runInput(ProjectCommandLexer.words(raw), files: project.files, directory: currentDirectory, projectID: project.id)
                    guard let onRunWithInput else { throw ProjectWorkflowFailure("CLI input is unavailable in this view.") }
                    onRunWithInput(input)
                } catch { append(error.localizedDescription, kind: .error) }
            }
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

    private func runSQL(arguments: [String], project: CrabrixProject, isBusy: Bool) {
        guard !isBusy, workflowTasks[project.id] == nil else { append("Wait for the current project operation.", kind: .error); return }
        guard arguments.count >= 2 else { append("usage: sqlite3 tasks.db 'SELECT …' · sqlite3 tasks.db .read migrations/001.sql", kind: .error); return }
        let name = arguments[0]
        let query: String
        if arguments[1] == ".read", arguments.count == 3 {
            guard let path = normalizedPath(arguments[2], project: project), let text = project.files[path] else { append("SQL script does not exist in this project.", kind: .error); return }
            query = text
        } else if arguments.count == 2, !arguments[1].hasPrefix(".") { query = arguments[1] }
        else { append("Use a quoted SQL script or .read <project.sql>. SQLite dot-shell commands are outside this profile.", kind: .error); return }
        workflowTasks[project.id] = Task { [weak self] in
            let outcome: Swift.Result<ProjectSQLDatabase.Result, any Error> = await Task.detached {
                do { return .success(try ProjectSQLDatabase.open(projectID: project.id, name: name).execute(query)) }
                catch { return .failure(error) }
            }.value
            guard let self else { return }; workflowTasks[project.id] = nil
            guard projectID == project.id else { return }
            switch outcome {
            case let .success(value):
                if value.columns.isEmpty { append("SQLite: \(value.changes) row(s) changed.", kind: .success) }
                else {
                    let rows = [value.columns] + value.rows.map { $0.map { $0 ?? "NULL" } }
                    append(rows.map { $0.joined(separator: "\t") }.joined(separator: "\n"), kind: .info)
                }
            case let .failure(error): append("SQLite: " + error.localizedDescription, kind: .error)
            }
        }
    }

    private func runHTTP(arguments: [String], project: CrabrixProject) {
        guard workflowTasks[project.id] == nil else { append("Wait for the current terminal request.", kind: .error); return }
        var index = 0, method: String?, body: Data?, url: URL?, headers: [String: String] = [:]
        var includeHeaders = false, fail = false
        do {
            while index < arguments.count {
                let argument = arguments[index]
                if ["-s", "-S", "-sS"].contains(argument) { index += 1; continue }
                if argument == "-i" || argument == "--include" { includeHeaders = true; index += 1; continue }
                if argument == "-f" || argument == "--fail" { fail = true; index += 1; continue }
                if ["-X", "--request", "-H", "--header", "-d", "--data", "--data-binary"].contains(argument) {
                    guard index + 1 < arguments.count else { throw ProjectWorkflowFailure("curl: option needs a value.") }
                    let value = arguments[index + 1]; index += 2
                    if argument == "-X" || argument == "--request" {
                        guard method == nil, ["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"].contains(value) else { throw ProjectWorkflowFailure("curl: unsupported or duplicate method.") }; method = value
                    } else if argument == "-H" || argument == "--header" {
                        guard let colon = value.firstIndex(of: ":") else { throw ProjectWorkflowFailure("curl: header needs Name: value.") }
                        let key = String(value[..<colon]), field = value[value.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                        guard !key.isEmpty, key.utf8.count <= 128, key.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }),
                              !field.contains("\r"), !field.contains("\n"), field.utf8.count <= 8192,
                              !["host", "content-length", "transfer-encoding", "connection"].contains(key.lowercased()) else { throw ProjectWorkflowFailure("curl: invalid or reserved header.") }
                        headers[key] = field
                    } else {
                        guard body == nil else { throw ProjectWorkflowFailure("curl: provide one request body.") }
                        if value.hasPrefix("@") {
                            guard let path = normalizedPath(String(value.dropFirst()), project: project), let text = project.files[path] else { throw ProjectWorkflowFailure("curl: request body file is missing.") }
                            body = Data(text.utf8)
                        } else { body = Data(value.utf8) }
                    }
                } else {
                    guard !argument.hasPrefix("-"), url == nil, let candidate = URL(string: argument),
                          let parts = URLComponents(url: candidate, resolvingAgainstBaseURL: false),
                          parts.user == nil, parts.password == nil, parts.fragment == nil,
                          candidate.scheme == "https" || candidate.scheme == "http" && ["127.0.0.1", "localhost", "::1"].contains(candidate.host ?? "") else {
                        throw ProjectWorkflowFailure("curl: use one HTTPS URL or an HTTP loopback URL; unsupported options are refused.")
                    }
                    url = candidate; index += 1
                }
            }
            guard let url, (body?.count ?? 0) <= 65536, headers.count <= 32 else { throw ProjectWorkflowFailure("curl: URL required; request body is limited to 64 KiB.") }
            var request = URLRequest(url: url); request.httpMethod = method ?? (body == nil ? "GET" : "POST")
            request.httpBody = body
            for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
            if body != nil, request.value(forHTTPHeaderField: "Content-Type") == nil { request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type") }
            let captured = request, showHeaders = includeHeaders, failOnStatus = fail
            workflowTasks[project.id] = Task { [weak self] in
                do {
                    let (data, response) = try await ProjectHTTPClient().send(captured)
                    guard let self else { return }; workflowTasks[project.id] = nil
                    guard projectID == project.id else { return }
                    let header = "HTTP \(response.statusCode)\n" + response.allHeaderFields.sorted { String(describing: $0.key) < String(describing: $1.key) }.map { "\($0.key): \($0.value)" }.joined(separator: "\n")
                    let output = (showHeaders ? header + "\n\n" : "") + String(decoding: data, as: UTF8.self)
                    append(output.isEmpty ? "HTTP \(response.statusCode)" : output, kind: failOnStatus && response.statusCode >= 400 ? .error : .info,
                        syntaxPath: showHeaders ? "response.http" : response.value(forHTTPHeaderField: "Content-Type")?.contains("json") == true ? "response.json" : nil)
                } catch {
                    guard let self else { return }; workflowTasks[project.id] = nil
                    if projectID == project.id { append("curl: " + error.localizedDescription, kind: .error) }
                }
            }
        } catch { append(error.localizedDescription, kind: .error) }
    }

    private func startHTTP(arguments: [String], project: CrabrixProject, isBusy: Bool) {
        guard !isBusy, !httpServer.isRunning, workflowTasks[project.id] == nil else { append("Stop the previous service with http stop and wait for active operations.", kind: .error); return }
        var port: UInt16 = 8080, databaseName: String?, index = 0
        var seen: Set<String> = []
        do {
            while index < arguments.count {
                let option = arguments[index]
                guard seen.insert(option).inserted, index + 1 < arguments.count else { throw ProjectWorkflowFailure("usage: cargo serve [--port 8080] [--database tasks.db]") }
                if option == "--port", let value = UInt16(arguments[index + 1]), value >= 1024 { port = value }
                else if option == "--database" { databaseName = arguments[index + 1] }
                else { throw ProjectWorkflowFailure("usage: cargo serve [--port 8080] [--database tasks.db]") }
                index += 2
            }
            guard project.manifest?.dependencies.isEmpty != false else {
                throw ProjectWorkflowFailure("The local stdin HTTP adapter currently accepts std-only handlers. Axum/TCP projects use the documented desktop profile.")
            }
            guard let source = project.files[project.entryFile], project.entryFile.hasSuffix(".rs") else { throw ProjectWorkflowFailure("Select a Rust program entry before starting HTTP.") }
            var support = project.files; support.removeValue(forKey: project.entryFile)
            let supporting = support
            let database = try databaseName.map { try ProjectSQLDatabase.open(projectID: project.id, name: $0) }
            let cancellation = CompilerInvocationCancellation()
            let compiler = WasmRustCompiler(); serviceCompiler = compiler
            append("Building the frozen HTTP handler; no request is executed until the loopback listener is ready.", kind: .info)
            workflowTasks[project.id] = Task { [weak self] in
                let result = await compiler.build(source: source, sourcePath: project.entryFile, supportingFiles: supporting)
                guard let self else { return }; workflowTasks[project.id] = nil
                guard projectID == project.id, serviceCompiler === compiler else { return }
                guard result.succeeded else { serviceCompiler = nil; append(result.stderr.isEmpty ? result.detail : result.stderr, kind: .error); return }
                do {
                    try httpServer.start(port: port, handler: { [weak self] request in
                        let value = await compiler.run(source: source, sourcePath: project.entryFile, supportingFiles: supporting,
                            input: .init(standardInput: request, database: database), cancellation: cancellation)
                        if value.succeeded { return value.stdout }
                        await MainActor.run { [weak self] in
                            guard let self, projectID == project.id else { return }
                            append("[handler] " + (value.stderr.isEmpty ? value.detail : value.stderr), kind: .error)
                        }
                        return "HTTP/1.1 500 Internal Server Error\r\nContent-Type: text/plain\r\n\r\nHandler execution failed; inspect and test the Rust program."
                    }, event: { [weak self] message, error in
                        guard let self, projectID == project.id else { return }
                        append(message, kind: error ? .error : .info)
                    }, onStop: { cancellation.cancel() })
                } catch { serviceCompiler = nil; append(error.localizedDescription, kind: .error) }
            }
        } catch { append(error.localizedDescription, kind: .error) }
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
        append("[git] " + text, kind: isError ? .error : .info, syntaxPath: text.contains("@@") ? "change.diff" : nil)
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
        case .buildFailed: "[build-failed:previous-compiler-failure]"
        case .unsupported: "[unsupported:\(package.compatibility.reasonCode?.rawValue ?? "unspecified-requirement")]"
        }
    }

    private var currentDirectory: String {
        projectID.flatMap { workingDirectories[$0] } ?? ""
    }

    private static let availableCommands: Set<String> = [
        "help", "pwd", "ls", "cd", "tree", "cat", "head", "tail", "wc",
        "grep", "find", "touch", "mkdir", "rm", "cp", "mv", "echo",
        "sqlite3", "sql", "curl", "http", "whoami", "uname", "env", "date", "which", "cargo", "rustfmt", "git", "npm", "history", "clear",
    ]

    private static func shellWords(_ input: String) -> [String]? {
        try? ProjectCommandLexer.words(input).map(\.value)
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
                append(content, kind: .info, syntaxPath: path)
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
            guard redirectIndex + 2 == arguments.count, arguments.filter({ $0 == ">" || $0 == ">>" }).count == 1,
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
        for pattern in [#"(?i)(Authorization|Cookie|X-API-Key)\s*:\s*[^\"'\r\n]*"#,
                        #"(?i)\b([A-Z0-9_]*(?:TOKEN|SECRET|PASSWORD|API_KEY)[A-Z0-9_]*)=(?:\"[^\"]*\"|'[^']*'|[^\s]+)"#] {
            if let expression = try? NSRegularExpression(pattern: pattern) {
                result = expression.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "$1=<redacted>")
            }
        }
        return result
    }

    private func append(_ text: String, kind: Line.Kind, syntaxPath: String? = nil) {
        let preview = text.utf8.count > 131072
            ? String(decoding: text.utf8.prefix(131072), as: UTF8.self) + "\n[Terminal preview limited; full compiler output remains in Output.]"
            : text
        lines.append(Line(text: preview, kind: kind, syntaxPath: syntaxPath))
        var bytes = lines.reduce(0) { $0 + $1.text.utf8.count }
        while lines.count > 1000 || bytes > 2 * 1024 * 1024 {
            bytes -= lines.removeFirst().text.utf8.count
        }
        if let projectID { buffers[projectID] = lines }
    }
}
