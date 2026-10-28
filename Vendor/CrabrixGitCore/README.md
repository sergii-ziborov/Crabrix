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

The HTTPS profile accepts canonical GitHub repository URLs only, with platform
certificate verification, no redirects/proxy or inherited Git credential helpers.
Clone/fetch/push have transfer, object, storage and time bounds and cooperative
cancellation. Credentials are transient inputs to this package. The app owns
repository-scoped, device-only Keychain storage; neither this source package nor
its portable repository format stores tokens. Pull accepts clean fast-forwards;
push is explicit and non-force. SSH, submodules, LFS and rebase are outside this
profile. Imports validate object IDs, bounded expanded objects, index/tree paths
and rebuild configuration before opening the repository with libgit2.

Complete portable copies preserve standard commit IDs, refs, worktree bytes and
executable modes. Opaque worktree resources can be handed separately to the local
compiler; repository metadata and credentials are never compiler inputs. The
small resource identity read is independent of the serialized network operation,
so ordinary project autosave does not wait behind an HTTPS transfer.

Rebuild/test: `swift test --package-path Vendor/CrabrixGitCore` on macOS, or build
the local package with the iOS app. Tests invoke standard desktop Git only in
the macOS test target, never in the app. `scripts/probes/build_native_git.py`
reproduces the independently qualified CMake iOS prototype from the pinned tar.
Network qualification requires explicit environment opt-in; default offline tests
skip those cases visibly. Private interoperability uses a disposable private
fixture and a token supplied only to that test process. Do not store a token in a
URL, test fixture, source file or receipt.
