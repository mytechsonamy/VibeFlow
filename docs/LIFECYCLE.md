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

## Two stores, kept in sync: lifecycle.json + the engine

There are two pieces of state, and a new cycle must reset **both**:

- **`.vibeflow/state/lifecycle.json`** — skill-managed; tracks the cycle list
  (id, kind, phase, branch, status).
- **the `sdlc-engine` MCP** (`project.json`) — the gate behind `/vibeflow:advance`
  and `phase-runner`; tracks `currentPhase` + satisfied criteria for **one
  linear pass**.

When a new increment opens, `brownfield-intake` opens the lifecycle cycle **and**
calls **`sdlc_start_cycle`** on the engine — which resets `currentPhase` to
REQUIREMENTS, clears criteria + consensus, and bumps an engine `cycle` counter.
Without that reset the engine would stay pinned at the previous cycle's terminal
phase (DEPLOYMENT) while lifecycle.json says REQUIREMENTS, and `phase-runner`
would refuse on a phase-mismatch. `sdlc_start_cycle` is an explicit, audited
**cycle boundary** — not a backward rewind within a cycle (the engine still
refuses `advance_phase` going backward). (Added in v2.36.0 / Sprint 48; before it,
the multi-cycle lifecycle had no engine reset and cycle-2 stalled at the gate.)

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

## What "completed" means (and the common trap)

A cycle is `completed` **only** when its `status` field says so — and that flips
**only** on **DEPLOYMENT GO** (`release.decision.go` = GO + `deployment.verified`
+ `consensus.deployment.approved`). These are **not** completion:

- the increment branch was **merged to main**,
- the project **reached DEPLOYMENT** (the last phase),
- all the *code* is written and pushed.

A very common shape: the code is done, the PR is merged, but `deployment.verified`
can't pass because there's **no real CI / deploy / health infra yet**. The cycle
correctly sits at DEPLOYMENT `in-progress`. That is *not* a finished cycle, and
the next `phase-runner` run **resumes** it — it does **not** offer a new
increment. When you're deliberately stopping before a real deploy, **you** close
the cycle explicitly (set `status`, with a note like "shipped to repo; deploy
deferred") — the framework never infers completion from a merge.

> The trap to avoid: "PR merged + at DEPLOYMENT → start the next increment with
> brownfield-intake." That silently abandons an open cycle. Resume it, finish the
> deploy, or close it on purpose.

## Why this fixes "resume ≠ brownfield"

Before Sprint 42, `onboard` keyed "brownfield" off *file presence*, so a
greenfield project that had written code and was merely **paused** could be
misread as brownfield on return. Now the signal is the **cycle status**: an
in-progress cycle always resumes; only a *completed* cycle starts a new
(increment) cycle. File presence is irrelevant.
