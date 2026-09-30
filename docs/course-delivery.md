# Course delivery

The authored corpus, schema, exporter, parity report, and seven published 1.0.1 archives live in [crabrix-courses](https://github.com/sergii-ziborov/crabrix-courses). The app bundles the same signed packs as migration resources. Its public catalog URL is `https://raw.githubusercontent.com/sergii-ziborov/crabrix-courses/main/catalog.v1.json`; release descriptors and archives are served by GitHub Releases.

## Format and trust

The catalog and each descriptor use Ed25519 over the exact payload bytes with different domain prefixes. The built-in public keyring verifies them. Catalog entries name exact descriptor/archive hashes; the descriptor names the ZIP hash and version. Each ZIP manifest lists payload paths, lengths, and SHA-256 values, with no self hash. A repeated `(courseID, language, contentVersion)` with a new digest and a network sequence rollback are rejected.

`CoursePackVerifier` rejects extra or missing payload files, unsafe paths, links, path collisions, forbidden executable payload roles, excessive entries, and byte limits. `CourseInstaller` copies to same-volume staging, streams extraction with a second digest check, writes a journal, then atomically replaces the active-version index. Recovery retains the old pointer after an interrupted activation. Installed packs are under Application Support and excluded from backup as replaceable resources; user work is elsewhere.

The network client accepts the signed catalog from `raw.githubusercontent.com`. Archive transfers start at `github.com` and allow redirects only to `release-assets.githubusercontent.com` and `objects.githubusercontent.com`. It limits received bytes to the signed catalog size, verifies hashes, and keeps a resume record when URLSession supplies resume data. The current UI shows the archive size before an update, progress, Pause, and Retry/Resume. A transfer error leaves the prior course active. Catalog fetch is user initiated through **Check for course updates**.

## Offline migration

The previous binary is absent after an iOS app update. For that reason, all seven transition packs are resources of the new binary. Before the current progress store can write its schema, the app persists a first-launch decision from existing progress, lesson evidence, or project files. An existing learner gets all seven packs verified and activated locally without an old bundle lookup or network connection. A clean install activates Basics and lists the other six from the signed catalog for user-selected downloads. Already installed newer course versions are not downgraded. A lesson retains its content snapshot while open. Quick Practice, Code Recall, and Term Train snapshot only installed course content when a round starts; an update cannot change a question or answer mid-round.

Manage course downloads removes an installed copy from Application Support without deleting projects or progress. A one-time baseline activation marker prevents the next launch from silently reinstalling a course the user removed; a previously opened lesson retains its decoded content snapshot. Guaranteed resumable transfers on every URLSession cancellation and crash injection at every installation boundary are still pending. Progress counters and compiler fallbacks still use parts of the older Swift catalogs; they remain open migration tasks.
