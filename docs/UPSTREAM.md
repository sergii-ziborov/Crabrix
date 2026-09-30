# Upstream and owned repositories

| Component | Repository and exact baseline | Relationship |
| --- | --- | --- |
| App | [Crabrix](https://github.com/sergii-ziborov/Crabrix), inventoried at `c38423e7503a56d6cd97e3a6c17651d5a5c33d62` | Native app, private commercial license terms despite public source. |
| Courses | [crabrix-courses](https://github.com/sergii-ziborov/crabrix-courses), 1.0.1 corpus | Author's content, separate content terms. |
| Runtime | [crabrix-runtime](https://github.com/sergii-ziborov/crabrix-runtime), fork of [swiftwasm/WasmKit](https://github.com/swiftwasm/WasmKit) 0.4.1 at `a0471eaee817c523b8023d8ebb1c70ff70b7950a` | MIT history, notices, and fork patches retained. |
| Toolchain builder | [crabrix-toolchain](https://github.com/sergii-ziborov/crabrix-toolchain), fork of [AngelOnFira/wasm-rustc](https://github.com/AngelOnFira/wasm-rustc) at `d7c1a08a60816ed824bb04f75fe79fa797996deb` | MIT builder history and component notices retained; no own release artifact yet. |

The app currently bundles Weblings `artifacts-test-7` as a pinned compatibility compiler. Public ownership of a fork does not erase upstream authorship or imply that this older artifact was built by Crabrix.
