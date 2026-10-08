# Changelog

## 1.1 (26) — 2026-10-08

- Bring the Duo editor header in line with My Projects: project name and in-file search stay visible without the old top tabs and close button. Keep the Code, Problems, Output, and Terminal tabs aligned above the keyboard in laptop and landscape layouts.
- Keep the terminal input focused when its tab opens, add a visible keyboard dismiss control, and show a clearer result for completed, empty, stopped, and failed runs.
- Add in-file search to the iPad editor header. Refresh iPhone, iPad, and Duo captures for the website, README, and App Store listing.

## 1.1 (24) — 2026-10-07

- Refresh the release build, App Store screenshots, documentation, and reviewer guidance for the 1.1 candidate. No app behavior changes from build 23.

## 1.1 (23) — 2026-10-05

- Map all 37 five-tier local achievement ladders to Game Center progress while retaining the ten earlier individual milestones. Game Center remains optional and off by default.

## 1.1 (22) — 2026-10-05

- Add an off-by-default Game Center switch to Profile. When enabled, the local rating can appear on Apple's leaderboard and ten selected milestones sync to Apple achievements.
- Keep local rating, course progress, projects, and achievements working when Game Center is off or unavailable. Changing the Apple player invalidates the submission cache.
- Include the Game Center entitlement in Release, configure its leaderboard and achievements for the existing Bundle ID, and refresh the privacy and tester documentation.

## 1.1 (21) — 2026-10-05

- Add a parser-only Cargo feature profile when `syn`, `quote`, or `proc-macro2` is selected from the package catalog. The explicit manifest setting avoids the host-only `proc_macro` dependency on iPhone.
- Offer a one-tap repair for existing plain `syn` dependencies. Block incompatible package graphs before invoking rustc and show a readable dependency error in Output.
- Verify `syn 3.0.6` and its four-crate graph with a real bundled compiler Run on the iOS Simulator.
- Keep the learner on step 2 after either quick-check answer and scroll to the feedback or hint. Add a compact rating and achievements link in the lesson header.
- Let project folders create nested Rust files, text files, and module folders from their own visible add menu. Reject file and folder path collisions.

## 1.1 (20) — 2026-10-03

- Show the full project-specific guide on each of the 46 Code Examples pages before the source preview. Four examples include original local diagrams with captions and alternative text.
- Offer newer signed Examples content from the installed Examples card when available; existing editable project copies remain separate from downloaded course material.
- Add the Ferris guide to the App Store screenshot set. The signed build 20 IPA and public CoursePack identities are recorded in the [release manifest](docs/releases/1.1-build20.json).

## 1.1 (19) — 2026-10-03

- Open installed courses and Code Examples from the card body. Swipe left or use the options menu to remove a downloaded pack after confirmation; progress and copied projects stay local.
- Replace the Academy's generic course symbols with original illustrated icons, and give Cyberpunk a darker amber-accented palette and angular panels.
- Make the project manifest summary open `Cargo.toml`, and shorten the New Project import button to Files while keeping iCloud Drive available through the system picker.

## 1.1 (18) — 2026-10-03

- Present the separately downloadable Code Examples pack as a path of 46 open examples. Each example has a short description, source preview, and Open in Code action. Examples do not have lesson answers, scores, or unlock steps.
- Keep the Projects, Learn, and Settings navigation visible on the path and example pages.

## 1.1 (17) — 2026-10-03

- Added the separate signed Examples CoursePack with 46 Rust projects and individual README files.
- Preserved editable project copies and progress when a downloaded pack is removed.

See [release manifests](docs/releases/) and [validation](docs/VALIDATION.md) for exact build identities and observed checks.
