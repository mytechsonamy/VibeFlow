# Sprint 19 — Refocus Consensus on Primary Artifacts + End-to-End Phase Automation (v2.7.0)

## Context

Sprint 18 (v2.6.0) completed auto-satisfy across every automatable exit criterion. Sprint 18.1 hotfix (v2.6.1, shipped earlier today 2026-04-22) added the `save-plan-doc.sh` persistence hook and backfilled SPRINT-14..18 docs. The FlowBridge_TR walkthrough exposed a deeper architectural flaw: **we optimize the analyzer's opinion, not the project artifact.**

Concrete evidence from the 2026-04-22 run:

1. `prd-quality-analyzer` runs on the PRD → writes `prd-quality-report.md` and a marker whose `artifact` field points **to the report**, not the PRD.
2. `consensus-orchestrator` pipes that file into `codex exec` / `gemini` — so the 3-AI panel reviews the **report**, not the PRD. Reviewer comments then target the report ("Remove AMB-T-002 from report") instead of the PRD.
3. Aggregator hits `criticalTotal >= 2 → REJECTED` (consensus-aggregator.sh:267) **despite zero reviewers actually voting REJECTED** (2× NEEDS_REVISION + 1× APPROVED). Reviewer sentiment is overridden by a mechanical count.
4. Iteration loop never runs round 2 because REJECTED is hard-stop.
5. `consensus-specialist` refuses to dispatch on REJECTED (SKILL.md:64–71), leaving the operator hand-editing `verdict.json`.

User framing: "odağımız proje dokümanları olması gerekirken konsensa kalite raporlarını gönderiyoruz… sdlc süreçlerini sürtünmesiz, kaliteli ve otomatik yapacak bir kurgu."

Three root causes, one goal:
- **Wrong review target** (evidence vs primary artifact)
- **Mechanical REJECTED** (critical count overrides reviewer sentiment)
- **Manual chaining** (operator shepherds analyzer → consensus → arbiter → apply → re-consensus → advance)

## Design Overview

Five groups, nine tickets.

### Group 1 — Primary-artifact review refocus (S19-A, S19-B)

**Marker schema v2.** Every analysis skill's Final Step writes:

```json
{
  "primaryArtifact": "docs/FlowBridge_TR_SRS_v1_1.docx",
  "evidence": [
    ".vibeflow/reports/prd-quality-report.md",
    ".vibeflow/reports/prd-cost-avoidance.md"
  ],
  "artifact": ".vibeflow/reports/prd-quality-report.md",
  "requiredCommand": "/vibeflow:consensus-orchestrator docs/FlowBridge_TR_SRS_v1_1.docx",
  "createdAt": "…",
  "createdBy": "prd-quality-analyzer"
}
```

`artifact` is retained for backward compatibility — `consensus-gate.sh:93–94` only reads `artifact` + `requiredCommand` today, so no hook change is forced. The gate's operator message will point at the primary now because `requiredCommand` changes.

**Primary-artifact map per phase:**

| Phase | Primary artifact | Evidence sources | Analyzer skill |
|---|---|---|---|
| REQUIREMENTS | `docs/**/*.{docx,md}` PRD | `prd-quality-report.md`, `prd-cost-avoidance.md` | `prd-quality-analyzer` |
| DESIGN | `design/**` (operator-driven, no analyzer ships) | `design-report.md`, `accessibility-*.md` | — |
| ARCHITECTURE | `docs/architecture.md` + `docs/adr/**` | `architecture-report.md` | `architecture-validator` |
| PLANNING | `docs/test-strategy.md` + `docs/scenario-set.md` | `rtm.md`, carried-forward `prd-quality-report.md` | `test-strategy-planner`, `traceability-engine` |
| DEVELOPMENT | staged files in `HEAD` working tree (git diff HEAD~1..HEAD) | `quality-gates-report.md` | `quality-gates` |
| TESTING | `tests/**` + `coverage-report.md` summary | `mutation-report.md`, `coverage-report.md` | `coverage-analyzer`, `mutation-test-runner` |
| DEPLOYMENT | `release-notes/<version>.md` | `deploy-verification.md`, `release-decision.md` | `release-decision-engine`, `deploy-verifier` |

**Orchestrator prompt (S19-B).** Step 3 (`consensus-orchestrator/SKILL.md:113–147`) currently does `cat "$ARTIFACT" | codex exec "Review this for …"`. New logic:

