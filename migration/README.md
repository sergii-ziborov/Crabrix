# Academy baseline export

`bash migration/export_legacy.sh` materializes the exact Swift curriculum
sources from the recorded historical Git commit, then compiles and executes
those models without launching the app or compiling student answers. It writes
`baseline-inventory.json`, the immutable semantic fixture for the CoursePack
migration. Run with a different output path to compare before replacing it.
The checkout must contain that historical commit; a shallow clone without it
will stop instead of exporting a different curriculum.

The exporter uses lightweight signatures for app-only compiler/project types;
the course, lesson, Atlas, writing, depth, checks, sample-source, and project
gallery models come from the exact pre-migration source tree. The current
Release app reads installed CoursePacks and does not compile the old gallery.
The fixture records every field that the migration reads, plus per-object
SHA-256 digests.

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

Current-tree parity tests compile the old Swift models in Debug. To run a
Release-optimized test bundle that still references those fixtures, pass
`'OTHER_SWIFT_FLAGS=$(inherited) -DCRABRIX_LEGACY_FIXTURES'` to `xcodebuild test`.
Production Release builds omit that condition and contain only the signed
CoursePack transition resources.
