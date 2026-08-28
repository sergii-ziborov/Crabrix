import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

struct RustSourceEdit: Equatable, Sendable {
    let startLine: Int
    let endLine: Int
    let replacement: String

    var lineLabel: String {
        startLine == endLine ? "line \(startLine)" : "lines \(startLine)–\(endLine)"
    }
}

struct RustDiagnosticAdvice: Equatable, Sendable {
    enum Verification: Equatable, Sendable {
        case explanationOnly
        case verified
        case rejected(String)
    }

    let filePath: String
    let originalSource: String
    let proposedSource: String?
    let explanation: String
    let changeSummary: String
    let edits: [RustSourceEdit]
    let verification: Verification

    var canApply: Bool {
        proposedSource != nil && verification == .verified
    }
}

enum RustDiagnosticAdviceState: Equatable, Sendable {
    case idle
    case generating
    case verifying
    case ready(RustDiagnosticAdvice)
    case unavailable(String)

    var isWorking: Bool {
        switch self {
        case .generating, .verifying: true
        default: false
        }
    }
}

struct RustDiagnosticDraft: Equatable, Sendable {
    let explanation: String
    let changeSummary: String
    let edits: [RustSourceEdit]
}

enum RustSourcePatch {
    enum PatchError: LocalizedError, Equatable {
        case tooManyEdits
        case invalidRange(Int, Int)
        case overlappingEdits
        case replacementTooLarge

        var errorDescription: String? {
            switch self {
            case .tooManyEdits:
                "The suggestion contains too many separate edits."
            case let .invalidRange(start, end):
                "The suggestion targets an invalid line range: \(start)–\(end)."
            case .overlappingEdits:
                "The suggestion contains overlapping edits."
            case .replacementTooLarge:
                "The suggested replacement is unexpectedly large."
            }
        }
    }

    static func applying(_ edits: [RustSourceEdit], to source: String) throws -> String {
        guard edits.count <= 4 else { throw PatchError.tooManyEdits }
        guard edits.reduce(0, { $0 + $1.replacement.utf8.count }) <= 12_000 else {
            throw PatchError.replacementTooLarge
        }
        guard !edits.isEmpty else { return source }

        var lines = source.components(separatedBy: "\n")
        let ordered = edits.sorted {
            $0.startLine == $1.startLine
                ? $0.endLine < $1.endLine
                : $0.startLine < $1.startLine
        }

        for edit in ordered {
            guard edit.startLine >= 1,
                  edit.endLine >= edit.startLine,
                  edit.endLine <= lines.count
            else {
                throw PatchError.invalidRange(edit.startLine, edit.endLine)
            }
        }
        for pair in zip(ordered, ordered.dropFirst()) where pair.0.endLine >= pair.1.startLine {
            throw PatchError.overlappingEdits
        }

        // The model uses line numbers from the original snapshot. Applying from
        // bottom to top keeps every earlier line number stable.
        for edit in ordered.reversed() {
            let replacement = sanitizedReplacement(edit.replacement)
                .components(separatedBy: "\n")
            lines.replaceSubrange((edit.startLine - 1)..<edit.endLine, with: replacement)
        }
        return lines.joined(separator: "\n")
    }

    private static func sanitizedReplacement(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .newlines)
        if value.hasPrefix("```") {
            var lines = value.components(separatedBy: "\n")
            if !lines.isEmpty { lines.removeFirst() }
            if lines.last?.trimmingCharacters(in: .whitespacesAndNewlines) == "```" {
                lines.removeLast()
            }
            value = lines.joined(separator: "\n")
        }
        return value
    }
}

enum AppleIntelligenceDiagnosticAdvisorError: LocalizedError {
    case unavailable(String)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case let .unavailable(reason): reason
        case .emptyResponse: "Apple Intelligence did not produce a useful explanation."
        }
    }
}

