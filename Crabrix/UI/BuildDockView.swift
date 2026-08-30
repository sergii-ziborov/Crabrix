import SwiftUI

enum BuildDockTab: String, CaseIterable, Identifiable {
    case code
    case problems
    case output
    case terminal

    var id: String { rawValue }

    var title: String { rawValue.uppercased() }

    var systemImage: String {
        switch self {
        case .code: "chevron.left.forwardslash.chevron.right"
        case .problems: "exclamationmark.triangle"
        case .output: "text.alignleft"
        case .terminal: "apple.terminal"
        }
    }

    var tint: Color {
        switch self {
        case .code: CrabrixTheme.blue
        case .problems: CrabrixTheme.coral
        case .output: CrabrixTheme.blue
        case .terminal: CrabrixTheme.mint
        }
    }
}

struct BuildDockView<CodeContent: View>: View {
    @Binding var selectedTab: BuildDockTab
    @ObservedObject var terminal: ProjectTerminalSession

    let project: CrabrixProject
    let result: CompilationResult?
    let activity: CompilerViewModel.Activity
    let canStartBuild: Bool
    let onCheck: () -> Void
    let onRun: () -> Void
    let onReplaceFiles: ([String: String], String?) -> Bool
    let workspace: CargoWorkspaceSnapshot
    let onFetch: () -> Void
    let onCancel: () -> Void
    let canContinueLearning: Bool
    let lessonEvidenceMessage: String?
    /// What the last successful run was scored on, so the reward is explained
    /// rather than appearing from nowhere.
    let contribution: CodeContribution?
    let onOpenDiagnostic: (RustDiagnostic) -> Void
    let diagnosticAdviceState: RustDiagnosticAdviceState
    let onOpenDiagnosticAdvisor: () -> Void
    let onContinueLearning: () -> Void
    let codeContent: CodeContent

