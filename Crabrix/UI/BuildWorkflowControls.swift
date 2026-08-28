import SwiftUI

/// The Check → Run workflow, with live build state and a Stop affordance.
///
/// This used to live only in the strip above the editor. It now belongs to the
/// Build inspector so there is exactly one place in the workspace that starts,
/// reports, and stops a build.
struct BuildWorkflowControls: View {
    let activity: CompilerViewModel.Activity
    let cargoStage: CargoPreparationStage
    let result: CompilationResult?
    let canRun: Bool
    let onCheck: () -> Void
    let onRun: () -> Void
    let onCancel: () -> Void

    private var checkPassed: Bool {
        result?.succeeded == true && result?.phase == .check
    }

    private var runPassed: Bool {
        result?.succeeded == true && result?.phase == .run
    }

    private var checkNeedsAttention: Bool {
        guard let result else { return false }
        return !result.succeeded || !result.diagnostics.isEmpty
    }

    /// While a build runs, the Cargo stage is the most useful subtitle: a
    /// dependency compile takes minutes, and silence reads as a hang.
    private var workingSubtitle: String {
        cargoStage.isWorking ? cargoStage.label : "Tap to stop"
    }

    private var connectorLabel: String {
        if runPassed { return "Done" }
        if checkPassed { return "Run next" }
        if checkNeedsAttention { return "Fix, then retry" }
        return "then"
    }

    var body: some View {
        VStack(spacing: 8) {
            ViewThatFits(in: .horizontal) {
                fullWorkflow.frame(minWidth: 430)
                compactWorkflow
            }
            if cargoStage.isWorking {
                BuildStageStrip(stage: cargoStage)
            }
        }
    }

    private var fullWorkflow: some View {
        HStack(spacing: 10) {
            WorkflowActionButton(
                step: 1,
                title: activity == .checking ? "Checking" : (checkPassed ? "Checked" : "Check code"),
                subtitle: activity == .checking
                    ? workingSubtitle
                    : (checkNeedsAttention ? "Fix errors and retry" : "Find errors, don't run"),
                systemImage: activity == .checking
                    ? "stop.fill"
                    : (checkPassed ? "checkmark.circle.fill" : "checkmark.shield.fill"),
                tint: checkPassed
                    ? CrabrixTheme.mint
                    : (checkNeedsAttention ? CrabrixTheme.coral : CrabrixTheme.blue),
                isWorking: activity == .checking,
                isEmphasized: !checkPassed && !runPassed,
                action: activity == .checking ? onCancel : onCheck
            )
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(activity == .running || (activity == .idle && !canRun))

            workflowConnector

            WorkflowActionButton(
                step: 2,
                title: activity == .running ? "Running" : (runPassed ? "Ran successfully" : "Run project"),
                subtitle: activity == .running
                    ? workingSubtitle
                    : (runPassed ? "Output is ready" : "Compile and show output"),
                systemImage: activity == .running
                    ? "stop.fill"
                    : (runPassed ? "checkmark.circle.fill" : "play.fill"),
                tint: runPassed ? CrabrixTheme.mint : CrabrixTheme.coral,
                isWorking: activity == .running,
                isEmphasized: checkPassed || !runPassed,
                action: activity == .running ? onCancel : onRun
            )
            .keyboardShortcut("r", modifiers: .command)
            .disabled(activity == .checking || (activity == .idle && !canRun))
        }
    }

    private var compactWorkflow: some View {
        HStack(spacing: 8) {
            CompactWorkflowButton(
                step: 1,
                title: activity == .checking ? "Stop" : (checkPassed ? "Checked" : "Check"),
                systemImage: activity == .checking
                    ? "stop.fill"
                    : (checkPassed ? "checkmark.circle.fill" : "checkmark.shield.fill"),
                tint: checkPassed ? CrabrixTheme.mint : CrabrixTheme.blue,
                isWorking: activity == .checking,
                action: activity == .checking ? onCancel : onCheck
            )
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(activity == .running || (activity == .idle && !canRun))

            Image(systemName: runPassed ? "checkmark" : "arrow.right")
                .font(.caption.bold())
                .foregroundStyle(runPassed || checkPassed ? CrabrixTheme.mint : CrabrixTheme.muted)

            CompactWorkflowButton(
                step: 2,
                title: activity == .running ? "Stop" : (runPassed ? "Done" : "Run"),
                systemImage: activity == .running
                    ? "stop.fill"
                    : (runPassed ? "checkmark.circle.fill" : "play.fill"),
                tint: runPassed ? CrabrixTheme.mint : CrabrixTheme.coral,
                isWorking: activity == .running,
                action: activity == .running ? onCancel : onRun
            )
            .keyboardShortcut("r", modifiers: .command)
            .disabled(activity == .checking || (activity == .idle && !canRun))
        }
    }

    private var workflowConnector: some View {
        VStack(spacing: 3) {
            Image(systemName: runPassed ? "checkmark" : "arrow.right")
                .font(.caption.bold())
            Text(connectorLabel)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
        }
        .foregroundStyle(runPassed || checkPassed ? CrabrixTheme.mint : CrabrixTheme.muted)
        .frame(width: 64)
        .accessibilityHidden(true)
    }
}

/// A one-line "what is the build doing right now" indicator.
struct BuildStageStrip: View {
    let stage: CargoPreparationStage

    var body: some View {
        HStack(spacing: 7) {
            ProgressView().controlSize(.mini).tint(CrabrixTheme.amber)
            Text(stage.label)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(CrabrixTheme.muted)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .transition(.opacity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(stage.label)
    }
}

struct WorkflowActionButton: View {
    let step: Int
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    let isWorking: Bool
    let isEmphasized: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                ZStack {
                    Circle()
                        .fill(tint.opacity(isEmphasized ? 0.24 : 0.14))
                    if isWorking {
                        ProgressView().tint(tint).controlSize(.small)
                    } else {
                        Text("\(step)")
                            .font(.caption.monospaced().bold())
                            .foregroundStyle(tint)
                    }
                }
                .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.bold())
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(CrabrixTheme.muted)
                        .lineLimit(1)
                }

                Spacer(minLength: 2)

                Image(systemName: systemImage)
                    .font(.subheadline.bold())
                    .foregroundStyle(tint)
            }
            .padding(.horizontal, 11)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(tint.opacity(isEmphasized ? 0.13 : 0.06))
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(tint.opacity(isEmphasized ? 0.52 : 0.18), lineWidth: isEmphasized ? 1.5 : 1)
            }
        }
        .buttonStyle(.plain)
        .opacity(isWorking ? 0.85 : 1)
    }
}

struct CompactWorkflowButton: View {
    let step: Int
    let title: String
    let systemImage: String
    let tint: Color
    let isWorking: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                ZStack {
                    Circle().fill(tint.opacity(0.16))
                    if isWorking {
                        ProgressView().tint(tint).controlSize(.mini)
                    } else {
                        Text("\(step)").font(.caption.monospaced().bold())
                    }
                }
                .frame(width: 22, height: 22)
                Image(systemName: systemImage)
                Text(title)
                    .lineLimit(1)
            }
            .font(.caption.bold())
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .padding(.horizontal, 8)
            .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 11))
            .overlay { RoundedRectangle(cornerRadius: 11).stroke(tint.opacity(0.45)) }
        }
        .buttonStyle(.plain)
    }
}
