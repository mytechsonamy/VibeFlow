# Sprint 25 — Autonomous-Loop Observability (v2.13.0)

> ✅ **COMPLETE** — shipped v2.13.0 on 2026-06-05. All five tickets (S25-A..E) landed. Tests: sdlc-engine 182→185, hooks 155→167, new `sprint-25.sh` (42); total baseline 2620 → 2677 across 25 layers.

## Context

Sprints 20–24 built a deep autonomous slow loop: consensus history
mining, reviewer memory, learning-apply, bounded auto-apply +
auto-revert, and self-correcting meta-learning. Each landed its own
telemetry — `history.jsonl` rows (`verdict`, `arbiter-decision`,
`auto-apply`, `auto-revert`, `auto-apply-held`), `auto-apply-reverts.md`,
`cooldown-<key>` markers, `auto-apply/watch.json`,
`consensus-learning-report.md`, `learning-apply-decisions.md`,
`phase-runner-progress.json`. The loop is now quite autonomous **but
opaque**: an operator who wants to answer "what has the loop been doing —
what auto-applied, what got reverted, which keys are cooled down, what
does the learning report recommend?" has to open six files. There is no
single pane of glass.

`/vibeflow:status` only surfaces phase + quality + the Sprint 21-D
phase-runner progress. Sprint 25 makes the autonomous loop **observable
and auditable** from one place — the trust layer the autonomy now needs.

User direction (this session): **autonomy audit / observability**, surfaced
as a **new `/vibeflow:status` section fed by a testable audit reader
script** (not a separate skill).

## Design Overview — four groups, five tickets

### Group 1 — `loop-audit.sh` reader (S25-A)

New read-only `hooks/scripts/loop-audit.sh` that consolidates the
scattered telemetry into one compact JSON summary on stdout. It reuses
`vf_state_dir` / `vf_cwd` and is **fully guarded** — every absent file
degrades to zeros/empties, so it never errors on a fresh project.

Reads:
- `history.jsonl` — group `auto-apply` / `auto-revert` / `auto-apply-held`
  rows by `key` over the recent `loopAudit.window` rows; also the latest
  `verdict` agreement.
- `auto-apply/cooldown-*` markers → currently cooled-down keys.
- `auto-apply/watch.json` → the armed (pending-evaluation) watch, if any.
- `consensus-learning-report.md` → finding count (count of `### ` finding
  headers).
- `learning-apply-decisions.md` → the last few decision headers.

Emits:
```json
{
  "autoApply": {
    "applied": 3, "reverted": 2, "held": 1,
    "armedWatch": { "keys": ["consensus.maxIterations"], "phase": "…", "primaryArtifact": "…" },
    "cooldowns": ["consensus.maxIterations"]
  },
  "perKey": [
    { "key": "consensus.maxIterations", "applied": 3, "reverted": 2, "held": 1, "revertRate": 0.67, "cooledDown": true }
  ],
  "learning": { "reportExists": true, "findingCount": 4 },
  "recentDecisions": ["CONFIG-TUNE — consensus.maxIterations 5 → 7", "…"]
}
```

- **Harness `[S25-A]`:** hook-test runtime — seed `history.jsonl` +
  cooldown markers + a watch + reports; assert the reader's counts,
  per-key `revertRate`, `cooledDown`, `armedWatch`, and `findingCount`;
  empty project → all-zero well-formed JSON.

### Group 2 — `/vibeflow:status` "Autonomous Loop" section (S25-B)

Add **Section 6 — Autonomous Loop** to `skills/status/SKILL.md`. It runs
`loop-audit.sh` and renders:
- auto-apply tally (applied / held / reverted) + per-key revert rates,
  flagging any key whose `revertRate ≥ 0.5` as "candidate for removal
  from `autoApply.keys`" (mirrors the S24-B detector signal);
- currently **cooled-down** keys + the **armed watch** (a tune awaiting
  next-round judgement);
- the learning report's finding count + how to read it
  (`/vibeflow:learning-loop-engine --mode consensus-history`);
- the last few `learning-apply` decisions.

When `autoApply` was never enabled (no rows, no markers, no reports), the
section collapses to a single line: "Autonomous loop: idle (autoApply
off / no activity)" — no noise for projects that don't use it.

- **Harness `[S25-B]`:** status prose sentinels (runs `loop-audit.sh`,
  renders cooldowns / armed watch / revert-rate flag / learning count /
  recent decisions + the idle collapse).

### Group 3 — Config (S25-C)

`config.ts`: new `LoopAuditConfigSchema` — `{ window: 20 }` (the recent-row
window the reader summarizes; `int [1, 1000]`). Compose into
`EngineConfigSchema` + `loadFileConfig` merge (mirror S20-H/S22-D).
`loop-audit.sh` reads `loopAudit.window` (default 20). Unit tests
(default + range + partial-merge).

