---
name: phase-runner
description: End-to-end phase orchestrator. For the current SDLC phase, runs every registered analyzer, then drives a real cross-AI consensus verdict HEADLESSLY via hooks/scripts/consensus-run.sh (runs the codex/gemini reviewer CLIs + finalises verdict.json — no dependency on the disable-model-invocation consensus skills, so phase-runner no longer deadlocks). On APPROVED it records consensus + auto-advances via the sdlc-engine MCP tools; on NEEDS_REVISION/REJECTED it stops with an explicit operator breadcrumb (the deep-rewrite specialist→arbiter→apply chain edits the primary artifact and stays operator-confirmed by design). In TESTING it first generates the coverage artifact (Sprint 29). One command replaces the manual analyzer → consensus → advance walk.
disable-model-invocation: false
allowed-tools: Read Write Bash(bash hooks/scripts/consensus-run.sh*) Bash(jq *) Bash(mkdir *) Bash(rm *) Bash(npm *) Bash(npx *) Bash(pnpm *) Bash(yarn *) Bash(pytest *) Bash(dotnet *) Bash(cargo *) Bash(go *) mcp__sdlc-engine__sdlc_get_state mcp__sdlc-engine__sdlc_advance_phase mcp__sdlc-engine__sdlc_list_phases mcp__sdlc-engine__sdlc_record_consensus
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
| DESIGN | `design-bootstrap` (operator-interactive — produces the design spec; not auto-forked) | `design/design-spec.md` |
| ARCHITECTURE | `architecture-bootstrap` (operator-interactive author) → `architecture-validator` (validate, model-invocable) | `docs/architecture.md` |
| PLANNING | `test-strategy-planner`, `traceability-engine` | `.vibeflow/reports/test-strategy.md` |
| DEVELOPMENT | `quality-gates` | the increment diff — `git diff <base>..HEAD`, base resolved robustly (see below; **not** a hardcoded `HEAD~1..HEAD`) |
| TESTING | _(generate coverage — Step 2a)_ → `coverage-analyzer`, `mutation-test-runner` **+ (UI-facing increment only) the front-end battery: `input-validation-matrix`, `e2e-test-writer`, `business-rule-validator`, `traceability-engine`, `visual-ai-analyzer`, `uat-executor`** (Sprint 44) | `.vibeflow/reports/coverage-report.md` |
| DEPLOYMENT | `release-decision-engine`, `deploy-verifier` | `release-notes/<version>.md` |

