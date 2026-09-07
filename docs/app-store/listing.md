# App Store listing

Everything App Store Connect asks for, kept in the repository so the listing and
the app cannot drift apart. Character limits are Apple's.

## Identity

| Field | Value |
| --- | --- |
| Name (30) | `Crabrix: Rust Compiler` |
| Subtitle (30) | `Cargo IDE, offline on-device` — 28 characters. The name already carries "Rust" and "Compiler", so the subtitle spends its room on the words it does not: Cargo, IDE, offline, on-device. |
| Bundle ID | `com.sergiiziborov.Crabrix` |
| SKU | `crabrix-ios-001` |
| Primary category | Developer Tools |
| Secondary category | Education |
| Price | Tier for **$9.99** at launch, raised as the app grows. One-time, no IAP. |
| Age rating | Answer the current questionnaire honestly, question by question; the app has no objectionable content, so the computed rating should come out low. Do not paste an expected result. |
| Copyright | `2026 Serhii Ziborov` |

### URLs

| Field | Value |
| --- | --- |
| Marketing URL | `https://crabrix.com/technology` — the page that answers a reviewer's and a developer's first question: which compiler, under which limits, with which gaps |
| Support URL | `https://crabrix.com/support` |
| Privacy Policy URL | `https://crabrix.com/privacy` |

## Promotional text (170)

> A real bundled rustc and crates.io dependencies, built on device. 142 guided
> lessons and 200 algorithm patterns, practised against the real compiler. Works
> offline.

164 characters. Not "checked by the compiler itself": the exercises are compiled
and the answers are graded, but there is no canonical proof over all 200 patterns
and the text must not imply one.

## Description (4000)

```
Crabrix runs a real bundled Rust compiler locally on your iPhone and iPad.
Build multi-file projects, add crates.io dependencies, read and edit the source
of those dependencies, learn from real compiler errors, and keep working with
the network off — with no cloud compiler and no account.

Not a sandbox that sends your code to a server. Not an interpreter written to
look like the real thing. Crabrix bundles an actual build of rustc and the Rust
standard library, and executes it on your device — real rustc diagnostics with
the standard rustc error codes, from the toolchain pinned inside the app.

REAL COMPILATION, ON DEVICE
• A bundled build of the Rust compiler and standard library
• Real rustc diagnostics, with the error codes you can look up
• Your program runs in a sandbox with a memory cap and no network
• First builds do the work; identical repeat runs come from a local cache

A REAL PACKAGE MANAGER
• Add dependencies from crates.io by name and version
• Sparse index resolution, SemVer ranges, and feature unification
• SHA-256 checksums verified before any source is extracted or trusted
• Every extracted crate path is listed; supported source is completely viewable
  and editable, or the package is blocked before compilation
• Vendor & Edit creates a project-local editable patch with Diff and Reset
• Cached graphs rebuild offline; Pin for Offline survives iOS cache eviction

AN EDITOR BUILT FOR A PHONE
• Rust syntax highlighting, line numbers, and no line wrapping
• Completion, diagnostic navigation, and a keyboard row that fits your thumbs
• Multi-file Cargo projects, a file tree, and a project terminal
• Import from GitHub or Files, export as a package or a plain ZIP

LEARN RUST PROPERLY
• 142 lessons across six courses: from fn main to unsafe, FFI, and async
• 142 guided lessons with written explanations and highlighted examples
• A separate Algorithm Atlas: 20 independent solution-method chapters, 200 patterns, and 600 steps ordered within their method
• Every pattern has a mental model, use-case guide, and local Rust challenge
• Compiler-backed labs across the curriculum use the bundled rustc as evidence
• Interview preparation that goes past the language: memory, atomics,
  networking, databases, and distributed systems
• Quick Practice, Term Train, and Code Recall — all generated from the same
  curriculum, all scheduled with SM-2 spaced repetition
• Health and energy that scale with your rank, and training that never costs
  either, so there is always a way to keep going

RATING THAT MEANS SOMETHING
A successful run is scored on how much Rust actually changed since the last one.
Pressing Run on an untouched sample is not work, and Crabrix does not pretend
otherwise. Rating and achievements remain local in the production 1.0 build.

NO ACCOUNT. NO SUBSCRIPTION. NO TRACKING.
Buy it once. There is no sign-up, no password, no advertising, no analytics
SDK, and no data sold to anyone. Your code is never uploaded to compile it: it
leaves the device only if you export it or attach it to a support message.

WHAT IT CANNOT DO
The bundled compiler targets wasm32-wasip1 and has no native linker, so crates
needing C code, build scripts, or procedural macros generally cannot build on
device. Crabrix detects these and tells you, instead of failing halfway. There
is no debugger yet. Compilation is interpreted WebAssembly, so a first build is
slower than on a laptop.

The compiler, curriculum, and local projects work offline. Cached dependencies
rebuild while iOS retains them; Pin for Offline keeps their exact verified
archives durable after a cache eviction. First-time package downloads and GitHub
imports require a connection.

There is no account, no analytics, and no leaderboard. Your rating, ranks and
achievements stay on your device.
```

