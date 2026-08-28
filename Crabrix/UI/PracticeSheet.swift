import SwiftUI

struct PracticeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var source: String
    @State private var cursorOffset = 0
    @State private var isChecking = false
    @State private var feedback = "Move one line so the name is printed before the Vec changes."
    @State private var passed = false

    let validate: (String) async -> CompilationResult

    init(initialSource: String, validate: @escaping (String) async -> CompilationResult) {
        _source = State(initialValue: initialSource)
        self.validate = validate
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("MICRO-PRACTICE · E0502")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(CrabrixTheme.coral)
                    Text("Release the borrow before mutation")
                        .font(.title2.bold())
                    Text("Make the program compile and print Ada. The same bundled compiler validates the answer.")
                        .font(.subheadline)
                        .foregroundStyle(CrabrixTheme.muted)
                }

                // The practice editor is a real Rust editor, so it gets the same
                // highlighting, gutter, and Rust keyboard as the workspace.
                SyntaxCodeEditor(
                    text: $source,
                    cursorOffset: $cursorOffset,
                    filePath: "practice.rs",
                    isEditable: !isChecking,
                    diagnostics: [],
                    navigationTarget: nil,
                    onRequestCompletion: {}
                )
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(CrabrixTheme.border)
                }

                HStack(spacing: 9) {
                    Image(systemName: passed ? "checkmark.circle.fill" : "info.circle")
                        .foregroundStyle(passed ? CrabrixTheme.mint : CrabrixTheme.blue)
                    Text(feedback)
                        .font(.caption)
                        .foregroundStyle(passed ? CrabrixTheme.mint : CrabrixTheme.muted)
                    Spacer()
                }
                .padding(12)
                .crabrixPanel(cornerRadius: 9)

                Button {
                    Task { await check() }
                } label: {
                    HStack {
                        if isChecking { ProgressView().tint(.white) }
                        Text(isChecking ? "Running bundled rustc…" : passed ? "Passed" : "Check and run locally")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(passed ? CrabrixTheme.mint.opacity(0.6) : CrabrixTheme.coral)
                .disabled(isChecking || passed)
            }
            .padding(20)
            .background(CrabrixTheme.panel.ignoresSafeArea())
            .foregroundStyle(CrabrixTheme.primary)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func check() async {
        isChecking = true
        let result = await validate(source)
        isChecking = false
        if result.succeeded, result.stdout.contains("Ada") {
            passed = true
            feedback = "rustc accepted the solution · stdout: Ada"
        } else if let diagnostic = result.diagnostics.first {
            feedback = "\(diagnostic.code ?? "error") · \(diagnostic.message)"
        } else {
            feedback = result.detail
        }
    }
}
