# Sprint 58 — Full-stack increments must be integration-verified with real test data, not mocked (v2.46.0)

## Context

An operator working ANTOS hit a defect that is really a **VibeFlow** defect: a
cycle shipped **mock frontends** over a backend that was only *claimed* to exist,
and reached the end of the SDLC without the frontend ever once being connected to
a real backend and exercised end-to-end. The operator's principle:

> Create test data and **verify every completed process end-to-end**; backend and
> frontend should be connected and validated *as you progress* — unless the
> increment is genuinely frontend-only or backend-only.

The framework does not enforce this today. Code-anchored gap:

- **`frontend-render-check`** (TESTING) renders the UI on **mock data, no backend
  by design** (`skills/frontend-render-check/SKILL.md` Step 2 + the "live
  integration — not here" note at L116-122). It proves the UI *looks* right, never
  that it *talks* to a backend.
- **`uat-executor`** is the only step that drives the **real backend**, but it
  requires a **live staging URL** (`targetUrl: https://staging.example.com`,
  `skills/uat-executor/SKILL.md`). `phase-runner` TESTING wiring (L190-193) says
  "when a staging URL is configured (else breadcrumb it as the operator's manual
  step)" — so on any project without a deployed staging env (ANTOS has **no HTTP
  server at all**), the front↔back integration is **never verified**. It falls
  through the crack between mock-TESTING and staging-DEPLOYMENT.
- **No local integration step exists.** `contract-test-writer` checks spec
  contracts; `e2e-test-writer` writes flows — neither boots a real backend, seeds
  data, and points the real frontend at it.
- A frontend whose links have **no backend behind them** (a dangling
  `fetch('/api/...')` over an endpoint no server implements) has **no detector** —
  unlike a `skinless` UI, which Sprint 55's `ui-styling-check.sh` catches.

