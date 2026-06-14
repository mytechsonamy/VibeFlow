# Integration testing — a *claimed* backend is not a *verified* backend

A cycle can ship a UI that renders beautifully on mock data, passes every unit and
component test, reads clean in code review — and is wired to a backend that was
only **claimed** to exist. The endpoints behind its links 404 the moment a real
request reaches them, or there is no HTTP server at all, only domain modules. The
gap stays invisible because every gate up to this point looks at the UI *in
isolation* or the backend *in isolation* — never the two **talking**.

Sprint 58 adds the rung that exercises the claim: **`integration-verifier`**.

## The three rungs

| Rung | Skill | Backend | Deploy? | Phase | Proves |
|---|---|---|---|---|---|
| 1 | `frontend-render-check` | **mocked** | no | TESTING | the UI *renders* + matches the design |
| 2 | **`integration-verifier`** | **real, local** | **no** | TESTING | the UI *talks* to a real backend with real data |
| 3 | `uat-executor` | real, deployed | yes (staging) | DEPLOYMENT | the deployed system works end-to-end with humans |

Rung 2 was the missing one. Before it, the only live-backend check was rung 3 —
which needs a **deployed staging URL** most projects never stand up. So full-stack
increments slid from "renders on mocks" straight to GO with the integration never
verified.

## What `integration-verifier` does

For a **full-stack increment** it, locally and with **no deploy**:

1. **Boots the real back-end** (detects the server framework / Next API routes /
   raw server; resolves the start command + port). A back-end that can't boot —
   including *no HTTP server at all* — is itself the finding (**BLOCKED**).
2. **Seeds deterministic test data** via `test-data-manager` (same seed → same
   data), loaded through the back-end's own seed path. The verification is only
   reproducible if the data is.
3. **Points the real front-end at the real back-end** — flips the API base off
   mocks (`VITE_API_URL` / `NEXT_PUBLIC_API_URL` / the app's config) onto
   `http://localhost:<backend-port>`.
4. **Drives the data-binding scenarios** (`SCN-UI-<screen>-DATA-*` from
   `scenario-set.md`, enumerated up front in PLANNING — Sprint 57) against **real**
   responses, per state: **populated** (the screen shows the *seeded* value, not a
   placeholder), **loading**, **empty**, **error** (4xx/5xx → the UI's error
   state), **offline** (back-end stopped → graceful degrade, no infinite spinner /
   no fake data). It also `curl`s each endpoint to catch a **404 / missing route**
   the UI might swallow.

**Verdict**: `PASS` (real data flows front↔back across the states) /
`NEEDS_REVISION` (a genuine tool/env gap, with the wire otherwise proven by
`curl`) / `BLOCKED` (won't boot, no HTTP server, a 404 endpoint, or the UI errors
on real data). Arms the consensus marker **only on PASS** (Sprint 43).

## The full-stack-vs-single-tier rule (the carve-out)

This gate applies **only** when an increment crosses the front↔back boundary.
The read-only `hooks/scripts/integration-wiring-check.sh` classifies the repo:

| Status | Meaning | `integration-verifier` |
|---|---|---|
| `wired` | UI server calls **and** a backend serving routes | **runs** (per-endpoint proof) |
| `unwired` | UI server calls but **no backend** serves them — "links have no behind" | **runs** → records the dangling boundary as BLOCKED |
| `single-tier` | front-end-only (static / external API) **or** back-end-only | **skipped** — the carve-out |
| `no-app` | neither tier detected | skipped (fail-safe) |

A front-end-only or back-end-only increment doesn't need this gate, exactly as the
operator's rule says: *verify end-to-end **unless** the increment is genuinely
single-tier.*

## Caught early, gated late

The same `integration-wiring-check.sh` runs in **DEVELOPMENT** (phase-runner
Step 0) and surfaces an `"unwired"` UI **prominently** — a dangling-link UI is
caught *as it's built*, the same way Sprint 55 surfaces a `skinless` UI. It also
flags an `unwired` boundary left over from an **earlier** cycle (like
`ui-verification-debt` does for never-rendered UIs), so a mock-front-end buried
under later backend cycles doesn't stay hidden. DEVELOPMENT only *surfaces*; the
**hard gate** is `integration-verifier` in TESTING.

## Running it

It's part of the one-command walk — phase-runner runs it in the TESTING front-end
battery for a full-stack increment, between the mock render and the staging UAT:

```
/vibeflow:phase-runner          # TESTING: … → frontend-render-check → integration-verifier → uat-executor
```

Or invoke it directly: `/vibeflow:integration-verifier`.

## Relationship to the rest

- `contract-test-writer` checks the API **spec** contract (OpenAPI/GraphQL diff);
  `integration-verifier` checks the **running** wire with real data — complementary.
- `e2e-test-writer` writes functional flows (often against mocks/fixtures);
  `integration-verifier` runs the real front↔back specifically.
- Provisioning a containerized/staging environment stays `uat-executor` /
  DEPLOYMENT — rung 2 deliberately needs nothing beyond what runs the app locally.
