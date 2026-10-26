# Terminal keyboard toggle — 26 October 2026

The terminal's Hide action now resigns its own UIKit field directly during
the button action. It no longer changes the first responder inside
`UIViewRepresentable.updateUIView`, where dismissal could leave SwiftUI using
the previous keyboard safe area. The transcript can fill the freed height;
the quick commands, input and dock tabs return to the bottom of the workspace.

`TerminalKeyboardController` owns only that field. Its state follows UIKit's
editing callbacks, updates outside SwiftUI layout, and cancels queued focus
after Hide or removal of the terminal. Both the command-row button and the
existing Duo terminal tab-row control switch between Hide keyboard and Show
keyboard. Opening Terminal still focuses the command input automatically.

No manual keyboard-height reservation, padding, overlay or frame workaround
was added. The fold calculations, tab heights, code keyboard accessories,
50-point terminal input row and main navigation are unchanged. Keyboard Send
still submits commands; no duplicate Run control is restored.

## Verification

The optimized simulator app and hosted tests used Xcode 27.1 RC / SDK 27.1 on
the iPhone 17 Pro simulator running iOS 26.5. The final result bundle is
`build/compiler-optimization-20261024/terminal-keyboard-20261026-final.xcresult`.

- **10 passed, 0 failed, 0 skipped**: two keyboard/layout tests and all eight
  `ProjectTerminalSessionTests`.
- The real dock is hosted inside a native TabView and nested GeometryReaders.
  Entering Terminal focuses the real UITextField. Three show/hide cycles check
  that the field moves upward with the system keyboard and returns within
  two points of its original full-height position after dismissal.
- Hide cancels a queued focus request. Native UIKit dismissal followed by a
  command-binding update leaves the field unfocused.
- The final run has no SwiftUI warning about publishing during view updates.
- Native visual inspection is unavailable while the Mac is locked. No
  screenshot comparison, physical iPhone or Duo-posture verification is claimed.

The compiler/runtime configuration, signed production toolchain and separate
native compiler candidate are unchanged by this fix.
