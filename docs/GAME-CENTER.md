# Optional Game Center

Crabrix keeps its rating, achievements, course progress, projects, and code on
the device. In Profile, the player can turn on Apple Game Center to share the
numeric rating with a global leaderboard and progress for every local
achievement ladder. This is off by default. No Crabrix account or Crabrix-hosted board
exists. Turning it off stops future submissions from this app; it does not
delete scores already held by Apple or alter local progress. Apple manages
Game Center identity and its data under its own terms.

The app's Release configuration compiles `CRABRIX_SOCIAL`, links GameKit, and
has the `com.apple.developer.game-center` entitlement. Authentication begins
only after the player opts in. A failed or unavailable Game Center connection
does not prevent lessons, compiler runs, or local scoring.

## Configured App Store Connect objects

- Existing Bundle ID: `com.sergiiziborov.Crabrix`.
- Game Center detail: `7575900e-ade8-462e-aa17-a1c9a7e18e9c`.
- Game Center app version for 1.1: `b2899c70-b327-4e45-b2b6-d5bd9bfb54a7`, enabled.
- Best-score, descending, global leaderboard: `com.sergiiziborov.Crabrix.rating`.
- 47 Game Center achievements are defined in
  [`game-center-catalog.json`](game-center-catalog.json): the ten individual
  milestones already published for build 22, plus one for each of the 37
  five-tier Crabrix achievement ladders. Game Center IDs use the
  `com.sergiiziborov.Crabrix.` prefix and replace hyphens with underscores.

Apple limits one game to 100 Game Center achievements. Crabrix has 185 local
tiers, so every local tier advances its family achievement by at least 20%.
A completed five-tier ladder completes its Game Center achievement. The ten
previously published individual milestones keep their IDs. Local badges and
rewards remain independent of Apple. New downloadable course data cannot
create Game Center achievements without an app and App Store Connect update.
The 1024px achievement images are in `docs/app-store/game-center/`; rebuild
them on macOS with Pillow using `python3 scripts/render-game-center-badges.py`.
The [publication inventory](app-store/game-center-publication-2026-10-05.json)
records all 47 App Store Connect IDs, localization IDs, releases, and verified
`COMPLETE` image states.

## Behavior and testing

When the player signs in after opting in, the app submits the current local
rating and achievement ladder progress. Later local changes are coalesced and
submitted in order. The local store remains authoritative; a network error
never rolls back local points. The leaderboard uses best score, so a later
local reset cannot remove an old Game Center score. A new Game Center account
can receive the current local score when enabled; the app does not merge
progress or recover it from Game Center.

Simulator builds and App Store Connect configuration verify compilation and
metadata, not a real player session. Test on a signed physical TestFlight build:
opt in, authenticate, earn tiers in a ladder, open Game Center achievements, turn Game
Center off, earn more points offline, and confirm local progress is unchanged.
Then opt in again and verify the score catches up. Check the signed archive's
embedded entitlement and the newly generated provisioning profile before
upload. Do not mark Game Center behavior verified until that device test passes.

The app privacy manifest and [site privacy policy](../site/privacy.html)
describe this Apple-hosted optional path. No source, project, answer, lesson
history, or personal photo is sent by Crabrix to Game Center.
