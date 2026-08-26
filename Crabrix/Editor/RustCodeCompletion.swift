import Foundation
import SwiftUI

#if canImport(FoundationModels)
import FoundationModels
#endif

enum RustCompletionProvider: String, Sendable {
    case local = "Instant Rust"
    case appleIntelligence = "Apple Intelligence"
}

struct RustCodeCompletion: Identifiable, Equatable, Sendable {
    let id = UUID()
    let insertion: String
    let provider: RustCompletionProvider
    let detail: String
}

@MainActor
final class RustCompletionController: ObservableObject {
    @Published private(set) var suggestion: RustCodeCompletion?
    @Published private(set) var isLoading = false
    @Published private(set) var message: String?

    private var requestTask: Task<Void, Never>?

    func request(
        source: String,
        cursorOffset: Int,
        filePath: String,
        useAppleIntelligence: Bool
    ) {
        requestTask?.cancel()
        suggestion = nil
        message = nil

        guard filePath.lowercased().hasSuffix(".rs") else {
            message = "Completion is available for Rust source files."
            return
        }

        let safeOffset = min(max(cursorOffset, 0), (source as NSString).length)
        let prefix = (source as NSString).substring(to: safeOffset)
        let local = RustLocalCompleter.suggestion(for: prefix)

        // Known Rust constructs should feel instant even when the on-device model is
        // enabled. The model remains the fallback for contexts the deterministic
        // completer does not recognize.
        if let local {
            suggestion = local
            return
        }

        guard useAppleIntelligence else {
            message = "Type at least two characters of a Rust construct first."
            return
        }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                isLoading = true
                requestTask = Task { [weak self] in
                    do {
                        let completion = try await AppleIntelligenceRustCompleter.complete(prefix: prefix)
                        guard !Task.isCancelled else { return }
                        self?.suggestion = completion
                        self?.message = completion == nil
                            ? "No useful completion was produced."
                            : nil
                    } catch {
                        guard !Task.isCancelled else { return }
                        self?.message = "Apple Intelligence could not complete this code."
                    }
                    self?.isLoading = false
                    self?.requestTask = nil
                }
                return
            case .unavailable:
                break
            @unknown default:
                break
            }
        }
        #endif

        message = "Apple Intelligence is unavailable; type at least two characters of a Rust construct."
    }

    func dismiss() {
        requestTask?.cancel()
        requestTask = nil
        isLoading = false
        suggestion = nil
        message = nil
    }
}

enum RustCompletionSupport {
    @MainActor
    static var appleIntelligenceStatus: String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return "Available on this device"
            case let .unavailable(reason):
                switch reason {
                case .deviceNotEligible:
                    return "Device is not eligible"
                case .appleIntelligenceNotEnabled:
                    return "Not enabled in Settings"
                case .modelNotReady:
                    return "Model is not ready"
                @unknown default:
                    return "Unavailable"
                }
            }
        }
        #endif
        return "Requires iOS 26 or newer"
    }
}

enum RustLocalCompleter {
    static func suggestion(for prefix: String) -> RustCodeCompletion? {
        let line = prefix.split(separator: "\n", omittingEmptySubsequences: false).last.map(String.init) ?? ""
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        let insertion: String?
        switch true {
        case trimmed.hasSuffix("fn "):
            insertion = "main() {\n    \n}"
        case trimmed.hasSuffix("let mut "):
            insertion = "items = Vec::new();"
        case trimmed.hasSuffix("let "):
            insertion = "value = 0;"
        case trimmed.hasSuffix("match "):
            insertion = "value {\n    Some(value) => value,\n    None => return,\n}"
        case trimmed.hasSuffix("for "):
            insertion = "item in items.iter() {\n    println!(\"{item:?}\");\n}"
        case trimmed.hasSuffix("impl "):
            insertion = "Default for AppState {\n    fn default() -> Self {\n        Self {}\n    }\n}"
        case trimmed.hasSuffix("use std::"):
            insertion = "collections::HashMap;"
        case trimmed.hasSuffix("Vec::"):
            insertion = "new()"
        case trimmed.hasSuffix("."):
            insertion = "iter()"
        default:
            insertion = completionForCurrentToken(in: trimmed)
        }

        guard let insertion else { return nil }
        return RustCodeCompletion(
            insertion: insertion,
            provider: .local,
            detail: "Deterministic, instant, and fully offline"
        )
    }

    private static func completionForCurrentToken(in line: String) -> String? {
        var token = String(
            line.reversed().prefix { character in
                character.isLetter
                    || character.isNumber
                    || character == "_"
                    || character == ":"
                    || character == "."
            }.reversed()
        )
        if let lastDot = token.lastIndex(of: "."), !token.contains("::") {
            token = String(token[lastDot...])
        }
        guard token.count >= 2 else { return nil }

        let candidates = [
            "println!(\"Hello, Crabrix!\");",
            "print!(\"{value}\");",
            "fn main() {\n    \n}",
            "let mut value = 0;",
            "match value {\n    Some(value) => value,\n    None => return,\n}",
            "for item in items.iter() {\n    println!(\"{item:?}\");\n}",
            "while condition {\n    \n}",
            "loop {\n    break;\n}",
            "struct AppState {\n    \n}",
            "enum Message {\n    \n}",
            "impl Default for AppState {\n    fn default() -> Self {\n        Self {}\n    }\n}",
            "pub fn ",
            "return ",
            "vec![]",
            "Vec::new()",
            "String::new()",
            "Some(value)",
            "None",
            "Ok(value)",
            "Err(error)",
            "Result<T, E>",
            "Option<T>",
            "std::collections::HashMap",
            ".iter()",
            ".iter_mut()",
            ".into_iter()",
            ".collect::<Vec<_>>()",
            ".unwrap_or_default()",
        ]

        let candidate = candidates.first(where: {
            $0.hasPrefix(token) && $0.count > token.count
        }) ?? candidates.first(where: {
            $0.lowercased().hasPrefix(token.lowercased()) && $0.count > token.count
        })
        guard let candidate else { return nil }
        return String(candidate.dropFirst(token.count))
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
private enum AppleIntelligenceRustCompleter {
    @MainActor
    static func complete(prefix: String) async throws -> RustCodeCompletion? {
        let context = String(prefix.suffix(2_400))
        let session = LanguageModelSession(
            instructions: """
            You are a conservative Rust code completion engine. Return only the short code suffix that should be inserted at the cursor. Never use Markdown fences, explanations, or repeat the supplied prefix. Prefer valid stable Rust and at most eight lines.
            """
        )
        let response = try await session.respond(
            to: "Complete the Rust source exactly at <CURSOR>:\n\n\(context)<CURSOR>"
        )
        let cleaned = sanitize(response.content)
        guard !cleaned.isEmpty else { return nil }
        return RustCodeCompletion(
            insertion: cleaned,
            provider: .appleIntelligence,
            detail: "Generated on device; review before inserting"
        )
    }

    private static func sanitize(_ raw: String) -> String {
        var value = raw
        if value.hasPrefix("```") {
            let lines = value.split(separator: "\n", omittingEmptySubsequences: false)
            value = lines.dropFirst().joined(separator: "\n")
        }
        if value.hasSuffix("```") {
            value = String(value.dropLast(3))
        }
        return value.trimmingCharacters(in: .newlines)
    }
}
#endif