```bash
# If incoming path is a marker JSON, resolve
if jq -e '.primaryArtifact' "$INPUT" >/dev/null 2>&1; then
  PRIMARY="$(jq -r '.primaryArtifact' "$INPUT")"
  EVIDENCE_FILES=( $(jq -r '.evidence[]?' "$INPUT") )
else
  PRIMARY="$INPUT"   # legacy single-file invocation
  EVIDENCE_FILES=()
fi
```

Reviewer prompt:

```
[base review instructions]

PRIMARY ARTIFACT UNDER REVIEW (verdict is about THIS document):
<content of PRIMARY, head + tail + findings-anchored sections if >30k tokens>

SUPPORTING EVIDENCE (analyzer context — informational, not the target):
1. <evidence[0] filename>: <top-3 findings distilled>
2. <evidence[1] filename>: <summary>

Review the PRIMARY ARTIFACT. Use EVIDENCE for context. Your verdict
decides whether the PRIMARY ARTIFACT is ready for phase exit.
```

### Group 2 — Status rule refactor (S19-C)

`hooks/scripts/consensus-aggregator.sh:267–268`:

```jq
# BEFORE
if .criticalTotal >= 2 then "REJECTED"
elif (.rejected * 2) > .total then "REJECTED"
elif .agreement >= 0.9 and .criticalTotal == 0 then "APPROVED"
else "NEEDS_REVISION" end

# AFTER — reviewer sentiment authoritative
if (.rejected * 2) > .total then "REJECTED"         # strict reject majority
elif .rejected >= 1 and .criticalTotal >= 2 then "REJECTED"  # reject + critical escalation
elif .agreement >= 0.9 and .criticalTotal == 0 then "APPROVED"
else "NEEDS_REVISION"
end
```

The `.criticalTotal >= 2` path loses its unconditional REJECTED promotion and becomes a modifier that requires at least one actual REJECTED vote. The FlowBridge_TR case (0 rejects + critical=2) now correctly lands as NEEDS_REVISION and iteration continues.

Field name is **`criticalTotal`**, not `criticalDedup` — Sprint 17-B's dedup logic already folds into `criticalTotal`'s computation.

### Group 3 — Specialist guardrail softening (S19-D)

`consensus-specialist/SKILL.md:64–71` currently stops on both APPROVED and REJECTED. New Step 1:

```
- APPROVED                               → stop ("nothing to rewrite")
- REJECTED with verdict.rejected >= 1    → stop ("genuine reject — operator triage")
- NEEDS_REVISION                         → dispatch specialist
- HUMAN_APPROVAL_REQUIRED                → dispatch specialist (per S17-C)
```

Reads `verdict.json.rejected` count to distinguish. With the S19-C rule change, the "soft REJECTED" case (0 rejects + critical>=2) no longer exists — aggregator now labels those NEEDS_REVISION, so specialist dispatches naturally.

### Group 4 — Apply auto-chain (S19-E)

`apply-arbiter-patch/SKILL.md` gains Step 8 "Auto-chain consensus":

1. Executes only after successful `git apply` + (if `--run-tests`) passing suite.
2. Reads `verdict.json.round` from the draining session; computes `nextRound = round + 1`.
3. If `nextRound > consensus.maxIterations`, skip auto-chain and write advisory `.vibeflow/reports/max-iterations-reached.md`.
4. Writes `.vibeflow/state/consensus-needed.json`:
   ```json
   {
     "primaryArtifact": "<carried from incoming session>",
     "evidence": ["<original evidence>", ".vibeflow/reports/arbiter-decisions.md"],
     "artifact": "<primaryArtifact, for gate back-compat>",
     "requiredCommand": "/vibeflow:consensus-orchestrator <primaryArtifact>",
     "createdAt": "…",
     "createdBy": "apply-arbiter-patch (auto-chain)",
     "autoChain": { "round": <nextRound>, "parentSessionId": "<sid>" }
   }
   ```
5. Prints: *"Round N applied. consensus-gate will block next tool call — run `/vibeflow:consensus-orchestrator <primary>` to verify convergence. Use `--no-chain` or `VF_SKIP_AUTO_CHAIN=1` to opt out."*

**Note on iteration storage.** Iteration tracking piggybacks on the existing `verdict.json.round` field (written by `consensus-aggregator.sh` since Sprint 17-A) rather than introducing a new `manifest.json.iteration` field. The orchestrator already increments rounds; apply just has to read the last round and point the next round at the updated primary.

