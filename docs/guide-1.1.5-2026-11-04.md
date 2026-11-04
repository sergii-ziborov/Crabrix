# User guide alignment with Crabrix 1.1.5 — 4 November 2026

The `/guide/` page already described Crabrix MCP 0.5.0 and Connect AI, but its introduction still called 1.1.4 build 123 the version in review. It also described all shared file structural edits as requiring a local copy, and Open in Crabrix as a local-copy action.

The guide now uses 1.1.5 build 128 as its documented native baseline without claiming a new App Store release. Earlier feature requirements retain their version/build boundaries, rather than stale TestFlight availability claims. Website and SDK versions remain separate.

Updates cover stable file identities, rename/move behavior, deleted-file Recovery, Restore/Download/Clear, Recovery in source ZIPs, live-files-only Copy to local, native read-only reasons, and compatibility with older room formats. Open in Crabrix is correctly described as joining the shared room. The guide distinguishes local MCP decryption from the website's optional remote MCP route, including AI-provider access to source read by its tools. It locates native execution permissions under Share → Connect AI agent and explains that received output does not execute code on another client.

Evidence: `docs/app-store/review-notes-build128.txt`, `whats-new-1.1.5.txt`, `testflight-what-to-test-1.1.5.txt`; `Crabrix/Playground/PlaygroundSharingSheet.swift`, `PlaygroundLiveSession.swift`; `site/components/playground/workspace.tsx`, `recovery-panel.tsx`; `site/lib/mcp-download.json`.

The guide links the new local-versus-remote MCP study. TechArticle, OpenGraph and sitemap modification dates are 2026-11-04. Existing anchors, screenshots, styling and lesson access rules are retained. No native app or package-registry release is part of this documentation update. Verification and publication results are recorded in the accompanying release receipt.

Before publication, all 117 existing site tests, the production build and TypeScript checking passed. A local browser matrix covered 390, 820 and 1440 pixels in all five themes (15 cases): the guide's anchors resolve, IDs stay unique, metadata dates match, and the edited Recovery and AI sections have no page overflow or browser errors.
