# Offline Atlas replay and personal-code route — build 115

This is the LEARN-01/LEARN-02 portion of roadmap stage 4. It is in signed
TestFlight build 115. App Review selection is recorded separately in the delivery receipt; build 114 remains selected until replacement is confirmed.
Semantic navigation remains the subsequent IDE-01 work.

## Data and trust

Twenty optional sections cover all 600 Atlas lesson steps through 400 unique
recordings. Their archives total 798,286 bytes; catalog, descriptors and
qualification metadata are separate small files. The existing production
CoursePack publisher signs catalog and descriptors. No key is stored in Git.
The [immutable data release](https://github.com/sergii-ziborov/crabrix-courses/releases/tag/algorithm-replays-2026-10-28.1)
has 42 assets; every GitHub asset digest was read back and matched locally.

The signed descriptor binds the section index, which binds each recording's
bytes and SHA-256. Lesson lookup separately requires the exact example source
digest. A changed lesson cannot silently receive an older recording. Native
decoding validates source sites, value references, stack activations and bounded
recursive data. Scalars retain exact Rust display strings, including integers
outside JavaScript's safe integer range.

Recordings were made with native Rust 1.99.0 at author time. Personal projects use
wasm32-wasip1; target-sized values such as usize can have different limits. The
player's details state this distinction and disclose omitted captures. A
recording does not represent subsequently edited code.

Sections use the existing bounded transport and transactional installer in a
separate Atlas root. Installed recordings load locally with signature, index and
byte checks. Stop cancels acquisition. Removing a section waits for its active
job and leaves personal projects, courses and progress intact. No login is needed.

The bundled Academy catalog advances from sequence 3 to signed sequence 15. The
first UI run correctly rejected old lesson text against a new recording. New
learners can now download matching course versions directly. Existing learners
retain explicit updates and pinned open sessions. Bootstrap/prebuild verify
both signatures with CryptoKit using the macOS host SDK.

## Native flow

Learn → lesson → Watch algorithm steps opens a themed modal. Previous/next,
restart, play/pause, speed and scrubbing remain at the bottom while inspecting
data and highlighted Rust. Indexed arrays, matrices, maps/sets, adjacency edges
and weights, and linked nodes preserve recorded values. Exact data is separately
inspectable. Editor, keyboard dock and Duo geometry are preserved.

Open personal copy in Code creates an ordinary project with original input and
source plus lesson/course/recording provenance. It never starts a validator or
executes automatically. Run and Debug use current editable source. Project
settings offers Return to lesson without replacing the copy. Existing project
formats preserve optional provenance.

## Qualified behavior

- All 600 references / 400 recordings installed and decoded in the native host
  without network. Core cases cover exact numbers, invalid references, stale
  source, tampering, uninstall/reinstall and personal-data preservation.
- A fourth case uses the actual prepared signed algorithms 1.0.6 course. It copies
  linear scan, changes input and runs the real app compiler and Debug. Current
  output is `1`; original recording output remains `2`. Provenance survives
  serialization; Academy completion/evidence stays unchanged. A fifth case verifies
  graph directions, exact large edge weights, self-edges and linked-node meaning.
  All five plus course bootstrap/verification/installation/download regression
  cases passed: **34/34 on iPhone Simulator and 34/34 on iPad Simulator**, no skips.
- Both phone and iPad UI passed lesson → steps/back/restart → reopen prepared recording →
  personal copy → real Run → real Debug/Continue → Return to lesson. Four editor
  dock tabs remain. Final scoped-control passes include the fixed bottom controls
  and visible chevrons. Phone used Dark; iPad passed Amber Circuit and a separate final Cyberpunk run.
- Course preparation reuses the actual public archive after its SHA-256 check.
  The large illustrated course is separate from small optional trace sections.
  An interrupted network-preparation attempt is not counted as a product pass.
- Signed build 115 has been verified against source `adbc23e` and is VALID / IN_BETA_TESTING. Its archive action succeeded; a redundant Cloud Build action failed while downloading XcodeGen before source bootstrap. No physical-device timing is claimed. Semantic IDE work remains open.

[Build 115 delivery receipt](app-store/release-1.1.3-build115.json).

Evidence is in `build/atlas-offline-20261028/`. Rebuild data with
`scripts/build_atlas_packs.py` and an explicitly supplied publisher seed outside
Git. Ordinary builds only verify public signatures and never sign.