**Guardrails:**
- `--no-chain` CLI flag (new; joins the existing `--yes`/`--run-tests`/`--dry-run` flag set).
- `VF_SKIP_AUTO_CHAIN=1` env override.
- Convergence-stall guard: if `verdict(round).agreement - verdict(round-1).agreement <= 0.05` and `round >= 2`, emit "convergence stalled" advisory and refuse chain.

### Group 5 — Phase runner (S19-F, S19-G)

New skill `/vibeflow:phase-runner [TARGET_PHASE]`:

```
allowed-tools: Read, Write, Bash(jq *), Bash(mkdir *), mcp__sdlc-engine__*
disable-model-invocation: false
```

Flow:
1. Resolve phase — arg or from `sdlc_get_status`.
2. Look up phase's analyzer(s) + primary from the built-in map below.
3. Invoke analyzer skill → it writes v2 marker → consensus-gate blocks next call.
4. Invoke consensus-orchestrator with the primary artifact (orchestrator resolves marker).
5. Branch on verdict:
   - **APPROVED:** call `mcp__sdlc-engine__sdlc_advance_phase` directly (no shelling out to `/vibeflow:advance`) if `phaseRunner.autoAdvance` is true.
   - **NEEDS_REVISION / HUMAN_APPROVAL_REQUIRED:** fork `consensus-specialist` → on patch success, `apply-arbiter-patch` auto-chain re-enters this loop (S19-E).
   - **REJECTED:** stop, emit operator triage advisory.
6. Bounded by `phaseRunner.maxConvergenceAttempts` (default 3) — distinct from `consensus.maxIterations` (default 5) which bounds a single convergence cycle.

Phase→analyzer map (hardcoded in the skill; matches `skills/phase-policy.json` registry):

```
REQUIREMENTS → [prd-quality-analyzer]
DESIGN       → []                         # no analyzer ships; skill announces manual criterion reminder
ARCHITECTURE → [architecture-validator]
PLANNING     → [test-strategy-planner, traceability-engine]
DEVELOPMENT  → [quality-gates]
TESTING      → [coverage-analyzer, mutation-test-runner]
DEPLOYMENT   → [release-decision-engine, deploy-verifier]
```

## Critical Files

### New
- `skills/phase-runner/SKILL.md` — end-to-end phase orchestrator
- `docs/PRIMARY-ARTIFACT.md` — marker schema v2 + phase-to-primary map + evidence distillation rules + back-compat notes
- `tests/integration/sprint-19.sh` — **≈85 assertions** across [S19-A]..[S19-Z] (sized from sprint-17.sh:283 lines/98 asserts, sprint-18.sh:223 lines/67 asserts)
- `release-notes/2.7.0.md`

### Modified
- `skills/consensus-orchestrator/SKILL.md` — Step 3 resolves marker vs legacy path; builds primary+evidence prompt
- `skills/consensus-arbiter/SKILL.md` — add note confirming `suggestions[].target.file` targets primary (already does per audit §6; just make it explicit)
- `skills/consensus-specialist/SKILL.md` — Step 1 guardrail: the 4-case rule above
- `skills/apply-arbiter-patch/SKILL.md` — new Step 8 auto-chain; `--no-chain` flag; convergence-stall guard
- `skills/{prd-quality-analyzer,architecture-validator,test-strategy-planner,traceability-engine,coverage-analyzer,mutation-test-runner,release-decision-engine,deploy-verifier}/SKILL.md` — marker v2 (8 skills — **audit confirmed the set**; `quality-gates` also writes a marker and will be included = 9 total, verify during implementation)
- `hooks/scripts/consensus-aggregator.sh` — new 4-branch status rule (lines 267–268)
- `hooks/scripts/consensus-gate.sh` — **no change needed** (reads only `artifact`+`requiredCommand`; both remain in marker v2)
- `mcp-servers/sdlc-engine/src/config.ts` — add `PhaseRunnerConfigSchema`; unit test +3 (defaults, overrides, invalid)
- `skills/phase-policy.json` — register `phase-runner` (phases: ALL)
- `docs/CONSENSUS-FLOW.md` — Layer 1 diagram: review target is primary; evidence is context
- `docs/CONSENSUS-ITERATION.md` — auto-chain flow diagram
- `docs/AUTO-SATISFY.md` — phase-runner as one-command alternative
- `CLAUDE.md` — **18 → 19 test layers, baseline 2180 → ≈2265** (+≈85 from sprint-19.sh + ≈4 from hooks/tests + ≈4 from sdlc-engine)
- `CHANGELOG.md` `[2.7.0] — 2026-04-22` (or next UTC day)
- `.claude-plugin/plugin.json` + `.claude-plugin/marketplace.json` — **2.6.1 → 2.7.0**
- `tests/integration/sprint-4.sh` — `EXPECTED_PLUGIN_VERSION=2.7.0`
- `mcp-servers/sdlc-engine/package.json` — minor bump (new schema; additive)

