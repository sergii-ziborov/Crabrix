import Foundation
import SwiftUI

/// Renders a crate README well enough to read on a phone.
///
/// `AttributedString(markdown:)` alone collapses a README into one paragraph:
/// it parses inline syntax but drops block structure, so headings, lists, and
/// fenced code all run together. This keeps the blocks and formats each one,
/// which is the difference between a readable guide and a wall of text.
enum MarkdownRenderer {
    /// Past this the README is truncated rather than laid out in full.
    static let maximumCharacters = 60_000

    static func attributed(_ markdown: String) -> AttributedString {
        var output = AttributedString()
        let source = markdown.count > maximumCharacters
            ? String(markdown.prefix(maximumCharacters)) + "\n\n…"
            : markdown

        for block in blocks(of: source) {
            output.append(render(block))
        }
        return output
    }

    enum Block: Equatable {
        case heading(level: Int, text: String)
        case code(String)
        case bullet(String)
        case paragraph(String)
        case blank
    }

    /// Splits a README into blocks, keeping fenced code intact.
    static func blocks(of markdown: String) -> [Block] {
        var result: [Block] = []
        var codeLines: [String] = []
        var inFence = false
        var paragraph: [String] = []

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            result.append(.paragraph(paragraph.joined(separator: " ")))
            paragraph = []
        }

        for rawLine in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                if inFence {
                    result.append(.code(codeLines.joined(separator: "\n")))
                    codeLines = []
                } else {
                    flushParagraph()
                }
                inFence.toggle()
                continue
            }

            if inFence {
                codeLines.append(line)
                continue
            }

            if trimmed.isEmpty {
                flushParagraph()
                result.append(.blank)
                continue
            }

            if trimmed.hasPrefix("#") {
                flushParagraph()
                let level = trimmed.prefix(while: { $0 == "#" }).count
                let text = trimmed.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
                result.append(.heading(level: min(level, 4), text: text))
                continue
            }

            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
                flushParagraph()
                result.append(.bullet(String(trimmed.dropFirst(2))))
                continue
            }

            paragraph.append(trimmed)
        }

        // An unterminated fence still has to render, not vanish.
        if inFence, !codeLines.isEmpty {
            result.append(.code(codeLines.joined(separator: "\n")))
        }
        flushParagraph()
        return result
    }

    private static func render(_ block: Block) -> AttributedString {
        switch block {
        case let .heading(level, text):
            var line = inline(text)
            line.font = .system(
                size: [0: 22.0, 1: 22, 2: 19, 3: 17, 4: 15][level] ?? 15,
                weight: .bold
            )
            line.foregroundColor = CrabrixTheme.primary
            return line + AttributedString("\n\n")

        case let .code(code):
            var line = AttributedString(code)
            line.font = .system(size: 12, design: .monospaced)
            line.foregroundColor = CrabrixTheme.mint
            return line + AttributedString("\n\n")

        case let .bullet(text):
            var bullet = AttributedString("  •  ")
            bullet.foregroundColor = CrabrixTheme.coral
            return bullet + inline(text) + AttributedString("\n")

        case let .paragraph(text):
            return inline(text) + AttributedString("\n\n")

        case .blank:
            return AttributedString()
        }
    }

    /// Inline markdown only — bold, code spans, links — which AttributedString
    /// already handles correctly once the block structure is out of the way.
    private static func inline(_ text: String) -> AttributedString {
        var line = (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
        line.font = .system(size: 14)
        line.foregroundColor = CrabrixTheme.primary
        return line
    }
}
