import UIKit
import Combine

/// Owns only the terminal prompt's responder. Keyboard insets remain owned by
/// the system, including the existing Duo layout beside the hinge.
@MainActor
final class TerminalKeyboardController: ObservableObject {
    @Published private(set) var isFocused = false
    private weak var field: UITextField?
    private var wantsFocus = false

    func toggle() {
        if isFocused || wantsFocus { dismiss() }
        else { focus() }
    }

    func focus() {
        wantsFocus = true
        guard let field else { return }
        focusWhenAttached(field)
    }

    func dismiss() {
        wantsFocus = false
        // Run during the button action, before SwiftUI starts another layout
        // transaction, so the system restores the workspace's full safe area.
        field?.resignFirstResponder()
    }

    func attach(_ field: UITextField) {
        self.field = field
    }

    func detach(_ field: UITextField) {
        guard self.field === field else { return }
        self.field = nil
        wantsFocus = false
        field.resignFirstResponder()
        synchronizeFocus()
    }

    func focusWhenAttached(_ field: UITextField) {
        // Switching away from Code removes its first responder in this run
        // loop. Recheck the latest request so Hide or a tab switch cancels any
        // queued focus rather than bringing the keyboard straight back.
        DispatchQueue.main.async { [weak self, weak field] in
            guard let self, let field, self.field === field,
                  self.wantsFocus, field.window != nil,
                  !field.isFirstResponder else { return }
            field.becomeFirstResponder()
        }
    }

    func didBeginEditing(_ field: UITextField) {
        guard self.field === field else { return }
        wantsFocus = true
        synchronizeFocus()
    }

    func didEndEditing(_ field: UITextField) {
        guard self.field === field else { return }
        wantsFocus = false
        synchronizeFocus()
    }

    private func synchronizeFocus() {
        // UIKit can end editing while SwiftUI dismantles a tab. Publish after
        // that update, and read the current field so an older callback cannot
        // overwrite the state of a newly mounted terminal.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let focused = self.field?.isFirstResponder == true
            if self.isFocused != focused { self.isFocused = focused }
        }
    }
}

final class TerminalTextField: UITextField {
    weak var keyboardController: TerminalKeyboardController?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { keyboardController?.focusWhenAttached(self) }
    }
}
