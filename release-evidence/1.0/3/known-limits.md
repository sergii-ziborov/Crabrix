# Crabrix 1.0 build 3 — what is proven, and what is not

Evidence for the 1.0 (3) candidate on `release/1.0-app-store`. Everything below
is either measured on this candidate's own tree or named as inherited from an
earlier one. Nothing here is carried over because it looked good in build 2.

## Proven on this candidate

- The fast release suite passes **390 tests, 0 failures**, built and run with
  **Xcode 26.6 (17F113), Swift 6.3.3** — the App Store-accepted release on this
  Mac, not the Xcode-beta 27.0 also installed here.
- A **Release archive** exists at `build/Crabrix-1.0-3.xcarchive`, 161 MiB,
  reporting `1.0 (3)`. It links no GameKit, carries no `GKLocalPlayer` string,
  and has the App Group on the app.
- The **programming-environment area** was re-measured from screenshots of this
  build: 72.9% of the screen on iPhone, 30.0% on iPad as the app opens, and
  66.2% for the largest arrangement the iPad layout permits. Every percentage in
  `programming-environment/area-measurement.json` is computed from the pixel
  rectangle printed beside it.
- **Store screenshots were recaptured** from a Release build of this tree on
  freshly erased simulators, at both required sizes.
- The new **Report a problem** screen is covered by unit tests: an empty report
  cannot be sent, the environment toggle removes the four detail lines, the
  `mailto:` draft survives newlines and `+`, and the device name is never
  attached.

## Not proven, and why

- **There is no App Store artifact yet.** `xcodebuild -exportArchive` fails here
  with *No Accounts / No signing certificate "iOS Distribution" found*: the
  distribution certificate is Apple-managed and needs an authenticated Xcode
  account session, and this Mac currently has no provisioning profiles
  installed. The archive above is development-signed with `get-task-allow=true`,
  which is normal for an archive and is **not** the shipping binary. Until the
  export runs, no IPA hash exists to record.
- **Report a problem has not been used on the physical phone.** The owner's
  testing predates it, and the build that contains it could not be installed on
  2026-09-06 because the device was not reachable. This is a short delta check,
  not a new matrix.
- **The bundled-compiler gate suite was not re-run on this commit.** Its last
  full pass (21 of 21) was on an earlier candidate; the compiler, runtime and
  package pipeline are unchanged since, but that is an inherited result and is
  counted as such.
- **App Store Connect state is unknown from here** — agreements, tax and bank
  details, App Privacy answers, the age questionnaire, the DSA trader
  declaration and which builds have been uploaded are all owner-side.

## Historical

The 1.0 (2) folder records a real `Apple Distribution` IPA with
`get-task-allow=false` and a zero-device Store profile. That export genuinely
happened, which is why the same export is expected to work again once the Xcode
account session is present — but the file it describes was deleted from
`build/export/` during a later rebuild and no longer exists on this Mac.
