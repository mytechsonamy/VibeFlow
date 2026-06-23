# Team work — parallel work-streams (Sprint 60)

Two developers, two features, at the same time: one builds auth while the other
builds payments, each progressing the SDLC **independently**, neither clobbering
the other's state. VibeFlow supports this through **work-streams**.

> **History.** VibeFlow v1.x had a Postgres-backed "team mode" (a single shared
> database). It was retired in v2.0.0 for a simpler, git-versioned filesystem
> store. Work-streams bring parallel team work back on top of that store — without
> a shared database, using git as the source of truth.

## The model

- A **work-stream** = one feature = one git branch (usually one git worktree) =
  one `projectId` = one **independent** SDLC cycle, with its own `currentPhase`,
  satisfied criteria, consensus, and `lifecycle.json`.
- The `sdlc-engine` already isolates every `projectId` in its own
  `proper-lockfile`-locked `.vibeflow/state/<id>/` directory. Work-streams simply
  **derive a per-branch `projectId`** so each branch gets its own isolated state.
- Streams flow independently and reconcile in two places — both at the **merge
  point** (`/vibeflow:integrate`): in the **code** (the git merge) and in **one
  integration gate** (cross-feature verification + consensus). There is no shared
  SDLC state to merge.

```
acme__feature-auth   REQUIREMENTS → … → DEPLOYMENT-ready   (branch feature/auth)
acme__feature-pay    REQUIREMENTS → … → TESTING            (branch feature/pay)
                                   │
                merge both ──▶ integration branch (main) ──▶ /vibeflow:integrate
                                   │                          combined verify + consensus
                                   └──▶ DEPLOYMENT GO = ship
```

## Turning it on

Work-streams are **opt-in** (off by default, so single-developer projects are
unchanged). In `vibeflow.config.json`:

```json
{
  "project": "acme",
  "streams": { "enabled": true, "idStrategy": "branch" }
}
```

- `enabled` (default `false`) — the kill switch. Off ⇒ the bare `project` id is
  used everywhere, exactly as before.
- `idStrategy` (default `"branch"`) — `"branch"` derives `<project>__<branch-slug>`
  per git branch; `"fixed"` keeps the bare `project` id (an explicit no-op escape
  hatch, e.g. to use the dashboard without per-branch suffixes).

The stream id is computed by `hooks/scripts/_lib.sh` → `vf_stream_id` and exposed
read-only via `hooks/scripts/stream-id.sh`. The default branch (`main`/`master`),
a detached HEAD, or a non-git directory all collapse to the bare `project` id, so
the **initial** stream keeps the legacy `.vibeflow/state/<project>/` path. An
explicit `VIBEFLOW_STREAM=<name>` env var overrides the branch derivation.

## Recommended layout — one worktree per stream

Use a git **worktree** per feature so each stream has its own working directory
(and its own Claude Code session + MCP server):

```bash
git worktree add ../acme-auth feature/auth
git worktree add ../acme-pay  feature/pay
# developer A works in ../acme-auth, developer B in ../acme-pay
```

Each worktree has its own `.vibeflow/state/`, so the streams are isolated both
**physically** (separate directories) and **logically** (branch-derived
`projectId`). Switching branches inside one shared directory also stays isolated
(the `projectId` changes with the branch), but separate worktrees are cleaner and
let two people work at once on one machine.

## Seeing all streams

```
/vibeflow:streams        # full per-stream dashboard (branch, phase, cycle, conflicts)
/vibeflow:flow-status    # one-line "N work-streams active" glance
```

Both read `hooks/scripts/streams-audit.sh` (read-only). The dashboard writes a
durable `.vibeflow/reports/streams.md`.

## The merge point — `/vibeflow:integrate`

When feature branches merge into the integration/release branch, run
`/vibeflow:integrate` **there** (after the merges). It:

1. Identifies which feature streams landed (`streams-audit.sh` × `git branch --merged`).
2. Opens an **integration cycle** on the integration stream (`sdlc_start_cycle`).
3. Runs `integration-verifier` over the **combined** front↔back surface with
   seeded data — the one check that proves the independently-built slices work
   **together**, not just each alone.
4. Drives a **cross-feature consensus** verdict over the integrated result.
5. Continues the integration stream to **DEPLOYMENT GO** — which is the real ship
   (not any single feature stream's local DEPLOYMENT).

## Scope and limits (v1)

- **Single-machine visibility.** State is local to each checkout/worktree.
  `/vibeflow:streams` shows the streams visible **here**. Two developers on two
  machines each see their own local streams; they reconcile through **git** (the
  code) and `/vibeflow:integrate`, not through shared state. This matches
  VibeFlow's "git is the source of truth" design. A shared remote registry is a
  possible future addition, deliberately out of scope for v1.
- **Do not commit `.vibeflow/state/`.** It is in `.gitignore` for good reason —
  committing per-branch state invites merge conflicts on `project.json` /
  `lifecycle.json`. State is event-sourced and regenerable
  (`bin/replay-events.sh`); the durable artifact that travels with a branch is the
  **code + the docs/reports**, not the engine state.
- **Consensus markers are per-directory.** `.vibeflow/state/consensus-needed.json`
  is one-per-checkout; with the one-worktree-per-stream layout it is naturally
  isolated.

## See also

- `docs/LIFECYCLE.md` — cycles, resume, and how a stream's cycle is tracked.
- `docs/INTEGRATION-TESTING.md` — the integration-verifier mechanics the merge
  point reuses.
- `docs/CONFIGURATION.md` — all config knobs.
