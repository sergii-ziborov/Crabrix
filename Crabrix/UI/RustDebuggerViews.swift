import SwiftUI

struct RustDebuggerPresentation: ViewModifier {
    @ObservedObject var model: CompilerViewModel
    @Binding var presented: Bool
    @Binding var selectedTab: BuildDockTab
    @Binding var navigationTarget: EditorNavigationTarget?
    let keyboard: RustEditorKeyboardBridge
    func body(content: Content) -> some View {
        content.onChange(of: model.debugPause) { _, paused in
            guard let paused else { return }
            keyboard.dismissKeyboard(); model.selectFile(paused.site.file)
            navigationTarget = EditorNavigationTarget(filePath: paused.site.file, line: paused.site.line, column: paused.site.column)
            selectedTab = .code
        }.sheet(isPresented: $presented) {
            RustDebuggerInspector(model: model).presentationDetents([.large]).presentationDragIndicator(.visible)
        }
    }
}

struct RustDebuggerBar: View {
    @ObservedObject var model: CompilerViewModel
    var onInspect: (() -> Void)? = nil
    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                if model.debugPause != nil {
                    action("Continue", "play.fill") { model.resumeDebug(.continue) }
                    action("Step into", "arrow.down.to.line") { model.resumeDebug(.into) }
                    action("Step over", "arrow.turn.up.right") { model.resumeDebug(.over) }
                    action("Step out", "arrow.up.to.line") { model.resumeDebug(.out) }
                } else {
                    action("Pause debugger", "pause.fill", model.pauseDebug)
                    Text("Debug build · local execution").font(.caption).foregroundStyle(CrabrixTheme.muted)
                }
                Spacer(minLength: 0)
                if let onInspect { action("Inspect debugger state", "list.bullet.rectangle", onInspect) }
            }
            if let paused = model.debugPause {
                Text("\(paused.reason == "breakpoint" ? "Breakpoint" : "Paused") · \(paused.site.file):\(paused.site.line) · \(paused.site.function)")
                    .font(.caption.monospaced()).foregroundStyle(CrabrixTheme.lessonCode)
                    .lineLimit(1).truncationMode(.middle).frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("debugger-location")
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(CrabrixTheme.panel).overlay(alignment: .top) { Rectangle().fill(CrabrixTheme.border).frame(height: 1) }
    }
    private func action(_ label: String, _ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon).frame(width: 36, height: 32).contentShape(Rectangle()) }
            .buttonStyle(.plain).foregroundStyle(CrabrixTheme.lessonCode).accessibilityLabel(label)
    }
}

struct RustDebuggerInspector: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: CompilerViewModel
    @State private var selectedFrame = 0
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(model.debugPause.map { "Paused · \($0.site.file):\($0.site.line)" } ?? (model.debugActive ? "Running locally" : "Debug session finished"))
                        .font(.headline).accessibilityIdentifier("debugger-status")
                    if model.debugActive { RustDebuggerBar(model: model) }
                    let frames = Array((model.debugPause?.frames ?? []).reversed())
                    if !frames.isEmpty {
                        Text("Call stack").font(.headline)
                        ForEach(frames.indices, id: \.self) { index in
                            let frame = frames[index]
                            Button { selectedFrame = index } label: {
                                HStack { Text(frame.site.function).font(.body.monospaced()); Spacer(); Text("\(frame.site.file):\(frame.site.line)").font(.caption.monospaced()).foregroundStyle(CrabrixTheme.muted) }
                                    .padding(10).background(selectedFrame == index ? CrabrixTheme.blue.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 8))
                            }.buttonStyle(.plain)
                        }
                        Text("Locals · primitive values").font(.headline)
                        let variables = frames[min(selectedFrame, frames.count - 1)].locals
                        if variables.isEmpty { Text("No inspectable primitive locals at this statement.").foregroundStyle(CrabrixTheme.muted) }
                        ForEach(variables.indices, id: \.self) { index in
                            let value = variables[index]
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 3) { Text(value.name).font(.body.monospaced()); Text(value.type).font(.caption.monospaced()).foregroundStyle(CrabrixTheme.muted) }
                                Spacer(); Text(value.value).font(.body.monospaced()).textSelection(.enabled)
                            }.accessibilityElement(children: .combine)
                        }
                    }
                    Text("Breakpoints").font(.headline)
                    Text("Tap a line number in the Rust editor to toggle a breakpoint. Debug compiles a separate source snapshot; original files and normal Run stay unchanged.").font(.caption).foregroundStyle(CrabrixTheme.muted)
                    ForEach(model.debugBreakpoints.sorted { ($0.file, $0.line) < ($1.file, $1.line) }, id: \.self) { breakpoint in
                        Button { model.toggleDebugBreakpoint(file: breakpoint.file, line: breakpoint.line) } label: { HStack { Image(systemName: "circle.fill").foregroundStyle(CrabrixTheme.coral); Text("\(breakpoint.file):\(breakpoint.line)").font(.callout.monospaced()); Spacer(); Image(systemName: "xmark") } }.buttonStyle(.plain)
                    }
                    Text("Safe primitive locals are inspected. Aggregates and borrowed/captured locals are not decoded. Macro expansions, const and async bodies are not stepped internally. Execution is local; paused time is excluded from the running-time budget.").font(.caption).foregroundStyle(CrabrixTheme.muted)
                }.padding(20).frame(maxWidth: 680).frame(maxWidth: .infinity, alignment: .center)
            }
            .background(CrabrixTheme.background).foregroundStyle(CrabrixTheme.primary)
            .navigationTitle("Debugger").navigationBarTitleDisplayMode(.inline)
            .toolbar { CrabrixModalCloseAction(label: "Close debugger state") { dismiss() } }
            .toolbar { if model.debugActive { ToolbarItem(placement: .topBarLeading) { Button("Stop", role: .destructive) { model.cancelBuild() }.accessibilityLabel("Stop debugging") } } }
            .onChange(of: model.debugPause) { _, _ in selectedFrame = 0 }
        }
    }
}
