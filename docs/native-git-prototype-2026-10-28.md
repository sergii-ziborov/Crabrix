# Native Git feasibility — not yet a shipping feature

The stage-3 technical prototype uses official
[libgit2 1.9.7](https://github.com/libgit2/libgit2/releases/tag/v1.9.7), a security
release. The [official build documentation](https://github.com/libgit2/libgit2)
describes iOS and the system SecureTransport HTTPS backend.

Source archive SHA-256:
`1a4fbe7589e814777ae76b64734ad80f4ecad22cd33a22682a2aaea4ae5375e7`.
`scripts/probes/build_native_git.py` pins/checks that input and builds a static
arm64 library for iOS 18 Simulator, with SSH disabled and SecureTransport enabled.
The source is not compiled by the shipping app target at this stage.

Actual native Simulator probe `scripts/probes/native-git.c` confirmed:

- Repository initialization, staging selected paths and two real commits.
- Status for modified and untracked files.
- Branch creation, safe checkout and reopening the same history.
- A hidden `.rustfmt.toml` and a non-UTF-8 binary asset survive the selected
  source commit and branch switch byte-for-byte.
- Standard desktop `git fsck --full` reads the result with no errors; all refs
  and both commits are ordinary Git objects, not custom snapshot history.
- Actual HTTPS clone of `octocat/Hello-World` in the native Simulator process,
  using default system certificate verification, without checking out files.
  Observed remote HEAD: `7fd1a60b01f91b314f59955a4e4d4e80d8edf11d`.

Evidence is under `build/git-20261028/`: `probe2.json`, `https-probe.json`,
the standard repository, build logs and static-library provenance. The probe
has no user credentials, private repo access, push, UI or project-store mutation.
It is **not** evidence of a complete Git feature or physical-device performance.

The next implementation must add a durable Git/object location outside replaceable
project snapshots, a canonical complete tree with opaque-file preservation,
revision-checked operations, the Changes UI and terminal service, then HTTPS
credentials in Keychain and the remote acceptance matrix. No existing GitHub
snapshot-import provenance is silently promoted into a historical commit.
