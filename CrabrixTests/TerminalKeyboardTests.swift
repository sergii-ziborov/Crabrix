import SwiftUI
import UIKit
import XCTest
@testable import Crabrix

@MainActor
final class TerminalKeyboardTests: XCTestCase {
    @MainActor private final class WorkspaceState: ObservableObject {
        @Published var tab: BuildDockTab
        @Published var text = "fn main() { println!(\"crab\"); }"
        @Published var cursor = 0
        let editorKeyboard = RustEditorKeyboardBridge()

        init(tab: BuildDockTab) { self.tab = tab }
    }

    private struct Host: View {
        @ObservedObject var state: WorkspaceState
        @StateObject private var terminal = ProjectTerminalSession()

        var body: some View {
            GeometryReader { _ in
            TabView {
                GeometryReader { _ in
                VStack(spacing: 0) {
                    Text("Project toolbar").frame(height: 58)
                    BuildDockView(
                        selectedTab: $state.tab, terminal: terminal,
                        project: CrabrixProject(name: "keyboard-lab", files: ["main.rs": "fn main() {}"], entryFile: "main.rs", provenance: nil),
                        result: nil, activity: .idle, canStartBuild: true,
                        onCheck: {}, onRun: {}, onReplaceFiles: { _, _ in true },
                        workspace: .empty, onFetch: {}, onCancel: {},
                        canContinueLearning: false, lessonEvidenceMessage: nil,
                        lessonHint: nil, contribution: nil, onOpenDiagnostic: { _ in },
                        diagnosticAdviceState: .idle, onOpenDiagnosticAdvisor: {},
                        onContinueLearning: {}, keyboardBridge: state.editorKeyboard,
                        duoHingePresent: false, hingePartiallyOpen: false,
                        hingeGlobalY: 0, assistantUsesAppleIntelligence: false,
                        onRequestCompletion: {}
                    ) {
                        SyntaxCodeEditor(
                            text: $state.text, cursorOffset: $state.cursor,
                            filePath: "main.rs", isEditable: true,
                            navigationTarget: nil,
                            keyboardBridge: state.editorKeyboard,
                            onRequestCompletion: {}
                        )
                    }
                }
                }
                .tabItem { Label("Projects", systemImage: "folder.fill") }
                Color.clear.tabItem { Label("Learn", systemImage: "graduationcap") }
            }
            }
        }
    }

    private final class KeyboardFrames: NSObject {
        var endFrame = CGRect.null

        override init() {
            super.init()
            NotificationCenter.default.addObserver(
                self, selector: #selector(changed(_:)),
                name: UIResponder.keyboardWillChangeFrameNotification, object: nil
            )
        }

        @objc private func changed(_ notification: Notification) {
            if let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                endFrame = frame
            }
        }

