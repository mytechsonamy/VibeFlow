# Sprint 29 — phase-runner TESTING Auto-Run (v2.17.0)

> ✅ **COMPLETE** — shipped v2.17.0 on 2026-06-05 (backlog B5). Four tickets (S29-A..D), skill-only. Tests: new `sprint-29.sh` (34); total baseline 2840 → 2874 across 29 layers (sdlc-engine 199 + hooks 174 unchanged).

## Context

`/vibeflow:phase-runner` is a one-command phase walk for every phase
*except* TESTING. The gap: the TESTING analyzers don't generate their own
inputs. **`coverage-analyzer` parses an existing `coverage-summary.json`
/ `coverage-final.json`** — it does not run the test suite to produce it.
So today, on a TESTING walk, the operator must first run
`npx vitest run --coverage` (or equivalent) by hand to generate the
coverage artifact, *then* let phase-runner run the analyzer on it. That
manual generate step is exactly the "operator confirm" friction Sprint 26
parked as backlog **B5**.

(`mutation-test-runner` is self-sufficient — per its contract it
*generates* mutations and runs the suite itself, so it only needs
`tech.testCommand` available. The missing piece is **coverage
generation**.)

Sprint 29 closes B5: phase-runner gains a **TESTING-only generate step**
that runs the project's coverage command (resolved from
`vibeflow.config.json.tech.*`, the same `tech` block `quality-gates`
already uses) *before* forking the TESTING analyzers — so TESTING becomes
a genuine one-command autonomous walk (generate → analyze → consensus →
advance) like every other phase.

User direction (this session): **B5 phase-runner TESTING auto-run**.

## Design Overview — four groups, four tickets

### Group 1 — TESTING generate-artifacts pre-step (S29-A)

In `skills/phase-runner/SKILL.md` Step 2, add a **TESTING-only** sub-step
that runs **before** the analyzer list:

- Resolve the coverage command from `vibeflow.config.json.tech.coverageCommand`;
  if absent, default per `tech.testRunner` (the same resolution shape as
  `quality-gates`):
  - `vitest` → `npx vitest run --coverage`
  - `jest`   → `npx jest --coverage`
  - `pytest` → `pytest --cov --cov-report=json`
  - `dotnet` → `dotnet test --collect:"XPlat Code Coverage"`
  - unknown  → skip with a logged note (no command to run).
- Run it, recording a `generate:coverage` step in the Sprint-21 progress
  ledger (`running → done|failed`). `mutation-test-runner` self-generates,
  so the generate step only ensures **coverage** output exists; it also
  verifies `tech.testCommand` is resolvable for the mutation analyzer and
  notes it in the ledger.
- Then proceed to the existing analyzer fork (`coverage-analyzer`,
  `mutation-test-runner`) unchanged — now their inputs exist.

`allowed-tools` gains the runner binaries (mirroring `quality-gates`):
`Bash(npm *) Bash(npx *) Bash(pnpm *) Bash(yarn *) Bash(pytest *) Bash(dotnet *) Bash(cargo *) Bash(go *)`.

- **Harness `[S29-A]`:** generate-step prose + per-testRunner default
  table + `tech.coverageCommand` override + ledger `generate:coverage`
  step + allowed-tools runners.

### Group 2 — Best-effort + opt-out + TESTING-only guard (S29-B)

- **Best-effort.** If the coverage command is absent (unknown runner) or
  exits non-zero, phase-runner **logs it and continues** to the analyzers
  rather than aborting — `coverage-analyzer` then surfaces the
  missing/empty-coverage block clearly (its existing gate), so the
  operator gets a precise "coverage didn't generate" signal instead of a
  silent phase-runner failure.
- **Opt-out.** New `--no-generate` flag (and `VF_SKIP_GENERATE=1`) skips
  the generate step entirely — for operators who generate coverage in CI
  / by hand and just want the analyze→consensus→advance walk.
- **TESTING-only guard.** The generate step runs **only** in TESTING; the
  REQUIREMENTS/ARCHITECTURE/PLANNING/DEVELOPMENT/DEPLOYMENT walks are
  byte-for-byte unchanged.

- **Harness `[S29-B]`:** best-effort/continue-on-failure prose +
  `--no-generate` / `VF_SKIP_GENERATE` opt-out + the "generate runs only
  in TESTING" guard sentinel.

