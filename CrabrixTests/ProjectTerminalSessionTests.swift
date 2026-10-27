import XCTest
@testable import Crabrix

@MainActor
final class ProjectTerminalSessionTests: XCTestCase {
    func testNpmPreviewAliasesAndPrefixTargetOnlyTheRequestedBrowserApp() {
        let terminal = ProjectTerminalSession()
        let project = CrabrixProject(name: "browser", files: [
            "package.json": "{}", "index.html": "",
            "web/package.json": "{\"scripts\":{\"preview\":\"vite preview\"}}", "web/index.html": "",
        ], entryFile: "index.html", provenance: nil)
        var received: [String] = []
        for command in ["npm --prefix web i", "npm run preview --prefix=web", "npm --prefix web run-script build", "npm run preview"] {
            terminal.command = command
            terminal.submit(project: project, isBusy: false, onCheck: { XCTFail("Rust check") }, onRun: { XCTFail("Rust run") }, onBrowserCommand: {
                switch $0 {
                case let .install(frozen, directory): received.append("install:\(frozen):\(directory)")
                case let .build(run, directory): received.append("build:\(run):\(directory)")
                }
            })
        }
        XCTAssertEqual(received, ["install:false:web", "build:true:web", "build:false:web", "build:true:"])
        terminal.command = "pwd"
        terminal.submit(project: project, isBusy: false, onCheck: {}, onRun: {})
        XCTAssertEqual(terminal.lines.last?.text, "/workspace/browser")
    }

    func testNpmRejectsEscapingOrMissingPrefixAndHostCommands() {
        let terminal = ProjectTerminalSession()
        let project = CrabrixProject(name: "browser", files: [
            "package.json": "{\"scripts\":{\"dev\":\"node server.js\"}}", "index.html": "",
        ], entryFile: "index.html", provenance: nil)
        for command in ["npm --prefix ../outside install", "npm --prefix missing run build", "npm --prefix", "npm --prefix= run build", "npm --prefix . --prefix . install", "npm run dev", "npm run build -- --watch", "npm install react"] {
            terminal.command = command
            terminal.submit(project: project, isBusy: false, onCheck: {}, onRun: {}, onBrowserCommand: { _ in XCTFail("Unsupported command dispatched: \(command)") })
            XCTAssertEqual(terminal.lines.last?.kind, .error, command)
        }
    }

    func testNpmCommandsRouteThroughBrowserToolsAndRespectWorkingDirectory() {
        let terminal = ProjectTerminalSession()
        let project = CrabrixProject(name: "browser", files: ["web/package.json": "{\"scripts\":{\"dev\":\"vite\"}}", "web/index.html": ""], entryFile: "web/index.html", provenance: nil)
        var received: [String] = []
        terminal.command = "cd web"
        terminal.submit(project: project, isBusy: false, onCheck: {}, onRun: {})
        for command in ["npm install", "npm ci", "npm run dev", "npm start", "npm run build", "npm run check"] {
            terminal.command = command
            terminal.submit(project: project, isBusy: false, onCheck: { XCTFail("Rust check") }, onRun: { XCTFail("Rust run") }, onBrowserCommand: {
                switch $0 {
                case let .install(frozen, directory): received.append("install:\(frozen):\(directory)")
                case let .build(run, directory): received.append("build:\(run):\(directory)")
                }
            })
        }
        XCTAssertEqual(received, ["install:false:web", "install:true:web", "build:true:web", "build:true:web", "build:false:web", "build:false:web"])
        terminal.command = "npm install"
        terminal.submit(project: project, isBusy: true, onCheck: {}, onRun: {}, onBrowserCommand: { _ in XCTFail("Busy") })
        XCTAssertTrue(terminal.lines.last?.text.contains("Wait") == true)
    }

    func testTerminalCommandsUseCurrentProjectSnapshot() {
        let terminal = ProjectTerminalSession()
        let project = CrabrixProject(
            name: "terminal-lab",
            files: [
                "Cargo.toml": "[package]\nname = \"terminal-lab\"\n[dependencies]\nserde = \"1\"",
                "src/main.rs": "fn main() {}",
            ],
            entryFile: "src/main.rs",
            provenance: nil
        )

        terminal.attach(to: project)
        terminal.command = "cat src/main.rs"
        terminal.submit(project: project, isBusy: false, onCheck: {}, onRun: {})
        terminal.command = "cargo tree"
        terminal.submit(project: project, isBusy: false, onCheck: {}, onRun: {})

        let transcript = terminal.lines.map(\.text).joined(separator: "\n")
        XCTAssertTrue(transcript.contains("fn main() {}"))
        XCTAssertTrue(transcript.contains("serde 1"))
    }