Outcome wanted: VibeFlow refuses to let a **full-stack increment** reach GO
without a **local** (no-deploy-required) integrated test — real backend booted,
deterministic **test data** seeded, real frontend driven against it — while
genuinely **single-tier** increments (frontend-only behind an already-wired
backend, or backend-only) skip it (the operator's carve-out).

## Approach

Mirror the existing Sprint 53/54/55 pattern exactly: a **read-only detector hook**
+ a **TESTING-phase gate skill** + **phase-runner wiring** (change-type-conditional)
+ **docs** + **tests**. Reuse `test-data-manager` for the seeded data rather than
inventing fixtures. No engine/MCP change — this is skill + hook + docs, same class
as Sprints 53–57.

### S58-A — `integration-wiring-check.sh` read-only detector
New `hooks/scripts/integration-wiring-check.sh`, sibling of
`hooks/scripts/ui-styling-check.sh` / `ui-verification-debt.sh` (same
fail-safe, surface-only, bash-3.2, sources `_lib.sh` style). Given a repo root it
classifies the front↔back boundary:
- **`wired`** — frontend client→server calls (`fetch`/`axios`/an api-client
  module / react-query/swr hooks targeting `/api/...`) map to backend routes that
  are actually implemented (route/handler defs + a server entry).
- **`unwired`** — calls exist but **no server implements them** (dangling
  endpoints), or the frontend is hard-bound to mock fixtures/middleware with no
  real client path — "the links have no behind."
- **`single-tier`** — frontend-only with no server boundary, **or** backend-only
  with no frontend → integration N/A (the carve-out).
- **`no-app`** — neither detected; fail-safe.
Runtime probes added to `hooks/tests/run.sh` over fixtures for each class.

### S58-B — `integration-verifier` skill (TESTING, full-stack only)
New `skills/integration-verifier/SKILL.md` (`disable-model-invocation: false`, a
TESTING **Phase Contract**, arm-on-pass — same envelope as `frontend-render-check`):
1. Gate on full-stack: run `integration-wiring-check.sh .`; if `single-tier` /
   `no-app`, say "not a full-stack increment — skipping" and stop (carve-out).
2. **Boot the backend locally** — detect the server entry / dev command; **no
   deployed staging required**. A backend that can't be booted locally is the
   defect itself (ANTOS's "no HTTP server") → surfaced as a **BLOCKED** finding,
   not hidden.
3. **Seed deterministic test data** via the `test-data-manager` skill (the
   operator's "test verisi oluştur") — the same seed → same data.
4. **Point the frontend at the real local backend** (flip the data source off
   mocks), and **drive the backend-data-binding scenarios** (`SCN-UI-*-DATA-*`
   from Sprint 57's `scenario-set.md`) + key flows end-to-end against **real**
   responses across the states (loading / populated / empty / error / offline).
5. **Verdict**: `BLOCKED` when the backend won't boot, a called endpoint
   404s / doesn't exist, or the frontend renders nothing/errors on real data
   (every one is a "claimed-but-unverified backend" signal). `NEEDS_REVISION`
   only for a genuine tool gap (no headless runner) — with a breadcrumb, **never
   a silent skip**. `PASS` only when real data flows front↔back end-to-end.
6. Writes `.vibeflow/reports/integration-conformance.md`; arms
   `consensus-needed.json` **only on PASS** (Sprint 43 arm-on-pass).

### S58-C — phase-runner TESTING wiring + the ladder reframe
In `skills/phase-runner/SKILL.md` TESTING front-end battery (L164-201), insert
`integration-verifier` **after** `frontend-render-check` (mock render) and
**before** `uat-executor` (staging), conditional on full-stack
(`integration-wiring-check` = `wired`/`unwired`, or change-type `mixed`);
single-tier increments skip it. Reframe the three-rung ladder explicitly:
mock-render (looks right) → **local integration with seeded data (talks right —
new TESTING gate, no deploy)** → staging UAT (deployed walk, DEPLOYMENT, when a
staging URL exists). Fixes the hole where integration was only ever checked on a
staging env most projects don't have. Add the skill's bins to `allowed-tools`.

### S58-D — DEVELOPMENT early surfacing (catch it while building)
`phase-runner` DEVELOPMENT Step 0 surfaces an `unwired` result from
`integration-wiring-check.sh` **prominently** — same precedent as Sprint 55's
skinless surfacing (`skills/phase-runner/SKILL.md` L112-124) — so a frontend whose
calls have no backend behind them is caught *as you build*, not at the end.
Surface-only in DEVELOPMENT (the hard gate stays `integration-verifier` in
TESTING). Like `ui-verification-debt`, it also flags a repo that *has* an `unwired`
boundary from an earlier cycle, not just the current increment.

### S58-E — docs
- New `docs/INTEGRATION-TESTING.md`: the mock-render → local-integration →
  staging-UAT ladder, the full-stack-vs-single-tier rule, and the "a *claimed*
  backend is not a *verified* backend" principle.
- Refresh `docs/FRONTEND-TESTING.md` (the "live integration is DEPLOYMENT-only"
  framing is now wrong — local integration is a TESTING gate) and the
  `frontend-render-check` L116-122 "not here" note to point at `integration-verifier`.

### S58-F — registration + tests
- Register `integration-verifier` (+ the new hook) in
  `hooks/scripts/phase-policy.json`.
- New `tests/integration/sprint-58.sh`: static sentinels (skill structure +
  Phase Contract + arm-on-pass + full-stack guard, phase-policy registration,
  phase-runner wiring of the new lane + DEVELOPMENT surfacing, the docs) + a
  harness self-audit `[S58-Z]`.
- `hooks/tests/run.sh`: runtime probes for `integration-wiring-check.sh`
  (wired / unwired / single-tier / no-app fixtures).
- Keep all prior suites green (sprint-53/54/55 especially — this extends, doesn't
  rewrite, their philosophy). Bump version → **v2.46.0**; update CHANGELOG +
  the CLAUDE.md sprint ledger on completion.

## Verification

- `bash hooks/tests/run.sh` — new `integration-wiring-check.sh` runtime probes pass; existing assertions unchanged.
- `bash tests/integration/sprint-58.sh` — new layer green.
- `bash tests/integration/run.sh` + `sprint-53/54/55.sh` — regression: still green.
- Manual end-to-end on a fixture full-stack repo: `integration-verifier` BLOCKs
  when the backend can't boot / an endpoint 404s, PASSes when seeded data flows
  front↔back; a single-tier fixture is correctly skipped.

## Out of scope
- No new MCP/engine tool (pure skill + hook + docs, like Sprints 53–57).
- A/B and production-traffic verification stays out (observability MCP).
- Containerized/staging provisioning stays `uat-executor` / DEPLOYMENT.
