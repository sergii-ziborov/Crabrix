# Crabrix native Git core

Official libgit2 1.9.7 source, pinned by `upstream-manifest.json`. The original
source archive is included byte-for-byte. COPYING includes GPLv2 and the
upstream linking exception; dependency notices retain their original terms.

The SwiftPM C target builds the explicit 211-source Apple profile: SecureTransport,
collision-detecting SHA-1, system zlib/iconv and the bundled HTTP/regex/diff code.
SSH and command-line tools are excluded. Generated configuration headers are
pinned as source. `-fno-modules` applies to C translation units to avoid private
C struct tags colliding through Darwin Clang modules; the public C API remains
importable by Swift. No project hooks or external Git process are invoked.

`Sources/CrabrixGit` is the app's bounded, transactional Swift service. Git objects
and opaque files live outside replaceable text-project snapshots. It uses
explicit revisions, staged root replacement and retained recovery data.

Rebuild/test: `swift test --package-path Vendor/CrabrixGitCore` on macOS, or build
the local package with the iOS app. Tests invoke standard desktop Git only in
the macOS test target, never in the app. `scripts/probes/build_native_git.py`
reproduces the independently qualified CMake iOS prototype from the pinned tar.
