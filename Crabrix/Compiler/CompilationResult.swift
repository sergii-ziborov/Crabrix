import Foundation

struct CompilationResult: Sendable {
    enum Phase: String, Codable, Sendable {
        case check
        case compile
        case run
        case setup
    }

    let succeeded: Bool
    let phase: Phase
    let exitCode: UInt32?
    let diagnostics: [RustDiagnostic]
    let stdout: String
    let stderr: String
    let duration: Duration
    let detail: String

    var wasStopped: Bool {
        !succeeded && detail.hasPrefix("Build stopped.")
    }

    /// Cargo preparation and sandbox failures have no rustc JSON or source
    /// span. They still belong in Problems. Keep these separate from rustc
    /// diagnostics, which drive source edits, lesson evidence and rewards.
    var problemDiagnostics: [RustDiagnostic] {
        guard !wasStopped else { return [] }
        guard !succeeded, !diagnostics.contains(where: { $0.level == "error" }) else {
            return diagnostics
        }
        let message = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        let diagnostic = RustDiagnostic(
            level: "error",
            message: message.isEmpty ? "The build could not finish." : message,
            code: nil,
            rendered: stderr,
            spans: []
        )
        return [diagnostic] + diagnostics
    }

    static func failure(
        phase: Phase,
        detail: String,
        stderr: String = "",
        duration: Duration = .zero
    ) -> CompilationResult {
        CompilationResult(
            succeeded: false,
            phase: phase,
            exitCode: nil,
            diagnostics: [],
            stdout: "",
            stderr: stderr,
            duration: duration,
            detail: detail
        )
    }
}

struct ToolchainStatus: Sendable, Equatable {
    let isReady: Bool
    let rustcSize: Int64
    let label: String
    let detail: String
}
