# Sprint 28 — Cross-Project Meta-Learning (Read-Only, v2.16.0)

> ✅ **COMPLETE** — shipped v2.16.0 on 2026-06-05 (backlog B2). Five tickets (S28-A..E) landed. Tests: sdlc-engine 196→199, hooks 167→174, new `sprint-28.sh` (44); total baseline 2786 → 2840 across 28 layers.

## Context

The meta-learning loop (Sprint 24) is **single-project**: it records each
auto-tune outcome (`auto-apply` → `auto-revert` | `auto-apply-held`) in
that project's `history.jsonl`, and `learning-loop-engine`'s
`auto-tune-ineffective` detector mines it. But every project re-learns
from scratch — a config tune that reliably *holds* in five repos is
re-discovered (and re-reverted on the bad ones) in the sixth.

The operator here runs many projects (FlowBridge + ~20 others). Sprint 28
lets them share what auto-tuning learned **across** repos — safely:

- **Opt-in, default off** — nothing leaves a project unless turned on.
- **Privacy-safe** — only `{config-key, outcome, phase, projectHash}`
  leaves a repo. No code, no content, no artifact/file names, no theme
  text. `projectHash` is a one-way hash of the project id, so distinct
  repos can be *counted* but not *identified*.
- **Read-only recommendation** — a new project *reads* the cross-project
  signal and surfaces it as a **recommendation** in the learning report
  ("`consensus.maxIterations` held in 8/10 projects — consider
  allowlisting"). It **never** auto-allowlists or auto-applies anything;
  the operator decides.

User direction (this session): **B2 cross-project meta-learning**, **opt-in
read-only recommendation** store (privacy-safe).

## Design Overview — five groups, five tickets

### Group 1 — Config + global store path (S28-A)

- `config.ts`: new top-level `GlobalLearningConfigSchema`
  `{ enabled: false }` (compose into `EngineConfigSchema` + `loadFileConfig`
  merge, mirror Sprint 25-C `loopAudit`). Default **off**.
- `hooks/scripts/_lib.sh`: new `vf_global_dir()` →
  `${VIBEFLOW_GLOBAL_DIR:-$HOME/.vibeflow}` (overridable for tests).
- `vf_project_hash()` → `shasum -a 256` of the project id, first 12 chars
  (stable, one-way; no external dep beyond `shasum`, present on macOS +
  Linux).
- Unit tests (config default + merge); hook-test for the helpers.

### Group 2 — Write privacy-safe outcomes to the global store (S28-B)

When `globalLearning.enabled` is true, mirror each auto-tune outcome to
`$(vf_global_dir)/global-learning.jsonl` — **only** the privacy-safe
fields:

```json
{ "key": "consensus.maxIterations", "outcome": "held",
  "phase": "REQUIREMENTS", "projectHash": "a1b2c3d4e5f6", "recordedAt": "…" }
```

Write points (gated, append-only, never blocks the caller):
- `consensus-aggregator.sh` — the Sprint 23-C/24-A `auto-revert`
  (`outcome:"reverted"`) and `auto-apply-held` (`outcome:"held"`) branches.
- `skills/learning-apply/SKILL.md` Step 7 — the `auto-apply`
  (`outcome:"applied"`) row.

No `primaryArtifact`, no theme titles, no file paths — those stay in the
per-project `history.jsonl` only.

- **Harness `[S28-B]`:** hook-test runtime — enabled ⇒ a privacy-safe row
  appears in the global store with exactly `{key, outcome, phase,
  projectHash, recordedAt}` and **no** `primaryArtifact`/file fields;
  disabled (default) ⇒ nothing written; the per-project history.jsonl is
  unaffected either way.

### Group 3 — `cross-project-signal` detector (S28-C)

`learning-loop-engine` `consensus-history` mode gains a detector that
reads `$(vf_global_dir)/global-learning.jsonl` (when present), aggregates
per-key outcomes **across distinct `projectHash`es**, and emits a
**read-only recommendation**:

- **`LEARNING-CROSS-PROJECT-SIGNAL`** — for a config key seen in ≥ 3
  distinct projects: if its hold-rate (`held / (held+reverted)`) ≥ 0.7 →
  "consider allowlisting `<key>` (held in N/M projects)"; if ≤ 0.3 →
  "avoid auto-applying `<key>` (reverted in N/M projects)". Always
  advisory; the report states explicitly that this **does not**
  auto-allowlist. `references/pattern-detection.md` catalog entry;
  `patternCatalogVersion` → 4.

- **Harness `[S28-C]`:** detector named in SKILL + catalog entry +
  cross-project hold-rate signature + the explicit "recommendation only,
  never auto-allowlists" guardrail.

### Group 4 — Docs + harness (S28-D)

- New `docs/CROSS-PROJECT-LEARNING.md` — the opt-in model, the
  privacy-safe row (what does / does NOT leave a repo), the read-only
  recommendation guarantee, the global store path + `VIBEFLOW_GLOBAL_DIR`
  override, and how to wipe it (`rm ~/.vibeflow/global-learning.jsonl`).
  Refresh `docs/META-LEARNING.md` (single → cross-project).
- `tests/integration/sprint-28.sh` — **≈55 assertions** across
  `[S28-A]..[S28-Z]` + self-audit `[S28-Z]` (config + helper sentinels +
  privacy-shape prose + detector sentinels + a write/read runtime probe
  using `VIBEFLOW_GLOBAL_DIR` pointed at a temp dir).
- `hooks/tests/run.sh` — +≈5 (global-store write enabled/disabled +
  privacy-shape + projectHash stability).

### Group 5 — Release (S28-E)

- `.claude-plugin/plugin.json` + `marketplace.json`: 2.15.0 → 2.16.0.
- `@vibeflow/sdlc-engine`: 1.13.0 → 1.14.0 (`GlobalLearningConfigSchema`).
- `CHANGELOG.md` + `release-notes/2.16.0.md`; CLAUDE.md test counts +
  Sprint-28 ✅ COMPLETE; ROADMAP appendix row + tick **B2**; mark
  `docs/SPRINT-28.md` COMPLETE; commit + tag `v2.16.0` + push.

## Files Touched (representative)

| Area | Files |
|---|---|
| Config + helpers (S28-A) | `mcp-servers/sdlc-engine/src/config.ts` (+ tests), `hooks/scripts/_lib.sh` |
| Global-store writes (S28-B) | `hooks/scripts/consensus-aggregator.sh`, `skills/learning-apply/SKILL.md` (+ `hooks/tests/run.sh`) |
| Detector (S28-C) | `skills/learning-loop-engine/SKILL.md` (+ `references/pattern-detection.md`) |
| Docs/harness (S28-D) | `tests/integration/sprint-28.sh`, `docs/CROSS-PROJECT-LEARNING.md`, `docs/META-LEARNING.md` |
| Release (S28-E) | `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `mcp-servers/sdlc-engine/package.json`, `CHANGELOG.md`, `release-notes/2.16.0.md`, `CLAUDE.md`, `ROADMAP.md` |

## Reused patterns (don't reinvent)

- **Gated, append-only outcome rows** — Sprint 24-A `history.jsonl`
  writes; S28-B is the same shape, privacy-filtered, to a global path.
- **consensus-history detectors** — Sprint 20-B/24-B catalog in
  `references/pattern-detection.md`; S28-C adds one entry.
- **Typed config defaulted + partial-merge** — `config.ts` schema family.
- **`vf_state_dir` / `vf_config_get`** — `hooks/scripts/_lib.sh`;
  `vf_global_dir`/`vf_project_hash` are siblings.

## Verification (merge-green gate)

| Layer | Before (v2.15.0) | After (v2.16.0, target) | Delta |
|---|---|---|---|
| `sdlc-engine` unit | 196 | ~199 | +≈3 (GlobalLearningConfigSchema) |
| `hooks/tests/run.sh` | 167 | ~172 | +≈5 (global-store write/privacy/hash) |
| `tests/integration/run.sh` | 399 | 399 | 0 |
| Sprint-*.sh bundle | ~2038 | ~2093 | +≈55 (sprint-28.sh) |
| **Total** | **2786** | **~2849** | **+≈63** |

Run with `env -u VF_ALLOW_PHASE_WRITE` and `VIBEFLOW_GLOBAL_DIR` pointed
at a temp dir in tests (never touch the real `~/.vibeflow`): 5 MCP
`npm test`, `bash hooks/tests/run.sh`, `bash tests/integration/run.sh`,
`bash tests/integration/sprint-28.sh`. Rebuild `sdlc-engine` dist.

**E2E walk:** with `globalLearning.enabled:false` (default) finalize an
auto-tune outcome → nothing in the global store. Set it true → a
privacy-safe row (`{key, outcome, phase, projectHash}` only — no file
names) lands in `$VIBEFLOW_GLOBAL_DIR/global-learning.jsonl`. Seed the
global store with the same key held across 3 distinct `projectHash`es →
`learning-loop-engine --mode consensus-history` emits a
`cross-project-signal` recommendation naming the key + N/M, explicitly
noting it does NOT auto-allowlist.

## Out of Scope (→ Sprint 29+)

- **Auto-seeding `autoApply.keys` from cross-project data** — rejected
  this session; cross-project is read-only recommendation. One repo's
  record never changes another's behaviour automatically.
- **Embedding-based excerption** (B3), **live TUI** (B4), **phase-runner
  TESTING auto-run** (B5) — unchanged backlog.
- **Networked / shared-team store** — the store is a local file
  (`~/.vibeflow`); no server, no sync.
