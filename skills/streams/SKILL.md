---
name: streams
description: The parallel team-work dashboard. When streams.enabled is on, VibeFlow keys state per git branch so multiple developers (each on their own branch / git worktree) progress independent SDLC work-streams that never clobber each other. This skill consolidates every locally-visible work-stream — its branch, SDLC phase, cycle status, and the engine revision — into one read-only view, flags any shared-branch conflicts, and writes a durable .vibeflow/reports/streams.md. Read-only — never changes config or state. Use to see "who is working on what, and which phase each feature is in".
allowed-tools: Read Write AskUserQuestion Bash(bash *streams-audit.sh*) Bash(jq *)
---

# Streams — the parallel team-work dashboard (Sprint 60)

VibeFlow keys all SDLC state on a **work-stream id**. With the default
single-stream setup that is just the project id and there is nothing to show.
When `streams.enabled` is on (opt-in — see `docs/TEAM-WORK.md`), each git branch
gets its own isolated `.vibeflow/state/<streamId>/` so two developers on two
branches/worktrees run **independent** SDLC states. This skill answers: *which
work-streams exist here, what branch + phase + cycle is each in, and do any of
them collide?*

## Step 1 — Read the audit

```bash
bash "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/streams-audit.sh"
```

`streams-audit.sh` (read-only, fully guarded) returns one JSON document:
`streamsEnabled`, `currentStreamId` (the stream for the current branch),
`owner` (this checkout's git user), `streams[]` (one per stream: `streamId`,
`phase`, `revision`, `updatedAt`, `cycleId`/`cycleTitle`/`cycleStatus`,
`branch`, `isCurrent`), and `conflicts[]` (streams sharing a branch).

## Step 2 — Render the dashboard

Render the JSON as a single human dashboard:

```
VibeFlow Work-Streams — <project>   (owner: <owner>)

  ▸ <streamId>   <branch>   <phase>   cycle <cycleId> (<cycleStatus>)   rev <revision>   <← current>
  ▸ …

  Conflicts:  <branch> shared by <streamIds>   (or "none")
```

- Mark the row whose `isCurrent` is true with `← current`.
- Sort streams with the current one first, then by `updatedAt` (most recent
  next) so the active work is at the top.
- **Conflicts.** For each `conflicts[]` entry, surface it prominently — two
  streams pointing at the same branch means their isolated state has drifted
  from a one-branch-per-stream layout (usually a `VIBEFLOW_STREAM` override or
  `idStrategy:fixed`); name the streamIds and the branch.
- **Streams off.** When `streamsEnabled` is false, render a single line:
  `Streams: off (single-stream project). Enable streams.enabled for parallel team work — see docs/TEAM-WORK.md.`
- **No streams yet.** When `streams[]` is empty, render:
  `No work-streams with local state yet.`

## Step 3 — Write the durable audit

Write the same content as Markdown to `.vibeflow/reports/streams.md` — a
shareable snapshot of the team's parallel work. Header with the project +
owner + a UTC timestamp, then the same dashboard.

## Next step — as a tappable choice (Sprint 63)

**Operator choice (mobile-friendly — see `docs/OPERATOR-CHOICES.md`).** When the
dashboard surfaces a **clear recommended action**, present it with the
**`AskUserQuestion`** tool as 2–4 tappable options (recommended first, condensed
rationale per option, always a **"Stay / do nothing"** option; "Other" lets the
operator type) instead of a bare prose next-step. Typical cases:

- on an **integration/base branch with merged feature streams** → **Run
  `/vibeflow:integrate`** (the merge point) · Stay.
- on a **feature-branch stream that's in-progress** → **Run
  `/vibeflow:phase-runner`** (continue this stream) · Stay.
- a **shared-branch conflict** was flagged → surface **Resolve the conflict**
  (name the streams/branch) · Stay.

Omit the card when streams are off or there's nothing actionable. Read-only —
picking an option just launches the named command.

## Read-only

`streams` **never** changes `vibeflow.config.json`, lifecycle state, or any
source/artifact. Its only write is the `.vibeflow/reports/streams.md` audit.

## Scope (single-machine)

`streams-audit.sh` lists the streams whose state lives in **this** checkout /
git worktree. Two developers on two machines each see their own local streams;
they reconcile through **git** (the code) and `/vibeflow:integrate` at the merge
point, not through shared state. See `docs/TEAM-WORK.md` for the model and the
recommended one-worktree-per-stream layout.

## See also

- `docs/TEAM-WORK.md` — the parallel team-work model.
- `/vibeflow:integrate` — the merge point where streams reconcile.
- `/vibeflow:flow-status` — the per-stream status glance.
