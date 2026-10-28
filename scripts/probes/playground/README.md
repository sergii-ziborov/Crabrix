# Cross-client Playground verification

The relay must be running on localhost:3393 (`SITE_ORIGIN` must match).
Use the bundled Node runtime or Node 24. All test source, generated binaries,
room links and screenshots go under the ignored `build/playground-20261027/`.
No user project or account is used.

1. Install the locked site dependencies with pnpm; build the fixed native codec:
   `node scripts/build_playground_bridge.mjs`.
2. Compile the Swift transport probe, linking the same source used in the app:

   ```sh
   swiftc -parse-as-library CrabrixShared/PlaygroundLink.swift \
     Crabrix/Playground/Playground{Document,Codec,Encryption,RelayConfiguration,LiveSession}.swift \
     scripts/probes/playground/native-probe.swift \
     -o build/playground-20261027/native-probe
   ```

3. Run `node scripts/probes/playground/collaboration.cjs`. The local Playwright
   runtime path in the script may need replacing on another computer.
4. `CrabrixPlaygroundGate` is a real native UI test: another independent native
   engine creates a room; the app opens it, receives source/selection, sends
   UITextView edits back and runs the shared program with its bundled compiler.
5. `CrabrixBrowserPlaygroundGate` runs the complete page and compiler in iOS
   WebKit. It needs the same loopback server and no physical iPhone.

The CLI matrix proves encryption, document/selection compatibility and live
transport between independent Swift processes and browser contexts. It is not
an assertion that two physical devices, Universal Link production entitlements,
or every mobile keyboard layout have been tested. Inspect the actual xcresult
attachments and qualified verification record before publishing a release.

For the two actual app instances plus a browser, start `two-devices.cjs` and
wait for its READY message (loopback fixture port 3395 must return 200). Run
`PlaygroundTwoDeviceTests` concurrently on the iPhone and iPad QA Simulators
with `CrabrixTwoDevicePlaygroundGate`. Use separate `test-without-building`
commands and separate result bundles; the Xcode 27.1 RC multi-destination
finalizer stalled during the first attempt. The qualified phone and iPad
xcresults both passed; a selector for either hittable keyboard-dismiss button
handles the native iPad system accessory alongside the app's accessory.

`node scripts/probes/playground/api-security.mjs` checks the actual HTTP routes,
including four SSE participants, view-only access and owner deletion.

Set `CRABRIX_PLAYGROUND_ORIGIN=https://crabrix.com` to qualify the production
relay with the same matrix or two-app driver. The driver supplies this origin
to the Simulator UI runners, so native clients and the browser use the actual
HTTPS service. The UI gate requires the compiler to finish and checks exact
STDOUT, rather than matching a string still visible in source code.

`node scripts/probes/playground/publication.cjs` additionally verifies AASA,
the real native Output screenshot, sitemap exclusion of room URLs and a fresh
guest browser compilation. Initial toolchain transfer has an inactivity deadline;
received byte progress extends only loading, not compilation or program execution.

## Paired local debugger and URL gate (2026-10-28)

The coordinator drives two real Simulator apps and Chromium through the production encrypted relay. Each client compiles and runs locally. It checks source convergence, native selections in the browser, browser selections in native transport/canvases, String/Vec inspection, cancellation when shared source changes, and exact stdout on all three clients.

1. Run `bash scripts/probes/playground/build-native-peer.sh` to build the observer from the same Swift codec, CryptoKit and transport sources used by the app.
2. Build the `CrabrixTwoDevicePlaygroundGate` scheme for testing with configuration `CompilerCandidate` and a Simulator destination.
3. Start `node scripts/probes/playground/cross-client.cjs` from the repository root. `CRABRIX_PLAYWRIGHT_MODULE` can point to an installed Playwright module; `CRABRIX_NATIVE_PROBE` can override the observer binary. Wait for `READY`.
4. Run `PlaygroundTwoDeviceTests/testLinksSelectionsAndDebugAcrossTwoAppsAndWebsite` concurrently on an iPhone Simulator and an iPad Simulator using `xcodebuild test-without-building`. Disable parallel testing within each Xcode process. Use separate result bundles. The local coordinator owns port 3395.
5. Run `PlaygroundTwoDeviceTests/testHTTPSLinkOpensFreshRoomWithoutAutoOpenArguments` on each Simulator. It creates a new production room and verifies its unique source through the native HTTPS URL entry point. It does not use auto-open launch fixtures.
6. Require one actual executed/passed test per result bundle, zero failures and zero skipped tests. A successful Xcode exit with zero executed tests is not a pass. After an interrupted Simulator runner, reinstall that test runner before retrying.

`CRABRIX_LOCAL_TOOLCHAIN_MIRROR=1` supplies only the two large compiler assets from `site/public`, after comparing their SHA-256 with the pinned manifest. The page, encrypted relay, source/presence transport and app clients still use production HTTPS. Compilation and execution still happen in the browser Worker. This option does not test the initial public download; test that separately when the toolchain or serving rules change.

The results qualify Simulator UI and app URL handlers. They do not prove Safari's external Universal Link policy on a physical device. Check the site's AASA, Apple's cached AASA and the signed release entitlements separately, and verify physical-device handoff when a device is available.
