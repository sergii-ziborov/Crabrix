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

    private func project(named name: String) -> CrabrixProject {
        CrabrixProject(
            name: name,
            files: ["main.rs": "fn main() {}"],
            entryFile: "main.rs",
            provenance: nil
        )
    }
}
