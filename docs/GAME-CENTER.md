# Game Center

Crabrix has no accounts of its own — no password to store, no reset email to
send, no personal data to hold. Identity, achievements, and the global
leaderboard come from Game Center, which the player already has.

Everything in the app works signed out. Rating, achievements, vitals, and
progress are stored on the device and are the source of truth. Game Center adds
a verified display name, a photo, and a global board on top of that.

## Current state

The code is in place (`Crabrix/Social/GameCenterService.swift`) and reports
`unavailable` at runtime, because the entitlement is not yet on the profile:

```
error: Provisioning profile "iOS Team Provisioning Profile:
com.sergiiziborov.Crabrix" doesn't include the Game Center capability.
```

The app handles that path deliberately: `GameCenterService.status` becomes
`.unavailable`, the Profile screen shows "Playing offline", and nothing else
changes.

## Turning it on

Needs a paid Apple Developer account, then:

1. In the developer portal, enable **Game Center** on the App ID
   `com.sergiiziborov.Crabrix`.
2. Add the entitlement to `Crabrix/Crabrix.entitlements`:

   ```xml
   <key>com.apple.developer.game-center</key>
   <true/>
   ```

3. In App Store Connect, create one leaderboard with the ID that
   `GameCenterService.leaderboardID` already uses:

   ```
   com.sergiiziborov.Crabrix.rating
   ```

   Type: classic, score format integer, sort high-to-low.

4. Create one Game Center achievement per entry in
   `CrabrixAchievementCatalog.all`. Achievements are tiered, so an id is
   `<family>.<tier>` with the tier as a number from 0 (Bronze) to 4 (Diamond) —
   `builds.0`, `builds.1`, … `recall-lines.4`.
   `GameCenterService.submitAchievements` reports percentages against those
   ids, so they must match exactly. Print the full list with:

   ```swift
   CrabrixAchievementCatalog.all.map(\.id)
   ```

Nothing in the app needs to change: `authenticate()` starts succeeding and the
Profile screen switches to the signed-in layout on its own.

## Why the in-app banner stays

`showsCompletionBanner` is `false` on every reported achievement. Crabrix draws
its own unlock animation (`AchievementCelebrationView`), which fires the moment
the achievement is earned locally — including offline, where Game Center has
nothing to say.