### Group 3 — Docs + harness (S29-C)

- Refresh `docs/TESTING-READINESS.md`: TESTING is now a true one-command
  walk (`/vibeflow:phase-runner TESTING` generates coverage → analyzes →
  consensus → advances); document `tech.coverageCommand` + the
  per-runner defaults + `--no-generate`. Refresh the phase→analyzer note.
- `tests/integration/sprint-29.sh` — **≈45 assertions** across
  `[S29-A]..[S29-Z]` + self-audit `[S29-Z]`. Skill is prose, so coverage
  is sentinel-based: generate-step presence, the per-runner default
  table, ledger wiring, opt-out flags, TESTING-only guard, allowed-tools,
  docs. Plus a tiny runtime probe of the **command-resolution defaulting**
  (extract the `vibeflow.config.json.tech.coverageCommand // <default by
  testRunner>` jq into the harness and assert each runner resolves).

### Group 4 — Release (S29-D)

- `.claude-plugin/plugin.json` + `marketplace.json`: 2.16.0 → 2.17.0.
- `@vibeflow/sdlc-engine`: unchanged (no engine change — skill-only).
- `CHANGELOG.md` + `release-notes/2.17.0.md`; CLAUDE.md test counts +
  Sprint-29 ✅ COMPLETE; ROADMAP appendix row + tick **B5**; mark
  `docs/SPRINT-29.md` COMPLETE; commit + tag `v2.17.0` + push.

## Files Touched (representative)

| Area | Files |
|---|---|
| Generate step (S29-A/B) | `skills/phase-runner/SKILL.md` |
| Docs/harness (S29-C) | `tests/integration/sprint-29.sh`, `docs/TESTING-READINESS.md` |
| Release (S29-D) | `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `CHANGELOG.md`, `release-notes/2.17.0.md`, `CLAUDE.md`, `ROADMAP.md` |

## Reused patterns (don't reinvent)

- **`tech.*` command resolution by runner** — `quality-gates/SKILL.md`
  (Sprint 18-F) resolves `lint/typecheck/testCommand` exactly this way;
  S29 adds `coverageCommand` in the same shape.
- **Progress ledger steps** — `phase-runner` Sprint-21-C `vf_progress`;
  `generate:coverage` is a new step name in the existing mechanism.
- **Best-effort + opt-out env flag** — `apply-arbiter-patch`
  `VF_SKIP_AUTO_CHAIN` / `--no-chain` (S19-E) is the same shape.

## Verification (merge-green gate)

| Layer | Before (v2.16.0) | After (v2.17.0, target) | Delta |
|---|---|---|---|
| `sdlc-engine` unit | 199 | 199 | 0 (skill-only) |
| `hooks/tests/run.sh` | 174 | 174 | 0 |
| `tests/integration/run.sh` | 399 | 399 | 0 |
| Sprint-*.sh bundle | ~2082 | ~2127 | +≈45 (sprint-29.sh) |
| **Total** | **2840** | **~2885** | **+≈45** |

Run with `env -u VF_ALLOW_PHASE_WRITE`: 5 MCP `npm test`,
`bash hooks/tests/run.sh`, `bash tests/integration/run.sh`,
`bash tests/integration/sprint-29.sh`. (No `sdlc-engine` dist rebuild
needed — no engine change.)

**E2E walk:** in a vitest project at TESTING, `/vibeflow:phase-runner
TESTING` → confirm it (1) runs `npx vitest run --coverage` first
(`generate:coverage` in the ledger), (2) then forks `coverage-analyzer`
on the produced JSON + `mutation-test-runner`, (3) runs consensus +
auto-advances. With `--no-generate` → skips the generate step. With an
unknown `testRunner` → logs "no coverage command" and continues (the
analyzer surfaces the missing-coverage block). A non-TESTING walk → no
generate step at all.

## Out of Scope (→ Sprint 30+)

- **Typed `tech` config schema** — `tech` stays a freeform
  `vibeflow.config.json` block read ad-hoc by skills (consumer-specific
  fields); no Zod schema this sprint.
- **Embedding-based excerption** (B3 — design-philosophy tension) +
  **live TUI** (B4) — remaining backlog.
- **Auto-running mutation generation tools** (stryker, etc.) beyond what
  `mutation-test-runner` already self-runs.
