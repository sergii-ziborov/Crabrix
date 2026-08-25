import Foundation

struct BorrowExplanation {
    struct Step: Identifiable {
        let id = UUID()
        let line: Int
        let title: String
        let source: String
        let isConflict: Bool
    }

    let title: String
    let summary: String
    let rule: String
    let steps: [Step]

    static func make(for diagnostic: RustDiagnostic) -> BorrowExplanation {
        guard diagnostic.code == "E0502" else {
            return BorrowExplanation(
                title: diagnostic.code ?? "Compiler diagnostic",
                summary: diagnostic.message,
                rule: "The bundled compiler is the source of truth.",
                steps: diagnostic.spans.map {
                    Step(
                        line: $0.lineStart,
                        title: $0.label ?? diagnostic.message,
                        source: $0.sourceLine.trimmingCharacters(in: .whitespaces),
                        isConflict: $0.isPrimary
                    )
                }
            )
        }

        let immutable = diagnostic.spans.first { $0.label?.contains("immutable borrow occurs") == true }
        let laterUse = diagnostic.spans.first { $0.label?.contains("later used") == true }
        let mutation = diagnostic.spans.first { $0.label?.contains("mutable borrow occurs") == true }

        return BorrowExplanation(
            title: "Mutable and immutable borrows overlap",
            summary: "The reference keeps an immutable borrow alive until its last use. The Vec cannot be changed inside that interval.",
            rule: "At one moment, a value may have many immutable references or one mutable reference — not both.",
            steps: [
                immutable.map {
                    Step(line: $0.lineStart, title: "Immutable borrow begins", source: $0.sourceLine.trimmingCharacters(in: .whitespaces), isConflict: false)
                },
                laterUse.map {
                    Step(line: $0.lineStart, title: "The reference must stay alive", source: $0.sourceLine.trimmingCharacters(in: .whitespaces), isConflict: false)
                },
                mutation.map {
                    Step(line: $0.lineStart, title: "Mutable access is requested", source: $0.sourceLine.trimmingCharacters(in: .whitespaces), isConflict: true)
                },
                mutation.map {
                    Step(line: $0.lineStart, title: "The intervals overlap, so rustc rejects the program", source: "memory safety preserved", isConflict: true)
                },
            ].compactMap { $0 }
        )
    }
}
