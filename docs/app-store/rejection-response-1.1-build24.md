# Draft reply for the 4.3(a) rejection

Use this in the existing App Review submission
`67fcdbd6-987a-4865-ae9e-1726e08331a2` after the refreshed 1.1 (24)
metadata and screenshots are saved. The submission still shows Unresolved
Issues, even though its item now shows 1.1 (24); Apple's September 29 message
specifically says it reviewed 1.0 (8). This is a draft; it has not been sent.

> Hello App Review,
>
> Thank you for reviewing Crabrix. We have replaced the previously reviewed
> 1.0 (8) build with 1.1 (24) on the same app record and have substantially
> rebuilt the product. We would appreciate a fresh review of the current build
> under Guideline 4.3(a).
>
> Crabrix now has a complete, selectable Rust Academy. A new user chooses
> which of seven courses to download, sees each size, and can read installed
> material offline. The separate Code Examples download includes 46 open
> examples, each with a description, source preview, and editable project with
> README. Course progress and user projects persist independently of downloads.
>
> The native workspace supports multiple project files and nested folders,
> local Check/Run diagnostics, and supported Cargo dependencies. Compilation
> and execution happen on the device using a bundled Rust compiler, WASI
> sysroot, and our maintained WasmKit 0.4.1-derived runtime. There is no
> remote compiler, required account, or downloaded executable update.
>
> The revised interface brings project management, file navigation, Code,
> Problems, Output, and Terminal into a simpler flow. Appearance includes a
> full Cyberpunk theme, and optional local device authentication is available.
> Rating and achievements are stored locally; users can optionally enable
> Apple's Game Center sync. There is no Crabrix-hosted leaderboard.
>
> To evaluate the current experience: launch the app, open Projects and Run
> the starter project; then open Learn, download Rust Basics or Ownership,
> complete a lesson, and open its starter in Code. Download Code Examples to
> inspect any example and make an editable copy. The new screenshots show
> these flows. The compiler/runtime remain bundled even when courses are not
> downloaded.
>
> The app, Academy sources and packages, runtime fork, and source-pinned
> toolchain builder are public:
> https://github.com/sergii-ziborov/Crabrix
> https://github.com/sergii-ziborov/crabrix-courses
> https://github.com/sergii-ziborov/crabrix-runtime
> https://github.com/sergii-ziborov/crabrix-toolchain
>
> We have updated the version's Review Notes with the exact paths, delivery
> hosts, and privacy behavior. Please let us know if a particular remaining
> similarity needs clarification; the previous message did not identify a
> specific app or component for us to address.

The reply describes observed features only. It does not assert that changing
WasmKit alone resolves 4.3(a), guarantee approval, or claim a universal speed
ratio. Sending it and pressing **Submit for Review** are separate actions.
