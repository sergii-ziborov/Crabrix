# Two open blog dates — October 2026

Requested editorial dates and original prose counts (code excluded):

| Date | Article | Prose words | Generated images |
| --- | --- | ---: | ---: |
| 25 October | Rust Serde and JSON: build a trustworthy data boundary | 2070 | 3 |
| 28 October | Rust Arc, Mutex and RwLock: shared state without surprises | 2078 | 3 |

These are original practical guides, not republished news. They fill the two
remaining editorial slots between the first blog date, 5 October, and 29 October.
The actual delivery date is 29 October. Existing article dates and prose remain;
two existing guides gain contextual links to the new articles.

Source content is in `site/content/posts.json`. Six PNG originals are under
`site/public/blog/rust-serde-json-*` and `site/public/blog/rust-shared-state-*`,
with full/card WebP delivery copies. The built-in image_gen tool generated every
original: see [exact prompts](image-prompts.json) and [asset hashes](image-assets.json).
Each guide has a conceptual infographic, cover and workshop illustration with
an orange crab. All outputs were visually inspected; no existing UI CSS changed.

Eight complete programs were formatted with rustfmt and executed on desktop
Rust 1.99.0, including invalid inputs, patch presence, enum round trips, streaming,
concurrent insertion, stale commit rejection, trait bounds and poison recovery.
[Verification](example-verification.json) records code hashes and observed output.
Run `python3 docs/blog/backfill-2026-10-29/verify-examples.py` from the repository;
the two recorded lockfiles constrain the verification dependency graph.
The deliberate caught panic may print through the default hook. No timing or
physical-iPhone compatibility claim is made. Serde derives require the qualified
procedural-macro profile; OS-thread examples are explicitly desktop examples.

Sources are linked beside the relevant discussion: official Serde attribute,
lifetime and enum references; serde_json 1.0.145 API documentation; the standard
Arc/Mutex/RwLock/Send/Sync/scoped-thread/ordering/channel references; and the
Tokio shared-state tutorial. Scenarios, examples, fixtures and explanatory prose
were written for these guides. No source article was copied or paraphrased as a
replacement for original writing.

Existing canonical, OpenGraph/Twitter, BlogPosting/breadcrumb, responsive image
and sitemap machinery applies to both posts. Every lesson/article URL was
matched against the local curriculum and public-style routes; browser checks
cover code highlighting, images, internal links, date metadata and overflow at
390/820/1440 widths with dark/light coverage. Delivery receipt records publication.