## Sprint Ticket Breakdown (9 tickets)

### S19-A — Marker schema v2 rollout (8 skills + 1 to verify)
Update each analysis skill's Final Step to write `primaryArtifact` + `evidence[]` + keep legacy `artifact`. Ship `docs/PRIMARY-ARTIFACT.md`. Harness `[S19-A]`: per-skill sentinel + primary-artifact-correctness + back-compat `artifact` field still present.

### S19-B — Orchestrator primary-artifact review
`consensus-orchestrator/SKILL.md` Step 3 parses input path: if marker JSON, resolve primary+evidence; else treat as primary (legacy). Reviewer prompt gains `PRIMARY ARTIFACT UNDER REVIEW` + `SUPPORTING EVIDENCE` blocks with distillation. >30k-token artifacts carry head + tail + findings-anchored sections. Harness `[S19-B]`: prose sentinels + legacy single-file invocation regression.

### S19-C — Aggregator status rule refactor
Replace lines 267–268 in `consensus-aggregator.sh`. Hook-test regression: `{rejected:0, approved:1, needs_revision:2, total:3, criticalTotal:2}` → NEEDS_REVISION; `{rejected:1, approved:0, needs_revision:2, total:3, criticalTotal:2}` → REJECTED; reject-majority `{rejected:2, …total:3}` → REJECTED. Harness `[S19-C]`.

### S19-D — Specialist guardrail refactor
`consensus-specialist/SKILL.md` Step 1 reads `verdict.json.rejected` to distinguish genuine vs soft REJECTED. Harness `[S19-D]`: 4-case prose coverage.

### S19-E — Apply auto-chain (iteration via verdict.round)
`apply-arbiter-patch/SKILL.md` Step 8 + `--no-chain` flag + `VF_SKIP_AUTO_CHAIN=1` + convergence-stall guard. Harness `[S19-E]`: prose + flag-presence + stall-guard prose.

### S19-F — Phase-runner skill (new)
`skills/phase-runner/SKILL.md` with hardcoded phase→analyzer map; calls `mcp__sdlc-engine__sdlc_advance_phase` MCP tool directly (not `/vibeflow:advance`); respects `phaseRunner.{autoAdvance,maxConvergenceAttempts}`. Harness `[S19-F]`: skill exists, map pins, auto-advance gate, max-convergence guard.

### S19-G — Config + phase-policy updates
`sdlc-engine/src/config.ts`:

```typescript
export const PhaseRunnerConfigSchema = z.object({
  autoAdvance:            z.boolean().default(true),
  maxConvergenceAttempts: z.number().int().min(1).max(10).default(3),
}).default({ autoAdvance: true, maxConvergenceAttempts: 3 });
```

Register on the root config schema. `skills/phase-policy.json` + `hooks/scripts/phase-policy.json` both register `phase-runner` (phases: ALL). Unit tests +3.

### S19-H — sprint-19.sh + docs update
`tests/integration/sprint-19.sh` ≈85 assertions. `docs/PRIMARY-ARTIFACT.md`, `docs/CONSENSUS-FLOW.md`, `docs/CONSENSUS-ITERATION.md`, `docs/AUTO-SATISFY.md` refreshes. Harness self-audit `[S19-Z]`.

### S19-I — v2.7.0 release
Plugin 2.6.1→2.7.0. sdlc-engine minor bump. CLAUDE.md: 19 test layers + baseline 2180→≈2265. CHANGELOG + release-notes/2.7.0.md. sprint-4.sh `EXPECTED_PLUGIN_VERSION`. package-plugin.sh regen. Tag + push + gh release.

## Verification — FlowBridge_TR re-run

