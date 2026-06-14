---
name: integration-verifier
description: For a full-stack increment, proves the front-end actually talks to a REAL back-end end-to-end with seeded test data — locally, no deployed staging required. Boots the back-end, seeds deterministic test data (via test-data-manager), points the real front-end at the local back-end instead of mocks, and drives the backend-data-binding scenarios (SCN-UI-*-DATA-* from scenario-set.md) across loading/populated/empty/error/offline. This is the rung between frontend-render-check (renders on mocks — looks right) and uat-executor (deployed staging walk): it answers "does it TALK right?" without needing infra. BLOCKs when the back-end won't boot, an endpoint 404s, or the UI errors on real data — the exact "mock front-end over a claimed-but-unverified backend" trap. Use in TESTING for any increment that crosses the front↔back boundary; single-tier (front-end-only / back-end-only) increments are skipped.
disable-model-invocation: false
allowed-tools: Read Write Bash(mkdir *) Bash(jq *) Bash(ls *) Bash(cat *) Bash(npm *) Bash(npx *) Bash(pnpm *) Bash(yarn *) Bash(node *) Bash(curl *) Bash(lsof *) Bash(kill *) Bash(pytest *) Bash(dotnet *) Bash(go *) Bash(npx playwright *) Bash(bash *integration-wiring-check.sh*)
---

# Integration Verifier

A UI can render perfectly on mock data and pass every unit + component test while
the back-end behind it is **only claimed to exist** — never booted, never hit, an
endpoint that 404s the moment a real request reaches it. `frontend-render-check`
uses mocks **on purpose** (so design conformance runs without infra); this step
is the other half of the truth: it boots a **real** back-end, seeds **real test
data**, points the **real** front-end at it, and proves data flows end-to-end.

It closes the gap where integration was only ever verified by `uat-executor` —
which needs a **deployed staging URL** most projects don't have (a back-end with
no HTTP server can never reach staging, so its integration was *never checked at
all*). This runs **locally**, in TESTING, with no deploy.

## Phase Contract

Runs in **TESTING**, **full-stack increments only**. First action — classify the
front↔back boundary:

```bash
bash "${CLAUDE_PLUGIN_ROOT:-.}/hooks/scripts/integration-wiring-check.sh" .
```

- `"single-tier"` / `"no-app"` → say "not a full-stack increment (front-end-only
  or back-end-only) — skipping integration verification" and **stop**. This is the
  operator's carve-out: a UI behind an already-wired backend, or a backend with no
  UI, doesn't need this gate.