    func testTerminalKeepsIndependentProjectBuffers() {
        let terminal = ProjectTerminalSession()
        let first = project(named: "first")
        let second = project(named: "second")

        terminal.attach(to: first)
        terminal.command = "pwd"
        terminal.submit(project: first, isBusy: false, onCheck: {}, onRun: {})
        terminal.attach(to: second)
        XCTAssertFalse(terminal.lines.map(\.text).joined().contains("/workspace/first"))
        terminal.attach(to: first)
        XCTAssertTrue(terminal.lines.map(\.text).joined().contains("/workspace/first"))
    }

    func testSameNamedProjectsKeepIndependentTerminalState() {
        let terminal = ProjectTerminalSession()
        let first = project(named: "demo")
        let second = project(named: "demo")

        terminal.attach(to: first)
        terminal.command = "echo first"
        terminal.submit(project: first, isBusy: false, onCheck: {}, onRun: {})
        terminal.attach(to: second)

        XCTAssertEqual(terminal.projectID, second.id)
        XCTAssertFalse(terminal.lines.map(\.text).joined().contains("first"))

        terminal.command = "echo second"
        terminal.submit(project: second, isBusy: false, onCheck: {}, onRun: {})
        terminal.attach(to: first)

        let restored = terminal.lines.map(\.text).joined(separator: "\n")
        XCTAssertTrue(restored.contains("first"))
        XCTAssertFalse(restored.contains("second"))
    }

    func testCargoRunInvokesBuildCallback() {
        let terminal = ProjectTerminalSession()
        let project = project(named: "runner")
        var didRun = false

        terminal.command = "cargo run"
        terminal.submit(
            project: project,
            isBusy: false,
            onCheck: {},
            onRun: { didRun = true }
        )

        XCTAssertTrue(didRun)
    }

    func testCommandHistoryRestoresDraftAndStaysWithProject() {
        let terminal = ProjectTerminalSession()
        let first = project(named: "first")
        let second = project(named: "second")

        submit("pwd", to: terminal, project: first)
        submit("cargo metadata", to: terminal, project: first)
        terminal.command = "unfinished"
        terminal.recallPrevious()
        XCTAssertEqual(terminal.command, "cargo metadata")
        terminal.recallPrevious()
        XCTAssertEqual(terminal.command, "pwd")
        terminal.recallNext()
        XCTAssertEqual(terminal.command, "cargo metadata")
        terminal.recallNext()
        XCTAssertEqual(terminal.command, "unfinished")

        terminal.attach(to: second)
        XCTAssertFalse(terminal.canRecallPrevious)
        terminal.attach(to: first)
        XCTAssertTrue(terminal.canRecallPrevious)
        XCTAssertTrue(terminal.lines.map(\.text).joined().contains("Package: first"))
    }

    func testLinuxStyleListingAndNavigation() {
        let terminal = ProjectTerminalSession()
        let project = CrabrixProject(
            name: "shell-lab",
            files: [
                "Cargo.toml": "[package]",
                "src/main.rs": "fn main() {\n    println!(\"hello\");\n}",
            ],
            entryFile: "src/main.rs",
            provenance: nil
        )

        submit("ls -la", to: terminal, project: project)
        submit("cd src", to: terminal, project: project)
        submit("pwd", to: terminal, project: project)
        submit("head -n 1 main.rs", to: terminal, project: project)

        let transcript = terminal.lines.map(\.text).joined(separator: "\n")
        XCTAssertTrue(transcript.contains("drwxr-xr-x"))
        XCTAssertTrue(transcript.contains("src/"))
        XCTAssertTrue(transcript.contains("/workspace/shell-lab/src"))
        XCTAssertTrue(transcript.contains("fn main() {"))
    }

    func testSearchCommandsInspectProjectFiles() {
        let terminal = ProjectTerminalSession()
        let project = CrabrixProject(
            name: "search-lab",
            files: [
                "src/main.rs": "fn main() {\n    println!(\"crab\");\n}",
                "src/lib.rs": "pub fn crab() {}",
            ],
            entryFile: "src/main.rs",
            provenance: nil
        )

        submit("grep -inr CRAB src", to: terminal, project: project)
        submit("find . -name '*.rs'", to: terminal, project: project)
        submit("wc -l src/main.rs", to: terminal, project: project)

        let transcript = terminal.lines.map(\.text).joined(separator: "\n")
        XCTAssertTrue(transcript.contains("src/main.rs:2"))
        XCTAssertTrue(transcript.contains("./src/lib.rs"))
        XCTAssertTrue(transcript.contains("3  src/main.rs"))
    }