    init(
        selectedTab: Binding<BuildDockTab>,
        terminal: ProjectTerminalSession,
        project: CrabrixProject,
        result: CompilationResult?,
        activity: CompilerViewModel.Activity,
        canStartBuild: Bool,
        onCheck: @escaping () -> Void,
        onRun: @escaping () -> Void,
        onReplaceFiles: @escaping ([String: String], String?) -> Bool,
        workspace: CargoWorkspaceSnapshot,
        onFetch: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        canContinueLearning: Bool,
        lessonEvidenceMessage: String?,
        contribution: CodeContribution?,
        onOpenDiagnostic: @escaping (RustDiagnostic) -> Void,
        diagnosticAdviceState: RustDiagnosticAdviceState,
        onOpenDiagnosticAdvisor: @escaping () -> Void,
        onContinueLearning: @escaping () -> Void,
        @ViewBuilder codeContent: () -> CodeContent
    ) {
        _selectedTab = selectedTab
        self.terminal = terminal
        self.project = project
        self.result = result
        self.activity = activity
        self.canStartBuild = canStartBuild
        self.onCheck = onCheck
        self.onRun = onRun
        self.onReplaceFiles = onReplaceFiles
        self.workspace = workspace
        self.onFetch = onFetch
        self.onCancel = onCancel
        self.canContinueLearning = canContinueLearning
        self.lessonEvidenceMessage = lessonEvidenceMessage
        self.contribution = contribution
        self.onOpenDiagnostic = onOpenDiagnostic
        self.diagnosticAdviceState = diagnosticAdviceState
        self.onOpenDiagnosticAdvisor = onOpenDiagnosticAdvisor
        self.onContinueLearning = onContinueLearning
        self.codeContent = codeContent()
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(CrabrixTheme.border)
            content
        }
        .background(CrabrixTheme.editor)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        HStack(spacing: 4) {
            ForEach(BuildDockTab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: tab.systemImage)
                        Text(tab.title)
                        if tab == .problems {
                            Text("\(result?.diagnostics.count ?? 0)")
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(CrabrixTheme.raised, in: Capsule())
                        }
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 34)
                    .foregroundStyle(selectedTab == tab ? tab.tint : CrabrixTheme.muted)
                    .background(
                        selectedTab == tab ? tab.tint.opacity(0.12) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 8)
                    )
                    .overlay(alignment: .bottom) {
                        if selectedTab == tab {
                            Capsule().fill(tab.tint).frame(height: 2)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show \(tab.title.lowercased())")
                .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
            }

            Spacer()
        }
        .font(.system(size: 9, weight: .semibold, design: .monospaced))
        .padding(.horizontal, 9)
        .frame(height: 38)
    }

    @ViewBuilder
    private var content: some View {
        Group {
            switch selectedTab {
            case .code:
                codeContent
            case .problems:
                ProblemsDockContent(
                    result: result,
                    adviceState: diagnosticAdviceState,
                    onOpenDiagnostic: onOpenDiagnostic,
                    onOpenDiagnosticAdvisor: onOpenDiagnosticAdvisor
                )
            case .output:
                OutputDockContent(
                    result: result,
                    activity: activity,
                    canStartBuild: canStartBuild,
                    canContinueLearning: canContinueLearning,
                    lessonEvidenceMessage: lessonEvidenceMessage,
                    contribution: contribution,
                    onRun: onRun,
                    onCancel: onCancel,
                    onContinueLearning: onContinueLearning
                )
            case .terminal:
                TerminalDockContent(
                    terminal: terminal,
                    project: project,
                    activity: activity,
                    canStartBuild: canStartBuild,
                    onCheck: onCheck,
                    onRun: onRun,
                    onReplaceFiles: onReplaceFiles,
                    workspace: workspace,
                    onFetch: onFetch
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
    }
}

private struct ProblemsDockContent: View {
    let result: CompilationResult?
    let adviceState: RustDiagnosticAdviceState
    let onOpenDiagnostic: (RustDiagnostic) -> Void
    let onOpenDiagnosticAdvisor: () -> Void

    var body: some View {
        ScrollView {
            if let diagnostics = result?.diagnostics, !diagnostics.isEmpty {
                LazyVStack(alignment: .leading, spacing: 7) {
                    if diagnostics.contains(where: { $0.level == "error" }) {
                        Button(action: onOpenDiagnosticAdvisor) {
                            HStack(spacing: 10) {
                                if adviceState.isWorking {
                                    ProgressView()
                                        .controlSize(.small)
                                        .tint(CrabrixTheme.blue)
                                } else {
                                    Image(systemName: "apple.intelligence")
                                        .foregroundStyle(CrabrixTheme.blue)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(advisorButtonTitle)
                                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                                        .foregroundStyle(CrabrixTheme.primary)
                                    Text(advisorButtonDetail)
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundStyle(CrabrixTheme.muted)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption2.bold())
                                    .foregroundStyle(CrabrixTheme.blue)
                            }
                            .padding(11)
                            .background(CrabrixTheme.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 9))
                            .overlay {
                                RoundedRectangle(cornerRadius: 9)
                                    .stroke(CrabrixTheme.blue.opacity(0.28))
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens Apple Intelligence analysis for the compiler error")
                    }

                    ForEach(Array(diagnostics.enumerated()), id: \.offset) { index, diagnostic in
                        Button {
                            onOpenDiagnostic(diagnostic)
                        } label: {
                            HStack(alignment: .top, spacing: 9) {
                                Image(systemName: "xmark.octagon.fill")
                                    .foregroundStyle(CrabrixTheme.coral)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("\(diagnostic.code ?? "error") · \(diagnostic.message)")
                                        .foregroundStyle(CrabrixTheme.primary)
                                    if let span = diagnostic.primarySpan {
                                        Text("\(span.fileName):\(span.lineStart):\(span.columnStart)")
                                            .foregroundStyle(CrabrixTheme.blue)
                                    }
                                }
                                Spacer()
                                Text("#\(index + 1)").foregroundStyle(CrabrixTheme.muted)
                                if diagnostic.primarySpan != nil {
                                    Image(systemName: "arrow.up.forward.square")
                                        .foregroundStyle(CrabrixTheme.blue)
                                }
                            }
                            .padding(10)
                            .background(CrabrixTheme.panel, in: RoundedRectangle(cornerRadius: 9))
                        }
                        .buttonStyle(.plain)
                        .disabled(diagnostic.primarySpan == nil)
                        .accessibilityHint(
                            diagnostic.primarySpan == nil
                                ? "No source location is available"
                                : "Open and highlight this source line"
                        )
                    }
                }
                .padding(12)
            } else {
                ContentUnavailableView(
                    "No problems",
                    systemImage: "checkmark.circle.fill",
                    description: Text("Compiler diagnostics for the current snapshot appear here.")
                )
                .foregroundStyle(CrabrixTheme.muted)
            }
        }
        .font(.system(size: 11, design: .monospaced))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var advisorButtonTitle: String {
        switch adviceState {
        case .idle:
            "Fix with Apple Intelligence"
        case .generating:
            "Apple Intelligence is analyzing…"
        case .verifying:
            "Verifying the suggested fix…"
        case let .ready(advice):
            advice.canApply ? "Review verified Apple Intelligence fix" : "Review Apple Intelligence advice"
        case .unavailable:
            "Apple Intelligence is unavailable"
        }
    }

    private var advisorButtonDetail: String {
        switch adviceState {
        case .idle:
            "Tap to analyze this rustc error on device"
        case .generating:
            "Generating a minimal source edit"
        case .verifying:
            "Checking the edit with the bundled rustc"
        case let .ready(advice):
            advice.canApply ? "The proposed edit passed rustc" : "Open the diagnostic advisor"
        case let .unavailable(message):
            message
        }
    }
}

private struct OutputDockContent: View {
    let result: CompilationResult?
    let activity: CompilerViewModel.Activity
    let canStartBuild: Bool
    let canContinueLearning: Bool
    let lessonEvidenceMessage: String?
    let contribution: CodeContribution?
    let onRun: () -> Void
    let onCancel: () -> Void
    let onContinueLearning: () -> Void

    private var parsedOutput: ParsedRustCanvasOutput? {
        result.map { RustCanvasOutput.parse($0.stdout) }
    }

    var body: some View {
        ScrollView {
            if let result {
                VStack(alignment: .leading, spacing: 12) {
                    Label(
                        !result.succeeded && result.phase == .compile
                            ? "Build failed — the program was not executed."
                            : result.detail,
                        systemImage: result.succeeded ? "checkmark.circle.fill" : "xmark.octagon.fill"
                    )
                    .foregroundStyle(result.succeeded ? CrabrixTheme.mint : CrabrixTheme.coral)
                    if let diagnostic = result.diagnostics.first {
                        OutputStreamBlock(
                            label: diagnostic.code ?? "ERROR",
                            text: diagnostic.message,
                            tint: CrabrixTheme.coral,
                            systemImage: "exclamationmark.triangle.fill"
                        )
                    }
                    if let frame = parsedOutput?.frame {
                        RustCanvasPreview(frame: frame)
                    }
                    if let plainText = parsedOutput?.plainText,
                       !plainText.isEmpty {
                        OutputStreamBlock(
                            label: "STDOUT",
                            text: plainText,
                            tint: CrabrixTheme.mint,
                            systemImage: "arrow.right.circle.fill"
                        )
                    }
                    if !result.stderr.isEmpty {
                        OutputStreamBlock(
                            label: "STDERR",
                            text: result.stderr,
                            tint: CrabrixTheme.coral,
                            systemImage: "exclamationmark.octagon.fill"
                        )
                    }
                    if result.phase == .run, let lessonEvidenceMessage {
                        Label(
                            lessonEvidenceMessage,
                            systemImage: canContinueLearning
                                ? "checkmark.seal.fill"
                                : "exclamationmark.triangle.fill"
                        )
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(
                            canContinueLearning ? CrabrixTheme.mint : CrabrixTheme.amber
                        )
                    }
                    runButton

                    if result.succeeded, result.phase == .run, let contribution {
                        ContributionSummaryRow(contribution: contribution)
                    }

                    if result.succeeded, result.phase == .run, canContinueLearning {
                        Button(action: onContinueLearning) {
                            HStack(spacing: 10) {
                                Image(systemName: "graduationcap.fill")
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Continue learning")
                                        .font(.subheadline.bold())
                                    Text("Return to your Rust course and continue from the next lesson.")
                                        .font(.caption)
                                        .foregroundStyle(CrabrixTheme.muted)
                                }
                                Spacer()
                                Image(systemName: "arrow.right")
                            }
                            .foregroundStyle(CrabrixTheme.mint)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                CrabrixTheme.mint.opacity(0.09),
                                in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .stroke(CrabrixTheme.mint.opacity(0.34))
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 42))
                        .foregroundStyle(CrabrixTheme.coral.opacity(0.7))
                    Text("Ready to run")
                        .font(.headline)
                        .foregroundStyle(CrabrixTheme.primary)
                    Text("Compile the current project and execute it locally.")
                        .font(.caption)
                        .foregroundStyle(CrabrixTheme.muted)
                        .multilineTextAlignment(.center)
                    runButton
                        .padding(.top, 4)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
                .padding(.vertical, 40)
            }
        }
        .font(.system(size: 11, design: .monospaced))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [CrabrixTheme.blue.opacity(0.045), .clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    /// Output is where you look for a result, so it can also produce one.
    private var runButton: some View {
        Button(action: activity == .running ? onCancel : onRun) {
            Label(
                activity == .running ? "Stop" : (result == nil ? "Run project" : "Run again"),
                systemImage: activity == .running ? "stop.fill" : "play.fill"
            )
            .font(.subheadline.bold())
            .frame(maxWidth: .infinity, minHeight: 40)
        }
        .buttonStyle(.borderedProminent)
        .tint(activity == .running ? CrabrixTheme.amber : CrabrixTheme.coral)
        .disabled(activity == .checking || (activity == .idle && !canStartBuild))
        .frame(maxWidth: 320)
    }
}

private struct RustCanvasPreview: View {
    let frame: RustCanvasFrame

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("VISUAL OUTPUT", systemImage: "paintpalette.fill")
                    .font(.system(
                        size: 9,
                        weight: .bold,
                        design: .monospaced
                    ))
                    .foregroundStyle(CrabrixTheme.blue)
                Spacer()
                Text("\(frame.width) × \(frame.height)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(CrabrixTheme.muted)
            }

            Text(frame.title)
                .font(.headline)

            Canvas { context, size in
                let cellWidth = size.width / CGFloat(frame.width)
                let cellHeight = size.height / CGFloat(frame.height)
                for row in 0..<frame.height {
                    for column in 0..<frame.width {
                        let pixel = frame.pixels[
                            row * frame.width + column
                        ]
                        let rect = CGRect(
                            x: CGFloat(column) * cellWidth,
                            y: CGFloat(row) * cellHeight,
                            width: cellWidth + 0.5,
                            height: cellHeight + 0.5
                        )
                        context.fill(
                            Path(rect),
                            with: .color(
                                Color(
                                    crabrixHex: frame.palette[pixel]
                                )
                            )
                        )
                    }
                }
            }
            .aspectRatio(
                CGFloat(frame.width) / CGFloat(frame.height),
                contentMode: .fit
            )
            .frame(maxWidth: 460, maxHeight: 420)
            .clipShape(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(CrabrixTheme.border)
            }
            .accessibilityLabel(
                "\(frame.title), \(frame.width) by \(frame.height) pixel canvas"
            )
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            CrabrixTheme.blue.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 12)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(CrabrixTheme.blue.opacity(0.3))
        }
    }
}

private extension Color {
    init(crabrixHex value: String) {
        let hex = String(value.dropFirst())
        let number = UInt64(hex, radix: 16) ?? 0
        self.init(
            .sRGB,
            red: Double((number >> 16) & 0xFF) / 255,
            green: Double((number >> 8) & 0xFF) / 255,
            blue: Double(number & 0xFF) / 255,
            opacity: 1
        )
    }
}

private struct OutputStreamBlock: View {
    let label: String
    let text: String
    let tint: Color
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(label, systemImage: systemImage)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(tint)
            Text(text)
                .foregroundStyle(CrabrixTheme.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(11)
        .background(tint.opacity(0.075), in: RoundedRectangle(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).stroke(tint.opacity(0.25)) }
    }
}

private struct TerminalDockContent: View {
    @ObservedObject var terminal: ProjectTerminalSession
    @FocusState private var commandIsFocused: Bool
    let project: CrabrixProject
    let activity: CompilerViewModel.Activity
    let canStartBuild: Bool
    let onCheck: () -> Void
    let onRun: () -> Void
    let onReplaceFiles: ([String: String], String?) -> Bool
    let workspace: CargoWorkspaceSnapshot
    let onFetch: () -> Void

    private let quickCommands = ["help", "ls", "cargo check", "cargo tree", "cargo run", "clear"]

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 5) {
                        ForEach(terminal.lines) { line in
                            TerminalHighlightedLine(line: line)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                                .id(line.id)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                }
                .onChange(of: terminal.lines.count) { _, _ in
                    if let last = terminal.lines.last {
                        withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            Divider().overlay(CrabrixTheme.border)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(quickCommands, id: \.self) { command in
                        Button {
                            run(command)
                        } label: {
                            Text(command)
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundStyle(command == "clear" ? CrabrixTheme.coral : CrabrixTheme.blue)
                                .padding(.horizontal, 10)
                                .frame(height: 30)
                                .background(
                                    (command == "clear" ? CrabrixTheme.coral : CrabrixTheme.blue).opacity(0.09),
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
            }
            .background(CrabrixTheme.panel.opacity(0.72))

            Divider().overlay(CrabrixTheme.border)

            HStack(spacing: 7) {
                Text("\(project.name) $ ")
                    .foregroundStyle(CrabrixTheme.mint)
                TextField("command", text: $terminal.command)
                    .textFieldStyle(.plain)
                    .focused($commandIsFocused)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.send)
                    .onSubmit(submit)
                    .padding(.horizontal, 10)
                    .frame(height: 34)
                    .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 8))
                Button(action: submit) {
                    Label("Run", systemImage: "return")
                        .font(.caption.bold())
                        .padding(.horizontal, 10)
                        .frame(height: 34)
                        .background(CrabrixTheme.blue.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .foregroundStyle(CrabrixTheme.blue)
            }
            .font(.system(size: 11, design: .monospaced))
            .padding(.horizontal, 12)
            .frame(height: 50)
            .background(CrabrixTheme.panel)
        }
        .task { terminal.attach(to: project) }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button { commandIsFocused = false } label: {
                    Image(systemName: "keyboard.chevron.compact.down")
                }
                .accessibilityLabel("Hide keyboard")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0.24), CrabrixTheme.mint.opacity(0.025)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private func submit() {
        terminal.submit(
            project: project,
            isBusy: activity != .idle || !canStartBuild,
            workspace: workspace,
            onCheck: onCheck,
            onRun: onRun,
            onFetch: onFetch,
            onReplaceFiles: onReplaceFiles
        )
    }

    private func run(_ command: String) {
        terminal.command = command
        submit()
    }

}

private struct TerminalHighlightedLine: View {
    let line: ProjectTerminalSession.Line

    var body: some View {
        if line.kind == .command, line.text.hasPrefix("$ ") {
            command
        } else if line.text.hasPrefix("[build]") {
            Text("[build]")
                .foregroundColor(CrabrixTheme.blue)
            + Text(String(line.text.dropFirst("[build]".count)))
                .foregroundColor(color)
        } else {
            Text(line.text).foregroundStyle(color)
        }
    }

    private var command: Text {
        let raw = String(line.text.dropFirst(2))
        let parts = raw.split(maxSplits: 1, whereSeparator: \.isWhitespace)
        let executable = parts.first.map(String.init) ?? raw
        let arguments = parts.count > 1 ? " " + parts[1] : ""
        return Text("$ ").foregroundColor(CrabrixTheme.mint)
            + Text(executable).foregroundColor(CrabrixTheme.amber)
            + Text(arguments).foregroundColor(CrabrixTheme.primary)
    }

    private var color: Color {
        switch line.kind {
        case .command: CrabrixTheme.primary
        case .info: CrabrixTheme.muted
        case .success: CrabrixTheme.mint
        case .error: CrabrixTheme.coral
        }
    }
}

/// Explains what the last run earned, and why.
///
/// Rating is paid on the diff now, so an unchanged rerun says so plainly
/// instead of looking like the score is broken.
private struct ContributionSummaryRow: View {
    let contribution: CodeContribution

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: contribution.changedLines > 0 ? "chart.bar.doc.horizontal.fill" : "arrow.clockwise")
                .foregroundStyle(CrabrixTheme.amber)
            VStack(alignment: .leading, spacing: 2) {
                Text("+\(contribution.points) rating")
                    .font(.subheadline.bold())
                    .monospacedDigit()
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(CrabrixTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if contribution.changedLines > 0 {
                Text(contribution.summary)
                    .font(.caption.monospaced().bold())
                    .foregroundStyle(CrabrixTheme.mint)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CrabrixTheme.amber.opacity(0.08), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(CrabrixTheme.amber.opacity(0.3))
        }
    }

    private var caption: String {
        if contribution.isFirstRun {
            "First run of this project — scored on everything in it."
        } else if contribution.changedLines > 0 {
            "Scored on the \(contribution.changedLines) lines you changed since the last run."
        } else {
            "Nothing changed since the last run, so this one is worth very little."
        }
    }
}
