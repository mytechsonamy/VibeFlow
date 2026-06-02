# Sprint 22 — Close the Action Gap: Actionable Learning Loop (v2.10.0)

> ✅ **COMPLETE** — shipped v2.10.0 on 2026-06-02. All six tickets (S22-A..F) landed. Tests: sdlc-engine 173→176, new `sprint-22.sh` (56); total baseline 2455 → 2514 across 22 layers.

## Context

Sprint 20 built the L3 slow loop: `learning-loop-engine --mode
consensus-history` mines the consensus telemetry and writes
`.vibeflow/reports/consensus-learning-report.md` with findings +
recommendations (slow-converging phases, recurring suggestion themes,
ineffective applied themes, convergence stalls). Sprint 20-G wired
`decision-recommender` to *frame* those findings as decision packages.

But the loop still has an **action gap**: nothing turns a recommendation
into a change. A finding that says "raise `consensus.maxIterations` —
REQUIREMENTS keeps needing 3 rounds" or "the `missing-acceptance-criteria`
theme recurs across 4 PRDs — fix the template" is read, framed… and then
sits in a report. The operator hand-edits `vibeflow.config.json` or
hand-invokes a specialist. The slow loop observes but never *acts*.

**Goal:** close the gap with a new `learning-apply` skill that turns
learning-loop recommendations into concrete, **diff-first, operator-
confirmed** changes — mirroring the proven `consensus-arbiter` →
`apply-arbiter-patch` safety pattern. It never writes config or source
directly; it proposes patches and routes template-class findings to the
existing phase specialists.

User direction (this session): **propose-only / diff-first** (operator
confirms every change — nothing auto-written) + scope = **config tuning
+ template-routing** (numeric/enum `vibeflow.config.json` tuning, plus a
bridge that routes recurring-theme findings to the right phase specialist).

## Design Overview — five groups, six tickets

### Group 1 — `learning-apply` skill: classify + propose (S22-A)

New `skills/learning-apply/SKILL.md` (phases: ALL; read-only +
patch-generation). Reads `consensus-learning-report.md` (and
`learning-report.md` for the other modes) and classifies each finding's
recommendation into one of three lanes:

- **config-tune** — the recommendation names a typed config key
  (`consensus.maxIterations`, `consensus.approvalThreshold`,
  `consensus.excerptStrategy`, `reviewerMemory.compaction`,
  `phaseRunner.maxConvergenceAttempts`, …). → emit a **diff-first patch**
  to `vibeflow.config.json` under
  `.vibeflow/state/patches/learning-<ts>/NN-<key>.patch` + a manifest.
- **template-route** — a `recurring-suggestion-theme` finding (the same
  theme across ≥3 artifacts). → emit a **specialist dispatch
  recommendation** (name the upstream artifact + the phase specialist,
  e.g. `prd-rewriter`); do NOT patch config. Bridged in S22-C.
- **escalate** — anything else (ambiguous, needs human judgement). →
  hand to `decision-recommender` / surface for the operator.

Audit log: `.vibeflow/reports/learning-apply-decisions.md` (one entry
per finding: lane, target, rationale, observations, patch/dispatch).
**Never Writes to `vibeflow.config.json` or source** — only to
`.vibeflow/state/patches/**` and the decisions report (same posture as
`consensus-arbiter/SKILL.md:14-16`).

- **Harness `[S22-A]`:** skill exists + frontmatter; three-lane prose;
  diff-first/never-writes-config sentinel; patch-dir + decisions-report
  paths; reads consensus-learning-report.md.

### Group 2 — Apply with confirmation + schema re-validation (S22-B)

`learning-apply` applies config patches **only** behind an explicit
confirm, mirroring `apply-arbiter-patch`:

- `--dry-run` (preview the diff, apply nothing — default is preview),
  `--yes` (apply after preview).
- **Schema re-validation gate:** before applying, run the patched
  `vibeflow.config.json` through the engine's `EngineConfigSchema`
  loader (`resolveConfig` / a tiny `node -e` against
  `mcp-servers/sdlc-engine/dist`). A patch that produces an invalid
  config (out-of-range, wrong enum) is **rejected**, never applied —
  the typed schema is the safety net.
- **Bounds guard:** a numeric tune may move at most
  `learningApply.maxRelativeStep` (default 0.5 = ±50%) from the current
  value and is always clamped to the schema's min/max; a finding below
  `learningApply.minObservations` is skipped.

- **Harness `[S22-B]`:** `--dry-run`/`--yes` prose; schema-revalidation
  gate sentinel; bounds-guard + clamp prose; reject-invalid sentinel.

### Group 3 — Template-route → phase-specialist bridge (S22-C)

For `template-route` findings, `learning-apply` reuses the Sprint 17-E
`consensus-specialist` dispatcher + phase→agent map: it names the
artifact owner and the matching specialist (REQUIREMENTS →
`prd-rewriter`, ARCHITECTURE → `adr-author`, PLANNING →
`test-strategy-refiner`, …) and emits the dispatch command. It does NOT
fork the specialist itself (that stays operator-initiated, propose-only)
— it writes the recommended `/vibeflow:consensus-specialist` invocation
into the decisions report.

- **Harness `[S22-C]`:** phase→specialist map sentinel; dispatch-
  recommendation prose; "does not auto-fork" guardrail.

### Group 4 — Config + phase-policy + tests (S22-D)

