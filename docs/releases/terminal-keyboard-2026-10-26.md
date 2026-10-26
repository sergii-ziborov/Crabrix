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
- A further focused rerun passed both keyboard tests with an absolute bottom
  position assertion: the input center returned to Y **727.67** in an
  **874-point** window. This rejects a repeatable but stale shrunken baseline.
  Its result is `terminal-keyboard-20261026-bottom.xcresult` in the same folder.
- Hide cancels a queued focus request. Native UIKit dismissal followed by a
  command-binding update leaves the field unfocused.
- The final run has no SwiftUI warning about publishing during view updates.
- Native visual inspection is unavailable while the Mac is locked. No
  screenshot comparison, physical iPhone or Duo-posture verification is claimed.

The compiler/runtime configuration, signed production toolchain and separate
native compiler candidate are unchanged by this fix.

## Delivery

Manual Xcode Cloud run 94 archived app source
`70f58c85157b7c07fd17ffc48c03c8bbccfb73e5` successfully. **1.1.2 (94)** is
VALID and IN_BETA_TESTING in TestFlight Internal QA. It replaces the pending
manual release of build 93; the new App Store submission is WAITING_FOR_REVIEW.
Release remains MANUAL. All 19 screenshots are COMPLETE, with Code first for
iPhone, Duo and iPad. What to Test, reviewer notes and release notes match a
fresh Apple readback. [Delivery evidence](../app-store/release-1.1.2-build94.json).

The later test-only bottom-position assertion does not change archived app
source, resources, project configuration or compiler capabilities.
