---
name: phase-runner
description: End-to-end phase orchestrator. For the current SDLC phase, runs every registered analyzer, invokes consensus-orchestrator on the primary artifact, chains through arbiter → apply-arbiter-patch on NEEDS_REVISION (up to consensus.maxIterations), and auto-advances on APPROVED via sdlc_advance_phase MCP tool. One command replaces the manual analyzer → consensus → arbiter → apply → advance walk.
disable-model-invocation: false
allowed-tools: Read Write Bash(jq *) Bash(mkdir *) Bash(rm *) mcp__sdlc-engine__sdlc_get_state mcp__sdlc-engine__sdlc_advance_phase mcp__sdlc-engine__sdlc_list_phases
---

# Phase Runner (Sprint 19-F)

The one-command phase loop. Before Sprint 19, an operator walking
REQUIREMENTS → DESIGN typed something like:

```
/vibeflow:prd-quality-analyzer docs/PRD.docx
/vibeflow:consensus-orchestrator docs/PRD.docx
/vibeflow:consensus-specialist <sid>
/vibeflow:apply-arbiter-patch <sid>
/vibeflow:consensus-orchestrator docs/PRD.docx  # round 2 (manual)
/vibeflow:advance
```

Sprint 19-F collapses that to `/vibeflow:phase-runner`. Every
step uses the same artifacts + skills that were already doing the
work — phase-runner just sequences them, gates on
`phaseRunner.autoAdvance`, and bounds iteration via
`phaseRunner.maxConvergenceAttempts`.

## Usage

```
/vibeflow:phase-runner [TARGET_PHASE]
```

- `TARGET_PHASE` (optional) — REQUIREMENTS / DESIGN / ARCHITECTURE
  / PLANNING / DEVELOPMENT / TESTING / DEPLOYMENT. Default: read
  `currentPhase` via `mcp__sdlc-engine__sdlc_get_state`.

Both the target phase and the current phase must match — the skill
does **not** run analyzers for a different phase than the project
is in. If they disagree the skill stops and tells the operator to
`/vibeflow:advance` first (or run the right analyzer by hand).

## Phase → analyzer map

Hardcoded in the skill. Matches `skills/phase-policy.json`
registrations + the Sprint 19-A `docs/PRIMARY-ARTIFACT.md` table.

| Phase | Analyzer skills (sequential) | Primary (resolved by marker v2) |
|---|---|---|
| REQUIREMENTS | `prd-quality-analyzer` | `<PRD path from argument or docs/>` |
| DESIGN | _(none — operator writes design + runs orchestrator directly)_ | `design/**` |
| ARCHITECTURE | `architecture-validator` | `docs/architecture.md` |
| PLANNING | `test-strategy-planner`, `traceability-engine` | `.vibeflow/reports/test-strategy.md` |
| DEVELOPMENT | `quality-gates` | `git diff HEAD~1..HEAD` (staged/committed work) |
| TESTING | `coverage-analyzer`, `mutation-test-runner` | `.vibeflow/reports/coverage-report.md` |
| DEPLOYMENT | `release-decision-engine`, `deploy-verifier` | `release-notes/<version>.md` |

When the analyzer list is empty (DESIGN), the skill announces the
manual-criterion reminder from `docs/AUTO-SATISFY.md` and
invokes consensus-orchestrator directly on the design spec path
from config (`design.sourceDir` fallback `design/`).

## Process

### Step 1: Resolve phase + config

```bash
CURRENT="$(mcp_sdlc_engine_sdlc_get_state | jq -r '.currentPhase')"
TARGET="${ARGUMENTS:-$CURRENT}"
TARGET="${TARGET^^}"  # upper-case

if [[ "$TARGET" != "$CURRENT" ]]; then
  echo "phase-runner mismatch: current=$CURRENT target=$TARGET. Advance or re-run with matching phase."
  exit 1
fi

AUTO_ADVANCE="$(vf_config_get '.phaseRunner.autoAdvance' 2>/dev/null || echo true)"
MAX_CONV="$(vf_config_get '.phaseRunner.maxConvergenceAttempts' 2>/dev/null || echo 3)"
MAX_ITER="$(vf_config_get '.consensus.maxIterations' 2>/dev/null || echo 5)"
```

### Step 2: Run phase analyzers

Look up the phase's analyzer list from the hardcoded map. For each:

1. Invoke the skill via its slash command (Claude forks it under
   normal skill dispatch).
2. The analyzer writes its marker (v2 per Sprint 19-A) +
   auto-satisfies its criterion (per Sprint 18) + writes
   `consensus-needed.json`.
