# App Store listing

Everything App Store Connect asks for, kept in the repository so the listing and
the app cannot drift apart. Character limits are Apple's.

## Identity

| Field | Value |
| --- | --- |
| Name (30) | `Crabrix: Rust Compiler` |
| Subtitle (30) | `Write and run Rust offline` |
| Bundle ID | `com.sergiiziborov.Crabrix` |
| SKU | `crabrix-ios-001` |
| Primary category | Developer Tools |
| Secondary category | Education |
| Price | Tier for **$17.99** at launch, moving to **$24.99**. One-time, no IAP. |
| Age rating | 4+ — no objectionable content. Answer "None" to every content question. |
| Copyright | `2026 Serhii Ziborov` |

### URLs

| Field | Value |
| --- | --- |
| Marketing URL | `https://crabrix.com` |
| Support URL | `https://crabrix.com/support` |
| Privacy Policy URL | `https://crabrix.com/privacy` |

## Promotional text (170)

> Now with 83 lessons, tiered achievements from Bronze to Diamond, a health-and-energy
> system that rewards rank, Code Recall for memory training, and a global board.

## Description (4000)

```
Crabrix runs the real Rust compiler on your iPhone and iPad.

Not a sandbox that sends your code to a server. Not an interpreter written to
look like the real thing. Crabrix bundles an actual build of rustc and the Rust
standard library, and executes it on your device — with the same diagnostics and
the same error codes you get on a laptop.

Turn off Wi-Fi and it still compiles.

REAL COMPILATION, ON DEVICE
• A bundled build of the Rust compiler and standard library
• Real rustc diagnostics, with the error codes you can look up
• Your program runs in a sandbox with a memory cap and no network
• First builds do the work; identical repeat runs come from a local cache

A REAL PACKAGE MANAGER
• Add dependencies from crates.io by name and version
• Sparse index resolution, SemVer ranges, and feature unification
• SHA-256 checksums verified before anything is written to disk
• Every downloaded crate is readable inside the app, file by file
• Once fetched, a project rebuilds with the network off

AN EDITOR BUILT FOR A PHONE
• Rust syntax highlighting, line numbers, and no line wrapping
• Completion, a symbol jump list, and a keyboard row that fits your thumbs
• Multi-file Cargo projects, a file tree, and a project terminal
• Import from GitHub or Files, export as a package or a plain ZIP

LEARN RUST PROPERLY
• 83 lessons across six courses: from fn main to unsafe, FFI, and async
• Every lesson has a written explanation, a highlighted example, and a lab
  checked by the compiler in the app
• Interview preparation that goes past the language: memory, atomics,
  networking, databases, and distributed systems
• Quick Practice, Term Train, and Code Recall — all generated from the same
  curriculum, all scheduled with SM-2 spaced repetition
• Health and energy that scale with your rank, and training that never costs
  either, so there is always a way to keep going

RATING THAT MEANS SOMETHING
A successful run is scored on how much Rust actually changed since the last one.
Pressing Run on an untouched sample is not work, and Crabrix does not pretend
otherwise. Publish your rating to the global board if you want to — it is
optional, off by default, and needs no account.

NO ACCOUNT. NO SUBSCRIPTION. NO TRACKING.
Buy it once. There is no sign-up, no password, no advertising, no analytics
SDK, and no data sold to anyone. Your code never leaves your device.

WHAT IT CANNOT DO
The bundled compiler targets wasm32-wasip1 and has no native linker, so crates
needing C code, build scripts, or procedural macros generally cannot build on
device. Crabrix detects these and tells you, instead of failing halfway. There
is no debugger yet. Compilation is interpreted WebAssembly, so a first build is
slower than on a laptop.

Everything else compiles and runs, in your hand, offline.
```

## Keywords (100, comma separated, no spaces)

```
rust,compiler,rustc,cargo,crates,code,programming,ide,editor,learn,offline,wasm,develop,tutorial
```

## What's New (4000) — version 1.0

