import Foundation

struct CompilationResult: Sendable {
    enum Phase: String, Sendable {
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
