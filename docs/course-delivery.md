# Course delivery

The authored corpus, schema, exporter, parity report, and seven published 1.0.1 archives live in [crabrix-courses](https://github.com/sergii-ziborov/crabrix-courses). The app bundles the same signed packs as migration resources. Its public catalog URL is `https://raw.githubusercontent.com/sergii-ziborov/crabrix-courses/main/catalog.v1.json`; release descriptors and archives are served by GitHub Releases.

## Format and trust

The catalog and each descriptor use Ed25519 over the exact payload bytes with different domain prefixes. The built-in public keyring verifies them. Catalog entries name exact descriptor/archive hashes; the descriptor names the ZIP hash and version. Each ZIP manifest lists payload paths, lengths, and SHA-256 values, with no self hash. A repeated `(courseID, language, contentVersion)` with a new digest and a network sequence rollback are rejected.

`CoursePackVerifier` rejects extra or missing payload files, unsafe paths, links, path collisions, forbidden executable payload roles, excessive entries, and byte limits. `CourseInstaller` copies to same-volume staging, streams extraction with a second digest check, writes a journal, then atomically replaces the active-version index. Recovery retains the old pointer after an interrupted activation. Installed packs are under Application Support and excluded from backup as replaceable resources; user work is elsewhere.

The network client accepts the signed catalog from `raw.githubusercontent.com`. Archive transfers start at `github.com` and allow redirects only to `release-assets.githubusercontent.com` and `objects.githubusercontent.com`. It limits received bytes to the signed catalog size, verifies hashes, and keeps a resume record when URLSession supplies resume data. The current UI shows the archive size before an update, progress, Pause, and Retry/Resume. A transfer error leaves the prior course active. Catalog fetch is user initiated through **Check for course updates**.

## Offline migration

The previous binary is absent after an iOS app update. For that reason, all seven transition packs are resources of the new binary. First launch verifies and activates them locally; no old bundle lookup or network connection is required. Already installed newer course versions are not downgraded. A lesson retains its content snapshot while open.

The current implementation does not yet offer removal of downloaded material, a clean-install choice of individual baseline courses, guaranteed resumable transfers on every URLSession cancellation, or crash injection at every installation boundary. The older Swift catalogs remain in several ancillary features. Those are open migration tasks, not completed release gates.