        deinit { NotificationCenter.default.removeObserver(self) }
    }

    func testCodeToTerminalKeepsDockTabsAboveKeyboardWithOrWithoutEditorKeyboard() async throws {
        let keyboardFrames = KeyboardFrames()
        try await withWorkspace(initialTab: .code) { view, state in
            for editorKeyboardOpen in [false, true, true] {
                state.tab = .code
                try await self.waitUntil { self.find(CodeEditorCanvas.self, in: view)?.window != nil }
                let editor = try XCTUnwrap(self.find(CodeEditorCanvas.self, in: view)).textView
                editor.becomeFirstResponder()
                let window = try XCTUnwrap(editor.window)
                try await self.waitUntil {
                    editor.isFirstResponder && keyboardFrames.endFrame.minY < window.bounds.maxY - 150
                }
                try await Task.sleep(for: .milliseconds(400))
                XCTAssertEqual(editor.inputAccessoryView?.bounds.height ?? 0, 46, accuracy: 0.5)
                if !editorKeyboardOpen {
                    editor.resignFirstResponder()
                    try await self.waitUntil { !editor.isFirstResponder }
                    try await Task.sleep(for: .milliseconds(400))
                    // Hiding Code's keyboard must not remove its helpers when
                    // the same editor receives focus again.
                    editor.becomeFirstResponder()
                    try await self.waitUntil { editor.isFirstResponder }
                    try await Task.sleep(for: .milliseconds(300))
                    XCTAssertEqual(editor.inputAccessoryView?.bounds.height ?? 0, 46, accuracy: 0.5)
                    editor.resignFirstResponder()
                    try await Task.sleep(for: .milliseconds(400))
                }

                // This is the same selection change as tapping Terminal. Its
                // real prompt requests focus while Code is being unmounted.
                BuildDockTab.terminal.select(
                    Binding(get: { state.tab }, set: { state.tab = $0 }),
                    editorKeyboard: state.editorKeyboard
                )
                try await self.waitUntil { self.find(TerminalTextField.self, in: view)?.isFirstResponder == true }
                let field = try XCTUnwrap(self.find(TerminalTextField.self, in: view))
                try await Task.sleep(for: .milliseconds(500))
                window.layoutIfNeeded()
                let inputBottom = field.convert(field.bounds, to: window).maxY
                let keyboardTop = window.convert(keyboardFrames.endFrame, from: window.screen.coordinateSpace).minY
                let spaceForTabs = keyboardTop - inputBottom
                print("CODE → TERMINAL editor keyboard open=\(editorKeyboardOpen), input bottom=\(inputBottom), keyboard top=\(keyboardTop), tabs space=\(spaceForTabs)")
                if !editorKeyboardOpen {
                    let image = UIGraphicsImageRenderer(bounds: view.bounds).image { _ in
                        view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
                    }
                    let attachment = XCTAttachment(image: image)
                    attachment.name = "terminal-after-code-app-view"
                    attachment.lifetime = .keepAlways
                    self.add(attachment)
                }
                // 8 points below the native field, a divider and the complete
                // 38-point dock header must remain above the keyboard.
                XCTAssertGreaterThanOrEqual(spaceForTabs, 45, "Dock tabs are covered after Code → Terminal")
                XCTAssertLessThan(spaceForTabs, 55, "Dock tabs moved away from the keyboard")
                field.keyboardController?.dismiss()
                try await self.waitUntil { !field.isFirstResponder }
                try await Task.sleep(for: .milliseconds(400))
            }
        }
    }

    func testHideRestoresFullTerminalHeightAndToggleReopensKeyboardRepeatedly() async throws {
        try await withTerminal { field, keyboard in
            // Entering Terminal still focuses its command line automatically.
            try await self.waitUntil { keyboard.isFocused && field.isFirstResponder }
            keyboard.dismiss()
            try await self.waitUntil { !keyboard.isFocused && !field.isFirstResponder }
            try await Task.sleep(for: .milliseconds(500))
            let fullHeightY = field.convert(field.bounds, to: nil).midY
            let window = try XCTUnwrap(field.window)
            // The hidden-keyboard baseline must itself be at the bottom, not
            // a stale shrunken position that happens to repeat after each Hide.
            XCTAssertGreaterThan(fullHeightY, window.bounds.maxY - 200)
            print("TERMINAL KEYBOARD full-height input Y=\(fullHeightY), window height=\(window.bounds.height)")

            for _ in 0..<3 {
                keyboard.toggle()
                try await self.waitUntil {
                    keyboard.isFocused && field.isFirstResponder
                        && field.convert(field.bounds, to: nil).midY < fullHeightY - 100
                }
                keyboard.toggle()
                try await self.waitUntil {
                    !keyboard.isFocused && !field.isFirstResponder
                        && abs(field.convert(field.bounds, to: nil).midY - fullHeightY) < 2
                }
            }
        }
    }

    func testHideCancelsQueuedFocusAndUIKitDismissalDoesNotReopenOnAnUpdate() async throws {
        try await withTerminal { field, keyboard in
            try await self.waitUntil { keyboard.isFocused }
            keyboard.dismiss()
            try await self.waitUntil { !keyboard.isFocused }
            // A pending request used to outlive Hide and reassert the old focus.
            keyboard.focus()
            keyboard.dismiss()
            try await Task.sleep(for: .milliseconds(300))
            XCTAssertFalse(field.isFirstResponder)
            XCTAssertFalse(keyboard.isFocused)

            keyboard.focus()
            try await self.waitUntil { field.isFirstResponder }
            field.resignFirstResponder() // e.g. iPad's native Hide control
            try await self.waitUntil { !keyboard.isFocused }
            field.text = "help"
            field.sendActions(for: .editingChanged)
            field.window?.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(300))
            XCTAssertFalse(field.isFirstResponder)
            XCTAssertFalse(keyboard.isFocused)
        }
    }

    private func withTerminal(_ check: @MainActor (TerminalTextField, TerminalKeyboardController) async throws -> Void) async throws {
        try await withWorkspace(initialTab: .terminal) { view, _ in
            try await self.waitUntil { self.find(TerminalTextField.self, in: view) != nil }
            let field = try XCTUnwrap(self.find(TerminalTextField.self, in: view))
            let keyboard = try XCTUnwrap(field.keyboardController)
            try await check(field, keyboard)
        }
    }

    private func withWorkspace(
        initialTab: BuildDockTab,
        _ check: @MainActor (UIView, WorkspaceState) async throws -> Void
    ) async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        let state = WorkspaceState(tab: initialTab)
        let root = UIHostingController(rootView: Host(state: state))
        window.rootViewController = root
        window.makeKeyAndVisible()
        defer {
            window.endEditing(true)
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKey()
        }
        root.view.layoutIfNeeded()
        try await check(root.view, state)
    }

    private func find<T: UIView>(_ type: T.Type, in view: UIView) -> T? {
        if let match = view as? T { return match }
        return view.subviews.lazy.compactMap { self.find(type, in: $0) }.first
    }


    private func waitUntil(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTFail("Terminal keyboard or full-height layout did not reach the expected state", file: file, line: line)
        throw NSError(domain: "TerminalKeyboardTests", code: 1)
    }
}
