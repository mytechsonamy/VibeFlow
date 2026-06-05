---
name: phase-runner
description: End-to-end phase orchestrator. For the current SDLC phase, runs every registered analyzer, invokes consensus-orchestrator on the primary artifact, chains through arbiter → apply-arbiter-patch on NEEDS_REVISION (up to consensus.maxIterations), and auto-advances on APPROVED via sdlc_advance_phase MCP tool. In TESTING it first generates the coverage artifact (Sprint 29 — runs tech.coverageCommand so coverage-analyzer has input), making TESTING a true one-command walk too. One command replaces the manual analyzer → consensus → arbiter → apply → advance walk.
disable-model-invocation: false
allowed-tools: Read Write Bash(jq *) Bash(mkdir *) Bash(rm *) Bash(npm *) Bash(npx *) Bash(pnpm *) Bash(yarn *) Bash(pytest *) Bash(dotnet *) Bash(cargo *) Bash(go *) mcp__sdlc-engine__sdlc_get_state mcp__sdlc-engine__sdlc_advance_phase mcp__sdlc-engine__sdlc_list_phases
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
| TESTING | _(generate coverage — Step 2a)_ → `coverage-analyzer`, `mutation-test-runner` | `.vibeflow/reports/coverage-report.md` |
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
# Sprint 29: TESTING coverage generate-step opt-out (flag or env).
NO_GENERATE=0
[[ "$ARGUMENTS" == *--no-generate* || "${VF_SKIP_GENERATE:-}" == "1" ]] && NO_GENERATE=1
```

### Step 1b: Initialise the progress ledger (Sprint 21-C)

`phase-runner` is a long walk (up to `maxConvergenceAttempts` ×
`maxIterations` reviewer rounds). So the operator can see where a run
is, write a structured ledger to
`.vibeflow/state/phase-runner-progress.json` and update it at **every
step boundary**. `/vibeflow:status` reads this file (Sprint 21-D).

```bash
LEDGER="$(vf_state_dir)/phase-runner-progress.json"
# Fresh ledger at run start — overwrites any stale prior run so a new
# walk never shows a phantom step from last time.
jq -n -c --arg phase "$CURRENT" --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --argjson maxConv "$MAX_CONV" \
  '{phase:$phase, startedAt:$ts, status:"running", attempt:1,
    maxConvergenceAttempts:$maxConv, currentStep:"init", steps:[]}' \
  > "$LEDGER"

# Helper used at every boundary below. Appends/updates a step and sets
# currentStep; pass status running|done|failed|skipped and an optional detail.
vf_progress() {                 # vf_progress <step-name> <status> [detail]
  local name="$1" st="$2" detail="${3:-}"
  local ts; ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  jq -c --arg name "$name" --arg st "$st" --arg detail "$detail" --arg ts "$ts" '
    .currentStep = $name
    | .steps = ((.steps // []) | map(select(.name != $name))
        + [{name:$name, status:$st, detail:$detail, updatedAt:$ts}])' \
    "$LEDGER" > "$LEDGER.tmp" && mv "$LEDGER.tmp" "$LEDGER"
}
```

Call `vf_progress` at each boundary: `analyzer:<name>` (running→done),
`consensus-round-<attempt>` (running, with `detail="agreement=<n>"`),
`specialist` / `arbiter`, `apply`, and `advance`. At the very end set
the terminal status (Step 5).

### Step 2a: Generate TESTING artifacts (Sprint 29 — TESTING only)

`coverage-analyzer` **parses** an existing coverage JSON — it does not
run the suite to produce one. So in **TESTING only**, before forking the
analyzers, generate the coverage artifact by running the project's
coverage command. (`mutation-test-runner` self-generates its mutants and
runs the suite itself, so it only needs `tech.testCommand` to exist.)
Other phases skip this step entirely — the REQUIREMENTS / ARCHITECTURE /
PLANNING / DEVELOPMENT / DEPLOYMENT walks are unchanged.

```bash
if [[ "$CURRENT" == "TESTING" && "$NO_GENERATE" != "1" ]]; then
  RUNNER="$(vf_config_get '.tech.testRunner' 2>/dev/null || echo "")"
  COV_CMD="$(vf_config_get '.tech.coverageCommand' 2>/dev/null || echo "")"
  if [[ -z "$COV_CMD" ]]; then
    case "$RUNNER" in
      vitest) COV_CMD='npx vitest run --coverage' ;;
      jest)   COV_CMD='npx jest --coverage' ;;
      pytest) COV_CMD='pytest --cov --cov-report=json' ;;
      dotnet) COV_CMD='dotnet test --collect:"XPlat Code Coverage"' ;;
      *)      COV_CMD='' ;;   # unknown runner → nothing to run
    esac
  fi
  vf_progress "generate:coverage" "running" "${COV_CMD:-<no coverage command>}"
  if [[ -n "$COV_CMD" ]]; then
    if eval "$COV_CMD"; then
      vf_progress "generate:coverage" "done" "$COV_CMD"
    else
      # Best-effort: do NOT abort. The coverage-analyzer below will
      # surface the missing/empty-coverage block, giving the operator a
      # precise "coverage didn't generate" signal instead of a silent
      # phase-runner failure.
      vf_progress "generate:coverage" "failed" "$COV_CMD (continuing — analyzer will surface the gap)"
    fi
  else
    vf_progress "generate:coverage" "skipped" "no coverage command for testRunner=$RUNNER"
  fi
fi
```

**Opt-out.** `--no-generate` (or `VF_SKIP_GENERATE=1`) sets
`NO_GENERATE=1`, skipping this step — for operators who generate coverage
in CI / by hand and just want the analyze → consensus → advance walk.

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

**Finalise the ledger (Sprint 21-C).** Set the terminal status so
`/vibeflow:status` stops showing a "running" walk:

```bash
FINAL=advanced   # or: approved | stalled | rejected | blocked
jq -c --arg st "$FINAL" --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '.status = $st | .finishedAt = $ts' \
  "$LEDGER" > "$LEDGER.tmp" && mv "$LEDGER.tmp" "$LEDGER"
```

## Flags

- `--pause-between-steps` — after each analyzer + each consensus
  round, stop and wait for operator `[enter]` before continuing.
  Useful when debugging a new phase.
- `--no-auto-advance` — override `phaseRunner.autoAdvance=true`
  for a single run.
- `--no-auto-chain` — override `apply-arbiter-patch`'s Sprint
  19-E chain (forwards `--no-chain` to every apply invocation).
- `--no-generate` (or `VF_SKIP_GENERATE=1`) — Sprint 29: skip the
  TESTING coverage generate-step (Step 2a). For operators who generate
  coverage in CI / by hand. No effect outside TESTING.

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
- **No interactive TUI**: there is no live-redrawing terminal UI.
  Sprint 21-C ships a structured progress **ledger**
  (`.vibeflow/state/phase-runner-progress.json`) that `/vibeflow:status`
  renders on demand (Sprint 21-D) — a real redrawing TUI would need a
  host-side renderer and stays Sprint 22+ out-of-scope.

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
