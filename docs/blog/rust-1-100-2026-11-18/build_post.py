#!/usr/bin/env python3
"""Insert the 18 November 2026 Rust 1.100.0 article into site/content/posts.json.

Displayed Rust code is read from ./examples so the published blocks are exactly
the files that verify_examples.py compiles and runs with rustc 1.100.0.
Re-running replaces the article in place.
"""
import json
import math
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
POSTS = ROOT / "site/content/posts.json"
SLUG = "rust-1-100-never-type-dropguard-cargo-cooldowns"
IMG = "/images/blog/november-2026/rust-1-100"
ANN = "https://blog.rust-lang.org/2026/11/12/Rust-1.100.0/"


def example(name: str) -> str:
    return (HERE / "examples" / name).read_text()


def image(name: str, alt: str, caption: str) -> dict:
    return {"src": f"{IMG}/{name}.png", "alt": alt, "caption": caption, "width": 1536, "height": 1024}


sections = [
    {
        "heading": "Rust 1.100.0 arrived on 12 November",
        "paragraphs": [
            "The Rust team released Rust 1.100.0 on 12 November 2026. The round number is a coincidence of the six-week train, but the contents are unusually broad. The never type can finally be written anywhere a type is expected. The core of the allocator API is stable for Vec and Box. A new DropGuard type runs a closure on every exit path. On the Cargo side, the release reports unused dependencies, changes the layout of the build directory and adds dependency cooldowns, which hold back versions that were published too recently.",
            "Every Rust program below was compiled and run with rustc 1.100.0 (0ef1bc386 2026-11-09) on an aarch64 Mac, and the never-type examples also with Rust 1.99.0 to show what changed. Cargo observations come from small test packages resolved against crates.io. We separate the announcement's promises from our own observations and note where Crabrix does not have these features yet."
        ],
        "sources": [
            {"title": "Announcing Rust 1.100.0", "url": ANN},
            {"title": "Rust 1.100.0 release notes", "url": "https://doc.rust-lang.org/stable/releases.html#version-11000-2026-11-12"}
        ],
        "image": image(
            "cover",
            "An orange paper crab stands on a glowing 1.100 milestone surrounded by an exclamation mark, memory blocks, a lantern and a crate under an hourglass",
            "Original generated illustration: the four themes of Rust 1.100 around a 1.100 milestone, from the never type to Cargo cooldowns."
        ),
    },
    {
        "heading": "The never type gets a name everywhere",
        "paragraphs": [
            "The never type, spelled ! in code, is the type of a computation that never produces a value. Expressions such as return, break, a panic or std::process::exit have this type, and any code after them is unreachable. Because no value of type ! can exist, Rust lets it coerce into any other type. That is why a match arm can say None => return while the other arm produces a u32: the diverging arm fits whatever type the match needs.",
            "Programs have relied on that behaviour for years, and a function could already declare -> ! when it never returns. What was missing was naming it elsewhere: from 1.100 you can write Result<T, !>, use ! as an associated type, or put it in a generic argument, after ten years and five failed stabilization attempts. At the same time, std::convert::Infallible becomes an alias for !, so existing APIs that were written with Infallible accept it unchanged."
        ],
        "sources": [
            {"title": "Never type section of the announcement", "url": ANN + "#never-type"},
            {"title": "The never primitive type", "url": "https://doc.rust-lang.org/stable/std/primitive.never.html"},
            {"title": "Stabilize the never type project goal", "url": "https://goals.rust-lang.org/2026/stabilize-never-type.html"}
        ],
    },
    {
        "heading": "Use ! when one implementation cannot fail",
        "paragraphs": [
            "The most practical use of the never type is an interface with an error type where one implementation genuinely cannot fail. In the example, a Settings trait has an associated Error. Settings parsed from user text can be malformed, so that implementation uses String. Settings that are already in memory cannot fail to be read, so their Error is !. The generic theme function is written once and works with both.",
            "The payoff is at the call site. Because the error type is !, the pattern let Ok(current) = theme(&loaded) is irrefutable: the compiler knows the Err case cannot occur, so there is no unwrap and no unreachable branch to maintain. The text version still forces the caller to handle its error. Running the program printed loaded: dark followed by text error: line 2: expected key=value. Keep ! for errors that are truly impossible; a merely rare failure still deserves a real error type."
        ],
        "code": example("never.rs"),
        "codeLanguage": "rust",
        "sources": [
            {"title": "Infallible is now an alias for !", "url": "https://doc.rust-lang.org/stable/std/convert/type.Infallible.html"}
        ],
    },
    {
        "heading": "The fallback change that can break older editions",
        "paragraphs": [
            "Making Infallible an alias required one breaking change. When the compiler has to infer a type only from a diverging expression, it picks a fallback type. Editions 2015, 2018 and 2021 used (), while edition 2024 already used !. Rust 1.100 switches the older editions to ! as well. Most code never notices. The rare case the announcement mentions is discarding the result of a generic function whose type parameter is never named.",
            "We reproduced that case with a load<T: Default>() function called as load()?; in edition 2021. Rust 1.99 already rejected it through the deny-by-default lint dependency_on_unit_never_type_fallback and suggested load::<()>(). Rust 1.100 reports error E0277, the trait bound !: Default is not satisfied, with a note pointing to issue 148922. The fix is the same in both cases: name the type you are throwing away, as in the program below, which compiles and prints ran on 1.100.",
            "Dependencies are where this is most likely to surprise you. Cargo caps lints for registry dependencies, so a crate that triggered the old lint could still compile inside your build; with 1.100 the same code is a type error. The team sent fixes to affected public crates in advance, so first update the failing dependency rather than patching it locally. Expect a few new unreachable-code warnings as well."
        ],
        "code": example("fallback_fixed.rs"),
        "codeLanguage": "rust",
        "sources": [
            {"title": "Never type fallback in the 2024 edition guide", "url": "https://doc.rust-lang.org/edition-guide/rust-2024/never-type-fallback.html"},
            {"title": "Inference change tracking issue 148922", "url": "https://github.com/rust-lang/rust/issues/148922"}
        ],
    },
    {
        "heading": "Allocators for Vec and Box",
        "paragraphs": [
            "Rust 1.100 stabilizes the core of the allocator API. The Allocator trait is public and stable, together with the Global and System allocators that implement it. Vec gains new_in, with_capacity_in, allocator and the raw-parts constructors that carry an allocator. Box gains new_in, from_raw_in, from_non_null_in, allocator and the matching into_raw conversions. The trait is also implemented for &A, &mut A, Box, Rc and Arc of an allocator, so one allocator value can be shared by reference among several collections.",
            "The scope is deliberately narrow. Only Vec and Box accept a custom allocator on stable today; String, HashMap and the other collections are not part of this release. Replacing the allocator of a whole program is still done with the #[global_allocator] attribute, which is a separate mechanism. The announcement describes this as the foundation of the Allocators 1.0 project goal and expects more collections and pointer types to follow now that the trait design is settled."
        ],
        "sources": [
            {"title": "Allocator trait documentation", "url": "https://doc.rust-lang.org/std/alloc/trait.Allocator.html"},
            {"title": "allocator_api tracking issue", "url": "https://github.com/rust-lang/rust/issues/32838"},
            {"title": "Allocators 1.0 project goal", "url": "https://goals.rust-lang.org/2026/allocators-1.0.html"}
        ],
        "image": image(
            "infographic",
            "Infographic titled Rust 1.100 at a glance with four cards: never type, allocators, DropGuard and Cargo cooldowns",
            "Original generated infographic: the four headline changes of Rust 1.100 with one short summary each, from the never type to Cargo cooldowns."
        ),
    },
    {
        "heading": "Measure one workload with a forwarding allocator",
        "paragraphs": [
            "A good first custom allocator does not manage memory at all. The Meter type below forwards every request to System and only records what it saw. The implementation is an unsafe impl because the trait has a contract the compiler cannot check: a returned block must fit the requested layout and remain valid until it is deallocated. Forwarding to System keeps that hard part inside the standard library, while the counting code stays trivial.",
            "The collections borrow the meter, since &Meter is an allocator too. Our run printed 100 ids, label \"report\" and then calls 3, peak 408 bytes, live after drop 0 bytes. Those numbers are explainable: the Vec started with room for two u32 values, which is 8 bytes, then grew to 400 bytes for 100 ids, and the Box took 6 bytes. The peak of 408 bytes shows that during growth the new block was allocated before the old one was released. The Cell fields make the meter single-threaded; sharing it between threads would need atomics."
        ],
        "code": example("allocator.rs"),
        "codeLanguage": "rust",
        "sources": [
            {"title": "Vec::with_capacity_in", "url": "https://doc.rust-lang.org/stable/std/vec/struct.Vec.html#method.with_capacity_in"},
            {"title": "Box::new_in", "url": "https://doc.rust-lang.org/stable/std/boxed/struct.Box.html#method.new_in"}
        ],
    },
    {
        "heading": "DropGuard turns cleanup into a value",
        "paragraphs": [
            "Drop already gives Rust reliable cleanup: when a value goes out of scope its destructor runs, whether the function returned normally, left early through ?, or unwound from a panic. The friction is that using Drop for one function's cleanup means declaring a type and an impl block. core::mem::DropGuard, also available as std::mem::DropGuard, removes that ceremony. It takes a value and a closure, derefs to the value so you can keep using it, and runs the closure with the value when the guard is dropped.",
            "DropGuard::dismiss is the other half. It hands the value back without running the closure, which makes all-or-nothing operations easy: arm a rollback at the start, and dismiss it only after every step has succeeded. Note the call syntax. dismiss is an associated function, so you write DropGuard::dismiss(guard) rather than guard.dismiss(). The announcement explains that this avoids name collisions with methods of the wrapped value, which are reachable through DerefMut."
        ],
        "sources": [
            {"title": "DropGuard section of the announcement", "url": ANN + "#dropguard-run-a-closure-on-every-exit-path"},
            {"title": "core::mem::DropGuard", "url": "https://doc.rust-lang.org/stable/core/mem/struct.DropGuard.html"}
        ],
        "image": image(
            "dropguard",
            "Diagram titled DropGuard every exit path: return Err and question-mark errors pass a lantern labelled guard runs roll back, success passes DropGuard dismiss",
            "Original generated diagram: early returns and ? errors run the guard and restore the shelf; DropGuard::dismiss on success keeps the changes."
        ),
    },
    {
        "heading": "A rollback that covers early returns and ?",
        "paragraphs": [
            "The example stocks a shelf from entries written as name:count. It records the current length, then wraps the shelf in a guard whose closure truncates back to that length and writes a log line. Inside the loop there are two ways to fail: an entry without a colon returns early with Err, and a count that is not a number fails through ?. Neither exit path needs its own cleanup code. Only after the whole batch has been accepted does the function dismiss the guard and keep the new items.",
            "The run printed Ok(2) for the valid batch, then an error for rivets, which has no count, and an error for pins:many, which has an invalid digit. The shelf still held exactly bolts and nuts, and the log read stocked 2 followed by two rolled back entries. Keep guard closures short and make sure they cannot panic, because a panic while another panic is unwinding aborts the process. Also remember that std::mem::forget on a guard is safe and skips the closure, so unsafe code must not rely on a DropGuard running to stay sound."
        ],
        "code": example("dropguard.rs"),
        "codeLanguage": "rust",
        "sources": [
            {"title": "Rust means never having to close a socket", "url": "https://blog.skylight.io/rust-means-never-having-to-close-a-socket/"}
        ],
    },
    {
        "heading": "conjure_zst is a tool for unsafe code",
        "paragraphs": [
            "`std::mem::conjure_zst` gives unsafe code a sanctioned way to create a value of a zero-sized type, replacing tricks such as transmuting `()` or calling `MaybeUninit::uninit().assume_init()`. It is unsafe because zero-sized types often act as proof tokens: PyO3's `Python<'py>` marker, the announcement's example, represents holding the Python interpreter lock, and conjuring one would let safe code skip that requirement. Application code rarely needs it. In review, treat a call like a transmute that must carry a safety comment."
        ],
        "sources": [
            {"title": "std::mem::conjure_zst", "url": "https://doc.rust-lang.org/stable/std/mem/fn.conjure_zst.html"},
            {"title": "Unsafe code guidelines", "url": "https://github.com/rust-lang/unsafe-code-guidelines"}
        ],
    },
    {
        "heading": "Cargo reports unused dependencies",
        "paragraphs": [
            "Unused dependencies cost build time, and rustc's unused_crate_dependencies lint was never a good fit under Cargo, because one dependencies table serves every target in a package. Cargo 1.100 now performs the check itself and warns about a dependency that no built target uses. The warning is part of a new linting system configured in the [lints.cargo] table of Cargo.toml, which completes the Cargo lints project goal.",
            "In our test package a path dependency that main.rs never referenced produced warning: unused dependency `helper` with the manifest line underlined, exactly as in the announcement. With unused_dependencies set to deny, as below, the build failed with could not finalize `app` (manifest). Running cargo check --bin app printed nothing, which matches the documented limitation: the lint appears only when every target that may use the table is built. Dev-dependencies are never reported. Check a full build, move platform-specific crates to target-specific tables, and switch CI to deny only once the list is clean."
        ],
        "code": "[lints.cargo]\nunused_dependencies = \"deny\"\n",
        "codeLanguage": "toml",
        "sources": [
            {"title": "Cargo lints reference", "url": "https://doc.rust-lang.org/stable/cargo/reference/lints.html"},
            {"title": "Cargo lints project goal", "url": "https://goals.rust-lang.org/2026/cargo-lints.html"}
        ],
    },
    {
        "heading": "The build directory has a new layout",
        "paragraphs": [
            "Cargo compiles everything in the build directory and then copies final artifacts into the target directory. Different configurations, such as other feature sets, produce different copies that are kept apart by a configuration hash, but that hash was not applied consistently. Rust 1.100 organizes the build directory by build step instead of file type and moves the hash from file names into parent directories. That removes extra and missed rebuilds, especially when git worktrees share a build directory.",
            "We saw the effect immediately. After a debug build of a package with serde_json, target/debug/deps no longer existed. Dependency outputs lived under target/debug/build/<package>/<hash>/, for example target/debug/build/serde_json with three hash directories, while the final binary was still copied to target/debug/cool. Scripts that globbed target/debug/deps for rlib files or parsed hashed file names will break. Read artifact paths from cargo build --message-format=json instead, and check cargo issue 17287 if a workaround of yours is affected."
        ],
        "sources": [
            {"title": "Reducing Cargo cache collisions", "url": ANN + "#reducing-cargo-cache-collisions"},
            {"title": "Call for testing: build-dir layout v2", "url": "https://blog.rust-lang.org/2026/03/13/call-for-testing-build-dir-layout-v2/"},
            {"title": "cargo issue 17287", "url": "https://github.com/rust-lang/cargo/issues/17287"}
        ],
    },
    {
        "heading": "Dependency cooldowns with min-publish-age",
        "paragraphs": [
            "Malicious versions of crates are often caught within hours or days of being published, by automated scanners or by the community. Rust 1.100 stabilizes publish-age aware resolution so you can wait out that window. Setting global-min-publish-age in .cargo/config.toml makes Cargo skip any version that is newer than the threshold and print what it held back. The idea is known more widely as dependency cooldowns.",
            "To see it clearly we used an exaggerated 90-day window on a package that depends on serde_json. Cargo printed Locking 11 packages to highest Rust 1.100.0 compatible versions as of 90 days ago, then lines such as Adding serde_json v1.0.151 (available: v1.0.154, published 38 days ago) and the same for itoa, syn and unicode-ident. Without the setting, the same manifest locked serde_json 1.0.154. A real policy would use a shorter window; the announcement's example uses three days."
        ],
        "code": "# .cargo/config.toml\n[registry]\nglobal-min-publish-age = \"3 days\"\n",
        "codeLanguage": "toml",
        "sources": [
            {"title": "Cargo min-publish-age section of the announcement", "url": ANN + "#cargo-min-publish-age-a-k-a-dependency-cooldowns"},
            {"title": "registry.global-min-publish-age", "url": "https://doc.rust-lang.org/cargo/reference/config.html#registryglobal-min-publish-age"}
        ],
        "image": image(
            "cooldown",
            "An orange paper crab with a clipboard guards a warehouse gate while new crates wait beside an hourglass and a calendar marked 3 days",
            "Original generated illustration: freshly published crates wait in a cooldown area before Cargo lets them through to the shelves."
        ),
    },
    {
        "heading": "Overrides last only until the next broad update",
        "paragraphs": [
            "Sometimes you need a new version immediately, for example a security fix. Asking for it with cargo update serde_json --precise 1.0.154 failed in our test with version 1.0.154 is too new (published 38 days ago, minimum age 90 days), and Cargo suggested the environment variable shown below. With CARGO_RESOLVER_INCOMPATIBLE_PUBLISH_AGE=allow the same command updated serde_json and recorded 1.0.154 in Cargo.lock.",
            "The detail worth knowing came next. A later plain cargo update, run while 1.0.154 was still inside the window, printed Downgrading serde_json v1.0.154 -> v1.0.151. The override is kept in the lockfile, as the announcement says, but only until something re-resolves it. If your team uses overrides, write down why each one was made and avoid running a broad cargo update in the same change, or the urgent fix can quietly disappear again."
        ],
        "code": "# refused while the version is inside the window\ncargo update serde_json --precise 1.0.154\n\n# deliberate, one-off override\nCARGO_RESOLVER_INCOMPATIBLE_PUBLISH_AGE=allow \\\n  cargo update serde_json --precise 1.0.154\n\n# a later broad update re-resolves and can downgrade it again\ncargo update\n",
        "codeLanguage": "shell",
        "sources": [
            {"title": "cargo update reference", "url": "https://doc.rust-lang.org/cargo/commands/cargo-update.html"}
        ],
    },
    {
        "heading": "What a cooldown does not do",
        "paragraphs": [
            "A cooldown depends on the registry recording when each version was published. Versions without a pubtime field in the index are never held back. cargo install ignores the minimum age for the installed crate and its dependencies, so pin an exact version with cargo install foo@1.2.3 when that matters. Most importantly, the announcement is explicit that cooldowns reduce the risk of some supply-chain attacks but are not a complete defense. Reviewing dependency updates is still part of the job.",
            "Choosing the window is a trade-off: a longer cooldown gives scanners more time but delays legitimate fixes. A few days plus a written override rule is a reasonable start. The crates.io supply chain hardening goal plans quarantine support and automated detection of suspicious releases."
        ],
        "sources": [
            {"title": "crates.io supply chain hardening project goal", "url": "https://goals.rust-lang.org/2026/crates-io-supply-chain-hardening.html"}
        ],
    },
    {
        "heading": "Smaller APIs that remove helper code",
        "paragraphs": [
            "The list of stabilized APIs is long, and several entries replace helpers that many projects write themselves. str::trim_prefix and trim_suffix behave like strip_prefix and strip_suffix but return the input unchanged when the affix is absent, instead of an Option. Slices and Path have the same pair; Path::trim_prefix works on whole components, so crates/report/src/lib.rs became report/src/lib.rs in our run. Vec::from_fn builds a vector from each index, and bool::toggle flips a flag in place.",
            "Box::map, Rc::map and Arc::map transform the wrapped value, and the documentation says Box::map reuses the allocation when possible; like dismiss, they are associated functions. Box::take moves the value out while keeping the allocation for reuse. Once now implements Default, UnsafeCell gains replace and unchecked reference accessors, and Windows code gets CommandExt::show_window and ChildExt::main_thread_handle. The program printed 1.100.0, then 1.99.1 unchanged, the trimmed path, [0, 1, 4, 9, 16], dark mode: true and 70.7."
        ],
        "code": example("small_apis.rs"),
        "codeLanguage": "rust",
        "sources": [
            {"title": "str::trim_prefix", "url": "https://doc.rust-lang.org/stable/std/primitive.str.html#method.trim_prefix"},
            {"title": "Box::map", "url": "https://doc.rust-lang.org/stable/std/boxed/struct.Box.html#method.map"},
            {"title": "Vec::from_fn", "url": "https://doc.rust-lang.org/stable/std/vec/struct.Vec.html#method.from_fn"}
        ],
    },
    {
        "heading": "An upgrade order for existing projects",
        "paragraphs": [
            "Upgrade in small, separate steps so each failure has one cause. First record the toolchain you use today and switch to 1.100 without touching the manifest. If a dependency fails with a never-type error, update that dependency on its own. Then build every target and run the tests, read the new unused-dependency warnings and fix scripts that depended on the old build directory. Adopt a cooldown last, in its own change, because it alters how every later update resolves. Separate commits keep a regression easy to bisect."
        ],
        "code": "rustc -V && cargo -V            # record the current toolchain\nrustup update stable\ncargo build --all-targets        # never-type errors, unused dependencies\ncargo test\ncargo build --message-format=json > artifacts.json  # paths for scripts\n",
        "codeLanguage": "shell",
        "sources": [
            {"title": "Install and update Rust", "url": "https://www.rust-lang.org/tools/install"}
        ],
    },
    {
        "heading": "Crabrix and Rust 1.100",
        "paragraphs": [
            "Be aware of one limit if you practise with Crabrix. The iPhone and iPad app and the browser Playground run a source-built compiler that reports Rust 1.96.0-dev for wasm32-wasip1. Writing ! as a type there fails with error E0658, the ! type is experimental, which is the same error we got from Rust 1.99. DropGuard, the Allocator trait and the new trim methods are not available either, and Crabrix's own package preparation does not read global-min-publish-age. Use a desktop 1.100 toolchain to try these features.",
            "The underlying ideas still work in Crabrix today. Diverging expressions already coerce, so match arms that return or panic behave as described above. Infallible remains available for error types that cannot occur, and a small struct with a Drop implementation gives the same rollback behaviour as a DropGuard. Code written that way keeps compiling on newer releases."
        ],
        "links": [
            {"title": "Technology and compiler limits", "url": "/technology/"},
            {"title": "Playground", "url": "/playground/"}
        ],
    },
    {
        "heading": "Next on nightly: a parallel front end",
        "paragraphs": [
            "Four days after the release, on 16 November, the compiler team announced that the parallel front end, which covers type checking and borrow checking, is enabled by default on nightly since nightly-2026-11-14, initially with two threads. In their benchmarks, checking some single crates such as nalgebra, cargo or diesel was almost three times faster with eight threads, while a whole-graph cargo check of the cargo crate went from 36.7 to 30.8 seconds, because Cargo and LLVM already keep the cores busy.",
            "Stable still uses the sequential front end. On nightly, `-Zunstable-options --jobs-frontend=N` changes the thread count and `--jobs-frontend=1` opts out. Diagnostics may appear in a nondeterministic order, and the team asks for crash and reproducibility reports before stabilization."
        ],
        "sources": [
            {"title": "Enabling the parallel frontend on nightly", "url": "https://blog.rust-lang.org/2026/11/16/enabling-parallel-frontend-on-nightly/"}
        ],
    },
    {
        "heading": "Summary",
        "paragraphs": [
            "Rust 1.100.0 names the never type, opens custom allocators for Vec and Box, turns scoped cleanup into a value and gives Cargo better build-hygiene and supply-chain tools. The main upgrade risk is the never-type fallback change in older editions. Update the compiler first, read what Cargo now reports, and adopt cooldowns as a deliberate policy."
        ],
        "sources": [
            {"title": "Full Rust 1.100.0 changes", "url": "https://github.com/rust-lang/rust/releases/tag/1.100.0"},
            {"title": "Cargo 1.100 changelog", "url": "https://doc.rust-lang.org/nightly/cargo/CHANGELOG.html#cargo-1100-2026-11-12"},
            {"title": "Clippy 1.100 changelog", "url": "https://github.com/rust-lang/rust-clippy/blob/master/CHANGELOG.md#rust-1100"}
        ],
    },
]