```
The first release of Crabrix.

A real Rust compiler on your iPhone and iPad, with a real crates.io package
manager, an editor built for a phone, and 83 lessons that check your work with
the compiler that ships in the app.

Everything runs on device. Everything works offline.
```

## App Privacy answers

Match `Crabrix/Resources/PrivacyInfo.xcprivacy` exactly.

| Question | Answer |
| --- | --- |
| Do you collect data from this app? | **Yes** — only through the optional leaderboard |
| Used for tracking? | **No**, for every type |
| Identifiers → User ID | Collected, **linked** to the user, not used for tracking. Purpose: **App Functionality**. The display name the reader types and a random key generated on device. |
| Usage Data → Product Interaction | Collected, **linked** to the user, not used for tracking. Purpose: **App Functionality**. Rating, lessons completed, lines changed, achievements, best Code Recall level. |
| Everything else | **Not collected** |

Say plainly in the review notes that this collection happens only after the
reader turns on "Publish my rating" in Profile, and that the same screen deletes
the entry.

## Export compliance

`ITSAppUsesNonExemptEncryption` is `false` in `Info.plist`.

Crabrix uses HTTPS (exempt) and SHA-256 to verify crate checksums. Hashing is
not encryption, and no proprietary or non-exempt cryptography is implemented.

## Review notes

```
Crabrix is a Rust development environment. No account is needed and nothing is
gated — all features are available immediately on launch.

TO SEE IT COMPILE
1. Projects → "Hello Rust" chip → Build tab → Run.
   The bundled compiler builds and runs it on device; output appears in Output.
2. Edit the string in main.rs and press Run again to see a fresh compile.

REGARDING GUIDELINE 2.5.2
Crabrix is an app designed to teach and develop code. The compiler and standard
library are bundled in the app, not downloaded. The only code downloaded at
runtime is Rust package source from the public crates.io registry, at the user's
explicit request, and it is used solely to build the user's own project inside
the app.

All such source is fully viewable in the app: Build → Packages → tap any
downloaded crate to browse every extracted file, with syntax highlighting. The
user's own source is fully viewable and editable throughout.

Programs execute inside a WebAssembly sandbox in the app's own process, with a
memory cap, no network access, and one writable directory. Crabrix spawns no
host processes; the "terminal" is a simulated shell over the in-app project
files only.

REGARDING USER-GENERATED CONTENT (1.2)
The only user-generated content is a display name on an optional leaderboard,
off by default. Names are filtered server-side for abuse and impersonation.
Reporting is available in the app (Learn → rating card → Report a name) and at
https://crabrix.com/support, and reported entries are removed.

REGARDING ACCOUNT DELETION (5.1.1v)
There is no account. The leaderboard entry a user can create is deleted from
inside the app: Learn → rating card → Profile → "Remove my entry from the
board".

CONTACT
support@crabrix.com
```

## Screenshots

Captured at exactly the sizes App Store Connect requires, ready to upload:

| Folder | Device | Size |
| --- | --- | --- |
| `docs/app-store/screenshots/iphone-6.9/` | iPhone 17 Pro Max | 1320 × 2868 |
| `docs/app-store/screenshots/ipad-13/` | iPad Pro 13-inch (M4) | 2064 × 2752 |

Upload order for the iPhone set, which tells the story in the right sequence:

1. `01-build` — the workspace, editor and build inspector
2. `03-learn` — Learn hub: rating, vitals, courses
3. `05-lesson` — a lesson with its highlighted example and the energy cost
4. `06-profile` — achievements, lifetime stats, the public board
5. `02-projects` — the dashboard with rating and vitals in the header
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

## Pre-submission checklist

- [x] `support@crabrix.com` delivers mail — Cloudflare Email Routing enabled on the zone, forwarding to the verified destination, with a catch-all so nothing to the domain is dropped
- [ ] Game Center capability enabled on the App ID, or the feature stays dormant
- [x] Screenshots captured at the two required sizes (`docs/app-store/screenshots/`)
- [ ] App Privacy answers entered to match the privacy manifest
- [ ] Export compliance answered
- [ ] Age rating questionnaire completed as 4+
- [ ] Review notes pasted from this file
