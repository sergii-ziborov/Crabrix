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
    let lessonHint: CourseHintSnapshot?
    /// What the last successful run was scored on, so the reward is explained
    /// rather than appearing from nowhere.
    let contribution: CodeContribution?
    let onOpenDiagnostic: (RustDiagnostic) -> Void
    let diagnosticAdviceState: RustDiagnosticAdviceState
    let onOpenDiagnosticAdvisor: () -> Void
    let onContinueLearning: () -> Void
    let keyboardBridge: RustEditorKeyboardBridge
    let assistantUsesAppleIntelligence: Bool
    let onRequestCompletion: () -> Void
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
        lessonHint: CourseHintSnapshot?,
        contribution: CodeContribution?,
        onOpenDiagnostic: @escaping (RustDiagnostic) -> Void,
        diagnosticAdviceState: RustDiagnosticAdviceState,
        onOpenDiagnosticAdvisor: @escaping () -> Void,
        onContinueLearning: @escaping () -> Void,
        keyboardBridge: RustEditorKeyboardBridge,
        assistantUsesAppleIntelligence: Bool,
        onRequestCompletion: @escaping () -> Void,
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
        self.lessonHint = lessonHint
        self.contribution = contribution
        self.onOpenDiagnostic = onOpenDiagnostic
        self.diagnosticAdviceState = diagnosticAdviceState
        self.onOpenDiagnosticAdvisor = onOpenDiagnosticAdvisor
        self.onContinueLearning = onContinueLearning
        self.keyboardBridge = keyboardBridge
        self.assistantUsesAppleIntelligence = assistantUsesAppleIntelligence
        self.onRequestCompletion = onRequestCompletion
        self.codeContent = codeContent()
    }

    var body: some View {
        GeometryReader { geometry in
            let fold = AdaptiveFold.horizontal(in: geometry)
            VStack(spacing: 0) {
                if let fold,
                   fold.minY > 120,
                   fold.maxY < geometry.size.height - 100 {
                    // Terminal replaces Code on the upper display. Problems
                    // and Output use the lower display in place of keyboard.
                    Group {
                        if selectedTab == .terminal { terminalContent(autoFocus: true) }
                        else { codeContent }
                    }
                        // The hinge is still visible display area in laptop
                        // pose. Let the upper pane use it instead of leaving a
                        // dead strip between the editor and lower controls.
                        // The terminal's system keyboard includes a taller
                        // suggestion strip than the code editor keyboard.
                        // Reserve the tab row at the end of the upper pane so
                        // it remains visible directly above that keyboard.
                        .frame(height: fold.maxY - (selectedTab == .terminal ? 34 : 0))
                        .clipped()
                    header(tabletop: true)
                    if selectedTab == .code {
                        RustKeyboardShortcutRow(
                            bridge: keyboardBridge,
                            usesAppleIntelligence: assistantUsesAppleIntelligence,
                            onComplete: onRequestCompletion
                        )
                        .padding(.bottom, 6)
                        Spacer(minLength: 0)
                    } else if selectedTab == .terminal {
                        Spacer(minLength: 0)
                    } else {
                        content
                    }
                } else {
                    content
                    Divider().overlay(CrabrixTheme.border)
                    header(tabletop: false)
                }
            }
            .background(CrabrixTheme.editor)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .preference(
                key: TabletopTabsGlobalYPreferenceKey.self,
                value: fold.map { geometry.frame(in: .global).minY + $0.maxY - (selectedTab == .terminal ? 34 : 0) }
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func header(tabletop: Bool) -> some View {
        let activeTab = selectedTab
        let tabs = BuildDockTab.allCases
        return HStack(spacing: 4) {
            ForEach(tabs) { tab in
                Button {
                    if tab == .problems || tab == .output {
                        keyboardBridge.dismissKeyboard()
                    }
                    selectedTab = tab
                    if tab == .code {
                        keyboardBridge.focusEditor()
                    }
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
                    .frame(height: tabletop ? 30 : 34)
                    .foregroundStyle(activeTab == tab ? tab.tint : CrabrixTheme.muted)
                    .background(
                        activeTab == tab ? tab.tint.opacity(0.12) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 8)
                    )
                    .overlay(alignment: .top) {
                        if activeTab == tab {
                            Capsule().fill(tab.tint).frame(height: 2)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show \(tab.title.lowercased())")
                .accessibilityAddTraits(activeTab == tab ? .isSelected : [])
            }

            Spacer()
        }
        .font(.system(size: 9, weight: .semibold, design: .monospaced))
        .padding(.horizontal, 9)
        .frame(height: tabletop ? 34 : 38)
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
                outputContent
            case .terminal:
                terminalContent(autoFocus: true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
    }

    private func terminalContent(autoFocus: Bool) -> some View {
        TerminalDockContent(
            terminal: terminal,
            project: project,
            activity: activity,
            canStartBuild: canStartBuild,
            onCheck: onCheck,
            onRun: onRun,
            onReplaceFiles: onReplaceFiles,
            workspace: workspace,
            onFetch: onFetch,
            autoFocus: autoFocus
        )
    }

    private var outputContent: some View {
        OutputDockContent(
            result: result,
            activity: activity,
            canStartBuild: canStartBuild,
            canContinueLearning: canContinueLearning,
            lessonEvidenceMessage: lessonEvidenceMessage,
            lessonHint: lessonHint,
            contribution: contribution,
            onRun: onRun,
            onCancel: onCancel,
            onContinueLearning: onContinueLearning
        )
        .id(lessonHint?.sessionToken)
    }
}

private struct RustKeyboardShortcutRow: View {
    let bridge: RustEditorKeyboardBridge
    let usesAppleIntelligence: Bool
    let onComplete: () -> Void

    private let symbols = ["::", "->", "=>", "&", "&mut ", "|", "_", "!", "<", ">", "{", "}", "[", "]", "(", ")", ";"]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                Button(action: onComplete) {
                    Image(systemName: usesAppleIntelligence ? "sparkles" : "curlybraces")
                        .foregroundStyle(usesAppleIntelligence ? Color.blue : CrabrixTheme.primary)
                        .frame(width: 34, height: 24)
                }
                .accessibilityLabel(usesAppleIntelligence
                    ? "Complete Rust code with Apple Intelligence"
                    : "Complete Rust code offline")

                Divider().frame(height: 24)

                ForEach(symbols, id: \.self) { symbol in
                    Button { bridge.insertSymbol(symbol) } label: {
                        Text(symbol)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(CrabrixTheme.primary)
                            .padding(.horizontal, 11)
                            .frame(height: 24)
                            .background(CrabrixTheme.raised, in: RoundedRectangle(cornerRadius: 5))
                    }
                    .accessibilityLabel(symbol)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 7)
        }
        .frame(height: 28)
        .background(CrabrixTheme.panel)
    }
}

private struct ProblemsDockContent: View {
    let result: CompilationResult?
    let adviceState: RustDiagnosticAdviceState
    let onOpenDiagnostic: (RustDiagnostic) -> Void
    let onOpenDiagnosticAdvisor: () -> Void

    var body: some View {
        GeometryReader { available in
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
                .frame(maxWidth: .infinity)
                .frame(minHeight: available.size.height)
            }
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
    @State private var isHintExpanded = false
    let result: CompilationResult?
    let activity: CompilerViewModel.Activity
    let canStartBuild: Bool
    let canContinueLearning: Bool
    let lessonEvidenceMessage: String?
    let lessonHint: CourseHintSnapshot?
    let contribution: CodeContribution?
    let onRun: () -> Void
    let onCancel: () -> Void
    let onContinueLearning: () -> Void

    private var parsedOutput: ParsedRustCanvasOutput? {
        result.map { RustCanvasOutput.parse($0.stdout) }
    }

    var body: some View {
        GeometryReader { available in
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
                    hintPanel

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
                    hintPanel
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
                .frame(minHeight: available.size.height)
            }
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

    @ViewBuilder
    private var hintPanel: some View {
        if let lessonHint {
            DisclosureGroup(isExpanded: $isHintExpanded) {
                Text(lessonHint.text)
                    .font(.subheadline)
                    .foregroundStyle(CrabrixTheme.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
            } label: {
                Label("Hint", systemImage: "lightbulb.fill")
                    .font(.subheadline.bold())
                    .foregroundStyle(CrabrixTheme.amber)
            }
            .padding(12)
            .background(CrabrixTheme.panel, in: RoundedRectangle(cornerRadius: 11))
            .overlay {
                RoundedRectangle(cornerRadius: 11)
                    .stroke(CrabrixTheme.amber.opacity(0.28))
            }
        }
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
    let autoFocus: Bool

    private let quickCommands = ["help", "ls", "tree", "history", "cargo check", "cargo tree", "cargo metadata", "cargo run", "clear"]

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
                Text("\(project.name):\(terminal.promptDirectory) $")
                    .foregroundStyle(CrabrixTheme.mint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
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
                Button {
                    terminal.recallPrevious()
                    commandIsFocused = true
                } label: {
                    Image(systemName: "chevron.up")
                        .frame(width: 24, height: 34)
                }
                .disabled(!terminal.canRecallPrevious)
                .accessibilityLabel("Previous command")

                Button {
                    terminal.recallNext()
                    commandIsFocused = true
                } label: {
                    Image(systemName: "chevron.down")
                        .frame(width: 24, height: 34)
                }
                .disabled(!terminal.canRecallNext)
                .accessibilityLabel("Next command")
                Button {
                    commandIsFocused = false
                } label: {
                    Image(systemName: "keyboard.chevron.compact.down")
                        .frame(width: 24, height: 34)
                }
                .accessibilityLabel("Hide keyboard")
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
        .task {
            terminal.attach(to: project)
            guard autoFocus else { return }
            // The editor resigns when Terminal replaces it. Wait for that
            // transition before giving the prompt first responder status.
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            commandIsFocused = true
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
        commandIsFocused = true
    }

}

private struct TerminalHighlightedLine: View {
    let line: ProjectTerminalSession.Line

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Text(marker)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(accent)
                .frame(width: 13, alignment: .center)
            styledText
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(accent.opacity(line.kind == .info ? 0.035 : 0.075),
                    in: RoundedRectangle(cornerRadius: 8))
        .overlay(alignment: .leading) {
            Capsule()
                .fill(accent.opacity(0.75))
                .frame(width: 2)
                .padding(.vertical, 7)
        }
    }

    private var styledText: Text {
        if line.kind == .command, line.text.hasPrefix("$ ") {
            return command
        }
        if line.text.hasPrefix("[build]") {
            return Text("[build]").foregroundColor(CrabrixTheme.blue)
                + Text(String(line.text.dropFirst("[build]".count)))
                    .foregroundColor(color)
        }
        if line.text.hasPrefix("Crabrix project terminal") {
            return Text(line.text).foregroundColor(CrabrixTheme.mint)
        }
        if line.kind == .info {
            return formattedInformation(line.text)
        }
        return Text(line.text).foregroundColor(color)
    }

    private func formattedInformation(_ output: String) -> Text {
        let rows = output.split(separator: "\n", omittingEmptySubsequences: false)
        return rows.enumerated().reduce(Text("")) { rendered, row in
            rendered + (row.offset == 0 ? Text("") : Text("\n"))
                + formattedRow(String(row.element))
        }
    }

    private func formattedRow(_ row: String) -> Text {
        if row == "Project shell commands" {
            return Text(row).foregroundColor(CrabrixTheme.mint).bold()
        }
        if row.hasPrefix("  "),
           let separator = row.range(of: #"\s{2,}"#, options: .regularExpression,
                                     range: row.index(row.startIndex, offsetBy: 2)..<row.endIndex) {
            let command = String(row[..<separator.lowerBound])
            let description = String(row[separator.lowerBound...])
            return Text(command).foregroundColor(CrabrixTheme.blue)
                + Text(description).foregroundColor(CrabrixTheme.primary)
        }
        if let colon = row.firstIndex(of: ":"),
           row.distance(from: row.startIndex, to: colon) <= 16 {
            return Text(row[...colon]).foregroundColor(CrabrixTheme.blue)
                + Text(row[row.index(after: colon)...]).foregroundColor(CrabrixTheme.primary)
        }
        if row.hasPrefix("/workspace/") || row.hasPrefix("~/") {
            return Text(row).foregroundColor(CrabrixTheme.mint)
        }
        return Text(row).foregroundColor(CrabrixTheme.primary)
    }

    private var marker: String {
        switch line.kind {
        case .command: "›"
        case .info: "·"
        case .success: "✓"
        case .error: "!"
        }
    }

    private var accent: Color {
        switch line.kind {
        case .command: CrabrixTheme.amber
        case .info: CrabrixTheme.blue
        case .success: CrabrixTheme.mint
        case .error: CrabrixTheme.coral
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
        case .info: CrabrixTheme.primary
        case .success: CrabrixTheme.primary
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
