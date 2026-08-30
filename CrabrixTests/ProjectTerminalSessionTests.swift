import XCTest
@testable import Crabrix

@MainActor
final class ProjectTerminalSessionTests: XCTestCase {
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
            features: ["default"],
            compatibility: .verified,
            isDownloaded: true,
            isDirect: true
        )
        let transitive = CratePackageStatus(
            package: PackageID(name: "cfg-if", version: SemanticVersion("1.0.4")!),
            features: [],
            compatibility: .review("runs build.rs, which Crabrix does not execute"),
            isDownloaded: true,
            isDirect: false
        )
        let workspace = CargoWorkspaceSnapshot(
            packages: [direct, transitive],
            plan: .empty,
            warnings: [],
            lockfile: nil,
            isOfflineReady: true,
            unresolvedDependencies: []
        )

        let rendered = ProjectTerminalSession.renderTree(
            project: project(manifest: "[package]\nname = \"tree-demo\"\nversion = \"0.1.0\""),
            workspace: workspace
        )

        XCTAssertTrue(rendered.contains("├── smallvec v1.15.2 [built]"))
        XCTAssertTrue(rendered.contains("└── cfg-if v1.0.4 [review] (transitive)"))
        XCTAssertTrue(rendered.contains("offline ready"))
    }
}
