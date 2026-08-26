import SwiftUI

struct RuntimeInspector: View {
    let toolchain: ToolchainStatus
    let onCheck: () -> Void
    let onRun: () -> Void

    @State private var isBuildTipExpanded = false
    @State private var isDeviceTipExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "hammer.fill")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(CrabrixTheme.blue)
                    .frame(width: 58, height: 58)
                    .background(CrabrixTheme.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))

                VStack(alignment: .leading, spacing: 6) {
                    Text("READY TO BUILD")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(CrabrixTheme.mint)
                    Text("Check the code, then run it")
                        .font(.system(size: 25, weight: .bold, design: .rounded))
                    Text("Compiler output and errors appear in the full-size Output and Problems tabs beside Code.")
                        .font(.subheadline)
                        .foregroundStyle(CrabrixTheme.muted)
                }
            }

            HStack(spacing: 10) {
                Button(action: onCheck) {
                    Label("Check", systemImage: "checkmark.shield.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(CrabrixTheme.blue)

                Button(action: onRun) {
                    Label("Run", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(CrabrixTheme.coral)
            }

            VStack(alignment: .leading, spacing: 9) {
                Text("NEXT STEP")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(CrabrixTheme.coral)
                Text("Use Check while editing. Run when you want fresh stdout. An unchanged successful Run can reuse the local artifact cache.")
                    .font(.caption)
                    .foregroundStyle(CrabrixTheme.muted)
            }
            .padding(14)
            .crabrixPanel(cornerRadius: 10)

            VStack(alignment: .leading, spacing: 12) {
                DisclosureGroup(isExpanded: $isBuildTipExpanded) {
                    VStack(alignment: .leading, spacing: 12) {
                        RuntimeRow(
                            title: toolchain.label,
                            detail: toolchain.detail,
                            icon: toolchain.isReady ? "checkmark.seal.fill" : "xmark.octagon.fill",
                            color: toolchain.isReady ? CrabrixTheme.mint : CrabrixTheme.coral
                        )
                        RuntimeRow(
                            title: "Native SwiftUI shell",
                            detail: "TextEditor · async compiler queue · app sandbox",
                            icon: "swift",
                            color: CrabrixTheme.coral
                        )
                        RuntimeRow(
                            title: "Bounded program sandbox",
                            detail: "\(WasmSandboxPolicy.memoryLimitLabel) memory · /sandbox write access",
                            icon: "lock.shield.fill",
                            color: CrabrixTheme.mint
                        )
                        RuntimeRow(
                            title: "No runtime network path",
                            detail: "Compiler and sysroot are app-bundle resources · no socket imports",
                            icon: "airplane",
                            color: CrabrixTheme.blue
                        )
                    }
                    .padding(.top, 12)
                } label: {
                    Label("How local builds work", systemImage: "lightbulb.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(CrabrixTheme.blue)
                }
            }
            .padding(14)
            .crabrixPanel()

            DisclosureGroup(isExpanded: $isDeviceTipExpanded) {
                Text("Airplane mode, peak memory, thermal behavior, and hard termination must still pass on a physical iPhone/iPad. Repeated-build gates run in the dedicated test scheme.")
                    .font(.caption)
                    .foregroundStyle(CrabrixTheme.muted)
                    .padding(.top, 8)
            } label: {
                Label("Simulator vs physical device", systemImage: "iphone.gen3")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(CrabrixTheme.amber)
            }
            .padding(14)
            .background(CrabrixTheme.amber.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(CrabrixTheme.amber.opacity(0.25))
            }
        }
    }
}

struct DiagnosticInspector: View {
    let diagnostic: RustDiagnostic
    let canRepair: Bool
    let practiceCompleted: Bool
    let onRepair: () -> Void
    let onPractice: () -> Void

    private var explanation: BorrowExplanation {
        BorrowExplanation.make(for: diagnostic)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("BORROW CHECKER DECODER")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(CrabrixTheme.coral)
                    Text(explanation.title)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                }
                Spacer()
                Text(diagnostic.code ?? "ERROR")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(CrabrixTheme.coral)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(CrabrixTheme.coral.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            Text(explanation.summary)
                .font(.subheadline)
                .foregroundStyle(CrabrixTheme.muted)

            HStack(alignment: .top, spacing: 11) {
                Image(systemName: "link")
                    .foregroundStyle(CrabrixTheme.blue)
                    .frame(width: 28, height: 28)
                    .background(CrabrixTheme.blue.opacity(0.1))
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text("Rule").font(.caption.weight(.bold))
                    Text(explanation.rule)
                        .font(.caption)
                        .foregroundStyle(CrabrixTheme.muted)
                }
            }
            .padding(13)
            .crabrixPanel(cornerRadius: 10)

            Text("What happened")
                .font(.subheadline.weight(.bold))

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(explanation.steps.enumerated()), id: \.element.id) { index, step in
                    HStack(alignment: .top, spacing: 11) {
                        Text("\(index + 1)")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(step.isConflict ? CrabrixTheme.coral : CrabrixTheme.blue)
                            .frame(width: 24, height: 24)
                            .overlay(Circle().stroke(step.isConflict ? CrabrixTheme.coral.opacity(0.5) : CrabrixTheme.border))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("line \(step.line) · \(step.title)")
                                .font(.caption.weight(.semibold))
                            Text(step.source)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(CrabrixTheme.muted)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 7)
                }
            }

            if canRepair {
                VStack(alignment: .leading, spacing: 10) {
                    Text("SMALLEST REPAIR")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(CrabrixTheme.mint)
                    Text("Use the reference before changing the Vec")
                        .font(.subheadline.weight(.semibold))
                    Text("The next Check must still prove that this edit is valid.")
                        .font(.caption)
                        .foregroundStyle(CrabrixTheme.muted)
                    Button(action: onRepair) {
                        Label("Apply to main.rs", systemImage: "arrow.triangle.2.circlepath")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(CrabrixTheme.mint.opacity(0.55))
                }
                .padding(14)
                .crabrixPanel(cornerRadius: 10)
            }

            Button(action: onPractice) {
                HStack {
                    Image(systemName: practiceCompleted ? "checkmark.circle.fill" : "bolt.fill")
                        .foregroundStyle(practiceCompleted ? CrabrixTheme.mint : CrabrixTheme.amber)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(practiceCompleted ? "Micro-practice passed" : "Reinforce with micro-practice")
                            .font(.subheadline.weight(.semibold))
                        Text("A second program, checked by the same bundled rustc")
                            .font(.caption2)
                            .foregroundStyle(CrabrixTheme.muted)
                    }
                    Spacer()
                    Image(systemName: "arrow.right")
                }
                .padding(13)
                .background(CrabrixTheme.amber.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(CrabrixTheme.amber.opacity(0.2))
                }
            }
            .buttonStyle(.plain)
        }
    }
}

