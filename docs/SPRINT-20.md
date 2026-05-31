# Sprint 20 — Close the L3 Learning Loop: Consensus Telemetry Mining + Cross-Session Reviewer Memory (v2.8.0)

> ✅ **COMPLETE** — shipped v2.8.0 on 2026-05-31. All ten tickets (S20-A..J) landed. Tests: sdlc-engine 160→168, hooks 117→133, new `sprint-20.sh` (85); total baseline 2270 → 2379 across 20 layers.

## Context

Sprints 14–19 built VibeFlow's **fast loop**: CLI-driven consensus (S14), the closed CLI-verdict plumbing (S15), the deterministic auto-consensus gate (S16), iterative negotiation rounds (S17), full auto-satisfy (S18), and primary-artifact refocus + `phase-runner` (S19). Each of those operates on a *single* run and asks "is this artifact ready right now?".

What's missing is the **slow loop** — the L3 Truth-Evolution layer that looks *across time*. Three facts make this the obvious Sprint 20:

1. **Telemetry already accrues but nobody reads it.** Every consensus round already persists `.vibeflow/state/consensus/<session>.jsonl` (per-reviewer rows: `round`, `verdict`, `criticalIssues`, `suggestions`) and `<session>.verdict.json` (aggregated, with a `rounds[]` agreement curve). Arbiter runs persist `.vibeflow/state/patches/<session>/manifest.json` (which suggestions were APPLIED vs REJECTED). This is rich data that is written and then ignored.
2. **`learning-loop-engine` exists on disk but is unwired** to that telemetry — it only consumes L2 *test* reports (regression/mutation/coverage). `consensus-arbiter/SKILL.md:210` even leaves a marker: *"learning-loop-engine (Sprint 18+ candidate) may consume the [telemetry]"*. Sprint 19's "Out of Scope" names this as the #1 Sprint 20 item.
3. **Reviewers have amnesia.** Every consensus round starts cold; a reviewer re-raises issues it raised last round (or last sprint) with no memory of whether they were resolved. Sprint 19 deferred "cross-session reviewer memory" to Sprint 20.

**Goal:** close the loop. Persist a durable cross-session consensus history, teach `learning-loop-engine` to mine it for structural quality drift, give reviewers memory of their prior verdicts, and clean up the two small S19-deferred polish items. Outcome: a team running VibeFlow accumulates institutional memory — consensus gets cheaper and sharper over sprints instead of resetting every run.

User direction (this session): **full L3 loop** + both polish items (`primaryArtifact` in the gate message + `decision-recommender` wiring).

## Design Overview — five groups, ten tickets

### Group 1 — Durable consensus history (foundation)

**S20-A — Append-only cross-session consensus history.**
The per-session files are siloed. Add one append-only roll-up the slow loop can scan: `.vibeflow/state/consensus/history.jsonl`. One row per finalized verdict round, written at the point the aggregated `verdict.json` is produced.

Row schema (compact, stable):
```json
{
  "sessionId": "…", "phase": "REQUIREMENTS", "primaryArtifact": "docs/PRD.docx",
  "round": 2, "status": "NEEDS_REVISION", "agreement": 0.78,
  "counts": { "approved": 1, "needsRevision": 2, "rejected": 0, "critical": 2 },
  "reviewers": [ { "name": "codex", "verdict": "NEEDS_REVISION", "critical": 1 }, … ],
  "suggestionThemes": ["ambiguity", "missing-acceptance-criteria"],
  "recordedAt": "…"
}
```
Plus an arbiter-decision row appended by `apply-arbiter-patch` per run: `{ sessionId, round, applied:[themes], rejected:[themes], recordedAt }`.

