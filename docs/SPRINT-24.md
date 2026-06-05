# Sprint 24 — Self-Correcting Auto-Apply: Meta-Learning + Transactional Revert (v2.12.0)

> ✅ **COMPLETE** — shipped v2.12.0 on 2026-06-05. All six tickets (S24-A..F) landed. Tests: sdlc-engine 179→182, hooks 149→155, new `sprint-24.sh` (41); total baseline 2570 → 2620 across 24 layers.

## Context

Sprint 23 made the slow loop autonomous *at the apply level*: allowlisted
config tunes auto-apply, and a tune that regresses the next consensus
round is auto-reverted + cooled down for the sprint. That generates real
telemetry — `auto-revert` rows in `history.jsonl`, `AUTO-APPLY HELD` /
`AUTO-REVERT` lines in `auto-apply-reverts.md` — but **nothing reads it
back**. So the loop is autonomous but not *self-correcting*: a key that
auto-applies and gets reverted every single sprint keeps getting
proposed and re-applied, burning a round each time before the cooldown
catches it. The per-sprint cooldown is a band-aid; the loop never learns
"this key just doesn't respond to tuning."

Sprint 24 closes that meta-loop. The learning loop learns from its **own**
auto-tuning outcomes and stops recommending keys that never stick, and
`learning-apply` self-demotes a chronically-reverted key to propose-only
even when it's allowlisted. Plus the Sprint-23 hardening item:
**multi-key transactional revert** — auto-apply a *set* of tunes as one
unit and revert the set atomically.

User direction (this session): **meta-learning (self-correcting
auto-apply)** + **include multi-key transactional revert**.

## Design Overview — five groups, six tickets

### Group 1 — Durable auto-apply outcome telemetry (S24-A)

The detector needs every auto-apply *outcome* in the one log the
learning loop already reads (`history.jsonl`). Today only `auto-revert`
lands there; `applied` and `held` don't. Add:

- `learning-apply` (Step 7) appends an `{type:"auto-apply", key, from,
  to, phase, primaryArtifact, appliedAt}` row to `history.jsonl` when it
  auto-applies (alongside arming the watch).
- `consensus-aggregator.sh` appends an `{type:"auto-apply-held", key,
  round, baselineAgreement, agreement, recordedAt}` row on the HELD
  branch (it already appends `auto-revert` on the revert branch).

Net: every auto-tune outcome (`auto-apply` → `auto-revert` |
`auto-apply-held`) is a queryable row keyed by `key`.

- **Harness `[S24-A]`:** learning-apply writes the `auto-apply` row;
  aggregator writes the `auto-apply-held` row (hook-test runtime); both
  carry `key`.

### Group 2 — `auto-tune-ineffective` detector (S24-B)

Add a detector to `learning-loop-engine`'s `consensus-history` mode +
`references/pattern-detection.md` catalog:

- **`LEARNING-AUTO-TUNE-INEFFECTIVE`** — a config key whose
  `auto-apply` rows are followed by `auto-revert` (not `auto-apply-held`)
  in ≥ `minObservations` (default 3) of its attempts, i.e. a high
  **revert rate**. Recommendation: "remove `<key>` from
  `autoApply.keys` — N of M auto-applies were reverted; tuning it doesn't
  move agreement." Severity escalates with revert count.

Emitted into `consensus-learning-report.md` like every other
consensus-history finding. Bump `patternCatalogVersion` to 3.

- **Harness `[S24-B]`:** detector named in SKILL + catalog entry +
  revert-rate signature + ≥3-observation floor.

### Group 3 — `learning-apply` self-demote (S24-C)

Before auto-applying an allowlisted key, `learning-apply` counts that
key's recent `auto-revert` rows in `history.jsonl`. If the count ≥
`autoApply.demoteAfterReverts` (new config, default 3), the key is
**demoted to propose-only for the run** even though it's allowlisted —
a longer-horizon guard than the per-sprint cooldown. The decisions
report records `Applied: demoted (N reverts ≥ threshold) — proposing
instead`. This is the apply-side enforcement of the S24-B signal: the
detector *recommends* removing the key; the self-demote *protects*
against it in the meantime.

- Config (S24-C): `autoApply.demoteAfterReverts` (int ≥ 1, default 3).
- **Harness `[S24-C]`:** self-demote prose + threshold config + "stays
  allowlisted but proposes" guardrail.

### Group 4 — Multi-key transactional revert (S24-D)

Today the watch tracks one key. Make a run's auto-applies a
**transaction**:

- `learning-apply` takes **one** pre-batch snapshot, applies all eligible
  allowlisted keys, and arms a single `watch.json` with `keys: [k1, k2,
  …]` (array) + the one snapshot + the batch baseline agreement.
  `autoApply.transactional` (new config, default true) gates this; false
  ⇒ Sprint-23 one-key-at-a-time behaviour.
- `consensus-aggregator.sh` revert path reads `keys // [key]` (back-
  compat with the Sprint-23 single-key watch), and on regression restores
  the one snapshot (already whole-file ⇒ atomic for the set) **and cools
  down every key in `keys[]`**, logging each. The set reverts or holds as
  a unit.

