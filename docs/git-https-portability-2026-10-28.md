# Native Git HTTPS and complete portability — stage 3B

Candidate on `codex/offline-browser-packages-20261027`; separate from TestFlight
and App Review 1.1.3 (113). The latter contains Test/Format and reliability work,
but no Git. A source implementation is not a signed delivery.

## Using the candidate

Project settings → Local Git keeps Changes, History and Branches and adds Remote.
Before initialization, Clone creates a separate project from a GitHub HTTPS URL.
Public repositories need no token. For a private repository, enter its canonical
URL, GitHub username and token, then explicitly Save access on this device.
Keychain storage is scoped to that repository, device-only and unlocked-only.
Remove saved access deletes it. Tokens are never retained in terminal history,
project files, Git configuration, archives, Shared messages or compiler inputs.

Fetch updates objects and remote-tracking refs without changing source or HEAD.
Pull fetches, then accepts a clean fast-forward; dirty or diverged work is kept
with an explanation. Push explicitly sends committed history, never a forced
rewrite or uncommitted editor text. Transfer progress and Stop remain in the
existing modal. Typing and autosave can continue during acquisition; checkout
uses the existing exclusive project-operation boundary.

Terminal uses the same service: `git clone https://github.com/owner/repo.git`,
`git remote add origin URL`, `git remote -v`, `git fetch`, `git pull --ff-only`,
and `git push`. Identity, local commits, diff, history and Restore retain the
[stage 3A behavior](local-git-2026-10-28.md). Repository acquisition is online;
compilation, execution, local commits and prepared dependencies remain local.

## Full transfer and resources

Changes → Save the complete repository → Prepare repository export produces a
`.crabrixrepo` archive. Save or share it using the native sheet. Opening it from
Files or Crabrix import creates a new project UUID and preserves source metadata,
standard Git commit IDs, refs, worktree bytes and executable modes. The archive
includes uncommitted work. It excludes prepared package caches and credentials.
Existing source ZIP and `.crabrixproject` formats remain text-only exports.

The bounded ZIP inventory records every path, size, digest and executable bit.
Import rejects missing/extra files, CRC/hash mismatch, traversal, case/Unicode
aliases, file/directory collisions, links and unsupported repository structures.
It validates expanded objects and IDs, HEAD tree and index, then rebuilds a
minimal supported config before libgit2 opens it. Imported credential helpers,
includes, custom hooks, linked worktrees and alternate object stores are refused.
An unsuccessful import cannot replace an existing project or Git root.

Opaque worktree resources are frozen separately from text source for compilation,
`include_bytes!`, Debug and supported local preview assets. Resource content is
part of artifact/dependency cache identity and saved-build evidence. Changing a
binary resource invalidates the previous build badge. `.git`, access tokens and
repository bookkeeping are never guest inputs. Runtime filesystem permissions
retain the existing sandbox profile; this does not add an arbitrary project mount.

## Bounds and explicit exclusions

- Editable source: 2,048 files, 2 MiB each, 16,000,000 UTF-8 bytes total.
- Full worktree: 8,192 files, 8 MiB each, 64 MiB total; Git root 192 MiB and
  32,768 entries. Transfer/archive bounds fail without evicting existing work.
- HTTPS: GitHub canonical repository URLs only, verified system TLS, no redirects,
  proxy, URL credentials or inherited Git helpers; 120-second transfer deadline,
  128 MiB received pack and 100,000 objects. Connect/read-write timeout is 10 seconds.
- Portable archive: 224 MiB compressed/expanded and 32,769 entries including a
  maximum 16 MiB inventory; individual Git objects max 8 MiB, 512 MiB aggregate
  expanded-object verification budget and 30-second verification deadline.
- No SSH, LFS, submodules, rebase, independent imported staging, arbitrary hosts,
  hooks, arbitrary shell processes, automatic push or backend code execution.
  Binary npm/ESM imports are not made universally compatible by retaining assets.

## Qualification recorded so far

`build/git-20261028/remote-private-integrated-qa.log`: all nine macOS core cases
executed and passed, including actual private clone → commit → push → second
client fetch → fast-forward, dirty/diverged refusal, wrong-token refusal, live
Tokio-repository clone cancellation and a successful next clone. Desktop Git
`fsck` and clone confirm standard history interoperability. The owned temporary
private fixture was archived after testing; the available GitHub token cannot
delete repositories, so it was not falsely reported as deleted.

`port-native-second.xcresult` (iPhone) and `port-native-pad.xcresult` (iPad): 18
cases each, zero failures. These include real native HTTPS, actual Keychain
scope/replace/remove, credential redaction, archive and unsafe-import cases,
local compiler cache invalidation, save → binary change → rebuild → full export
→ import → run, Debug byte/stdout parity and all bundled notices. The initial
native run found a README-only entry-selection defect, which was fixed and
retested. Tests do not execute imported code merely by opening or cloning it.

Four real UI scenarios passed on each phone/iPad Simulator: public HTTPS clone,
Remote/fetch and full export; local commit/history/Restore; Rust Test/Format/Undo;
and the existing Rust + Web breakpoint/Step/offline preview. The four editor dock
tabs and source remain intact. Remote and export captures are retained under
`docs/screenshots/iphone-git-*` and `ipad-git-*`; the public guide uses actual phone
captures. Website type checking, 34 tests and production build passed. A final
signed bundle and confirmed Apple delivery remain release gates.

These Simulator/desktop results do not claim physical-iPhone measurements.