- **Write points:** the aggregator/orchestrator path that already finalizes `verdict.json` (`consensus-aggregator.sh` + `consensus-orchestrator/SKILL.md` Step where the verdict is written), and `apply-arbiter-patch/SKILL.md` Step 8/9 for the arbiter row.
- **Reuse:** existing `vf_state_dir` helper from `hooks/scripts/_lib.sh`; existing `jq` row-building idiom from `append_cli_verdict()` in the orchestrator.
- **Harness `[S20-A]`:** append-on-finalize sentinel, JSONL well-formedness, schema-key presence, idempotency (re-running same round doesn't duplicate the row — keyed by `sessionId+round`).

### Group 2 — `learning-loop-engine` mines the history

**S20-B — New `consensus-history` mode (mode 4).**
Add a fourth mode to `skills/learning-loop-engine/SKILL.md` alongside `test-history` / `production-feedback` / `drift-analysis`. Input contract: `history.jsonl` over the sprint window (`--sprint N`, default last 3). Pattern detectors (each must carry ≥3 supporting observations — existing gate contract):
- **Slow-converging phases** — phases that repeatedly need `round > 1` before APPROVED.
- **Reviewer skew** — a reviewer raising a disproportionate share of criticals across sessions.
- **Recurring suggestion themes** — the same theme reappearing across artifacts/sprints (→ a systemic PRD/ADR/test gap, not a one-off).
- **Convergence stalls** — repeated `convergence-stalled.md` / `max-iterations-reached.md` events.
- **Primary-artifact churn** — one artifact consuming many rounds across sessions.

Output: `.vibeflow/reports/consensus-learning-report.md` with the explainability contract (`{finding, why, impact, confidence}`) + actionable recommendations.
- **Harness `[S20-B]`:** mode registered in frontmatter/prose, input-contract table row, ≥3-observation rule restated, output path sentinel.

**S20-C — Arbiter-decision effectiveness trace.**
Within the `consensus-history` mode, correlate APPLIED arbiter suggestions (from the S20-A arbiter rows + patch manifests) against the *next* round's `agreement` delta in `history.jsonl`. Surfaces "theme X applied but agreement didn't move" (wasted-effort signal) and "themes that reliably converge". Feeds the recommendations section.
- **Harness `[S20-C]`:** prose sentinel for the apply→next-round-delta correlation + wasted-effort recommendation example.

### Group 3 — Cross-session reviewer memory

**S20-D — Reviewer memory store.**
On each finalized reviewer verdict, append a bounded entry to `.vibeflow/state/consensus/reviewer-memory/<reviewer>.md` (one file per reviewer; `codex` / `gemini` / `claude`). Entry: `{ date, phase, primaryArtifact, status, top criticals (≤3) }`. Cap to the last `maxEntriesPerArtifact` entries per `(reviewer, artifact)` to bound size; oldest summarized/dropped.
- **Write point:** same finalize path as S20-A.
- **Harness `[S20-D]`:** per-reviewer file path, append-on-verdict sentinel, cap/bounding prose.

**S20-E — Orchestrator injects memory into reviewer prompts.**
In `consensus-orchestrator/SKILL.md`, before each `codex exec` / `gemini` invocation (and the `claude-reviewer` agent), prepend a bounded `PRIOR REVIEW MEMORY` block resolved from S20-D for that `(reviewer, primaryArtifact)`: *"On <date> at <phase> you raised: …. Verify whether these were addressed; do not re-raise resolved items; escalate if they recur."* Respects `reviewerMemory.tokenBudget`; absent memory → block omitted (clean first-run behavior).
- **Harness `[S20-E]`:** prompt-block prose sentinel, token-budget guard, no-memory-omitted regression.

### Group 4 — S19-deferred polish

**S20-F — `primaryArtifact` in the consensus-gate block message.**
`hooks/scripts/consensus-gate.sh:93` reads `.artifact`; the block message names the evidence report, not the doc under review. Change to read `.primaryArtifact // .artifact` and surface the primary path in the blocking stderr so the operator sees the real artifact.
- **Hook-test `[S20-F]`:** marker-with-`primaryArtifact` → message names the primary; legacy marker (only `.artifact`) → falls back, no regression.

**S20-G — `decision-recommender` consumes the learning report.**
Wire `skills/decision-recommender/SKILL.md` input contract to accept `consensus-learning-report.md` (S20-B) as a findings source, alongside its existing L2-report inputs, and emit `decision-package.md` (PIPELINE-4 step 2). Preserves existing gate contract (every recommendation cites findings; "do nothing" is option zero).
- **Harness `[S20-G]`:** input-contract row sentinel + PIPELINE reference.

### Group 5 — Config, docs, tests, release

**S20-H — Typed config + phase-policy registration.**
In `mcp-servers/sdlc-engine/src/config.ts`, add (matching the existing `ConsensusConfigSchema` / `PhaseRunnerConfigSchema` pattern):
- `LearningLoopConfigSchema` — `{ enabled: true, sprintWindow: 3, minObservations: 3 }`
- `ReviewerMemoryConfigSchema` — `{ enabled: true, maxEntriesPerArtifact: 5, tokenBudget: 600 }`

Compose both into `EngineConfigSchema`; add partial-merge branches in `loadConfig` (mirror the `consensus`/`phaseRunner` `safeParse` blocks at config.ts:107–118). Register both skills' write paths in `hooks/scripts/phase-policy.json`. Unit tests in `mcp-servers/sdlc-engine/tests/` for schema defaults + partial merge (mirror the S17-F / S19-G config tests).

**S20-I — Integration harness + hook tests + docs.**
- `tests/integration/sprint-20.sh` — **≈85 assertions** across `[S20-A]..[S20-Z]` (sized from sprint-19.sh's 87) + harness self-audit `[S20-Z]`.
- `hooks/tests/run.sh` — +≈6 assertions: history-append idempotency, gate-message `primaryArtifact` fallback (S20-F), reviewer-memory cap.
- Docs: new `docs/LEARNING-LOOP.md` + `docs/REVIEWER-MEMORY.md`; refresh `docs/CONSENSUS-FLOW.md` + `docs/CONSENSUS-ITERATION.md` to reference the history roll-up and memory injection.

**S20-J — v2.8.0 release.**
- `plugin.json`: `2.7.0 → 2.8.0` (minor — additive; history/memory absent ⇒ clean degrade, no breaking change).
- `@vibeflow/sdlc-engine`: minor bump (two new config schemas).
- `CHANGELOG.md` entry + `release-notes/v2.8.0.md`.
- Update CLAUDE.md test-layer counts + Sprint-20 ✅ COMPLETE summary line.
- Mark `docs/SPRINT-19.md` chain done, create this file as `docs/SPRINT-20.md`, update ROADMAP appendix row.
- Git tag `v2.8.0`.

## Files Touched (representative)

| Area | Files |
|---|---|
| History persistence (S20-A) | `hooks/scripts/consensus-aggregator.sh`, `skills/consensus-orchestrator/SKILL.md`, `skills/apply-arbiter-patch/SKILL.md` |
| Learning loop (S20-B/C) | `skills/learning-loop-engine/SKILL.md` (+`references/pattern-detection.md`) |
| Reviewer memory (S20-D/E) | `skills/consensus-orchestrator/SKILL.md`, `agents/claude-reviewer.md` |
| Polish (S20-F/G) | `hooks/scripts/consensus-gate.sh`, `skills/decision-recommender/SKILL.md` |
| Config (S20-H) | `mcp-servers/sdlc-engine/src/config.ts` (+ tests), `hooks/scripts/phase-policy.json` |
| Tests/docs (S20-I) | `tests/integration/sprint-20.sh`, `hooks/tests/run.sh`, `docs/LEARNING-LOOP.md`, `docs/REVIEWER-MEMORY.md`, `docs/CONSENSUS-FLOW.md`, `docs/CONSENSUS-ITERATION.md` |
| Release (S20-J) | `plugin.json`, `mcp-servers/sdlc-engine/package.json`, `CHANGELOG.md`, `release-notes/v2.8.0.md`, `CLAUDE.md`, `ROADMAP.md` |

## Verification (merge-green gate)

| Layer | Before (v2.7.0) | After (v2.8.0, target) | Delta |
|---|---|---|---|
| `sdlc-engine` unit | ~161 | ~166 | +≈5 (two config schemas + merge) |
| `hooks/tests/run.sh` | 117 | ~123 | +≈6 (history append, gate-msg, memory cap) |
| `tests/integration/run.sh` | 398 | 398 | 0 |
| Sprint-*.sh bundle | ~1593 | ~1678 | +≈85 (sprint-20.sh) |
| **Total** | **2270** | **~2366** | **+≈96** |

Run before declaring any ticket done (per CLAUDE.md): the 5 MCP `npm test` suites, `bash hooks/tests/run.sh`, `bash tests/integration/run.sh`, and `bash tests/integration/sprint-20.sh`. Rebuild `sdlc-engine` dist after the config change.

**E2E walk (FlowBridge_TR-style):** run two consensus rounds on a PRD via `phase-runner`; confirm (1) `history.jsonl` gains one row per round, (2) round 2's reviewer prompt carries a `PRIOR REVIEW MEMORY` block referencing round 1's criticals, (3) `learning-loop-engine --mode consensus-history` emits `consensus-learning-report.md` naming the recurring theme, (4) the consensus-gate block message names the PRD (not the report), (5) `decision-recommender` ingests the learning report into `decision-package.md`.

## Out of Scope (→ Sprint 21+)

- Phase-runner TUI / progress bar (S19 deferral, unchanged).
- Semantic primary-artifact excerption scoring (S19 deferral).
- Reviewer memory *summarization via LLM* (Sprint 20 uses simple recency cap; semantic compaction later).
- Auto-satisfy for `design.approved` / `accessibility.verified` / `sprint.planned` (stays manual per S18 decision).
