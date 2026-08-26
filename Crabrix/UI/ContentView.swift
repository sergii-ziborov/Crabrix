import SwiftUI

struct ContentView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @StateObject private var model = CompilerViewModel()

    var body: some View {
        ZStack {
            CrabrixTheme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                AppHeader(toolchain: model.toolchain)
                StageStrip(completed: model.completedStages)
                Divider().overlay(CrabrixTheme.border)

                if horizontalSizeClass == .regular {
                    HStack(spacing: 0) {
                        ProjectSidebar()
                            .frame(width: 210)
                        Divider().overlay(CrabrixTheme.border)
                        editorPane
                            .frame(minWidth: 420)
                        Divider().overlay(CrabrixTheme.border)
                        inspectorPane
                            .frame(minWidth: 350, idealWidth: 410, maxWidth: 470)
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            editorPane
                                .frame(minHeight: 590)
                            Divider().overlay(CrabrixTheme.border)
                            inspectorPane
                                .frame(minHeight: 500)
                        }
                    }
                }
            }
        }
        .foregroundStyle(.white)
        .sheet(isPresented: $model.isPracticePresented) {
            PracticeSheet(
                initialSource: RustSamples.practice,
                validate: model.validatePractice
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .task {
            if ProcessInfo.processInfo.arguments.contains("--crabrix-auto-check") {
                model.check()
            }
        }
    }

    private var editorPane: some View {
        VStack(spacing: 0) {
            EditorToolbar(
                activity: model.activity,
                canRun: model.toolchain.isReady && !model.isBusy,
                onLoadRunnable: model.loadRunnableSample,
                onLoadDiagnostic: model.loadBorrowDiagnosticSample,
                onCheck: model.check,
                onRun: model.run
            )

            ZStack(alignment: .topLeading) {
                TextEditor(text: $model.source)
                    .font(.system(size: 14, design: .monospaced))
                    .lineSpacing(6)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color(red: 0.052, green: 0.071, blue: 0.092))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .accessibilityLabel("Rust source editor")
                    .disabled(model.isBusy)

                if model.isBusy {
                    HStack(alignment: .top, spacing: 10) {
                        ProgressView()
                            .tint(CrabrixTheme.coral)
                            .padding(.top, 2)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(model.activity.label)
                                .font(.caption.monospaced())
                            Text(model.activity == .running
                                 ? "First local run takes about one minute. Keep Crabrix open."
                                 : "The first local check usually takes 15–20 seconds.")
                                .font(.caption2)
                                .foregroundStyle(CrabrixTheme.muted)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }

            ResultConsole(result: model.result)
                .frame(minHeight: 150, idealHeight: 190, maxHeight: 230)
        }
        .background(CrabrixTheme.background)
    }

    @ViewBuilder
    private var inspectorPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let result = model.result, result.succeeded {
                    SuccessInspector(result: result, practiceCompleted: model.practiceCompleted)
                } else if let diagnostic = model.primaryDiagnostic {
                    DiagnosticInspector(
                        diagnostic: diagnostic,
                        canRepair: BorrowRepair.apply(to: model.source, diagnostic: diagnostic) != nil,
                        practiceCompleted: model.practiceCompleted,
                        onRepair: model.applyRepair,
                        onPractice: model.presentPractice
                    )
                } else {
                    RuntimeInspector(toolchain: model.toolchain)
                }
            }
            .padding(22)
        }
        .background(
            LinearGradient(
                colors: [CrabrixTheme.panel, CrabrixTheme.background],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }
}

private struct AppHeader: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let toolchain: ToolchainStatus

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "ant.fill")
                .font(.title2)
                .foregroundStyle(CrabrixTheme.coral)
            Text("crabrix")
                .font(.system(size: 21, weight: .bold, design: .rounded))
            if horizontalSizeClass == .regular {
                Text("NATIVE PHASE 0")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(CrabrixTheme.muted)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 5)
                    .overlay(Capsule().stroke(CrabrixTheme.border))
            }

            Spacer()

            Label(horizontalSizeClass == .regular ? "NO WEBVIEW" : "NATIVE", systemImage: "swift")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(CrabrixTheme.mint)
            Label(toolchain.isReady ? (horizontalSizeClass == .regular ? "OFFLINE READY" : "OFFLINE") : "MISSING", systemImage: toolchain.isReady ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(toolchain.isReady ? CrabrixTheme.mint : CrabrixTheme.amber)
        }
        .padding(.horizontal, 18)
        .frame(height: 58)
        .background(CrabrixTheme.background.opacity(0.97))
    }
}

