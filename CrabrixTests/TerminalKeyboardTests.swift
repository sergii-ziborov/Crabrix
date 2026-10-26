import SwiftUI
import UIKit
import XCTest
@testable import Crabrix

@MainActor
final class TerminalKeyboardTests: XCTestCase {
    private struct Host: View {
        @State private var tab = BuildDockTab.terminal
        @StateObject private var terminal = ProjectTerminalSession()
        @StateObject private var editorKeyboard = RustEditorKeyboardBridge()

        var body: some View {
            GeometryReader { _ in
            TabView {
                GeometryReader { _ in
                VStack(spacing: 0) {
                    Text("Project toolbar").frame(height: 58)
                    BuildDockView(
                        selectedTab: $tab, terminal: terminal,
                        project: CrabrixProject(name: "keyboard-lab", files: ["main.rs": "fn main() {}"], entryFile: "main.rs", provenance: nil),
                        result: nil, activity: .idle, canStartBuild: true,
                        onCheck: {}, onRun: {}, onReplaceFiles: { _, _ in true },
                        workspace: .empty, onFetch: {}, onCancel: {},
                        canContinueLearning: false, lessonEvidenceMessage: nil,
                        lessonHint: nil, contribution: nil, onOpenDiagnostic: { _ in },
                        diagnosticAdviceState: .idle, onOpenDiagnosticAdvisor: {},
                        onContinueLearning: {}, keyboardBridge: editorKeyboard,
                        duoHingePresent: false, hingePartiallyOpen: false,
                        hingeGlobalY: 0, assistantUsesAppleIntelligence: false,
                        onRequestCompletion: {}
                    ) { Color.black }
                }
                }
                .tabItem { Label("Projects", systemImage: "folder.fill") }
                Color.clear.tabItem { Label("Learn", systemImage: "graduationcap") }
            }
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

    private func withTerminal(_ check: (TerminalTextField, TerminalKeyboardController) async throws -> Void) async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        let root = UIHostingController(rootView: Host())
        window.rootViewController = root
        window.makeKeyAndVisible()
        defer {
            window.endEditing(true)
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKey()
        }
        root.view.layoutIfNeeded()
        func find(_ view: UIView) -> TerminalTextField? {
            if let field = view as? TerminalTextField { return field }
            return view.subviews.lazy.compactMap(find).first
        }
        try await waitUntil { find(root.view) != nil }
        let field = try XCTUnwrap(find(root.view))
        let keyboard = try XCTUnwrap(field.keyboardController)
        try await check(field, keyboard)
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
