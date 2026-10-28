# Privacy Policy

Updated: 2026-10-28 · [Website copy](https://crabrix.com/privacy/)

The app keeps your code on your device. Website Academy accounts use a username, password and private recovery code. This page explains both.

LAST UPDATED 27 OCTOBER 2026

**The short version.** Crabrix has no required account or in-app analytics SDK. Your code, projects, answers, and course progress stay on your device unless you explicitly export source or create/join a temporary encrypted Playground. If you switch on Game Center in Profile, Crabrix sends your numeric rating and achievement ladder progress to Apple for its leaderboard and achievements. It is off by default; The app has no online profile or board of its own; website Academy accounts are separate. Other network requests are requested course downloads, package discovery and downloads, repository imports, and optional encrypted Playground collaboration. If you write to support — including through *Report a problem* — that email reaches a person, and this page says what happens to it.

## Who is responsible

Crabrix is made by Serhii Ziborov, an independent developer. There is no company, no investor. Hosting providers receive ordinary requests for the public assets described below. Optional Playground sharing sends encrypted source to the relay; its decryption key stays with participants. Learning progress is not sent to the relay. Contact: [write to support](https://crabrix.com/support/).

## What stays on your device

These items are stored locally. Optional source sharing is described below; the numeric rating and achievement ladder progress are sent to Apple if you enable Game Center:

- **Your Rust code and projects** — files you write, import from GitHub, or open from the Files app.

- **Build output** — compiler diagnostics, program stdout and stderr, and cached build artifacts.

- **Learning progress** — lessons completed, answers, topic mastery, rating and achievements. Game Center receives the numeric rating and achievement ladder progress described below.

- **Preferences** — appearance, editor font size, and the rest of Settings.

- **Optional profile photo** — chosen through the system photo picker, processed and stored locally, and never uploaded by Crabrix.

- **Downloaded crates** — package sources and compiled artifacts, cached so a project rebuilds offline.

- **Installed CoursePacks** — lesson text, media, starter source, and checks, stored separately from your progress and projects.

Deleting the app removes its local container. Copies in Files, iCloud Drive or a device backup follow those storage settings. Unshared local projects have no Crabrix server backup; temporary encrypted rooms are not a backup and may expire or end early. Apple may retain Game Center scores and achievements already shared after you switch the feature off or delete Crabrix. Your code, projects, answers, and lesson history reach someone else only if you export or share them yourself.

## What leaves your device

### Temporary encrypted Playgrounds and interviews

Playground is a public feature without login. Unshared editor source stays in browser memory. Run and Check compile and execute on your device; there is no compilation service receiving your source. The browser downloads and may cache verified compiler assets separately from source. Only editor preferences are stored in browser local storage.

Creating or joining a shared Playground sends encrypted source snapshots, edits, participant names, cursors and selections to Crabrix over HTTPS. Clients use AES-256-GCM and keep the encryption key in the link fragment after #; the key is not included in HTTP requests to the relay. Anyone who has the complete edit link can decrypt, edit, run and copy the source; a view-only link permits reading, running and copying. Do not share secrets or private credentials.

The relay keeps bounded ciphertext only in process memory for the chosen lifetime, up to 24 hours from creation. Opening a link never renews it. Expired rooms are removed automatically; no source is written to an account, database, application log or source backup. A process restart can remove a room earlier. Connection addresses and ordinary HTTP metadata may appear in infrastructure access logs, but link fragments and decrypted source do not. Temporary hashed request counters protect the service against abuse.

There is no public room directory or account project library. Downloading or opening a room in Crabrix creates a separate local source copy, which remains on your device after link expiry and may follow your device backup settings. Other participants can also keep copies; expiry cannot recall those copies. Stop sharing or use the creator's End room action to remove relay access early. Live collaboration needs a connection; local compilation and a saved native project work without the relay.

### 1. Package discovery and downloads (crates.io)

When you search for or add a dependency, Crabrix talks to the crates.io registry over HTTPS: searches and package and owner metadata through the crates.io API, the sparse index at `index.crates.io`, and package archives at `static.crates.io`. Requests contain the search terms or package names needed for the action you asked for; Crabrix adds no account or device identifier. These services are operated by the Rust Foundation and its providers under their own privacy policies, and like any web service they receive normal connection information such as your IP address as part of serving the request.

### Browser package preparation (public npm registry)

When you explicitly run `npm install` or `npm ci` in a browser project, Crabrix requests package version metadata and integrity-checked source archives from `registry.npmjs.org` over HTTPS. Requests identify the imported package names and versions; project source, answers, learning progress, account credentials and a Crabrix device identifier are not uploaded. The registry receives ordinary connection information such as your IP address and may retain access logs under its own privacy policy. Prepared modules and licenses are saved as editable local project files. Browser Run and Check use those files without fetching dependencies. The WebKit preview blocks external requests from the project program.

### 2. Repository import and optional native Git (GitHub)

If you import a public repository, Crabrix downloads its archive from `github.com` over HTTPS. The request identifies the public repository or archive you selected; this public-archive importer carries no account credentials. GitHub is operated under its own privacy policy and, like any web service, receives normal connection information such as your IP address as part of serving the request.

In app versions that include native Git, local commits and history stay on your device until you explicitly export or push them. Clone and Fetch request the selected repository and Git objects from GitHub over HTTPS. Pull fetches before applying a clean fast-forward. Push uploads the committed branch and its reachable history to the selected GitHub repository, including any personal information or secrets you put in those commits. It does not upload uncommitted editor changes. These actions do not use a Crabrix compiler server.

Private repository access is optional. When you choose Save access on this device, the repository-scoped GitHub username and access token are stored in the device Keychain, accessible only while the device is unlocked and marked not to migrate or synchronize. They are sent only to the selected GitHub repository for authentication; they are not placed in project source, Git configuration, repository exports, Playground messages or application logs. Remove saved access deletes that Keychain entry. Revoking the token on GitHub is a separate action. GitHub handles repository contents and authentication under its own privacy policy. Local repository exports contain the complete Git history and worktree, so share them only with intended recipients.

### 3. Course downloads (GitHub)

The initial signed course list is included in the app. When you choose to download a course, Crabrix requests its signed descriptor and archive from `github.com` and GitHub's release asset hosts. The request identifies the selected course asset and carries no Crabrix account, tracking ID, project code, answers, or progress. GitHub and its delivery providers receive normal connection information, including your IP address, and may keep access logs under their own policies. Crabrix does not control those provider logs.

Other app content and import requests include: course downloads, package discovery, and public file downloads. As with any HTTPS request, the receiving service sees your connection, including your IP address; Crabrix itself adds no account or device identifier.

### 4. Optional Game Center (Apple)

Profile has an off-by-default Game Center switch. If you turn it on and sign in with Apple Game Center, Crabrix sends your numeric rating to Apple's global leaderboard and progress for all 37 achievement ladders and ten previously published individual milestones. Apple supplies the player identity and may display your Game Center name and photo in its own interface. Crabrix does not send source code, project files, lesson answers, detailed course history, or your locally chosen profile photo. It has no leaderboard or account server of its own. Turning the switch off stops later submissions from the app and leaves local progress intact; it does not erase scores or achievements Apple already holds. Manage that data through Apple's Game Center settings and privacy controls. Game Center is subject to [Apple's privacy policy](https://www.apple.com/legal/privacy/).

## Your privacy choices

In the app, Profile → Game Center switches future rating and achievement submissions on or off. Apple manages already submitted Game Center data through its own account and privacy controls. You can export your own projects before removing local data or deleting the app. The app does not register an Academy account for you.

For the separate website service, [Account](https://crabrix.com/account/) lets you sign out, change or recover your password, download your account details, or delete the account. Use [Support](https://crabrix.com/support/) for other access, correction or deletion requests. Website account deletion does not delete your app projects or progress.

## Website Academy accounts

The website at `crabrix.com` is hosted by Hetzner in Germany. Anyone can read the blog, course catalogue and approximately the first 30% of each lesson. A free website account opens the complete Academy. The iOS app does not require this account.

We store your username, salted password hash, hashed recovery code, account creation time and the version of the Terms you accepted. We store hashed session tokens and their expiry times so you can remain signed in for up to 30 days. Passwords and recovery codes are not stored in readable form. No email, real name or payment details are required. Do not choose a username containing sensitive personal information.

A necessary, first-party session cookie keeps you signed in. It is marked Secure, HttpOnly and SameSite=Lax in production. Signing out ends that session. Changing or recovering your password revokes your other sessions. We use no advertising cookies or third-party visitor analytics. Reading a lesson does not create a website progress history; your app progress remains on your device.

Ordinary server access logs include your IP address, time, requested URL, response status and browser information. They are rotated after 14 days. Short-lived abuse counters use hashes of IP addresses and usernames and expire after 15 minutes; the original values are not stored in those counters. Form bodies, passwords and recovery codes are not written to access logs.

Account data remains while your account exists. You can download your username and creation date and delete your account in [Account](https://crabrix.com/account/). Deletion removes the active account, credentials and sessions. Restricted daily database backups expire after seven days. Non-readable deletion fingerprints are kept for up to eight days so a restore does not resurrect an erased account. If a backup is restored, account deletions recorded after it was created must be reapplied before access is reopened.

Where the GDPR applies, providing the account and requested lesson access is necessary to perform our agreement with you. Basic server security and abuse prevention rely on our legitimate interest in keeping the service available and secure. Hetzner processes hosting data for us. We do not sell account information, use it for advertising, make automated decisions with legal effects, or send it to Apple for sign-in.

You may request access, correction, deletion, portability where applicable, restriction or object to processing based on legitimate interests. Contact the developer using the support link below. You can also complain to the data protection authority in your place of residence where applicable. Support will verify ownership before disclosing or changing account data. Without your password or recovery code, we cannot reliably establish ownership or restore access.

## Optional support correspondence

If you choose **Report a problem** in Settings, Crabrix composes the report on your device and opens it in your own mail app, or copies the text when you ask it to. The app sends nothing: no message exists anywhere until you press send in your mail app, and you can edit or discard the draft first.

When you do send it, I receive the address you send from and whatever you chose to include. The report contains what you typed and, unless you switch the toggle off, four lines of technical detail: the app version and build, your iOS version and hardware model (for example `iPhone14,4`), the bundled compiler version and target, and whether the toolchain is installed. Crabrix does not attach your project files, your source code, your device name, or any identifier unique to you or your install. Anything else in the message is there because you put it there — so please remove passwords, tokens and private source before sending.

Support messages are used to answer you and to fix the problem, and for nothing else: no advertising, no mailing list, no profiling. They are kept while the problem is being worked on and deleted once it is closed, apart from any de-identified technical note needed to keep the fix from regressing. Use [write to support](https://crabrix.com/support/) to ask for a copy of your correspondence, a correction, or its deletion. Your mail provider and mine handle delivery under their own terms.

A public [GitHub](https://github.com/sergii-ziborov/Crabrix) issue is a different, public channel: anything you post there is visible to everyone, so do not put secrets or private project code in one.

## What the iOS app does not have

There is no Crabrix account, proprietary leaderboard, online profile, or Crabrix progress server. Rating, ranks and achievements are calculated and kept on your device; optional Game Center sharing is described above. Your source code is never uploaded for compilation: the compiler runs inside the app.

Crabrix has no remote compiler or required account. It does not provide permanent server project storage or learning-progress synchronization. Optional Playground rooms retain bounded ciphertext temporarily, as described above. Public course files are delivered by GitHub and its asset hosts; their request logs are described above.

## What the iOS app does not do

- No tracking, in the App Store sense or any other. Your activity is not linked to data from other apps or websites.

- No advertising, no ad identifiers, no advertising networks.

- No third-party analytics, crash reporting, or attribution SDK. None is linked into the app.

- No selling of data or disclosure to advertisers. Source reaches other participants only through exports or encrypted sharing you choose.

- No broad photo-library access: the only photo Crabrix ever sees is the one you explicitly select as a local avatar through the system photo picker. No camera, microphone, location, contacts, or health permissions are requested.

- No reading of your code by anyone but you. It is compiled on your device by a compiler that ships inside the app, and it is never uploaded to compile it. The exception is the obvious one: code you export yourself, or paste into a support message.

## Children

The website account service is for people aged 16 or older. We do not knowingly create accounts for younger children. If you believe a child has created an account, contact support so we can investigate and remove it. The iOS app is a separate programming tool. The app has no account or public profile, and one user cannot see another's projects or progress. Public asset hosts receive ordinary request information as described above. Writing to support is optional and is an email the sender writes themselves.

## Legal basis and your rights

Where the GDPR applies: Crabrix keeps your projects, source code, and learning progress on your device. Public content providers and the website host may keep request logs under their own policies. Deleting the app removes its local copy; it does not erase logs already held by those providers.

Support correspondence is handled separately. If you write to me, I hold that email — your address and what you chose to send — as the controller, in order to answer you and fix the problem. The lawful basis is legitimate interest in supporting the software you bought; you can object at any time by asking me to delete the correspondence. You may ask for access, correction, a copy, or erasure of it: [write to support](https://crabrix.com/support/). Website account data is described above.

Retention: nothing the app stores is retained anywhere but on your device. Support emails are kept while the problem is open and deleted when it is closed, except for de-identified technical notes — a compiler version, a crate name, a stack shape — that carry no address and no personal detail.

## Changes to this policy

If Crabrix ever collects something new, this page will say so before that version ships, and the date at the top will change. The app's App Store privacy details are kept in step with this page.