@MainActor
enum AppleIntelligenceDiagnosticAdvisor {
    static func generate(
        diagnostic: RustDiagnostic,
        project: CrabrixProject,
        targetFile: String
    ) async throws -> RustDiagnosticDraft {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return try await FoundationModelsRustDiagnosticAdvisor.generate(
                diagnostic: diagnostic,
                project: project,
                targetFile: targetFile
            )
        }
        #endif
        throw AppleIntelligenceDiagnosticAdvisorError.unavailable(
            "Apple Intelligence diagnostic fixes require iOS 26 or newer."
        )
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
private struct GeneratedRustSourceEdit {
    var startLine: Int
    var endLine: Int
    var replacement: String
}

@available(iOS 26.0, *)
@Generable
private struct GeneratedRustDiagnosticFix {
    var explanation: String
    var changeSummary: String
    var edits: [GeneratedRustSourceEdit]
}

@available(iOS 26.0, *)
@MainActor
private enum FoundationModelsRustDiagnosticAdvisor {
    static func generate(
        diagnostic: RustDiagnostic,
        project: CrabrixProject,
        targetFile: String
    ) async throws -> RustDiagnosticDraft {
        switch SystemLanguageModel.default.availability {
        case .available:
            break
        case let .unavailable(reason):
            throw AppleIntelligenceDiagnosticAdvisorError.unavailable(
                unavailableMessage(for: reason)
            )
        @unknown default:
            throw AppleIntelligenceDiagnosticAdvisorError.unavailable(
                "Apple Intelligence is unavailable on this device."
            )
        }

        guard let targetSource = project.files[targetFile] else {
            throw AppleIntelligenceDiagnosticAdvisorError.emptyResponse
        }
        let session = LanguageModelSession(
            instructions: """
            You are a conservative Rust compiler diagnostic assistant inside an educational editor. Analyze only the supplied rustc diagnostic and source context. Propose the smallest stable Rust 2024 edit that addresses the diagnostic without adding dependencies, unsafe code, unwrap, expect, or unrelated refactoring. Use original one-based line numbers. Each replacement must contain complete source lines without line-number prefixes or Markdown fences. Return at most four non-overlapping edits in the target file. If the evidence is insufficient, explain the issue and return no edits.
            """
        )
        let response = try await session.respond(
            to: prompt(
                diagnostic: diagnostic,
                project: project,
                targetFile: targetFile,
                targetSource: targetSource
            ),
            generating: GeneratedRustDiagnosticFix.self
        )
        let generated = response.content
        let explanation = generated.explanation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !explanation.isEmpty else {
            throw AppleIntelligenceDiagnosticAdvisorError.emptyResponse
        }
        let edits = generated.edits.prefix(4).map {
            RustSourceEdit(
                startLine: $0.startLine,
                endLine: $0.endLine,
                replacement: $0.replacement
            )
        }
        return RustDiagnosticDraft(
            explanation: explanation,
            changeSummary: generated.changeSummary.trimmingCharacters(in: .whitespacesAndNewlines),
            edits: edits
        )
    }

    private static func prompt(
        diagnostic: RustDiagnostic,
        project: CrabrixProject,
        targetFile: String,
        targetSource: String
    ) -> String {
        var sections = [
            "Target file: \(targetFile)",
            "Compiler diagnostic:\n\(String(diagnostic.rendered.prefix(3_500)))",
            "Target source (original one-based line numbers):\n\(numberedContext(for: targetSource, diagnostic: diagnostic, targetFile: targetFile))",
        ]

        if let manifest = project.files["Cargo.toml"] {
            sections.append("Cargo.toml context:\n\(String(manifest.prefix(1_200)))")
        }

        let related = diagnostic.spans.compactMap { span -> String? in
            guard span.fileName != targetFile, !span.sourceLine.isEmpty else { return nil }
            return "\(span.fileName):\(span.lineStart): \(span.sourceLine)"
        }
        if !related.isEmpty {
            sections.append("Related compiler spans:\n\(related.prefix(8).joined(separator: "\n"))")
        }
        return sections.joined(separator: "\n\n")
    }

    private static func numberedContext(
        for source: String,
        diagnostic: RustDiagnostic,
        targetFile: String
    ) -> String {
        let lines = source.components(separatedBy: "\n")
        let relevantLines = diagnostic.spans
            .filter { $0.fileName == targetFile }
            .flatMap { [$0.lineStart, $0.lineEnd] }

        let range: ClosedRange<Int>
        if lines.count <= 120, source.utf8.count <= 7_000 {
            range = 1...max(lines.count, 1)
        } else if let first = relevantLines.min(), let last = relevantLines.max() {
            range = max(first - 18, 1)...min(last + 18, lines.count)
        } else {
            range = 1...min(lines.count, 72)
        }

        return range.map { lineNumber in
            let text = lines.indices.contains(lineNumber - 1) ? lines[lineNumber - 1] : ""
            return "\(lineNumber) | \(text)"
        }.joined(separator: "\n")
    }

    private static func unavailableMessage(
        for reason: SystemLanguageModel.Availability.UnavailableReason
    ) -> String {
        switch reason {
        case .deviceNotEligible:
            "This device does not support Apple Intelligence."
        case .appleIntelligenceNotEnabled:
            "Turn on Apple Intelligence in Settings to generate diagnostic fixes."
        case .modelNotReady:
            "The Apple Intelligence model is still downloading or preparing."
        @unknown default:
            "Apple Intelligence is unavailable on this device."
        }
    }
}
#endif