### Group 4 — Docs, harness, release (S25-D, S25-E)

**S25-D — docs + harness.**
- New `docs/LOOP-AUDIT.md` (what the autonomous-loop audit surfaces, the
  reader's JSON contract, how to read each signal, config). Refresh
  `docs/AUTO-APPLY.md` + `docs/META-LEARNING.md` (point to the audit).
- `tests/integration/sprint-25.sh` — **≈55 assertions** across
  `[S25-A]..[S25-Z]` + self-audit `[S25-Z]` (reader prose + status
  section sentinels + config + a reader runtime probe).
- `hooks/tests/run.sh` — +≈6 for the `loop-audit.sh` reader runtime
  (counts, per-key revert rate, cooldowns, armed watch, empty-project).

**S25-E — v2.13.0 release.**
- `.claude-plugin/plugin.json` + `marketplace.json`: 2.12.0 → 2.13.0.
- `@vibeflow/sdlc-engine`: 1.10.0 → 1.11.0 (`LoopAuditConfigSchema`).
- `CHANGELOG.md` + `release-notes/2.13.0.md`; CLAUDE.md test counts +
  Sprint-25 ✅ COMPLETE; ROADMAP appendix row; mark `docs/SPRINT-25.md`
  COMPLETE; commit + tag `v2.13.0` + push.

## Files Touched (representative)

| Area | Files |
|---|---|
| Reader (S25-A) | `hooks/scripts/loop-audit.sh` (+ `hooks/tests/run.sh`) |
| Status section (S25-B) | `skills/status/SKILL.md` |
| Config (S25-C) | `mcp-servers/sdlc-engine/src/config.ts` (+ tests) |
| Docs/harness (S25-D) | `tests/integration/sprint-25.sh`, `docs/LOOP-AUDIT.md`, `docs/AUTO-APPLY.md`, `docs/META-LEARNING.md` |
| Release (S25-E) | `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `mcp-servers/sdlc-engine/package.json`, `CHANGELOG.md`, `release-notes/2.13.0.md`, `CLAUDE.md`, `ROADMAP.md` |

## Reused patterns (don't reinvent)

- **Guarded jq reader over `history.jsonl`** — same idiom as the Sprint
  20-A aggregator history append + Sprint 24 detector counting.
- **`/vibeflow:status` renders a state file** — Sprint 21-D phase-runner
  progress section is the template for Section 6 (incl. its idle/stale
  collapse).
- **`vf_state_dir` / `vf_cwd` helpers** — `hooks/scripts/_lib.sh`.
- **Typed config defaulted + partial-merge** — `config.ts` schema family.

## Verification (merge-green gate)

| Layer | Before (v2.12.0) | After (v2.13.0, target) | Delta |
|---|---|---|---|
| `sdlc-engine` unit | 182 | ~185 | +≈3 (LoopAuditConfigSchema) |
| `hooks/tests/run.sh` | 155 | ~161 | +≈6 (loop-audit reader runtime) |
| `tests/integration/run.sh` | 399 | 399 | 0 |
| Sprint-*.sh bundle | ~1898 | ~1953 | +≈55 (sprint-25.sh) |
| **Total** | **2620** | **~2684** | **+≈64** |

Run with `env -u VF_ALLOW_PHASE_WRITE`: 5 MCP `npm test`,
`bash hooks/tests/run.sh`, `bash tests/integration/run.sh`,
`bash tests/integration/sprint-25.sh`. Rebuild `sdlc-engine` dist.

**E2E walk:** seed `history.jsonl` with `auto-apply`/`auto-revert`/
`auto-apply-held` rows for two keys, a `cooldown-<key>` marker, an armed
`watch.json`, and a `consensus-learning-report.md`; run `loop-audit.sh`
→ confirm per-key counts + `revertRate` + `cooledDown` + `armedWatch` +
`findingCount`; render `/vibeflow:status` → confirm the Autonomous Loop
section shows them + flags the high-revert-rate key; empty project → the
section collapses to the idle line and the reader emits all-zero JSON.

## Out of Scope (→ Sprint 26+)

- **Template-route autonomy** (auto-fork the phase specialist) — still
  operator-initiated; Sprint 22-C routing unchanged.
- **Cross-project meta-learning** (shared auto-tune store) — single
  project only.
- **Embedding-based excerption / memory** (S21 deferral, unchanged).
- **A separate `/vibeflow:loop-status` skill / TUI** — Section 6 of
  `/vibeflow:status` is the chosen surface; a dedicated dashboard is
  later.