struct SuccessInspector: View {
    let result: CompilationResult
    let practiceCompleted: Bool
    let onRunNext: () -> Void
    let onContinueLearning: () -> Void

    private var performanceGateFailed: Bool {
        result.phase == .run && result.duration > .seconds(20)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: performanceGateFailed ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                .font(.system(size: 44))
                .foregroundStyle(performanceGateFailed ? CrabrixTheme.amber : CrabrixTheme.mint)

            Text("COMPILER EVIDENCE")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(CrabrixTheme.coral)
            Text(
                performanceGateFailed
                    ? "Runs locally — performance gate failed"
                    : (result.phase == .run ? "The code compiled and ran locally" : "The code passed rustc — run it next")
            )
                .font(.system(size: 28, weight: .bold, design: .rounded))
            Text(result.detail)
                .font(.subheadline)
                .foregroundStyle(CrabrixTheme.muted)

            VStack(alignment: .leading, spacing: 12) {
                EvidenceRow(label: "Runtime", value: "WasmKit in native Swift process")
                EvidenceRow(label: "Memory cap", value: WasmSandboxPolicy.memoryLimitLabel)
                EvidenceRow(label: "Writable FS", value: WasmSandboxPolicy.writableGuestDirectory)
                EvidenceRow(label: "Network", value: "Not used")
                EvidenceRow(label: "Exit", value: "\(result.exitCode ?? 0)")
                EvidenceRow(label: "Elapsed", value: result.duration.crabrixDescription)
                if performanceGateFailed {
                    EvidenceRow(label: "Performance", value: "Needs optimization · target ≤ 20 s")
                }
                if !result.stdout.isEmpty {
                    EvidenceRow(label: "stdout", value: result.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                EvidenceRow(label: "Practice", value: practiceCompleted ? "Passed" : "Not attempted")
            }
            .padding(14)
            .crabrixPanel()

            if result.phase == .check {
                NextWorkflowStep(
                    eyebrow: "STEP 1 COMPLETE",
                    title: "Next: Run project",
                    detail: "Compile the checked code, execute it locally, and inspect real stdout.",
                    buttonTitle: "Run project",
                    systemImage: "play.fill",
                    tint: CrabrixTheme.coral,
                    action: onRunNext
                )
            } else if result.phase == .run {
                NextWorkflowStep(
                    eyebrow: "BUILD COMPLETE",
                    title: "Continue on the Rust path",
                    detail: "Return to the learning map and choose the next available compiler lab.",
                    buttonTitle: "Continue learning",
                    systemImage: "arrow.right",
                    tint: CrabrixTheme.mint,
                    action: onContinueLearning
                )
            }

            Text("This proves compiler integration and configured sandbox bounds. Physical-device peak memory, thermal behavior, and hard-timeout termination remain separate gates.")
                .font(.caption)
                .foregroundStyle(CrabrixTheme.amber)
        }
    }
}

private struct NextWorkflowStep: View {
    let eyebrow: String
    let title: String
    let detail: String
    let buttonTitle: String
    let systemImage: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(eyebrow)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(tint)
            Text(title)
                .font(.headline)
            Text(detail)
                .font(.caption)
                .foregroundStyle(CrabrixTheme.muted)
            Button(action: action) {
                Label(buttonTitle, systemImage: systemImage)
                    .font(.subheadline.bold())
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(tint)
        }
        .padding(14)
        .background(tint.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(tint.opacity(0.28), lineWidth: 1)
        }
    }
}

private struct RuntimeRow: View {
    let title: String
    let detail: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.caption.weight(.semibold))
                Text(detail)
                    .font(.caption2.monospaced())
                    .foregroundStyle(CrabrixTheme.muted)
            }
        }
    }
}

private struct EvidenceRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(CrabrixTheme.muted)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
        }
        .font(.system(size: 11, design: .monospaced))
    }
}
