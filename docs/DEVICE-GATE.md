# Physical-device gate for the Academy/runtime/toolchain migration

Simulator results are recorded in [VALIDATION.md](VALIDATION.md). Release acceptance for this change requires the exact candidate binary on a physical iPhone and iPad. Keep app source SHA, runtime revision, toolchain digest, signed catalog sequence, device/OS, and build configuration in the observation record. An App Store submission is a separate owner action.

## Academy path

1. Upgrade an installation with legacy progress while offline. The transition packs must activate from the new app bundle, and the prior course, progress, achievements, and projects must still open.
2. Cold install: Basics should open offline. The other six courses should be offered for size-confirmed download. Download Ownership and Algorithm Atlas, then check a representative language lesson and Atlas challenge against the signed 1.0.1 package data.
3. Check for updates. Show the archive size, cancel during download, relaunch, resume or retry, and confirm the old course remains readable until activation.
4. Open a lesson while an update activates. Its text, answer, validator, and starter project must remain tied to the original content version until that session closes.
5. Create a project from a starter, edit it, restart offline, update or remove course material, and confirm the project and attempt are still durable. Reinstallation must not award completion twice.
6. For a crate exercise, distinguish installed course data from offline-ready dependencies. Pin the exact Cargo graph, purge the ordinary package cache, and rebuild in airplane mode.
7. Repeat installation with network loss, disk full, and process kill at each activation boundary. Inspect the active index and installed tree after relaunch; a mixed version is a failure.

## Runtime and compiler path

1. Check a deliberately broken borrow sample and confirm structured E0502 with correct spans. Repair it and Run the emitted program.
2. Run a multi-file project, an active root feature, a real supported crate, offline pinned dependencies, and Vendor & Edit.
3. Stop a pure `loop {}` program and a running compile. Record stop latency, CPU return to idle, memory recovery, and an immediate successful second Run.
4. Exercise memory/table growth, output stress, malformed input, WASI path traversal, and writes/rename/unlink through supposedly read-only preopens. A host abort, filesystem escape, or unbounded compiler output is a failure.
5. Record cold first Check, warm changed Check/Run, cache hits, dependency builds, warning replay, and a series of unique revisions on the same toolchain. Separate compute-only from network-inclusive timings. Capture thermal state and peak memory.
6. Only after the source-built compiler exists, repeat the same compiler/Cargo corpus on the same runtime with that toolchain. Keep old and new toolchain identities separate.

## Current state

The new Academy reader, first-launch selection, public signed fetch, compiler read-only preopens, the user-program output quota monitor, runtime fuel/Stop, E0502 Check, and warning snapshot parity have Simulator evidence. A hard write-time bound for compiler stdout/stderr, clean own toolchain production, device measurements, and the interruption/crash matrix are still open. No physical gate is marked passed merely because its test procedure is written here.
