# Project lifecycle — cycles, resume, and increments

VibeFlow tracks a project as a sequence of **cycles**. A cycle is one pass
through the SDLC for one deliverable:

- **Cycle 1 — the initial build.** Greenfield (you bring a PRD) or brownfield
  (you bring a codebase). This is the *only* place the greenfield/brownfield
  distinction lives.
- **Every later cycle — an increment.** A feature, refactor, fix, or migration
  on the now-existing codebase.

The key idea: at runtime the question is **never** "is this greenfield or
brownfield?" — it's **"is there an open cycle to resume, or did the last one
ship?"** And that's read from **state**, not from whether source files exist (a
greenfield project that reached DEVELOPMENT also has source files).

## State

`.vibeflow/state/lifecycle.json`:

```json
{
  "currentCycle": {
    "id": "cycle-1",
    "kind": "initial",            // initial | increment
    "title": "Acme — initial build",
    "phase": "REQUIREMENTS",
    "branch": "main",             // each cycle = one branch / one PR
    "prUrl": null,
    "status": "in-progress",      // in-progress | completed
    "startedAt": "2026-06-08T…Z"
  },
  "history": [ /* completed cycles */ ]
}
```

## The state machine

```
no .vibeflow/                         → /vibeflow:onboard
                                        opens cycle-1 (kind=initial, in-progress)
                                        greenfield→prd-quality-analyzer / brownfield→brownfield-intake

cycle in-progress  ── resume ──────────→ /vibeflow:phase-runner
(currentPhase not terminal)             continues from currentPhase
                                        ← a paused greenfield project lands HERE:
                                          it resumes, it is NOT re-onboarded or
                                          treated as brownfield

cycle completed    ── new increment ──→ git checkout -b increment/<slug>
(DEPLOYMENT GO)                          /vibeflow:brownfield-intake
                                        opens cycle-N (kind=increment, in-progress)
```

- **`onboard`** runs once. On an already-onboarded project it does **not**
  re-initialize — it routes you to resume (`phase-runner`) or, if the last cycle
  shipped, to the next increment (`brownfield-intake`).
- **`phase-runner`** reads `lifecycle.json` first: in-progress → resume;
  completed → breadcrumb the next increment on a new branch.
- A cycle **completes** when DEPLOYMENT is terminal-satisfied
  (`release.decision.go` = GO + `deployment.verified` +
  `consensus.deployment.approved`). phase-runner marks `status: completed`, moves
  the cycle to `history[]`, and breadcrumbs the PR merge + next increment.

## One cycle = one branch / one PR

Each cycle maps to a branch and a PR. VibeFlow **tracks** `branch`/`prUrl` in the
cycle and **breadcrumbs** the `git`/`gh` commands — it does not run them for you
(outward-facing git actions stay in your hands):

```
cycle-1   main / first PR        ──ship──▶ merge
cycle-2   increment/wealth-agg   ──ship──▶ merge
cycle-3   increment/kyc-refresh  ──in-progress…
```

When a cycle ships, the next `phase-runner` run sees `completed` and points you
at a fresh branch for the next increment — so new work is always tracked under
its own PR, never mixed into the finished one.

## Why this fixes "resume ≠ brownfield"

Before Sprint 42, `onboard` keyed "brownfield" off *file presence*, so a
greenfield project that had written code and was merely **paused** could be
misread as brownfield on return. Now the signal is the **cycle status**: an
in-progress cycle always resumes; only a *completed* cycle starts a new
(increment) cycle. File presence is irrelevant.
