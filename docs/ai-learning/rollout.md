# Phase 7 — staged launch, switches and rollback

Nothing here runs without the owner's separate permission (spec §17.5). Each stage is
independent; stop at any stage without affecting the ones before it or the existing Academy.

## Before any stage

1. Regression suite (`regression-suite.md`) green on all three repos; counts recorded.
2. Backups: the site's `/data` volume (`accounts.sqlite`, and from stage 3 `academy-events.sqlite`)
   has its daily backup; note the current site image digest and the MCP container image for rollback.
3. Hostwatch node disk: `retention_preview`; the site build needs 10 GiB free. Do not lower the
   floor silently.

## Stages

| Stage | What | Switch state | Watch for | Exit criteria |
|---|---|---|---|---|
| 1. Content | Merge crabrix-courses (paths, contract 1.1.0, practice starters, schema). No user-visible change. | — | course CI | tests green |
| 2. SDK | Bump to 0.6.0; publish npm, crates, Go, MCP registry; then merge the SDK PR (the plugin installs from main). | — | `npx crabrix@0.6.0 academy` starts; existing room flows (`crabrix_connect`, agent links) unchanged | install smoke test on a clean machine |
| 3. Remote MCP | Rebuild `crabrix-mcp-remote` with `--academy-origin https://crabrix.com`; keep the previous image tagged. | `CRABRIX_ACADEMY_MCP` unset | 5xx on `/mcp/academy`, room agent-link errors, memory | a real client lists the academy tools; an existing room link still works |
| 4. Site, quiet | Deploy the site with `CRABRIX_AI_LEARNING=off`: API, status, practice copies and events go live; no new UI. | `CRABRIX_AI_LEARNING=off` | Playground open rate for `?lesson=` links, API latency, page speed | lessons and Playground unchanged; API answers |
| 5. Site, visible | Rebuild with the UI on (`/learn/with-ai/`, the `/learn/` block, lesson prompts, feedback card). | all on | event counts, feedback answers, error logs, existing Academy traffic | no drop in lesson availability or Playground opens |
| 6. App | iOS build with the Learn with AI entry through TestFlight, then App Review on the owner's word. | `AcademyAIFeature.isEnabled = true`; `status.json` on | crash reports, CoursePack updates, restore/backup reports | TestFlight testers continue lessons offline; no progress reports |

## Switches (fast to slow)

| Problem | Do | Effect | Time |
|---|---|---|---|
| Academy MCP misbehaves | Set `CRABRIX_ACADEMY_MCP=off` on the MCP container (or `serve-http --no-academy`), restart it; set `CRABRIX_ACADEMY_MCP_STATE=paused` on the site | `/mcp/academy` 503; room links keep working; `status.json` reports paused | minutes |
| API misbehaves | `CRABRIX_ACADEMY_API=off` on the site container, restart | `/api/academy/v1/*` 503 except `status.json`; MCP tools report the API unavailable | minutes |
| Counters misbehave | `CRABRIX_ACADEMY_EVENTS=off`, restart | events accepted and discarded | minutes |
| UI must go | `CRABRIX_AI_LEARNING=off`, rebuild and deploy the site | page 404s, blocks and prompts gone; the app shows its paused notice through `status.json` | one site build |
| App screen must go | `status.json` paused (above) immediately; next app build with `AcademyAIFeature.isEnabled = false` | entry hidden at build time | App Review |
| Everything | Redeploy the previous site image and MCP image | pre-feature behaviour | one deployment each |

Rollback never touches learner data: progress is on devices and in the learner's own backups;
the only new server data is the counter table, which may be dropped
(`rm /data/academy-events.sqlite*`) without affecting accounts.

## After launch

- Daily for two weeks: counters (`node scripts/academy-events-report.mjs` inside the site
  container), feedback emails, site and MCP error logs, Playground `?lesson=` 404s.
- Compare with the two weeks before: lesson page availability, Playground opens, CoursePack update
  reports, app crash reports. If the existing Academy gets worse, switch the feature off first and
  investigate second.