private struct StageStrip: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let completed: Set<CompilerViewModel.Stage>

    var body: some View {
        HStack(spacing: 8) {
            Text(horizontalSizeClass == .regular ? "DEVICE HYPOTHESIS" : "PHASE 0")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(CrabrixTheme.coral)
            if horizontalSizeClass == .regular {
                Text("bundled rustc → diagnostic → repair → local run")
                    .font(.caption)
                    .foregroundStyle(CrabrixTheme.muted)
            }
            Spacer()

            ForEach(CompilerViewModel.Stage.allCases) { stage in
                let done = completed.contains(stage)
                HStack(spacing: 5) {
                    Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    Text(stage.title)
                }
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(done ? CrabrixTheme.mint : CrabrixTheme.muted)
                .lineLimit(1)
            }
        }
        .padding(.horizontal, 18)
        .frame(minHeight: 52)
        .background(CrabrixTheme.panel)
    }
}

private struct ProjectSidebar: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PROJECT")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(CrabrixTheme.muted)
                .padding(.bottom, 6)
            Label("phase0-lab", systemImage: "chevron.down")
                .font(.subheadline.weight(.semibold))
            Label("src", systemImage: "chevron.down")
                .font(.caption)
                .padding(.leading, 12)
            Label("main.rs", systemImage: "doc.text.fill")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.white)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(CrabrixTheme.raised)
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .padding(.leading, 24)

            Spacer()

            VStack(alignment: .leading, spacing: 7) {
                Label("Physical device gate", systemImage: "iphone.gen3")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(CrabrixTheme.amber)
                Text("Simulator proves integration, not memory, thermal behavior, or airplane-mode operation.")
                    .font(.caption2)
                    .foregroundStyle(CrabrixTheme.muted)
            }
            .padding(11)
            .crabrixPanel(cornerRadius: 9)
        }
        .padding(14)
        .background(CrabrixTheme.panel)
    }
}

private struct EditorToolbar: View {
    let activity: CompilerViewModel.Activity
    let canRun: Bool
    let onLoadRunnable: () -> Void
    let onLoadDiagnostic: () -> Void
    let onCheck: () -> Void
    let onRun: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Label("main.rs", systemImage: "doc.plaintext")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.white)
            Spacer()
            Menu {
                Button(action: onLoadRunnable) {
                    Label("Runnable stdout demo", systemImage: "play.fill")
                }
                Button(action: onLoadDiagnostic) {
                    Label("Borrow error E0502", systemImage: "exclamationmark.triangle.fill")
                }
            } label: {
                Label("Samples", systemImage: "chevron.down")
            }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(CrabrixTheme.muted)
                .disabled(activity != .idle)
            Button(action: onCheck) {
                Label("Check", systemImage: "checkmark")
            }
            .buttonStyle(.bordered)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!canRun)
            Button(action: onRun) {
                Label("Run", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(CrabrixTheme.coral)
            .disabled(!canRun)
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .background(CrabrixTheme.panel)
    }
}

private struct ResultConsole: View {
    let result: CompilationResult?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("PROBLEMS")
                Text("\(result?.diagnostics.count ?? 0)")
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(CrabrixTheme.raised)
                    .clipShape(Capsule())
                Text("OUTPUT")
                    .padding(.leading, 10)
                Spacer()
                if let result {
                    Text(result.duration.crabrixDescription)
                }
            }
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundStyle(CrabrixTheme.muted)
            .padding(.horizontal, 14)
            .frame(height: 36)

            Divider().overlay(CrabrixTheme.border)

            ScrollView {
                if let result {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(
                            !result.succeeded && result.phase == .compile
                                ? "Build failed — the program was not executed."
                                : result.detail,
                            systemImage: result.succeeded ? "checkmark.circle.fill" : "xmark.octagon.fill"
                        )
                        .foregroundStyle(result.succeeded ? CrabrixTheme.mint : CrabrixTheme.coral)

                        if let diagnostic = result.diagnostics.first {
                            Text("\(diagnostic.code ?? "error") · \(diagnostic.message)")
                                .foregroundStyle(.white)
                        }
                        if !result.stdout.isEmpty {
                            Text(result.stdout)
                                .foregroundStyle(CrabrixTheme.mint)
                        }
                        if !result.stderr.isEmpty {
                            Text(result.stderr)
                                .foregroundStyle(CrabrixTheme.coral)
                        }
                    }
                    .font(.system(size: 11, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                } else {
                    ContentUnavailableView(
                        "Ready to run",
                        systemImage: "play.circle.fill",
                        description: Text("Press Run to compile and execute this valid starter program locally.")
                    )
                    .foregroundStyle(CrabrixTheme.muted)
                }
            }
        }
        .background(Color(red: 0.035, green: 0.049, blue: 0.064))
        .overlay(alignment: .top) { Divider().overlay(CrabrixTheme.border) }
    }
}