    func testMutationCommandsReplaceProjectSnapshot() {
        let terminal = ProjectTerminalSession()
        var files = ["main.rs": "fn main() {}"]
        let projectID = UUID()

        func project() -> CrabrixProject {
            CrabrixProject(
                id: projectID,
                name: "edit-lab",
                files: files,
                entryFile: "main.rs",
                provenance: nil
            )
        }

        let replace: ([String: String], String?) -> Bool = { replacement, _ in
            files = replacement
            return true
        }
        submit("mkdir notes", to: terminal, project: project(), onReplaceFiles: replace)
        submit("echo 'ownership notes' > notes/lesson.txt", to: terminal, project: project(), onReplaceFiles: replace)
        XCTAssertEqual(files["notes/lesson.txt"], "ownership notes\n")

        submit("cp notes/lesson.txt notes/copy.txt", to: terminal, project: project(), onReplaceFiles: replace)
        XCTAssertEqual(files["notes/copy.txt"], "ownership notes\n")

        submit("rm -r notes", to: terminal, project: project(), onReplaceFiles: replace)
        XCTAssertFalse(files.keys.contains(where: { $0.hasPrefix("notes/") }))
    }

    private func submit(
        _ command: String,
        to terminal: ProjectTerminalSession,
        project: CrabrixProject,
        onReplaceFiles: (([String: String], String?) -> Bool)? = nil
    ) {
        terminal.command = command
        terminal.submit(
            project: project,
            isBusy: false,
            onCheck: {},
            onRun: {},
            onReplaceFiles: onReplaceFiles
        )
    }

    private func project(named name: String) -> CrabrixProject {
        CrabrixProject(
            name: name,
            files: ["main.rs": "fn main() {}"],
            entryFile: "main.rs",
            provenance: nil
        )
    }
}

final class ProjectTerminalCargoTreeTests: XCTestCase {
    private func project(manifest: String) -> CrabrixProject {
        CrabrixProject(
            name: "tree-demo",
            files: ["Cargo.toml": manifest, "src/main.rs": "fn main() {}"],
            entryFile: "src/main.rs",
            provenance: nil
        )
    }

    func testFallsBackToDeclaredDependenciesBeforeResolution() {
        let rendered = ProjectTerminalSession.renderTree(
            project: project(manifest: """
            [package]
            name = "tree-demo"
            version = "0.4.0"

            [dependencies]
            smallvec = "1"
            """),
            workspace: .empty
        )

        XCTAssertTrue(rendered.hasPrefix("tree-demo v0.4.0"))
        XCTAssertTrue(rendered.contains("smallvec 1 (unresolved)"))
        XCTAssertTrue(rendered.contains("cargo fetch"))
    }

    func testReportsNoDependenciesForAPlainProject() {
        let rendered = ProjectTerminalSession.renderTree(
            project: project(manifest: "[package]\nname = \"tree-demo\"\nversion = \"0.1.0\""),
            workspace: .empty
        )
        XCTAssertTrue(rendered.contains("no dependencies"))
    }

    func testRendersTheResolvedGraphWithCompatibilityMarkers() {
        let direct = CratePackageStatus(
            package: PackageID(name: "smallvec", version: SemanticVersion("1.15.2")!),
            checksum: String(repeating: "a", count: 64),
            features: ["default"],
            compatibility: .verified,
            isDownloaded: true,
            isLocallyPatched: false,
            isDirect: true
        )
        let transitive = CratePackageStatus(
            package: PackageID(name: "cfg-if", version: SemanticVersion("1.0.4")!),
            checksum: String(repeating: "b", count: 64),
            features: [],
            compatibility: .review("runs build.rs, which Crabrix does not execute"),
            isDownloaded: true,
            isLocallyPatched: false,
            isDirect: false
        )
        let workspace = CargoWorkspaceSnapshot(
            packages: [direct, transitive],
            plan: .empty,
            warnings: [],
            lockfile: nil,
            isOfflineReady: true,
            isOfflinePinned: true,
            unresolvedDependencies: []
        )

        let rendered = ProjectTerminalSession.renderTree(
            project: project(manifest: "[package]\nname = \"tree-demo\"\nversion = \"0.1.0\""),
            workspace: workspace
        )

        XCTAssertTrue(rendered.contains("├── smallvec v1.15.2 [link-verified]"))
        XCTAssertTrue(rendered.contains("└── cfg-if v1.0.4 [review] (transitive)"))
        XCTAssertTrue(rendered.contains("offline pinned"))
    }
}