- `"unwired"` → the UI calls a server API but **no backend serves those routes**.
  That is itself the finding — record a **BLOCKED** verdict naming it ("the UI's
  links have no backend behind them") and breadcrumb to build/wire the backend.
  Don't try to boot what isn't there.
- `"wired"` → proceed (the real per-endpoint proof is below — a static `wired`
  only means a server serving *some* routes exists, not that *these* calls work).

Outputs land in `.vibeflow/reports/integration/` + `.vibeflow/**`.

## Step 1: Boot the back-end — locally, no staging

Detect and boot the server (don't assume `apps/api` — detect):

- Find the back-end package: a `package.json` with a server framework
  (`express`/`fastify`/`koa`/`@nestjs`/`hono`/`@trpc/server`) or Next API routes
  (`app/api`/`pages/api`), or a raw `http.createServer`/`Bun.serve`/`Deno.serve`.
- Resolve its **start/dev command** (`npm run dev`/`start`, `next dev`, a
  `node dist/server.js`, `uvicorn`, `dotnet run`) and port.
- **Boot it** and capture startup output. A back-end that **can't boot locally**
  — including the case where there is **no HTTP server at all**, only domain
  modules — is a **real finding**, not an env glitch: stop with a **BLOCKED**
  verdict naming it. This is the precise defect that lets a "backend written"
  claim ship unverified.

## Step 2: Seed deterministic test data

Use the **`test-data-manager`** skill (invoke it as a Skill) to generate seeded,
deterministic fixtures from the back-end's types/Zod/JSON-schema (same seed → same
data on every machine), then load them through the back-end's own seed path
(a seed script / a test DB / an in-memory store). Record the seed + what was
loaded in the report — the verification is only reproducible if the data is.
Never hand-mock the *server's* responses here; the whole point is real data
flowing through the real back-end.

## Step 3: Point the real front-end at the real back-end

Flip the front-end's data source **off mocks** and onto the booted back-end:

- Set the API base (`VITE_API_URL` / `NEXT_PUBLIC_API_URL` / the app's config)
  to `http://localhost:<backend-port>`, disabling any mock middleware / fixture
  client used by `frontend-render-check`.
- Boot the front-end against it. (If the front-end and back-end share a dev
  proxy, just ensure the proxy targets the live local back-end, not the stub.)

## Step 4: Drive the data-binding scenarios end-to-end

From `.vibeflow/reports/scenario-set.md`, run the **backend-data-binding**
scenarios (`SCN-UI-<screen>-DATA-*`, Sprint 57) + the key flows — against **real**
responses, per state:

- **populated** — the screen shows the *seeded server value* (not a placeholder /
  not a mock constant). Assert the rendered value equals the seeded value.
- **loading** — the loading state appears while the request is in flight.
- **empty** — with no seeded rows, the empty state renders (not a crash / not stale
  mock data).
- **error** — when the back-end returns 4xx/5xx, the UI shows its error state.
- **offline** — with the back-end stopped, the UI degrades (doesn't hang on a
  spinner forever / doesn't show fake data).

Hit each called endpoint directly too (`curl`) to catch a **404 / missing route**
that the UI might swallow. A called endpoint that doesn't exist on the booted
back-end is a **BLOCKED** finding (the dangling-link case, now proven at runtime).

**Graceful-degrade:** no headless browser / runner available → do **not** fake it
and do **not** silently skip. Verify the endpoints with `curl` (that alone proves
the wire), leave the servers running, write a `▶ Next:` breadcrumb to open
`http://localhost:<fe-port>/` against the live back-end, and record
`NEEDS_REVISION` (a tool gap, not a pass).

## Step 5: Report + verdict

Write `.vibeflow/reports/integration-conformance.md`:

- Boot result for back-end + front-end (started? startup errors?).
- The seed used + what data was loaded.
- Per data-binding scenario: endpoint, HTTP status, the seeded value vs the
  rendered value, and the state coverage table (populated / loading / empty /
  error / offline).
- Per finding `{ finding, why, impact, confidence }`.
- **Verdict**: `PASS` (real data flows front↔back across the states) /
  `NEEDS_REVISION` (a genuine tool/env gap with the wire otherwise proven by
  `curl`) / `BLOCKED` (back-end won't boot or has no HTTP server, a called
  endpoint 404s, or the UI renders nothing / errors on real data — a real
  "the backend was claimed but never connected" signal).

## Relationship to the other rungs

- `frontend-render-check` — renders on **mocks**; proves it *looks* right. (TESTING)
- **`integration-verifier`** (this) — real back-end + seeded data, **local**;
  proves it *talks* right, with **no deploy**. (TESTING)
- `uat-executor` — the **deployed staging** walk with the real backend + human
  steps. (DEPLOYMENT, when a staging URL exists)

Note in the report that integration was verified locally with seeded data and the
deployed-staging walk remains the DEPLOYMENT/UAT step.

## Final Step: Auto-Consensus Marker (only on PASS — Sprint 43 arm-on-pass)

Write `.vibeflow/state/consensus-needed.json` (primaryArtifact
`.vibeflow/reports/integration-conformance.md`, createdBy `integration-verifier`)
**only if `VERDICT == "PASS"`**. On `NEEDS_REVISION`/`BLOCKED`, do **not** write
the marker — surface the named failure (won't boot / 404 endpoint / no relation
to real data) + a `▶ Next:` (build/wire the backend, fix the endpoint), and stop
so the gate stays clear for the fix iteration.

## Output

- `.vibeflow/reports/integration/` (per-scenario evidence, curl transcripts)
- `.vibeflow/reports/integration-conformance.md` (scenarios + state table + verdict)
