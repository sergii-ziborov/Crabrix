# Academy baseline export

`bash migration/export_legacy.sh` compiles and executes the existing Swift
curriculum models without launching the app or compiling student answers. It
writes `baseline-inventory.json`, the immutable semantic fixture for the
CoursePack migration.

The exporter uses lightweight signatures for app-only compiler/project types;
the course, lesson, Atlas, writing, depth, checks, sample-source, and project
gallery models themselves are the real production Swift sources. The fixture
records every field that the migration reads, plus per-object SHA-256 digests.

The baseline at source commit
`c38423e7503a56d6cd97e3a6c17651d5a5c33d62` contains 7 courses, 48 units,
742 lessons, 200 Algorithm Atlas patterns/challenges, 46 gallery projects, and
358 term pairs. Its integrity report has no ID collisions, missing writing, or
missing challenges. The complete authoring tree, deterministic CoursePacks,
signed catalog, and parity report live in
[crabrix-courses](https://github.com/sergii-ziborov/crabrix-courses).

The fixture contains authorial course/project content only. It contains no
user projects, progress, credentials, support correspondence, or App Store
material.
