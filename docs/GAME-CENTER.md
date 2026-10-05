# Optional Game Center

Crabrix keeps its rating, achievements, course progress, projects, and code on
the device. In Profile, the player can turn on Apple Game Center to share the
numeric rating with a global leaderboard and a selected set of achievement
milestones. This is off by default. No Crabrix account or Crabrix-hosted board
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
- Ten achievements: the local IDs and published English descriptions are in
  [`game-center-catalog.json`](game-center-catalog.json). The Game Center ID is
  `com.sergiiziborov.Crabrix.` plus the local ID, replacing `-` with `_` because
  App Store Connect does not accept a hyphen in an achievement vendor ID.

The local achievement catalogue has more milestones. Only the ten stable IDs
in `GameCenterService.achievementIDs` are submitted to Game Center; downloaded
course data cannot create Game Center achievements. The 1024px achievement
images are in `docs/app-store/game-center/` and can be rebuilt on macOS with
Pillow installed using `python3 scripts/render-game-center-badges.py`.

## Behavior and testing

When the player signs in after opting in, the app submits the current local
rating and earned selected achievements. Later local changes are coalesced and
submitted in order. The local store remains authoritative; a network error
never rolls back local points. The leaderboard uses best score, so a later
local reset cannot remove an old Game Center score. A new Game Center account
can receive the current local score when enabled; the app does not merge
progress or recover it from Game Center.

Simulator builds and App Store Connect configuration verify compilation and
metadata, not a real player session. Test on a signed physical TestFlight build:
opt in, authenticate, earn an achievement, open the leaderboard, turn Game
Center off, earn more points offline, and confirm local progress is unchanged.
Then opt in again and verify the score catches up. Check the signed archive's
embedded entitlement and the newly generated provisioning profile before
upload. Do not mark Game Center behavior verified until that device test passes.

The app privacy manifest and [site privacy policy](../site/privacy.html)
describe this Apple-hosted optional path. No source, project, answer, lesson
history, or personal photo is sent by Crabrix to Game Center.
