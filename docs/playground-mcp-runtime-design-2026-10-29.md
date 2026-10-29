# Client-local MCP execution — implementation contract

This is the next, **unreleased** MCP phase after published bridge 0.1.1 and signed
app 1.1.3 (118). Existing eight source/selection tools remain compatible. Neither
the edit URL nor a participant name supplies execution permission. No published
capability changes until the browser/native/MCP matrix and signed delivery pass.

## Current qualification

Shared local-file/origin fixes are qualified in 26 native cases and queued as
build 119 from `853ea3e`; they do not enable remote execution. The candidate
wire codec now passes 13 Node tests and 38 phone/iPad Simulator tests, including
a real WebCrypto signature verified in CryptoKit. The reproducible production
Swift ↔ Node WebCrypto probe is `node scripts/test_playground_runtime_crypto.mjs`.
[Qualification receipt](playground-mcp-runtime-qualification-2026-10-29.json).
A shared canonical source serialization now matches in native JavaScriptCore and
WebCrypto, including exact Unicode bytes and source/entry/edition changes. It
excludes nonexecution origin metadata. NFC/case aliases, file-directory conflicts
and isolated UTF-16 surrogates are refused before native dictionary decoding; a
malformed old-peer Yjs snapshot leaves the current source unchanged.
Signatures, edit-capability HMAC, canonical scalar headers, payload byte limits,
expiry and bounded nonce replay are implemented. Permission, transient runtime
transport and isolated jobs remain unwired; bridge 0.1.1 still exposes eight
source/selection tools only. These candidate files are absent from signed 119.

## Required sequence

1. Preserve local-only `.cargo`, `vendor`, `node_modules`, `.github` and `target`
   text across Shared updates. Shared deletions still remove shared files.
   Validate the combined local budget before changing editor/storage. An invalid
   merge disconnects this client and retains its previous source. Initial imports
   remain separate source-only copies. Formatting/semantic/feature proposals check
   the filtered room budget independently of the complete local budget.
2. Implement a bounded signed-message codec in WebCrypto and CryptoKit, and test
   signatures/bytes both directions. Keep all signing keys ephemeral in RAM.
3. Add signed capability discovery and explicit local permission UI. Implement
   a controller-specific, room/client/operation/expiry-bound grant, default off.
4. Add isolated shared-source-only jobs, diagnostics/results and debugger control.
   Start returns an acknowledged job ID promptly; polling is separate, so the
   bridge's existing serial queue cannot put Stop behind a long-running Run.
5. Qualify official SDK ↔ actual browser ↔ two actual Simulator clients, including
   code/selections, cancellation, denial, expiry, stale source and spoof/replay.
   Then version/publish a new bridge; immutable 0.1.1 is never overwritten.

## Shared source and private local files

The native creator currently remains in its full original project. Private
package/configuration roots and opaque Git resources are outside the shared
document. Remote execution must use an independent ephemeral workspace made only
from the validated room document, bundled standard library and an explicitly
qualified immutable dependency profile. Never call the ordinary full-project Run
with unshared files/resources/overlays implicitly attached. No host environment,
Keychain, Git metadata, account files, package manager or host shell is exposed.

The initial remote execution profile can be std/local modules, with unsupported
Cargo requirements refused before compilation. Ordinary user-triggered local
Cargo/Run keeps its existing independent profile. No implicit acquisition by an
MCP operation, including browser toolchain acquisition; advertise unready status.

Remote results are source/room/job bound. They must not certify an ordinary saved
full-project build when private inputs were deliberately excluded. Label shared
execution within the existing Output surface, preserving four tabs, keyboard,
phone/iPad/Duo dimensions and ordinary local run/test/format behavior.

## Transport and authentication

Prefer the existing end-to-end encrypted transient presence channel, without
placing commands/results in the durable Yjs source tree. Its 4,000-byte decoded
limit stays fixed. Reserve up to 1,000 bytes for selection, keep a runtime field
below 2,400 UTF-8 bytes and a decoded message payload below 768 bytes. Measure
the complete encoded presence before publishing; never discard a selection to
make room. Page diagnostics/output instead of raising the room/source budget.