# Inline code: each phrase must occur; it is wrapped in backticks for the renderer.
INLINE = [
    ("spelled ! in code", "spelled `!` in code"),
    ("Expressions such as return, break, a panic or std::process::exit", "Expressions such as `return`, `break`, a panic or `std::process::exit`"),
    ("no value of type ! can exist", "no value of type `!` can exist"),
    ("say None => return while", "say `None => return` while"),
    ("produces a u32", "produces a `u32`"),
    ("could already declare -> ! when", "could already declare `-> !` when"),
    ("you can write Result<T, !>, use ! as an associated type", "you can write `Result<T, !>`, use `!` as an associated type"),
    ("std::convert::Infallible becomes an alias for !, so existing APIs that were written with Infallible", "`std::convert::Infallible` becomes an alias for `!`, so existing APIs that were written with `Infallible`"),
    ("a Settings trait has an associated Error", "a `Settings` trait has an associated `Error`"),
    ("so that implementation uses String", "so that implementation uses `String`"),
    ("so their Error is !. The generic theme function", "so their `Error` is `!`. The generic `theme` function"),
    ("Because the error type is !, the pattern let Ok(current) = theme(&loaded) is irrefutable: the compiler knows the Err case", "Because the error type is `!`, the pattern `let Ok(current) = theme(&loaded)` is irrefutable: the compiler knows the `Err` case"),
    ("so there is no unwrap and", "so there is no `unwrap` and"),
    ("Running the program printed loaded: dark followed by text error: line 2: expected key=value. Keep ! for", "Running the program printed `loaded: dark` followed by `text error: line 2: expected key=value`. Keep `!` for"),
    ("Making Infallible an alias", "Making `Infallible` an alias"),
    ("2021 used (), while edition 2024 already used !. Rust 1.100 switches the older editions to ! as well.", "2021 used `()`, while edition 2024 already used `!`. Rust 1.100 switches the older editions to `!` as well."),
    ("with a load<T: Default>() function called as load()?; in edition 2021", "with a `load<T: Default>()` function called as `load()?;` in edition 2021"),
    ("lint dependency_on_unit_never_type_fallback and suggested load::<()>()", "lint `dependency_on_unit_never_type_fallback` and suggested `load::<()>()`"),
    ("the trait bound !: Default is not satisfied", "the trait bound `!: Default` is not satisfied"),
    ("which compiles and prints ran on 1.100", "which compiles and prints `ran` on 1.100"),
    ("The Allocator trait is public and stable, together with the Global and System allocators", "The `Allocator` trait is public and stable, together with the `Global` and `System` allocators"),
    ("Vec gains new_in, with_capacity_in, allocator and", "`Vec` gains `new_in`, `with_capacity_in`, `allocator` and"),
    ("Box gains new_in, from_raw_in, from_non_null_in, allocator and the matching into_raw conversions", "`Box` gains `new_in`, `from_raw_in`, `from_non_null_in`, `allocator` and the matching `into_raw` conversions"),
    ("implemented for &A, &mut A, Box, Rc and Arc of an allocator", "implemented for `&A`, `&mut A`, `Box`, `Rc` and `Arc` of an allocator"),
    ("String, HashMap and the other collections", "`String`, `HashMap` and the other collections"),
    ("with the #[global_allocator] attribute", "with the `#[global_allocator]` attribute"),
    ("The Meter type below forwards every request to System", "The `Meter` type below forwards every request to `System`"),
    ("is an unsafe impl because", "is an `unsafe impl` because"),
    ("since &Meter is an allocator too. Our run printed 100 ids, label \"report\" and then calls 3, peak 408 bytes, live after drop 0 bytes.", "since `&Meter` is an allocator too. Our run printed `100 ids, label \"report\"` and then `calls 3, peak 408 bytes, live after drop 0 bytes`."),
    ("room for two u32 values", "room for two `u32` values"),
    ("The Cell fields make", "The `Cell` fields make"),
    ("left early through ?, or unwound", "left early through `?`, or unwound"),
    ("core::mem::DropGuard, also available as std::mem::DropGuard, removes", "`core::mem::DropGuard`, also available as `std::mem::DropGuard`, removes"),
    ("DropGuard::dismiss is the other half", "`DropGuard::dismiss` is the other half"),
    ("so you write DropGuard::dismiss(guard) rather than guard.dismiss()", "so you write `DropGuard::dismiss(guard)` rather than `guard.dismiss()`"),
    ("reachable through DerefMut.", "reachable through `DerefMut`."),
    ("returns early with Err, and a count that is not a number fails through ?.", "returns early with `Err`, and a count that is not a number fails through `?`."),
    ("The run printed Ok(2) for the valid batch, then an error for rivets, which has no count, and an error for pins:many,", "The run printed `Ok(2)` for the valid batch, then an error for `rivets`, which has no count, and an error for `pins:many`,"),
    ("the log read stocked 2 followed by two rolled back entries", "the log read `stocked 2` followed by two `rolled back` entries"),
    ("that std::mem::forget on a guard", "that `std::mem::forget` on a guard"),
    ("rustc's unused_crate_dependencies lint", "rustc's `unused_crate_dependencies` lint"),
    ("in the [lints.cargo] table of Cargo.toml", "in the `[lints.cargo]` table of `Cargo.toml`"),
    ("that main.rs never referenced produced warning: unused dependency `helper` with", "that `main.rs` never referenced produced `warning: unused dependency helper` with"),
    ("With unused_dependencies set to deny, as below, the build failed with could not finalize `app` (manifest). Running cargo check --bin app printed nothing", "With `unused_dependencies` set to `deny`, as below, the build failed with `could not finalize app (manifest)`. Running `cargo check --bin app` printed nothing"),
    ("target/debug/deps no longer existed. Dependency outputs lived under target/debug/build/<package>/<hash>/, for example target/debug/build/serde_json with three hash directories, while the final binary was still copied to target/debug/cool. Scripts that globbed target/debug/deps for rlib files", "`target/debug/deps` no longer existed. Dependency outputs lived under `target/debug/build/<package>/<hash>/`, for example `target/debug/build/serde_json` with three hash directories, while the final binary was still copied to `target/debug/cool`. Scripts that globbed `target/debug/deps` for rlib files"),
    ("from cargo build --message-format=json instead", "from `cargo build --message-format=json` instead"),
    ("Setting global-min-publish-age in .cargo/config.toml makes", "Setting `global-min-publish-age` in `.cargo/config.toml` makes"),
    ("Cargo printed Locking 11 packages to highest Rust 1.100.0 compatible versions as of 90 days ago, then lines such as Adding serde_json v1.0.151 (available: v1.0.154, published 38 days ago) and the same for itoa, syn and unicode-ident. Without the setting, the same manifest locked serde_json 1.0.154.", "Cargo printed `Locking 11 packages to highest Rust 1.100.0 compatible versions as of 90 days ago`, then lines such as `Adding serde_json v1.0.151 (available: v1.0.154, published 38 days ago)` and the same for itoa, syn and unicode-ident. Without the setting, the same manifest locked serde_json 1.0.154."),
    ("Asking for it with cargo update serde_json --precise 1.0.154 failed in our test with version 1.0.154 is too new (published 38 days ago, minimum age 90 days), and", "Asking for it with `cargo update serde_json --precise 1.0.154` failed in our test with `version 1.0.154 is too new (published 38 days ago, minimum age 90 days)`, and"),
    ("With CARGO_RESOLVER_INCOMPATIBLE_PUBLISH_AGE=allow the same command updated serde_json and recorded 1.0.154 in Cargo.lock.", "With `CARGO_RESOLVER_INCOMPATIBLE_PUBLISH_AGE=allow` the same command updated serde_json and recorded 1.0.154 in `Cargo.lock`."),
    ("A later plain cargo update, run while 1.0.154 was still inside the window, printed Downgrading serde_json v1.0.154 -> v1.0.151.", "A later plain `cargo update`, run while 1.0.154 was still inside the window, printed `Downgrading serde_json v1.0.154 -> v1.0.151`."),
    ("avoid running a broad cargo update in the same change", "avoid running a broad `cargo update` in the same change"),
    ("without a pubtime field in the index", "without a `pubtime` field in the index"),
    ("cargo install ignores the minimum age", "`cargo install` ignores the minimum age"),
    ("with cargo install foo@1.2.3 when", "with `cargo install foo@1.2.3` when"),
    ("str::trim_prefix and trim_suffix behave like strip_prefix and strip_suffix but return the input unchanged when the affix is absent, instead of an Option. Slices and Path have the same pair; Path::trim_prefix works on whole components, so crates/report/src/lib.rs became report/src/lib.rs in our run. Vec::from_fn builds a vector from each index, and bool::toggle flips", "`str::trim_prefix` and `trim_suffix` behave like `strip_prefix` and `strip_suffix` but return the input unchanged when the affix is absent, instead of an `Option`. Slices and `Path` have the same pair; `Path::trim_prefix` works on whole components, so `crates/report/src/lib.rs` became `report/src/lib.rs` in our run. `Vec::from_fn` builds a vector from each index, and `bool::toggle` flips"),
    ("Box::map, Rc::map and Arc::map transform the wrapped value, and the documentation says Box::map reuses", "`Box::map`, `Rc::map` and `Arc::map` transform the wrapped value, and the documentation says `Box::map` reuses"),
    ("Box::take moves the value out", "`Box::take` moves the value out"),
    ("Once now implements Default, UnsafeCell gains replace and unchecked reference accessors, and Windows code gets CommandExt::show_window and ChildExt::main_thread_handle. The program printed 1.100.0, then 1.99.1 unchanged, the trimmed path, [0, 1, 4, 9, 16], dark mode: true and 70.7.", "`Once` now implements `Default`, `UnsafeCell` gains `replace` and unchecked reference accessors, and Windows code gets `CommandExt::show_window` and `ChildExt::main_thread_handle`. The program printed `1.100.0`, then `1.99.1` unchanged, the trimmed path, `[0, 1, 4, 9, 16]`, `dark mode: true` and `70.7`."),
    ("Writing ! as a type there fails with error E0658, the ! type is experimental, which", "Writing `!` as a type there fails with error E0658 (the `!` type is experimental), which"),
    ("does not read global-min-publish-age", "does not read `global-min-publish-age`"),
    ("Infallible remains available for", "`Infallible` remains available for"),
    ("a small struct with a Drop implementation gives the same rollback behaviour as a DropGuard", "a small struct with a `Drop` implementation gives the same rollback behaviour as a `DropGuard`"),
]
for old, new in INLINE:
    hits = [i for s in sections for i, p in enumerate(s["paragraphs"]) if old in p]
    assert len(hits) == 1, (old, len(hits))
    for s in sections:
        s["paragraphs"] = [p.replace(old, new) for p in s["paragraphs"]]

words = len(" ".join(p for s in sections for p in s["paragraphs"]).split())
post = {
    "slug": SLUG,
    "title": "Rust 1.100: the never type, DropGuard, allocators and Cargo cooldowns",
    "date": "2026-11-18",
    "publishedDate": "2026-11-18",
    "modifiedDate": "2026-11-18",
    "readingMinutes": math.ceil(words / 200),
    "summary": "Rust 1.100.0 stabilizes the never type, allocators for Vec and Box, DropGuard and Cargo cooldowns. Tested examples, the fallback break and an upgrade order.",
    "relatedSlugs": ["rust-1-99-upgrade", "rust-1-100-i686-windows-host-tools", "cargo-features-portable-dependencies"],
    "sections": sections,
}

posts = json.loads(POSTS.read_text())
posts = [p for p in posts if p["slug"] != SLUG]
posts.insert(0, post)
POSTS.write_text(json.dumps(posts, ensure_ascii=False, indent=2) + "\n")
print(json.dumps({"slug": SLUG, "proseWords": words, "readingMinutes": post["readingMinutes"],
                  "titleLength": len(post["title"]), "summaryLength": len(post["summary"]),
                  "sections": len(sections), "images": sum(1 for s in sections if "image" in s)}))
