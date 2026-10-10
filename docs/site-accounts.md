# Website Academy accounts

## Access boundary

The public Blog and catalogue stay readable without login. Each lesson's guest
HTML and RSC response contain approximately its first 30% by visible word count.
The rest of the text, exercises, answer reveals and private media are rendered
only after checking the server-side session. `content/courses.json` and
`content/learn-media` are not served as public files. Google receives the same
preview as every other guest; JSON-LD identifies the registration requirement.

The native app still has no website login. CoursePack catalogue sequence 9 and
public GitHub release assets are unchanged. This website gate cannot hide that
separate public corpus or prevent someone who can read content from copying it.
Making native course delivery private would require a compatible app migration.

## Data and credentials

The server uses Node 24's SQLite driver. Account database, daily backups and
short-lived deletion fingerprints are outside every deployment image at
`/srv/apps/crabrix-site/accounts`. Container UID 1000 owns that directory.

Usernames are normalised to lowercase. Passwords use a unique salt and scrypt
N=131072, r=8, p=1 with at most two concurrent hashes per process. The fixed
`scrypt-v1` format represents these exact parameters; future parameter changes
must add a new format and a migration-on-login verifier. Session tokens have
256 bits of random entropy, recovery codes 160 bits. Only hashes are stored.
Cookies are `__Host-crabrix_session`, Secure, HttpOnly and SameSite=Lax in HTTPS
production. A session lasts at most 30 days. Password change and recovery revoke
other sessions and replace the one-time recovery code. Account deletion requires
the password and typed confirmation and removes credentials and sessions.

Server Actions enforce SITE_ORIGIN and short-lived hashed IP/username counters.
Accepted Terms version is stored on registration. The site requests no email,
name or payment details. It stores no lesson progress history. Account export
contains username and creation time, not credentials. No advertising or visitor
analytics is introduced.

## Backup and restore

`crabrix-accounts-backup.timer` runs the backup script daily in the live container.
SQLite `VACUUM INTO` makes a consistent snapshot while the app is running.
Snapshots expire after seven days. Day-based deletion ledgers avoid racing with
new deletion writes and expire after at most eight days. Files are restricted.
These backups protect against a bad release or accidental database change; they
are on the same host and do not provide disaster recovery for loss of that host.

To restore, stop the website first. Run the same image as a temporary container
with the same `/data` mount and execute:

```sh
node scripts/backup-accounts.mjs --restore accounts-<timestamp>.sqlite
```

The script reapplies the deletion ledger and revokes all sessions before the
website is restarted. Never overwrite a live SQLite database or omit the ledger.
A restored erased account must not regain access. The automated restore test
covers this case. Keep backups, recovery codes, session values and password
hashes out of Git and support logs.

## Retention and policies

The Crabrix Nginx route uses separate logs under `/var/log/crabrix/`, with daily
rotation and 14 retained days. Request bodies are not logged. Abuse counters
expire after 15 minutes. Expired sessions are pruned at sign-in and daily backup.
Website account Terms and Privacy are dated 10 October 2026 and explain this
separately from the app's local data and optional Game Center. Website accounts
are for users aged 16 or older; app operation remains account-free.

Policy references checked for the account changes:
[GDPR Articles 6 and 17](https://eur-lex.europa.eu/legal-content/eng/TXT/PDF/?uri=CELEX%3A32016R0679)
and the [ICO guidance on necessary authentication cookies](https://ico.org.uk/for-organisations/direct-marketing-and-privacy-and-electronic-communications/guide-to-pecr/cookies-and-similar-technologies/).
The policy's retention periods describe the configured service and backup jobs.

## Verification

Five automated tests pass: account lifecycle, expiry/rate limits, backup/restore,
blog length/images and all 742 previews. The browser test exercises guest HTML
and RSC withholding, direct media denial, registration/recovery code, secure
cookie flags, complete lesson access, account export, logout, login, recovery
and deletion. Six Rust article examples compile; the quantity-parser boundary
test passes with Rust 1.96.1. Release-specific Rust 1.99 facts were checked against
the official announcement; the article does not claim the bundled app compiler
has been updated to 1.99.
