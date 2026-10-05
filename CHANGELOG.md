# Changelog

## 1.1 (21) — 2026-10-04

- Add a parser-only Cargo feature profile when `syn`, `quote`, or `proc-macro2` is selected from the package catalog. The explicit manifest setting avoids the host-only `proc_macro` dependency on iPhone.
- Offer a one-tap repair for existing plain `syn` dependencies. Block incompatible package graphs before invoking rustc and show a readable dependency error in Output.
- Verify `syn 3.0.6` and its four-crate graph with a real bundled compiler Run on the iOS Simulator.

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
