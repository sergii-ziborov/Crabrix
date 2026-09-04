# Launch assets

Everything that goes out on release day, written before release day so nothing
is drafted under pressure. Nothing here ships in the app; it is copy for the
App Store, Apple, and the places developers actually read.

The rule that governs all of it: **lead with the engineering, not with the
purchase.** The app is $9.99 up front, which means the technical story has to do
the work a free trial would otherwise do.

---

## Apple: featuring nomination

Submitted through App Store Connect. Apple asks for lead time, so this goes in
whether or not it can land on launch day.

**What the app is** (the field is short — this is the whole pitch):

> An independent developer project that bundles a real Rust compiler and builds
> crates.io dependencies locally on iPhone and iPad, with no cloud compilation
> service and no account. It combines a native programming environment, a
> 142-lesson Rust curriculum, and a 200-pattern algorithm course. User code
> never leaves the device.

**Why it is worth featuring**, in the order Apple's own guidance cares about:

- unusual platform engineering: a full compiler toolchain running inside an app,
  interrupted safely, with no JIT and no dynamic code loading;
- privacy as a build property, not a promise: no account, no analytics, no
  network path for user code;
- universal: the same workspace on iPhone and iPad;
- education: a curriculum whose exercises are checked by the compiler itself;
- solo developer, source publicly readable.

**Supplemental material to attach**: the 30-second demo, the architecture
article, the GitHub repository, and the release-evidence folder.

Do not write "best Rust IDE". Apple's editors decide that.

---

## Custom product pages

Three, each with its own screenshot order and its own audience. Referred
traffic converts better when the page answers the question the referrer raised.

### 1. Developer — for Hacker News, r/rust, the Rust forum

Headline: **Real Rust and Cargo on iPhone**

Screens: Build workspace → Packages with Link verified → Vendor & Edit diff →
E0502 diagnostic.

### 2. Learner — for r/learnrust and education posts

Headline: **Learn ownership from the real compiler**

Screens: Learn hub → a lesson with its quick check → E0502 repaired → profile
with rating and mastery.

### 3. Offline — for privacy and iPad audiences

Headline: **Rust without a cloud compiler**

Screens: runtime status → Pin for Offline → package source browser → Settings
showing the pinned toolchain.

---

## Show HN

Title:

> Show HN: I put rustc and crates.io dependency builds inside an iPhone app

Body — five short sections, no marketing voice:

1. **The problem.** Most Rust apps on iOS are either a learning shell or send
   the code to a server to compile. I wanted the whole loop local.
2. **The architecture.** rustc built for `wasm32-wasip1`, executed by WasmKit
   inside the app process; a Cargo-shaped resolver over the crates.io sparse
   index; dependencies compiled to rlib/rmeta on device and linked with
   `--extern`.
3. **What was actually hard.** Stopping `fn main() { loop {} }` in an
   interpreter that has no preemption. Feature unification and resolver
   differences. Making downloaded source completely viewable and editable to
   satisfy App Store guideline 2.5.2. Keeping package archives alive when iOS
   purges its caches.
4. **What it cannot do.** No proc macros, no build scripts, no native C, a slow
   first compile, no debugger.
5. **Links.** GitHub, App Store, the architecture article.

The App Store link goes last. HN forgives a paid app; it does not forgive a
pitch.

---

## r/rust

Title:

> I got real rustc + crates.io dependency builds running locally on iPhone/iPad

Open by saying it is my app and that a paid App Store link exists — then spend
the post on engineering. The parts this audience will actually argue about:
interruption, the resolver subset, artifact caching, and where the toolchain is
pinned. Answer every technical comment; do not defend the price.

## r/learnrust

Different post, different promise. Not architecture — teaching:

> I built the Rust learning environment I wanted on my phone. Feedback on the
> ownership path?

Show one lesson end to end: a real E0502, the hint after a wrong answer, the
repair, the compiler agreeing. Ask what is missing rather than announcing.

## Rust Users Forum — Announcements

The formal one:

> Announcing Crabrix 1.0 — a local Rust compiler and Cargo-shaped workspace for
> iPhone and iPad

Smaller audience, higher quality. Same honesty about limits.

---

## Video

**Hero, 30–45 seconds.** Airplane mode visible in the status bar the whole time.

| Time | Shot |
| --- | --- |
| 0–3s | iPhone, airplane mode, Crabrix open on the Build screen |
| 3–8s | Type a greeting, Run, output appears |
| 8–15s | Introduce a borrow error, Check, the real E0502 with its span |
| 15–24s | Add `smallvec = "1"`, resolve and build it |
| 24–31s | Open the downloaded source, Vendor & Edit |
| 31–37s | Pin for Offline |
| 37–45s | Card: Real Rust. Real Cargo. Local on iPhone and iPad. |

**Architecture, 5–8 minutes.** How rustc runs in an interpreter, how the
dependency pipeline works, and what breaks. This is the asset with a long tail:
it keeps being found months later, unlike a launch-day post.

---

## Articles

One per hard problem, each ending with a single line noting it is implemented in
Crabrix — never opening with it.

- Running rustc locally on iPhone with WebAssembly
- Building a Cargo-compatible crates.io pipeline on iOS
- How to stop `fn main() { loop {} }` inside a WebAssembly interpreter
- App Store guideline 2.5.2 for a programming environment
- Keeping package archives alive when iOS purges its caches

---

## Review codes

Up to 100 per version. Promo-code users cannot leave a rating, so these are for
coverage, not for stars. Send 15–25 personal notes — Rust newsletters, Rust and
iOS creators, educators — never a mailing list:

> I built an iPhone and iPad app that bundles rustc and builds crates.io
> dependencies locally. If that architecture is interesting to your audience I
> can send a free code and a short technical note.

---

## What not to do

- No "the first Rust compiler on iPhone" — it is not, and the claim invites
  someone to prove it.
- No lesson counts as the opening line. 742 steps is supporting evidence, not a
  hook.
- No asking for ratings in a launch post.
- No new features to chase a competitor's checklist.