## Keywords (100, comma separated, no spaces)

Apple already indexes the app name and subtitle, and tells developers not to
repeat those words here. With the name carrying `Rust` and `Compiler` and the
subtitle carrying `Cargo`, `IDE`, `offline` and `on-device`, the field is spent
on everything else a search might use:

```
crates,rustc,learn,programming,editor,wasm,ownership,borrowing,lifetimes,algorithm,tutorial,code
```

96 characters. No competitor app names: Apple rejects those.

## What's New (4000) — version 1.0

```
The first release of Crabrix.

A real Rust compiler on your iPhone and iPad, with a real crates.io package
manager, an editor built for a phone, 142 guided Rust lessons, and a separate
200-pattern Algorithm Atlas with compiler-backed challenges.

The compiler, curriculum, and local projects work offline. Cached dependencies
rebuild while iOS retains them; Pin for Offline keeps their exact verified
archives durable after a cache eviction. First-time package downloads and GitHub
imports require a connection. There is no account and no leaderboard.
```

## App Privacy answers — production 1.0

Match `Crabrix/Resources/PrivacyInfo.xcprivacy` exactly.

| Question | Answer |
| --- | --- |
| Do you collect data from this app? | **No** — Crabrix runs no service, and the production build is compiled without Game Center |
| Used for tracking? | **No** |
| Everything else | **Not collected** |

Crabrix operates no service of its own, and the production Release
configuration is built without `CRABRIX_SOCIAL`, so the binary links no GameKit
either; a CI step fails the build if it reappears. If a later release turns on
Game Center, update these answers and the review notes from the shipped binary
before submission.

**Report a problem does not change the answer, and here is why.** The screen
composes the report on device and hands it to the reader's own mail app through
a `mailto:` URL, or to the pasteboard. The app opens no connection, transmits
nothing, and receives nothing back; whether a message ever exists is decided in
a different app, by the person, who can edit or discard the draft. Nothing is
attached automatically beyond four lines of version and hardware facts the
reader can switch off, and no identifier unique to the person or the install is
among them. Data the app never collects is not data collected from this app.

What the correspondence does create is an email a human holds afterwards, which
is why `site/privacy.html` describes it, what it contains, how long it is kept
and how to have it deleted. Owner to confirm before submission: the retention
sentence there matches what will actually be done. If a future version ever
sends a report from inside the app, these answers change to Contact Info →
Email Address and Diagnostics, both **Customer Support**, not linked to
identity and not used for tracking.

## Content rights

App Store Connect asks whether the app contains, shows, or accesses third-party
content. Crabrix does: the user can add a crates.io package or import a public
GitHub repository. Answer accordingly and give this position rather than a bare
"no":