Native/Node/browser generate P-256 signing keys. Public keys use 65-byte X9.63
uncompressed form; fingerprints are SHA-256 of those bytes. Use SHA-256 ECDSA
with fixed 64-byte raw r||s signatures, not DER. Keys and grant state never enter
project files, snapshots, accounts, backups or logs. A signed presence assertion
is proof of key possession, not an Apple device attestation. Pair using the
device/controller fingerprint shown in the local permission interface.

Use a fixed ASCII-only JSON array for the signed header, for example:

```text
[protocol, kind, roomID, fromFingerprint, toFingerprint, requestID, operation,
 sourceRevision, jobID, nonce, issuedMs, expiresMs, payloadSHA256]
```

Identifiers/enumerations are bounded and canonical; integer times remain within
JavaScript's safe range. Payload is base64url UTF-8 JSON: sign its byte digest,
then parse its strictly bounded schema. This avoids cross-language dictionary
ordering and string-escaping disagreements. A separate common JS serialization
of validated room source supplies its revision; do not reuse locale-dependent
file sorting as a cross-language canonical form.

Commands carry a domain-separated HMAC-SHA256 proof using the room **edit access
capability**, bound to the signed header and signature. The AES room key alone
is insufficient because viewers also know it. The host must first confirm its
own access really is editable: use the existing authenticated, encrypted no-op
Yjs update and server acknowledgement. A URL's `mode=edit` fragment is not proof.
No-op role confirmation changes no source and needs no new backend execution or
room persistence. Confirm again for a new connection/access capability.

Only the explicitly granted controller key can operate the selected client.
Bind every command to room, target key, source revision, job and a short-lived
nonce. Maintain bounded replay protection keyed by request/nonce, not signature
bytes. Reject changed payloads, wrong rooms/targets, expired grants/commands,
unknown enums, oversized/deep objects and stale source before execution. Results
are signed by the selected target key and explicitly identify their source/job.

## Permission and job lifecycle

One controller grant per target initially; local UI selects allowed operations
and a short lifetime, no longer than the room. Grant UI explains that execution
uses room files only and that room participants can see shared output. No automatic
grant from an edit URL, source comment, MCP instruction or reported peer name.

Revoke on leaving/expiry/closure, app backgrounding, browser visibility loss,
project switch or explicit local action. Stop only the matching MCP-owned job;
never stop a later ordinary user build. Controller loss/lease timeout and grant
expiry cancel an owned job. Enforce a job deadline even when paused in Debug.
Source changes invalidate execution/results and stop the old owned job.

Start requires a free ready compiler, exact current source and no conflicting
local/Git operation. User local Stop always wins. Debug Step/Continue/breakpoints
require the matching paused owned job and allowed shared file/line. No arbitrary
watch evaluation or shell command. Failed checks, unsupported profiles, resource
limits and execution failures remain distinct.

Diagnostics/output are paged within the fixed payload budget, with explicit
truncation/next cursor. Shared file indices can replace long UTF-8 paths on the
wire; resolve them only against the exact signed source revision. Preserve valid
Unicode boundaries. Bound retained completed jobs/output and purge at revocation.

## Qualification gates

- WebCrypto ↔ CryptoKit raw key/signature vectors, wrong key/MAC, viewer
  capability, mode-fragment tampering, altered payload/room/source/job, expired
  nonce, replay and concurrent Stop.
- Malicious controller/name/presence cannot inherit another controller's grant.
- No grant, revoked/background/hidden/closed room, busy compiler or missing
  prepared profile does not start work or fetch anything.
- Unshared sentinel files/opaque resources are unreadable by remote Rust even
  when the creator's full native project retains them.
- Actual check/type diagnostics, compile-only Build (main untouched), Run/stdout,
  breakpoint/Step/Continue/Stop, source changes and Unicode selections across SDK,
  browser and both native clients. No guessed capability for old clients.
- Existing code edits, CAS, owner closure, default one-hour expiry, 4-participant
  limit, readonly roles, saving/reopen/export and four editor tabs still pass.

Primary references: [WebCrypto](https://www.w3.org/TR/WebCryptoAPI/#ecdsa),
[Node WebCrypto](https://nodejs.org/api/webcrypto.html),
[CryptoKit P256 public keys](https://developer.apple.com/documentation/cryptokit/p256/signing/publickey),
[CryptoKit raw signatures](https://developer.apple.com/documentation/cryptokit/p256/signing/ecdsasignature/init(rawrepresentation:)).
The implementation must verify actual cross-runtime vectors instead of assuming
compatible encodings from API names.
