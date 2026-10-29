# Interview Prep delivery — 29 October 2026

Interview Prep now contains 52 focused topics. All forty existing questions were
reviewed; twelve new topics cover interior mutability, Copy/Clone/Cow, UTF-8,
iterator ownership, closure traits, Pin/Future, Send futures, async lock scope,
async trait boundaries, typed errors, coherence and integer boundaries. Questions
include worked code, plausible alternatives, feedback and oral follow-ups.

The audit corrected a supposedly conflicting borrow that actually compiled,
Arc/Send/Sync bounds, Vec movement claims, HTTP/2 and quorum guarantees, and
idempotency assumptions. SQL/protocol/dependency snippets are identified as
contextual examples. OS-thread examples identify their desktop requirement.
The Send-bound async examples explicitly drop unpolled futures; their successful
execution does not claim those async bodies were polled.

The immutable, production-signed Interview 1.1.0 pack is published in catalog
sequence 16. In the app, open **Learn → refresh → Update** for Interview Prep.
The existing app can install it without replacing its binary. Old lesson IDs,
order and forty correct-answer positions are preserved; the native update test
also retains an already-open old course repository and its original bytes.
This is not a claim that every possible user progress state was exercised.

- [Public course](https://crabrix.com/learn/interview/)
- [Signed course release](https://github.com/sergii-ziborov/crabrix-courses/releases/tag/interview-2026-10-29)
- [Machine-readable delivery receipt](interview-prep-delivery-2026-10-29.json)
- [Native/content qualification](interview-prep-qualification-2026-10-29.json)

The website uses the same course source, with 154 Rust lessons plus 600 Atlas
steps. Production checks covered all 52 interview URLs, sitemap inclusion,
mobile/tablet/desktop widths, dark/light themes and no horizontal overflow.
All 52 course illustrations decode in the app; private lesson media remains
behind the existing website access rules.

Verification passed: 20 course-tool tests; 48 desktop compiler checks (42
successful programs and six intentional diagnostics); 35 website tests,
TypeScript and production build. Each phone/iPad Simulator passed 39 native
checks and one UI flow, including the signed update, tamper/replay rejection
and twelve new examples executed by the bundled offline WASM compiler. UI
captures were inspected, and the existing four editor tabs/source were retained.
These are Simulator results, not physical-device performance measurements.

The next app-code candidate separately adds structured compatibility reasons
and next steps in the existing preflight/terminal views. It passed the same
native gate but is **not included in signed 1.1.3 (120)**. Build 120 remains
WAITING_FOR_REVIEW; its TestFlight/review selection was not replaced.
[Candidate scope](compatibility-reasons-2026-10-29.md).

The full development plan remains open. Next work includes runtime
allocation/timeout/trap causality, compiler/procedural-macro candidate
qualification and the planned C/ABI prototypes. Physical performance needs
separate device qualification. This content release adds no backend execution,
automatic remote Run permission or main editor layout changes.