```
Crabrix is a programming and dependency tool. Third-party content appears only
because the user explicitly asks for it: a crates.io package they name, or a
public GitHub repository URL they provide. Crabrix downloads that source into
the user's own project so it can be read, edited and compiled locally by the
bundled Rust compiler.

Crabrix does not host, curate, promote or sell third-party content, operates no
marketplace or storefront, and applies no rights of its own to it. The one
browsing surface is a search over the public crates.io index, reached from the
open project's dependency list and used only to name a package to add — there is
no catalogue to wander, nothing is ranked or promoted, and nothing is sold. Each
package and repository stays under its own licence, which travels with the
source. crates.io is the Rust community's public package registry, operated by
the Rust Foundation.
```

## DSA / EU trader

The app is paid and commercial, so the trader declaration has to be completed
before EU availability, and Apple displays a verified trader's address, phone
and email in EU storefronts. Decide on the address to publish — a business or
P.O. Box rather than a home address — before enabling EU availability.

## Export compliance

`ITSAppUsesNonExemptEncryption` is `false` in `Info.plist`.

Crabrix uses HTTPS (exempt) and SHA-256 to verify crate checksums. Hashing is
not encryption, and no proprietary or non-exempt cryptography is implemented.

## Review notes

```
Crabrix is a Rust development environment. No account or subscription is needed,
and there are no in-app purchases. Free training is always available.

TO SEE IT COMPILE
1. Projects → "Hello Rust" chip → Build tab → Run.
   The bundled compiler builds and runs it on device; output appears in Output.
2. Edit the string in main.rs and press Run again to see a fresh compile.

PROGRAMMING ENVIRONMENT
Every Build screen carries a persistent "RUST PROGRAMMING ENVIRONMENT" label
with the exact bundled toolchain beside it (rustc 1.96.0-dev, wasm32-wasip1);
the same values are in Settings → Local compiler. The source editor occupies
66% of the screen on iPhone and 31% on iPad in its most editor-heavy state,
measured from Release-build screenshots.

Crabrix is not a store for code. crates.io is reachable only from the project
you are editing (Build → Packages → Add dependency). Searching crates.io by name
is part of choosing a dependency; what Crabrix does not offer is a standalone
marketplace, a promoted or trending feed, or any way to obtain a runnable app or
executable from another developer. It is dependency management for the Rust
project open in the editor, nothing else.

REGARDING GUIDELINE 2.5.2
Crabrix is an app designed to teach and develop code. The compiler and standard
library are bundled in the app, not downloaded. The only code downloaded at
runtime is Rust package source from the public crates.io registry, at the user's
explicit request, and it is used solely to build the user's own project inside
the app.

Every extracted path is listed in the app: Build → Packages → tap any downloaded
crate. For a supported package, every programming-source file is fully viewable
and can be copied with Vendor & Edit into the current project, edited in the
normal project editor, reviewed as a local diff, compiled under a distinct
patched fingerprint, or Reset to the checksum-backed registry source. If a
programming-source file exceeds the editor's complete file/tree limits or is not
valid UTF-8, Crabrix labels the package Unsupported and blocks it before rustc
runs. Binary assets remain visible as file metadata in the immutable registry
tree and are not misrepresented as editable text. The immutable registry copy is
never modified.

GITHUB IMPORT
The same rules cover repository import:
- public repositories only in 1.0, and only after an explicit user action;
- the downloaded archive becomes an ordinary editable project in the app, under
  the same bounded file, size and tree limits as any other project;
- no opaque downloaded binary is executed: source is compiled locally by the
  bundled rustc;
- the resulting program runs in the same bounded, network-free sandbox.

Programs execute inside a WebAssembly sandbox in the app's own process, with
memory/instruction/output/storage caps, no network access, and one writable
directory. Crabrix spawns no host processes; the "terminal" is a simulated shell
over the in-app project files only.

REVIEWER PROOF PATH
1. Open the included Hello Rust project and Run it with no network.
2. Open the E0502 borrowing sample, inspect the diagnostic, repair, and Run.
3. Add the supported smallvec package and build it locally.
4. Open smallvec under Build → Packages, tap Vendor & Edit, add a harmless
   comment, inspect Diff, Run, then Reset to Registry Source.
5. Pin the exact graph for offline, disable networking, clear purgeable package
   cache, and rebuild.
6. Run `fn main() { loop {} }`, tap Stop, then immediately Run Hello Rust.

ONLINE BOARDS
There are none, and there is no Crabrix service behind the app at all: no
account system, no server, no first-party board. Game Center is the only online
path the app will ever have and it is not compiled into the production 1.0
binary, which links no GameKit and has no display-name field or publishing
control anywhere in the interface. Rating, ranks and achievements are
calculated and stored on device.

CONTACT
https://crabrix.com/support — the contact form there opens a mail draft
addressed to the developer. The same address is in the App Store Connect
support and review-contact fields.
```