3. `consensus-gate` hook will now block further work until
   consensus runs.

Sequential runs so each analyzer's marker drain + re-write
doesn't collide with the next. For PLANNING and TESTING which
have two analyzers, the second analyzer overwrites the marker
(last-writer-wins — its evidence[] should include prior
analyzer's report to avoid losing signal).

### Step 3: Convergence loop (per phase-runner attempt)

```
for attempt in 1..maxConvergenceAttempts:
    invoke consensus-orchestrator on the primary artifact
    read verdict.json.status
    case status:
      APPROVED → break loop, go to Step 4
      REJECTED (rejected >= 1) → stop, emit operator triage
      REJECTED (rejected == 0)   ← can't happen post-S19-C, but defensive
      NEEDS_REVISION / HUMAN_APPROVAL_REQUIRED:
        invoke consensus-specialist (prefer deep rewrite) OR
        fall back to consensus-arbiter (mechanical)
        invoke apply-arbiter-patch --yes --run-tests
        Sprint 19-E auto-chain writes the next-round marker
        loop continues via attempt++
```

Each `consensus-orchestrator` invocation internally runs up to
`consensus.maxIterations` review rounds (Sprint 17-A). The
phase-runner's `maxConvergenceAttempts` counts **specialist-apply
cycles** on top of that — default 3. So the worst case walks
3 × 5 = 15 reviewer-round × specialist-rewrite × reviewer-round
passes before giving up. In practice most phases converge in 1.

### Step 4: Auto-advance (APPROVED only)

When the loop exited with APPROVED and `phaseRunner.autoAdvance`
is true, call the MCP tool directly — no shelling out to
`/vibeflow:advance`:

```
mcp__sdlc-engine__sdlc_advance_phase {
  "projectId": "<from config>",
  "to":        "<next phase per canonical order>"
}
```

If `autoAdvance` is false, emit a visible advisory naming the
next phase + the command the operator should run:

```
Consensus APPROVED for $CURRENT. autoAdvance=false. To advance:
  /vibeflow:advance
```

### Step 5: Summary output

One-screen summary:

```
phase-runner: $CURRENT
  analyzers: [list with OK/FAIL per analyzer]
  convergence: $attempts attempt(s), final status=$STATUS
  advanced:    <next phase> / deferred (autoAdvance=false) / blocked
  reports:     .vibeflow/reports/phase-runner-<phase>.md
```

Write `phase-runner-<phase>.md` with the full trace — analyzer
exit codes, verdict.json summaries per attempt, patch manifests
applied, and final status. Operators who want to audit a run
have a single doc to read.

## Flags

- `--pause-between-steps` — after each analyzer + each consensus
  round, stop and wait for operator `[enter]` before continuing.
  Useful when debugging a new phase.
- `--no-auto-advance` — override `phaseRunner.autoAdvance=true`
  for a single run.
- `--no-auto-chain` — override `apply-arbiter-patch`'s Sprint
  19-E chain (forwards `--no-chain` to every apply invocation).

## Guardrails

- **Phase mismatch**: refuses to run if `TARGET_PHASE != currentPhase`
  (see Step 1).
- **Config guard**: no `vibeflow.config.json` → refuse and suggest
  `/vibeflow:init`.
- **MCP unreachable**: if `mcp__sdlc-engine__sdlc_get_state` fails,
  emit a visible advisory and stop. The phase-runner needs state
  access to know which phase to run.
- **Idempotent**: re-running on an already-APPROVED phase is
  a no-op on Step 3 (orchestrator sees APPROVED immediately,
  loop exits, advance fires if configured — and advance is
  itself idempotent at the MCP layer).

## Non-goals

- **No new analyzers**: phase-runner orchestrates existing
  skills; adding a new analyzer is a separate sprint.
- **No breadth-first convergence**: handles one phase at a time.
  To walk multiple phases, invoke phase-runner multiple times
  (auto-advance makes the next invocation land on the new
  phase automatically).
- **No runtime TUI**: progress is prose-only. A TUI/progress
  bar is Sprint 21+ out-of-scope.

## See also

- `docs/PRIMARY-ARTIFACT.md` — marker v2 schema + per-phase
  primary map
- `docs/CONSENSUS-FLOW.md` — 4-layer consensus flow
- `docs/CONSENSUS-ITERATION.md` — round / iteration / auto-chain
  detail
- `docs/AUTO-SATISFY.md` — which criteria each analyzer
  auto-satisfies
- Sprint 18 release notes (`release-notes/2.6.0.md`) — the
  analyzer auto-satisfy rollout this skill composes over
