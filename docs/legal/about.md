# About Crabrix

Updated: 2026-10-10 · [Website copy](https://crabrix.com/about/)

A real Rust compiler on a phone, an honest account of its limits, and one developer behind it.

## What Crabrix is

Crabrix is a Rust workspace for iPhone and iPad. You write Rust, add real dependencies from crates.io, press Run, and the code compiles and executes on the device in your hand. There is no server doing the work and no account standing between you and the compiler.

That distinction is the whole point. Crabrix bundles and runs a real Rust compiler locally instead of relying on a cloud compilation service.

## How it actually works

**A real rustc**The app bundles a WebAssembly build of the Rust compiler and standard library. Diagnostics are real rustc diagnostics from Crabrix's pinned bundled toolchain, with the same error codes.

**Running in Swift**That WebAssembly module is executed by CrabrixRuntime, a maintained public fork of WasmKit 0.4.1, inside the app's own process. No JIT or daemon.

**A real package manager**Crabrix speaks the crates.io sparse index protocol, resolves SemVer ranges, unifies features, verifies SHA-256 checksums, extracts the sources, and compiles and links them.

**Sandboxed by construction**Your program runs inside the WebAssembly sandbox with a memory cap, no network, and a single writable directory. It cannot reach the rest of your device.

Every crate Crabrix downloads is fully readable inside the app, file by file, in the Packages screen. Nothing that runs on your device is hidden from you.

## The exact toolchain

Crabrix pins one compiler build and ships it in the app. Nothing is downloaded at runtime to compile your code, and the compiler identity is shown under Settings → Runtime:

- Target: `wasm32-wasip1`

- Toolchain artifact: [`crabrix-rust-2026-10-02.1`](https://github.com/sergii-ziborov/crabrix-toolchain/releases/tag/toolchain-2026-10-02.1)

- Runtime: [CrabrixRuntime](https://github.com/sergii-ziborov/crabrix-runtime) from WasmKit 0.4.1

The public [toolchain builder](https://github.com/sergii-ziborov/crabrix-toolchain) produced the signed compiler release from pinned source. Its build inputs, compatibility results, licenses and two-build difference report are public. The compiler has its own identity distinct from the runtime fork.

## What it cannot do

Being honest about the edges is more useful than a feature list. The bundled compiler targets `wasm32-wasip1` and has no native linker, so:

- Crates with C dependencies, build scripts, or procedural macros generally cannot build. Crabrix detects these and says so instead of failing halfway.

- Compilation is interpreted WebAssembly, so a first build is slower than on a laptop. Repeat builds come from a local artifact cache.

- There is no debugger and no `cargo test` harness yet.

The Packages screen labels every dependency verified, expected to work, needs review, or unsupported, based on real build outcomes recorded on device.

## Learning, not just tooling

Crabrix contains a full Rust course — 142 lessons across six language courses, from `fn main` through ownership, traits, and async to macros, unsafe, and FFI, plus interview preparation that reaches past the language into memory, networking, databases, and distributed systems. A separate Algorithm Atlas adds 200 reusable patterns across 20 independent solution methods. Each method has its own path, and every pattern is taught through a mental model, recognition guide, and local Rust challenge.

All 742 lessons and steps have expanded written guidance, inline code markup, a syntax-highlighted example, and an infographic with a caption and alt text. Crabrix includes compiler-backed labs across the Rust curriculum, and every Algorithm Atlas pattern ends in a local Rust challenge the bundled compiler has to accept. Three drills — Quick Practice, Term Train, and Code Recall — are generated from that same curriculum and scheduled with SM-2 spaced repetition, so what you are weakest at comes back soonest.

A new installation offers seven signed courses for individual download. Code Examples is a separate optional download with 46 editable projects. Existing learners receive all seven signed transition packs locally so previously available courses stay available offline. Later versions are published as data-only CoursePacks from the public [course repository](https://github.com/sergii-ziborov/crabrix-courses). Learn shows the size before a requested update. Opening a starter creates a separate editable project, so an updated course does not replace your work.

Rating is earned across everything, and a successful run is scored on how much Rust actually changed since the last one. Pressing Run on an untouched sample is not work, and the app does not pretend otherwise.

## Who makes it

Crabrix is built by **Serhii Ziborov**, an independent developer. It is not a company, it has no investors, and it has nobody's growth targets to hit. That is why it is a one-time purchase with no subscription, no advertising, no analytics, and no required app account. The separate website Academy offers free accounts for full lessons; its public previews and blog are open to everyone.

The source is on [GitHub](https://github.com/sergii-ziborov/Crabrix) for review. Questions, bugs, and disagreements are welcome — [write to support](https://crabrix.com/support/).

## Credits and licenses

The [license library](https://crabrix.com/licenses/) includes the application source terms, educational content rights and original third-party notices. The app also bundles About, Privacy and Terms for offline reading in Settings.

Crabrix stands on work by other people, all of it open source and attributed in full inside the app under Settings → About Crabrix → Open-source licenses:

- **The Rust Project** — the compiler and standard library, under Apache-2.0 or MIT.

- **WasmKit** by Akio Yasui — the Swift WebAssembly interpreter, MIT.

- **wasm-rustc** by Forest Anderson — the MIT-licensed builder recipe behind the source-built toolchain. Rust and toolchain dependencies keep their own terms.

- **ZIPFoundation** by Thomas Zoechling — archive reading and writing, MIT.

- **Swift System 1.8.1, Argument Parser 1.8.2, and Swift Syntax 604.0.0** — Apache-2.0 with the notices and applicable Runtime Library Exception.

Rust and the Rust logo are trademarks of the Rust Foundation. Crabrix is an independent project, not affiliated with or endorsed by the Rust Foundation or by Apple.