## Screenshots

Recaptured on 2026-09-06 from the Release build of the 1.0 (3) candidate, in
dark appearance, on freshly erased simulators. The device archive differs from
these builds only in signing and architecture, so re-capture is needed only if
the interface changes again before submission. The Settings frame shows the top
of the screen; the Help & problems section added in this build sits below its
fold and is not visible in it.

| Folder | Device | Size |
| --- | --- | --- |
| `docs/app-store/screenshots/iphone-6.9/` | iPhone 17 Pro Max | 1320 × 2868 |
| `docs/app-store/screenshots/ipad-13/` | iPad Pro 13-inch (M4) | 2064 × 2752 |

Every frame shows the shipped interface: the persistent programming-environment
label, the split Rust/Atlas counters, the rescaled rank ladder, 185 achievement
tiers, and no board, display name or Game Center control anywhere.

Upload order for the iPhone set, which tells the story in the right sequence:

1. `01-build` — the workspace, editor and build inspector
2. `03-learn` — Learn hub: rating, vitals, courses
3. `05-lesson` — a lesson with its highlighted example and the energy cost
4. `06-profile` — local profile, avatar, rating, vitals, and lifetime stats
5. `02-projects` — the dashboard and My Projects organization
6. `07-library` — the project library
7. `04-course` — a course path
8. `08-settings` — settings and About

### Reproducing them

Every frame comes from a launch argument, so the same build always produces the
same screens:

```bash
xcrun simctl launch <device> com.sergiiziborov.Crabrix \
  -CrabrixTab learn -CrabrixLearn borrowing
```

`-CrabrixTab` takes `projects`, `build`, `learn`, or `settings`.
`-CrabrixLearn` takes `profile`, a course id, or a lesson id.
`-CrabrixLibrary` opens the project library.
`-CrabrixCanvasGallery` opens it already filtered to the Rust Canvas projects.

## Launch assets

Featuring nomination, custom product pages, the Show HN and community drafts,
the video shot list, and the reviewer-outreach note live in
[launch.md](launch.md). They are written ahead of the submission so nothing is
drafted on the day.

## Pre-submission checklist

- [x] Support reaches a person — the site's contact form and the app's Report a problem both open a mail draft addressed to the developer's own inbox. The address is never rendered as text: it is decoded at click time, so it is not sitting on a public page to be harvested. Enter it directly in the App Store Connect support and review-contact fields.
- [x] Game Center is not in the production build, so no capability is needed on the App ID
- [x] Screenshots recaptured from the 1.0 (3) Release build at both required sizes, on freshly erased simulators
- [x] Programming-environment area re-measured on this build — 72.9% iPhone, 66.2% iPad at its widest, against an 80% limit
- [ ] App Store artifact exported — blocked on an Xcode account session, see [submission-status.md](submission-status.md)
- [ ] Report a problem exercised once on the physical phone
- [ ] Physical iPhone/iPad matrix and release-evidence bundle complete
- [ ] App Review 2.5.2 consultation/reviewer proof path confirmed
- [ ] App Privacy answers entered to match the privacy manifest
- [ ] Export compliance answered
- [ ] Age rating questionnaire completed as 4+
- [ ] Review notes pasted from this file