DESIGN's analyzer (`design-bootstrap`) is **operator-interactive** — it asks
which design source to use (Claude-native / Figma) — so phase-runner does NOT
auto-fork it. If `design/design-spec.md` does not exist yet, stop and emit the
breadcrumb `▶ Next: /vibeflow:design-bootstrap` (it authors the spec + arms the
consensus marker). Once the spec exists, phase-runner runs the headless
consensus (Step 3, `consensus-run.sh`) on `design/design-spec.md` (the
marker's primary, or `design.sourceDir` fallback `design/`) and announces the
manual-criterion reminder from `docs/AUTO-SATISFY.md` (`design.approved` +
`accessibility.verified` stay operator-confirmed).

**ARCHITECTURE is the same shape.** `architecture-validator` only *validates*
`docs/architecture.md` (its hard precondition is that the doc exists), and the
**operator-interactive** `architecture-bootstrap` is what *authors* it (asking
the technology baseline). So if `docs/architecture.md` does not exist yet, stop
and breadcrumb `▶ Next: /vibeflow:architecture-bootstrap`. Once it exists,
run `architecture-validator` as a **Skill** (Step 2 — not a general agent),
then headless consensus on `docs/architecture.md`.

**DEVELOPMENT — resolve the diff robustly (don't hardcode `HEAD~1..HEAD`).**
The analyzer-map lists the primary as "the diff", but a literal
`git diff HEAD~1..HEAD` is fragile: it **fails with exit 128** when the project
isn't a git repo or has fewer than two commits (no `HEAD~1`), and it only
reviews the **last commit** — a DEVELOPMENT increment usually spans several
commits (sprints / slices). Resolve the base first:

```bash
# 1) must be a git repo
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
  echo "DEVELOPMENT review needs a git repo (the primary is the work diff)."
  echo "▶ Next: git init + commit your work, then re-run /vibeflow:phase-runner"
  exit 0; }
# 2) prefer the increment base (merge-base with the default branch) so the WHOLE
#    increment is reviewed, not just the last commit
BASE="$(git merge-base HEAD origin/main 2>/dev/null \
     || git merge-base HEAD main 2>/dev/null \
     || git merge-base HEAD origin/master 2>/dev/null || echo '')"
# 3) fallbacks: ≥2 commits → HEAD~1 ; exactly 1 commit (initial) → the empty tree
if [ -z "$BASE" ]; then
  if git rev-parse HEAD~1 >/dev/null 2>&1; then BASE="HEAD~1"
  else BASE="$(git hash-object -t tree /dev/null)"; fi   # empty tree → first commit IS reviewable
fi
DIFF_RANGE="$BASE..HEAD"          # the DEVELOPMENT primary
```

Use `$DIFF_RANGE` as the primary the `quality-gates` analyzer + consensus
review. `quality-gates` runs lint/typecheck/tests (mechanical — invoke it as a
**Skill**, not a general agent); consensus on the diff satisfies `code.reviewed`.

**DEPLOYMENT closes the cycle (Sprint 42).** DEPLOYMENT is terminal — there is no
phase after it. When its exit criteria are satisfied (`release.decision.go` =
GO + `deployment.verified` + `consensus.deployment.approved`), the **cycle is
done**: update `.vibeflow/state/lifecycle.json` — set
`currentCycle.status = "completed"` + `completedAt`, then move it into
`history[]`. Close with the cycle-completion breadcrumb (track-and-breadcrumb;
the operator runs the git/gh):

```
Cycle <id> (<title>) shipped — DEPLOYMENT GO. The PR for this cycle is ready to merge.
▶ Next: gh pr merge <branch>   then   git checkout -b increment/<next>  &&  /vibeflow:brownfield-intake
```

Until those criteria are met, DEPLOYMENT stays `in-progress` (don't mark a cycle
complete on a CONDITIONAL/BLOCKED release decision).

**TESTING — UI-conditional front-end battery (Sprint 44).** The default TESTING
analyzers (`coverage-analyzer`, `mutation-test-runner`) measure *quality of
tests*, not whether the **UI** is right. So when the active increment is
**UI-facing** (the change-type classification from `brownfield-intake` /
`design-bootstrap` is `ui` or `mixed`, or `design/design-spec.md` exists for this
cycle), phase-runner runs the **front-end battery** in TESTING **in addition to**
coverage + mutation — each as a **Skill** (not a general agent), arm-on-pass
(Sprint 43), so their reports feed the TESTING consensus + the gated test suite:

1. **`input-validation-matrix`** — per-field data validation (required / type /
   boundary / format / type-mismatch / injection-safety / output-formatting).
2. **`e2e-test-writer`** then run — functional flows end-to-end (Playwright web /
   Detox mobile): the functions actually work.
3. **`business-rule-validator`** — the functions meet the PRD's rules.
4. **`traceability-engine`** — every UI requirement maps to a test (no
   untested requirement / orphan test).
5. **`visual-ai-analyzer`** — design conformance: each area matches
   `design-spec.md` (layout / typography / a11y); pairs with `design-bridge
   db_compare_impl` when a Figma file exists.
6. **`uat-executor`** — end-to-end on staging, when a staging URL is configured
   (else breadcrumb it as the operator's manual step).

Because the validation + e2e tests are written **into the project suite**, the
existing gates enforce them: they must pass (`regression-test-runner` /
`quality-gates`) and count toward `coverage.met`. The battery's reports
(`validation-matrix.md`, `rtm.md`, visual findings) become **evidence** for
`consensus.testing.approved`. A **backend/infra** increment skips the battery
entirely — coverage + mutation only, unchanged. `docs/FRONTEND-TESTING.md` maps
each step to what it guarantees.

## Process

### Step 0: Lifecycle — resume the open cycle, or start a new increment (Sprint 42)

**Run first.** A project moves through one or more **cycles** — one pass of the
SDLC per deliverable (the initial build, then one per increment). The runtime
question is never "greenfield or brownfield" (that was a one-time cycle-1
decision); it's **"is there an open cycle to resume, or did the last one ship?"**
— read from state, not from whether source files exist. Read
`.vibeflow/state/lifecycle.json`:

- **`currentCycle.status == "in-progress"`** → resume; continue to Step 1 at the
  cycle's `currentPhase`. (This is the *greenfield-paused-and-resumed* case — it
  must resume, never get re-onboarded or treated as brownfield.)
- **`currentCycle.status == "completed"`** (last cycle shipped) → there is no
  open work. Stop and breadcrumb a new increment on a fresh branch:
  > Last cycle (`<title>`) shipped (DEPLOYMENT GO). Start the next increment:
  > ▶ Next: git checkout -b increment/<slug>  &&  /vibeflow:brownfield-intake
- **No `lifecycle.json`** (pre-Sprint-42 project) → backfill an `in-progress`
  cycle from `currentPhase`, then resume.

Each cycle maps to **one branch / one PR** (track-and-breadcrumb — VibeFlow
records `branch`/`prUrl` in the cycle and *suggests* the `git`/`gh` commands;
the operator runs them).

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
step boundary**. `/vibeflow:flow-status` reads this file (Sprint 21-D).

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

1. **Run the analyzer as a skill — use the Skill tool (or its
   `/vibeflow:<analyzer>` slash command).** The analyzers
   (`architecture-validator`, `test-strategy-planner`, `traceability-engine`,
   `coverage-analyzer`, `quality-gates`, …) are model-invocable skills with
   their own logic + auto-satisfy gates. If an analyzer comes back as a
   bare *codebase exploration* / summary (no report written, no
   marker / criterion), that is the **Sprint 38 bug** — those skills used
   to carry `agent: Explore` in their frontmatter, which routed them to the
   read-only Explore agent that **cannot Write** their report, so they
   couldn't execute and the phase-gate was silently bypassed. v2.26.0
   removed `agent: Explore` from all of them; if you still see exploration,
   the installed plugin is stale — update it.
2. The analyzer writes its marker (v2 per Sprint 19-A) +
   auto-satisfies its criterion (per Sprint 18) + writes
   `consensus-needed.json`.
3. `consensus-gate` hook will now block further work until
   consensus runs.

If an analyzer is **operator-interactive** (it must ASK the operator
something before it can run — `design-bootstrap` for DESIGN,
`architecture-bootstrap` for ARCHITECTURE author the artifact and need a
human decision) phase-runner does NOT auto-run it: if its primary artifact
(`design/design-spec.md`, `docs/architecture.md`) doesn't exist yet, stop
and breadcrumb `▶ Next: /vibeflow:<bootstrap>` so the operator authors it,
then re-run phase-runner to validate + consensus it.

Sequential runs so each analyzer's marker drain + re-write
doesn't collide with the next. For PLANNING and TESTING which
have two analyzers, the second analyzer overwrites the marker
(last-writer-wins — its evidence[] should include prior
analyzer's report to avoid losing signal).

### Step 3: Consensus — headless, real verdict (Sprint 31-C)

phase-runner is the one **operator-invoked** entry point that may
drive consensus itself. The `/vibeflow:consensus-orchestrator` skill
(and specialist / arbiter / apply / advance) are
`disable-model-invocation: true`, so Claude **cannot fork them** —
before Sprint 31 that made this loop un-runnable and phase-runner
deadlocked against its own `consensus-gate` (the analyzer's
`consensus-needed.json` blocked every tool call, and the only thing
that could drain it was an un-forkable skill). Instead, call the
headless runner as **plain Bash**:

```bash
bash hooks/scripts/consensus-run.sh .vibeflow/state/consensus-needed.json
```

(If no marker exists — e.g. DESIGN, which has no analyzer — pass the
primary artifact path directly: `bash hooks/scripts/consensus-run.sh design/spec.md`.)

The runner resolves the primary, runs every external reviewer CLI on
PATH (codex, gemini), finalises a real `verdict.json` via
`consensus-aggregator.sh --finalize` (no 600s quorum stall — it knows
the panel is exactly the CLIs that ran), feeds the same
history.jsonl / reviewer-memory / auto-revert machinery the interactive
path uses, and **drains `consensus-needed.json`** so the gate unblocks.
It prints one JSON line:
`{sessionId, status, agreement, criticalTotal, reviewers, verdictFile}`.

**Exit 3 — no reviewer CLI on PATH.** A headless panel needs codex or
gemini (claude-reviewer is model-only). Stop and emit, as the last line:

```
No external reviewer CLI (codex/gemini) on PATH; headless consensus
can't run. Use the interactive path — it always has claude-reviewer:
▶ Next: /vibeflow:consensus-orchestrator <primary-artifact>
```

Read `status` from the runner's output (or `verdictFile`) and branch:

- **APPROVED** → record + advance (Step 4).
- **REJECTED** (`rejected ≥ 1`) → **stop**. Reviewers actively rejected
  the artifact; emit triage citing `verdictFile`. Do NOT advance, do NOT
  fabricate a pass.
- **NEEDS_REVISION / HUMAN_APPROVAL_REQUIRED** → **stop** with the honest
  revision breadcrumb. The deep-rewrite chain rewrites the primary
  artifact (PRD/ADR/…) and is `disable-model-invocation: true` **by
  design** — only the operator runs it. Emit, as the literal last lines:

  ```
  Consensus did not converge for $CURRENT (status=$STATUS, agreement=$AGREE).
  Resolve, then re-run phase-runner:
  ▶ Next: /vibeflow:consensus-specialist <session-id>   (deep rewrite)
      then  /vibeflow:apply-arbiter-patch <session-id> --yes
      then  /vibeflow:phase-runner
  ```

phase-runner does **not** auto-loop through specialist/apply — those
edit the primary artifact and need human review. Autonomy stops at the
verdict; human judgment owns the rewrite. One `phase-runner` invocation
= analyzers + one consensus verdict + (advance | breadcrumb).

### Step 4: Record + auto-advance (APPROVED only)

On APPROVED, first **record the verdict** into project state — the
advance gate reads `lastConsensus`, and consensus-run.sh (a shell
script) cannot call MCP tools, so phase-runner does it:

```
mcp__sdlc-engine__sdlc_record_consensus {
  "projectId": "<project id from config>",
  "phase":     "<currentPhase from config>",
  "status":    "APPROVED",
  "agreement": <verdict.json .agreement>,
  "criticalIssues": <verdict.json .criticalTotal>
}
```

Then, if `phaseRunner.autoAdvance` is true, advance directly:

```
mcp__sdlc-engine__sdlc_advance_phase {
  "projectId": "<from config>",
  "to":        "<next phase per canonical order>"
}
```

…and close with the breadcrumb for the new phase:

```
Advanced $CURRENT → <next>.
▶ Next: /vibeflow:phase-runner
```

If `autoAdvance` is false, emit the advisory instead:

```
Consensus APPROVED for $CURRENT. autoAdvance=false.
▶ Next: /vibeflow:advance
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
`/vibeflow:flow-status` stops showing a "running" walk:

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
  `/vibeflow:onboard`.
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
  (`.vibeflow/state/phase-runner-progress.json`) that `/vibeflow:flow-status`
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
