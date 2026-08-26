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
        self.codeContent = codeContent()
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(CrabrixTheme.border)
            statusStrip
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

            Text("FULL PANE")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(CrabrixTheme.muted)
        }
        .font(.system(size: 9, weight: .semibold, design: .monospaced))
        .padding(.horizontal, 9)
        .frame(height: 38)
    }

    private var statusStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                if activity != .idle {
                    ProgressView().controlSize(.small).tint(CrabrixTheme.blue)
                    Label(
                        activity == .checking ? "Type-check in progress" : "Compile and run in progress",
                        systemImage: "hammer.fill"
                    )
                    .foregroundStyle(CrabrixTheme.blue)
                    Text("You can keep editing")
                        .foregroundStyle(CrabrixTheme.muted)
                } else if let result {
                    Label(
                        result.succeeded ? "Last build passed" : "Last build failed",
                        systemImage: result.succeeded ? "checkmark.seal.fill" : "xmark.octagon.fill"
                    )
                    .foregroundStyle(result.succeeded ? CrabrixTheme.mint : CrabrixTheme.coral)
                    Text(result.phase.rawValue.uppercased())
                        .foregroundStyle(CrabrixTheme.muted)
                    Text(result.duration.crabrixDescription)
                        .foregroundStyle(CrabrixTheme.muted)
                } else {
                    Label("No build yet", systemImage: "circle.dashed")
                        .foregroundStyle(CrabrixTheme.muted)
                }
            }
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .padding(.horizontal, 12)
            .frame(height: 32)
        }
        .background(CrabrixTheme.panel.opacity(0.62))
    }

    @ViewBuilder
    private var content: some View {
        Group {
            switch selectedTab {
            case .code:
                codeContent
            case .problems:
                ProblemsDockContent(result: result)
            case .output:
                OutputDockContent(result: result)
            case .terminal:
                TerminalDockContent(
                    terminal: terminal,
                    project: project,
                    activity: activity,
                    canStartBuild: canStartBuild,
                    onCheck: onCheck,
                    onRun: onRun
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
    }
}

private struct ProblemsDockContent: View {
    let result: CompilationResult?

    var body: some View {
        ScrollView {
            if let diagnostics = result?.diagnostics, !diagnostics.isEmpty {
                LazyVStack(alignment: .leading, spacing: 7) {
                    ForEach(Array(diagnostics.enumerated()), id: \.offset) { index, diagnostic in
                        HStack(alignment: .top, spacing: 9) {
                            Image(systemName: "xmark.octagon.fill")
                                .foregroundStyle(CrabrixTheme.coral)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("\(diagnostic.code ?? "error") · \(diagnostic.message)")
                                    .foregroundStyle(CrabrixTheme.primary)
                                if let line = diagnostic.primarySpan?.lineStart {
                                    Text("line \(line)")
                                        .foregroundStyle(CrabrixTheme.muted)
                                }
                            }
                            Spacer()
                            Text("#\(index + 1)").foregroundStyle(CrabrixTheme.muted)
                        }
                        .padding(10)
                        .background(CrabrixTheme.panel, in: RoundedRectangle(cornerRadius: 9))
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
}

private struct OutputDockContent: View {
    let result: CompilationResult?

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
                    if !result.stdout.isEmpty {
                        OutputStreamBlock(
                            label: "STDOUT",
                            text: result.stdout,
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
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
            } else {
                ContentUnavailableView(
                    "Ready to run",
                    systemImage: "play.circle.fill",
                    description: Text("Press Run to compile and execute the current project locally.")
                )
                .foregroundStyle(CrabrixTheme.muted)
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
    let project: CrabrixProject
    let activity: CompilerViewModel.Activity
    let canStartBuild: Bool
    let onCheck: () -> Void
    let onRun: () -> Void

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
            HStack(spacing: 7) {
                Text("\(project.name) $ ")
                    .foregroundStyle(CrabrixTheme.mint)
                TextField("command", text: $terminal.command)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.send)
                    .onSubmit(submit)
                Button(action: submit) {
                    Image(systemName: "return").frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .foregroundStyle(CrabrixTheme.blue)
            }
            .font(.system(size: 11, design: .monospaced))
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(CrabrixTheme.panel)
        }
        .task { terminal.attach(to: project) }
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
            onCheck: onCheck,
            onRun: onRun
        )
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