```
/vibeflow:phase-runner
  ├─ prd-quality-analyzer runs → v2 marker written
  │    primaryArtifact = docs/FlowBridge_TR_SRS_v1_1.docx
  │    evidence        = [prd-quality-report.md, prd-cost-avoidance.md]
  ├─ consensus-orchestrator <PRD>
  │    Round 1: 2 NEEDS_REVISION + 1 APPROVED, criticalTotal=2, rejected=0
  │    → status = NEEDS_REVISION  (S19-C rule: no reject votes ⇒ not REJECTED)
  │    → auto-record consensus
  ├─ consensus-specialist dispatches prd-rewriter
  │    rewrites PRD as diff-first patch
  ├─ apply-arbiter-patch --run-tests
  │    patches apply, tests pass
  │    → Step 8 auto-chain: writes v2 marker, round=2, primary=<PRD>
  ├─ consensus-gate blocks next tool call
  ├─ consensus-orchestrator <PRD>  (round 2)
  │    Round 2: 3 APPROVED on the updated PRD
  │    → status = APPROVED
  └─ phase-runner sees APPROVED → mcp__sdlc-engine__sdlc_advance_phase
       REQUIREMENTS → DESIGN
```

Single operator command; end-to-end convergence.

## Risks & Mitigations

1. **Primary artifact too large for prompt.** 20–50k-line PRDs exceed context. Mitigation: orchestrator carries head + tail + findings-anchored excerpts for artifacts >30k tokens; specialist still receives the full file as diff-first input.
2. **Auto-chain infinite loop.** Mitigation: `consensus.maxIterations` hard stop + convergence-stall guard (agreement delta ≤ 0.05 ⇒ stop with advisory).
3. **Legacy (pre-v2.7.0) markers in flight.** Mitigation: orchestrator + arbiter + specialist all fall back to the `artifact` field when `primaryArtifact` is absent. Zero breaking change for in-flight projects.
4. **Phase-runner over-automation.** Mitigation: `phaseRunner.autoAdvance: false` keeps advance manual; prose announces every step before running; `--pause-between-steps` flag for one-at-a-time operation.
5. **`consensus-gate.sh` doesn't surface `primaryArtifact` in its block message.** Not a blocker — `requiredCommand` now points at the primary, so the operator message already tells them what to review. Deferred to Sprint 20 polish.
6. **`quality-gates` skill marker audit.** Audit named 8 marker-writing skills but `quality-gates` (Sprint 18-F) also writes one. Confirm inventory during S19-A implementation — may be 9, not 8.

## Versioning

- Plugin: **`2.6.1 → 2.7.0`** (minor — additive; backward-compatible via legacy-marker fallback)
- `@vibeflow/sdlc-engine`: minor bump (new `PhaseRunnerConfigSchema`)
- Git tag: `v2.7.0`

## Verification Summary (merge-green gate)

| Layer | Before (v2.6.1) | After (v2.7.0) | Delta |
|---|---|---|---|
| `sdlc-engine` unit | 157 | ≈161 | +4 (PhaseRunner schema + merge tests) |
| `hooks/tests/run.sh` | 117 | ≈121 | +4 (status-rule regressions) |
| `tests/integration/run.sh` | 398 | 398 | 0 |
| Sprint-*.sh bundle | ≈1508 | ≈1593 | +≈85 (sprint-19.sh) |
| **Total** | **2180** | **≈2265** | **+≈85** |

- FlowBridge_TR E2E: single-command phase-runner walks PRD convergence loop; false-positive REJECTED eliminated; specialist dispatches on NEEDS_REVISION; apply auto-chain drives round 2.

## Out of Scope (deferred)

- **Learning-loop-engine pattern mining.** Skill already exists on disk but isn't yet wired to arbiter/specialist telemetry. Sprint 20.
- **Cross-session reviewer memory.** Sprint 20+.
- **Phase-runner TUI / progress bar.** Sprint 21+.
- **Primary-artifact excerption smarts** (semantic section scoring). Initial head+tail+anchor excerpt is sufficient for v2.7.0. Sprint 21.
- **Auto-satisfy for `design.approved` / `accessibility.verified` / `sprint.planned`.** Stays manual per Sprint 18 design decision.
- **Surface `primaryArtifact` in consensus-gate block message.** Low value; `requiredCommand` already carries the primary path. Sprint 20 polish.