- Config (S24-D): `autoApply.transactional` (bool, default true).
- **Harness `[S24-D]`:** watch `keys[]` prose; aggregator `keys // [key]`
  read; cooldown-all-keys on revert (hook-test runtime with a 2-key
  watch → both cooled down + both restored).

### Group 5 — Config tests, docs, harness, release (S24-E, S24-F)

**S24-E — docs + harness + config tests.**
- `config.ts`: `AutoApplyConfigSchema` += `demoteAfterReverts` (int,
  default 3) + `transactional` (bool, default true); unit tests
  (defaults + range). (Both nest in the existing `autoApply` block — no
  new `EngineConfigSchema` wiring.)
- New `docs/META-LEARNING.md` (the self-correcting loop: telemetry →
  detector → self-demote, + transactional revert). Refresh
  `docs/AUTO-APPLY.md` + `docs/LEARNING-LOOP.md`.
- `tests/integration/sprint-24.sh` — **≈55 assertions** across
  `[S24-A]..[S24-Z]` + self-audit `[S24-Z]`.
- `hooks/tests/run.sh` — +≈6: `auto-apply-held` row, multi-key cooldown,
  `keys // [key]` back-compat.

**S24-F — v2.12.0 release.**
- `.claude-plugin/plugin.json` + `marketplace.json`: 2.11.0 → 2.12.0.
- `@vibeflow/sdlc-engine`: 1.9.0 → 1.10.0 (autoApply schema additions).
- `CHANGELOG.md` + `release-notes/2.12.0.md`; CLAUDE.md test counts +
  Sprint-24 ✅ COMPLETE; ROADMAP appendix row; mark `docs/SPRINT-24.md`
  COMPLETE; commit + tag `v2.12.0` + push.

## Files Touched (representative)

| Area | Files |
|---|---|
| Telemetry (S24-A) | `skills/learning-apply/SKILL.md`, `hooks/scripts/consensus-aggregator.sh` |
| Detector (S24-B) | `skills/learning-loop-engine/SKILL.md` (+ `references/pattern-detection.md`) |
| Self-demote (S24-C) | `skills/learning-apply/SKILL.md`, `mcp-servers/sdlc-engine/src/config.ts` |
| Transactional revert (S24-D) | `skills/learning-apply/SKILL.md`, `hooks/scripts/consensus-aggregator.sh`, `config.ts` |
| Config tests / docs / harness (S24-E) | `mcp-servers/sdlc-engine/tests/config.test.ts`, `tests/integration/sprint-24.sh`, `hooks/tests/run.sh`, `docs/META-LEARNING.md`, `docs/AUTO-APPLY.md`, `docs/LEARNING-LOOP.md` |
| Release (S24-F) | `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `mcp-servers/sdlc-engine/package.json`, `CHANGELOG.md`, `release-notes/2.12.0.md`, `CLAUDE.md`, `ROADMAP.md` |

## Reused patterns (don't reinvent)

- **history.jsonl typed rows** — Sprint 20-A (`verdict`/`arbiter-decision`)
  + Sprint 23-C (`auto-revert`); S24-A just adds `auto-apply` /
  `auto-apply-held`.
- **consensus-history pattern detectors** — Sprint 20-B/C catalog in
  `references/pattern-detection.md`; S24-B adds one entry.
- **Snapshot/restore + cooldown** — Sprint 23-C aggregator revert block;
  S24-D generalises the cooldown loop over `keys[]`.
- **Typed config defaulted + nested** — `AutoApplyConfigSchema` (S23-A).

## Verification (merge-green gate)

| Layer | Before (v2.11.0) | After (v2.12.0, target) | Delta |
|---|---|---|---|
| `sdlc-engine` unit | 179 | ~182 | +≈3 (demoteAfterReverts + transactional) |
| `hooks/tests/run.sh` | 149 | ~155 | +≈6 (held row, multi-key cooldown, keys back-compat) |
| `tests/integration/run.sh` | 399 | 399 | 0 |
| Sprint-*.sh bundle | ~1857 | ~1912 | +≈55 (sprint-24.sh) |
| **Total** | **2570** | **~2634** | **+≈64** |

Run with `env -u VF_ALLOW_PHASE_WRITE`: 5 MCP `npm test`,
`bash hooks/tests/run.sh`, `bash tests/integration/run.sh`,
`bash tests/integration/sprint-24.sh`. Rebuild `sdlc-engine` dist.

**E2E walk:** seed `history.jsonl` with 3 `auto-apply`→`auto-revert`
pairs for `consensus.maxIterations`; run `learning-loop-engine --mode
consensus-history` → confirm an `auto-tune-ineffective` finding names the
key; run `learning-apply` with the key allowlisted → confirm it
**self-demotes** to propose-only (`Applied: demoted`); arm a 2-key
transactional watch + finalise a regressing round → confirm both keys'
snapshot restored + both cooled down; `autoApply` off (default) ⇒
everything unchanged.

## Out of Scope (→ Sprint 25+)

- **Auto-applying source/template changes** / **auto-forking the phase
  specialist** (still operator-initiated; Sprint 22-C routing unchanged).
- **Embedding-based excerption / memory** (S21 deferral, unchanged).
- **Cross-project meta-learning** (sharing auto-tune effectiveness across
  repos). Single-project only.
