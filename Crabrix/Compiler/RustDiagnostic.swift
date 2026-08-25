import Foundation

struct RustDiagnostic: Identifiable, Equatable, Sendable {
    struct Span: Equatable, Sendable {
        let lineStart: Int
        let lineEnd: Int
        let columnStart: Int
        let columnEnd: Int
        let isPrimary: Bool
        let label: String?
        let sourceLine: String
    }

    let id = UUID()
    let level: String
    let message: String
    let code: String?
    let rendered: String
    let spans: [Span]

    var primarySpan: Span? {
        spans.first(where: \.isPrimary) ?? spans.first
    }
}

enum RustDiagnosticParser {
    private struct Envelope: Decodable {
        struct DiagnosticCode: Decodable {
            let code: String
        }

        struct CompilerSpan: Decodable {
            struct SourceText: Decodable {
                let text: String
            }

            let fileName: String
            let lineStart: Int
            let lineEnd: Int
            let columnStart: Int
            let columnEnd: Int
            let isPrimary: Bool
            let label: String?
            let text: [SourceText]

            enum CodingKeys: String, CodingKey {
                case fileName = "file_name"
                case lineStart = "line_start"
                case lineEnd = "line_end"
                case columnStart = "column_start"
                case columnEnd = "column_end"
                case isPrimary = "is_primary"
                case label
                case text
            }
        }

        let messageType: String?
        let message: String
        let code: DiagnosticCode?
        let level: String
        let spans: [CompilerSpan]
        let rendered: String?

        enum CodingKeys: String, CodingKey {
            case messageType = "$message_type"
            case message
            case code
            case level
            case spans
            case rendered
        }
    }

    static func parse(stderr: String) -> [RustDiagnostic] {
        let decoder = JSONDecoder()
        return stderr.split(separator: "\n").compactMap { line in
            guard line.first == "{",
                  let data = line.data(using: .utf8),
                  let envelope = try? decoder.decode(Envelope.self, from: data),
                  envelope.messageType == "diagnostic",
                  envelope.level == "error" || envelope.level == "warning"
            else {
                return nil
            }

            let spans = envelope.spans
                .filter { $0.fileName.hasSuffix("main.rs") }
                .map {
                    RustDiagnostic.Span(
                        lineStart: $0.lineStart,
                        lineEnd: $0.lineEnd,
                        columnStart: $0.columnStart,
                        columnEnd: $0.columnEnd,
                        isPrimary: $0.isPrimary,
                        label: $0.label,
                        sourceLine: $0.text.first?.text ?? ""
                    )
                }

            let rendered = (envelope.rendered ?? envelope.message)
                .replacingOccurrences(
                    of: "\u{001B}\\[[0-9;]*m",
                    with: "",
                    options: .regularExpression
                )
                .replacingOccurrences(of: "/work/main.rs", with: "main.rs")

            return RustDiagnostic(
                level: envelope.level,
                message: envelope.message,
                code: envelope.code?.code,
                rendered: rendered,
                spans: spans
            )
        }
    }
}
