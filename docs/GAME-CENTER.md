# Game Center

**Not in Crabrix 1.0.** This document exists so the code behind
`Crabrix/Social/` is not mistaken for a shipping feature.

## What the production build contains

Nothing. The Release configuration is compiled without `CRABRIX_SOCIAL`, so
`GameCenterService` and `LeaderboardClient` are not in the binary at all. The
archived app links no GameKit, carries no board endpoint, and has no
display-name field or publishing control anywhere in the interface. A step in
`.github/workflows/release-checks.yml` fails the build if any of that returns:

```
otool -L Crabrix | grep -i GameKit          → must find nothing
strings Crabrix | grep crabrix.com/api      → must find nothing
strings Crabrix | grep GKLocalPlayer        → must find nothing
```

Rating, ranks, achievements, mastery and vitals are calculated and stored on the
device. There is no account, no display name, and no server that holds anything
about a player.

## Why the code is still here

Development builds define `CRABRIX_SOCIAL`, which compiles the two services and
their profile UI. That keeps the work reviewable and lets the tests exercise it,
while `CrabrixReleaseFeatures.gameCenterEnabled` and `.crabrixBoardEnabled`
remain `false` even there.

## What a future version would need before enabling it

- the Game Center capability on the App ID and the provisioning profile;
- a leaderboard and achievement catalogue configured in App Store Connect;
- App Privacy answers rewritten: publishing a score is data leaving the device,
  and the current answers say nothing leaves it;
- the privacy policy, the terms, and the support page updated **before** the
  version ships, not after;
- moderation for anything a player can type, if a display name ever exists.

Until all of that is true, the honest description of Crabrix is the one in the
app, on the site, and in the App Store listing: no account, no leaderboard,
nothing published.