- `mcp-servers/sdlc-engine/src/config.ts`: new `LearningApplyConfigSchema`
  — `{ enabled: true, maxRelativeStep: 0.5, minObservations: 3 }`
  (mirror the S17-F/S19-G/S20-H/S21-E defaulted + partial-merge pattern);
  compose into `EngineConfigSchema`; merge branch in `loadFileConfig`.
- Register `learning-apply` in `skills/phase-policy.json` (phases: ALL,
  read-only + patch-generation).
- Unit tests in `tests/config.test.ts` (defaults + partial-merge +
  range rejection).

### Group 5 — Docs, harness, release (S22-E, S22-F)

**S22-E — docs + harness.**
- New `docs/ACTION-GAP.md` (the full learning → decide → apply loop) +
  `docs/LEARNING-APPLY.md` (skill reference: lanes, flags, bounds,
  safety). Refresh `docs/LEARNING-LOOP.md` (link the apply step) +
  `docs/CONSENSUS-FLOW.md`.
- `tests/integration/sprint-22.sh` — **≈70 assertions** across
  `[S22-A]..[S22-Z]` + self-audit `[S22-Z]`. (Skill is prose; coverage
  is sentinel-based + a config-schema-revalidation runtime probe via
  `node -e` against the built engine.)

**S22-F — v2.10.0 release.**
- `.claude-plugin/plugin.json` + `marketplace.json`: 2.9.0 → 2.10.0.
- `@vibeflow/sdlc-engine`: 1.7.0 → 1.8.0 (`LearningApplyConfigSchema`).
- `CHANGELOG.md` + `release-notes/2.10.0.md`; CLAUDE.md test counts +
  Sprint-22 ✅ COMPLETE; ROADMAP appendix row; mark `docs/SPRINT-22.md`
  COMPLETE; commit + tag `v2.10.0` + push.

## Files Touched (representative)

| Area | Files |
|---|---|
| learning-apply skill (S22-A/B/C) | `skills/learning-apply/SKILL.md` (+ `references/lanes.md`) |
| Specialist bridge (S22-C) | reuses `skills/consensus-specialist/SKILL.md` + `skills/phase-policy.json` (map) |
| Config (S22-D) | `mcp-servers/sdlc-engine/src/config.ts` (+ tests), `skills/phase-policy.json` |
| Docs/tests (S22-E) | `tests/integration/sprint-22.sh`, `docs/ACTION-GAP.md`, `docs/LEARNING-APPLY.md`, `docs/LEARNING-LOOP.md`, `docs/CONSENSUS-FLOW.md` |
| Release (S22-F) | `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `mcp-servers/sdlc-engine/package.json`, `CHANGELOG.md`, `release-notes/2.10.0.md`, `CLAUDE.md`, `ROADMAP.md` |

## Reused patterns (don't reinvent)

- **Diff-first + never-write-source** — `consensus-arbiter/SKILL.md`
  (patches under `.vibeflow/state/patches/<session>/`, audit md).
- **Preview + `--yes` + `--dry-run` apply** — `apply-arbiter-patch/SKILL.md`.
- **phase→specialist map** — `consensus-specialist/SKILL.md` (Sprint 17-E).
- **Typed config defaulted + partial-merge** — `config.ts`
  `LearningLoopConfigSchema` / `ReviewerMemoryConfigSchema` (S20-H/S21-E).

## Verification (merge-green gate)

| Layer | Before (v2.9.0) | After (v2.10.0, target) | Delta |
|---|---|---|---|
| `sdlc-engine` unit | 173 | ~177 | +≈4 (LearningApplyConfigSchema) |
| `hooks/tests/run.sh` | 139 | 139 | 0 (skill is prose; no new hook) |
| `tests/integration/run.sh` | 399 | 399 | 0 |
| Sprint-*.sh bundle | ~1758 | ~1828 | +≈70 (sprint-22.sh) |
| **Total** | **2455** | **~2529** | **+≈74** |

Run with `env -u VF_ALLOW_PHASE_WRITE` (so the dogfood phase-guard tests
still exercise the block path): 5 MCP `npm test`, `bash hooks/tests/run.sh`,
`bash tests/integration/run.sh`, `bash tests/integration/sprint-22.sh`.
Rebuild `sdlc-engine` dist after the config change.

**E2E walk:** seed a `consensus-learning-report.md` with one
config-tune finding (raise `maxIterations`) + one recurring-theme
finding; run `learning-apply`; confirm (1) a diff-first
`vibeflow.config.json` patch is written under
`.vibeflow/state/patches/learning-*/` (nothing applied yet), (2) the
template-route finding becomes a `/vibeflow:consensus-specialist`
dispatch line in `learning-apply-decisions.md`, (3) `--yes` applies the
config patch only after the patched config passes schema re-validation,
(4) an out-of-range tune is rejected, (5) defaults hold with an empty
`vibeflow.config.json`.

## Out of Scope (→ Sprint 23+)

- **Bounded auto-apply** (no operator confirm). Deliberately rejected
  this session — propose-only keeps the safety posture.
- **Auto-forking the phase specialist** from learning-apply. S22-C
  routes/recommends; the operator still initiates the rewrite.
- **Embedding-based excerption / memory** (S21 deferral, unchanged).
- **Auto-satisfy for `design.approved` / `accessibility.verified` /
  `sprint.planned`** — stays manual per the Sprint 18 decision.
