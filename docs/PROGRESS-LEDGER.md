# Phase-Runner Progress Ledger (Sprint 21)

`/vibeflow:phase-runner` walks a whole SDLC phase in one command —
analyzers → consensus → specialist/arbiter → apply → advance — which can
be a long run (up to `phaseRunner.maxConvergenceAttempts ×
consensus.maxIterations` reviewer rounds). v2.9.0 makes that run
**visible** via a structured ledger instead of leaving the operator
guessing.

## The ledger

`phase-runner` writes `.vibeflow/state/phase-runner-progress.json` and
updates it at every step boundary:

```json
{
  "phase": "REQUIREMENTS",
  "startedAt": "2026-05-31T00:00:00Z",
  "status": "running",
  "attempt": 1,
  "maxConvergenceAttempts": 3,
  "currentStep": "consensus-round-1",
  "steps": [
    { "name": "analyzer:prd-quality-analyzer", "status": "done",    "updatedAt": "…" },
    { "name": "consensus-round-1",              "status": "running", "detail": "agreement=0.78", "updatedAt": "…" }
  ]
}
```

Step names: `analyzer:<skill>`, `consensus-round-<attempt>`,
`specialist` / `arbiter`, `apply`, `advance`. Terminal `status` is one
of `approved`, `advanced`, `stalled`, `rejected`, `blocked`. The ledger
is **overwritten fresh** at the start of each run, so a new walk never
shows a phantom step from a previous run.

## Seeing it

`/vibeflow:status` renders a **Phase-Runner Progress** section from the
ledger: current step, attempt N of max, and completed-vs-total steps
with each step's status and detail.

**Stale-guard.** `/vibeflow:status` ignores a ledger whose `phase` no
longer matches the live phase, or whose `startedAt` predates the last
phase transition — a finished-and-advanced run never shows as "in
progress". A terminal-status ledger for the *current* phase may be shown
as the "last run".

## Not a TUI

This is a ledger + on-demand render, not a live-redrawing terminal UI.
Skills are prose+bash; a real TUI needs a host-side renderer and stays
Sprint 22+ out-of-scope. The ledger is the realistic, testable surface.

## See also

- [CONSENSUS-ITERATION.md](CONSENSUS-ITERATION.md) — the round /
  convergence loop the ledger tracks.
