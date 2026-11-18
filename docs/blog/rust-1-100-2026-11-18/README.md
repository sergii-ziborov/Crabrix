# Rust 1.100.0 article — 18 November 2026

`rust-1-100-never-type-dropguard-cargo-cooldowns` covers the Rust 1.100.0 release
(12 November 2026): the never type, the Allocator API for `Vec`/`Box`, `DropGuard`,
`conjure_zst`, Cargo unused-dependency reporting, the build-dir layout change and
`min-publish-age` dependency cooldowns, plus the 16 November nightly parallel front end.
About 2,660 prose words (paragraphs only), 19 sections, four generated images.

- `build_post.py` inserts the article into `site/content/posts.json`; Rust blocks are read
  from `examples/` so the published code is exactly what was verified.
- `verify_examples.py` compiles and runs every Rust block with rustc 1.100.0
  (0ef1bc386 2026-11-09, aarch64-apple-darwin) and checks that rustc 1.99.0 rejects `!`
  as a type with E0658. Results: `example-verification.json`.
- Cargo observations (unused-dependency warning/deny, `--bin` filter limitation, 90-day
  cooldown hold-backs, `--precise` refusal and override, a later `cargo update`
  downgrading the override, `target/debug/deps` gone) were made with Cargo 1.100.0 in
  `build/rust-1-100-cargo/` against crates.io on 18 November.
- Crabrix app and Playground compile with Rust 1.96.0-dev; the article says so and does
  not claim 1.100 features there.
- Images: `image-assets.json` (Figma `generate_image`, gpt-image-2.5-flare).
