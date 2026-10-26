# Code to Terminal keyboard handoff

## Report and cause

With Code's software keyboard already visible, opening Terminal could place
the dock's four tabs behind the keyboard. The source editor's 46-point input
accessory remained attached while the responder was being removed. The
incoming Terminal field then received a keyboard inset that was 46 points
too small. Merely resigning Code before the selection change did not fix it.

## Change

- Dock actions resign the Code responder before changing the selected panel.
- `RustSourceTextView` releases its input accessory before resigning and
  reloads the input views while it still belongs to the window. It retains
  the configured accessory and restores it before becoming first responder.
- The same lifecycle handles Code's Hide action and subsequent refocus. A
  refused resignation restores the accessory immediately.
- Terminal's existing focus controller and Hide/Show behavior are retained.
  No keyboard height, safe-area adjustment, overlay, tab dimensions or hinge
  calculation was added or changed.

## Verification

The hosted regression uses the actual `SyntaxCodeEditor`, `BuildDockView`,
native `TabView` and terminal prompt inside the existing nested geometry.
It performs Code to Terminal transitions with the keyboard hidden and open,
including repeated transitions and hiding/refocusing the same Code editor.
It verifies that the 46-point Code helper bar returns and measures the
terminal field against UIKit's keyboard frame.

Before the fix, only **0.33 points** remained between the input field's bottom
and the keyboard. After the fix, all three transitions leave **46.33 points**:
enough for the existing 38-point dock header, divider and command-row padding.

**13 tests passed, 0 failed, 0 skipped**, using the optimized app on the
iPhone 17 Pro simulator running iOS 26.5 with SDK 27.1. These include the three
terminal keyboard tests, six hosted source-editor tests and four horizontal
layout tests. The test-owned app-view render was inspected; it shows all
four dock tabs. It excludes the system keyboard and is not a Store screenshot.
No physical iPhone or Duo posture verification is claimed.

Result bundle: `build/compiler-optimization-20261024/code-terminal-responder-lifecycle.xcresult`.
