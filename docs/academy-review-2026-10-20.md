# Academy review — 20 October 2026

The website snapshot and signed native course updates share authored course
commit `e0f3ead2a98e4fb8e08118ce27632a15516adc70`. The curriculum still contains
742 lessons: 142 Rust lessons and 600 Algorithm Atlas steps. All lesson IDs,
progress identities, native source code and existing user project copies are
preserved.

The snapshot records that authored revision. Commit
`fac40d1a3781c7017b246cf62b04c20381d94e72` additionally tracks the generated
Interview unit digests already present in both the signed archive and website
snapshot. All seven courses, every unit and all 742 lesson objects were compared
with that committed corpus and match exactly. No published archive bytes were
changed by committing the generated metadata.

## Corrections

| Course / lesson | Correction |
| --- | --- |
| Basics / Strings | Distinguish UTF-8 bytes, Unicode scalar values and grapheme clusters; explain checked string slices, decomposed accents and the limits of `chars().count()`. Revise the worked example, question, exercise, feedback and diagram together. |
| Basics / Number Types | Explain that lossy integer casts have defined conversion behavior and do not automatically constitute memory unsafety. Show fallible conversion when the destination cannot represent the value. |
| Basics / Operators | Explain configurable overflow checking and explicit checked, wrapping and saturating policies without treating debug/release defaults as universal guarantees. |
| Basics / Collections | Define the missing input, provide a complete HashMap counting example and explicitly sort its report. Explain `entry` accurately without claiming every modern get/insert sequence is a borrow error. |
| Basics / Control Flow | Declare the value consumed by the complete worked example. |
| Basics / Enums | Declare the message consumed by the worked example and clarify the exhaustiveness caption. |
| Systems / FFI | Use Rust 2024 `unsafe extern "C"`; explain the C `abs` precondition, desktop linking context and why `INT_MIN` is excluded. |
| Interview / Syscalls and Buffering | Remove the one-syscall-per-buffer promise and fixed cost ratio; provide complete checked output code, correct flush versus durability semantics and a replacement diagram. |
| Interview / dyn Trait vs Generics | Provide complete borrowed trait-object code, distinguish allocation from dispatch and enums from an open implementation set; correct the question and avoid fixed speed or binary-size rankings. |
| Interview / FFI ABI | Use Rust 2024 extern syntax; explain ABI, ownership, pointer validity and lifetime requirements; label a declaration fragment and its requirement for a matching linked implementation. Replace the diagram. |

The three replacement teaching images were generated with built-in ImageGen,
visually reviewed and retained at the original media identities required by
the pack schema. Prompts are preserved in the course repository's
`artwork/review-20261020/imagegen-prompts.json` and the app repository's
[prompt record](blog-image-prompts-2026-10-20.md).

## Review and test scope

- Structural review covered all 742 lessons: references to available images,
  answer indices, worked-example placeholders and search descriptions.
- A Rust 2024 compilation probe inspected all 142 Rust worked-example blocks.
  **108 compiled** in standalone or simple `fn main` wrapping context. The
  remaining 34 include the deliberate compiler-error lesson, Cargo/TOML,
  SQL/shell, multi-file examples, dependency-dependent examples and declaration
  fragments. A standalone `rustc` probe is not a pass/fail criterion for those
  contexts. This is not a claim that every lesson was manually executed.
- All eight CoursePack manifests validated and **14 course-tool tests passed**.
- All 742 website descriptions are readable and unique, without Markdown
  backticks. **Eleven site tests**, TypeScript checking and a production Next.js
  build passed.
- **Eleven complete programs** in the five new blog articles compiled and ran.
  Their prose has 1,551–1,685 words per article, excluding code, headings and
  captions. Every new article has two original generated images, including an
  analytical diagram, and primary Rust documentation links.

These checks identify specific fixes and verify the publication pipeline. They
do not certify that a 742-lesson curriculum contains no remaining pedagogical
or contextual issues.

## App delivery

[Release `course-updates-2026-10-20`](https://github.com/sergii-ziborov/crabrix-courses/releases/tag/course-updates-2026-10-20)
contains Basics **1.0.6**, Systems **1.0.5** and their descriptors.
[The follow-up release](https://github.com/sergii-ziborov/crabrix-courses/releases/tag/course-updates-2026-10-20.2)
adds Interview **1.0.6** with its descriptor and signed catalog sequence **13**. The other five catalog entries
are unchanged. Published assets were downloaded again and verified byte for
byte. Signing uses the existing production key identity `crabrix-course-2026-10`.

The application's actual, unchanged Swift verifier, compatibility logic and
update planner were compiled on macOS against the app's bundled public keyring.
They accepted all three public archives for app 1.1.1, selected exactly three
updates from the previous installed versions, rejected a repeated catalog
sequence and rejected a modified ZIP. This is a shared native-logic test,
not an iPhone UI installation test. No app binary or TestFlight release is
needed for these text and media updates.

In the app, open **Learn**, refresh and choose **Update** or **Update all**.
The installed course is replaced through the existing verified update path;
learning progress and edited projects are retained separately.

[Native release verification record](https://github.com/sergii-ziborov/crabrix-courses/blob/main/artwork/review-20261020/release-verification-followup.json)
records archive sizes, SHA-256 digests, source and native verification results.
