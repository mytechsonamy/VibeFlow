---
name: status
description: Shows current VibeFlow project status including SDLC phase, pending tasks, quality metrics, and recent review results. Use when asking about project progress.
allowed-tools: Read Grep Glob
---

# VibeFlow Status

Read vibeflow.config.json and .vibeflow/ directory to compile project status.

## Report Sections

### 1. Current Phase
- Active SDLC phase (REQUIREMENTS through DEPLOYMENT)
- Phase progress (iteration X of max Y)

### 2. Quality Metrics
- Latest testability score (from prd-quality-analyzer)
- Test coverage percentage (from coverage-analyzer)
- Traceability score (from traceability-engine)
- Last consensus result and score

### 3. Pending Tasks
- Incomplete tasks in current phase
- Blocked items requiring attention
- Upcoming quality gates

### 4. Recent Activity
- Last 5 reviews with verdicts
- Last phase transition timestamp
- Recent skill invocations

### 5. Phase-Runner Progress (Sprint 21-D)
If `.vibeflow/state/phase-runner-progress.json` exists, render a
"Phase-Runner Progress" block from it:

- `currentStep` and `status` (running / approved / stalled / rejected /
  advanced / blocked)
- `attempt` of `maxConvergenceAttempts`
- completed vs total `steps[]` (e.g. "4 of 6 steps") with each step's
  `name` + `status` + `detail`

**Stale-guard — do not show a phantom run.** Skip the block entirely
when the ledger is stale:
- its `phase` ≠ the live `currentPhase` (a leftover ledger from an
  earlier phase), **or**
- its `startedAt` predates the last phase-transition timestamp (the
  run finished and the phase already advanced past it).

A ledger whose `status` is terminal (`advanced` / `approved` /
`rejected`) for the *current* phase may still be shown as the last
completed run, clearly labelled "last run" rather than "in progress".

## Output
Display a concise status summary directly in the conversation. Do not create a file.
