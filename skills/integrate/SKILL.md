---
name: integrate
description: The merge point for parallel work-streams. When teams develop features as independent per-branch work-streams (streams.enabled), each feature reaches its own DEPLOYMENT readiness in isolation — but the combined product was never verified together. Run this on the integration/release branch AFTER feature branches merge in: it identifies which feature streams landed, opens an integration cycle, runs integration-verifier over the combined front↔back surface with seeded data, drives a cross-feature consensus verdict, and breadcrumbs the ship. This is where independent streams reconcile — in the code (git merge) plus one integration gate — not in shared state.
disable-model-invocation: true
allowed-tools: Read Write AskUserQuestion Bash(git *) Bash(jq *) Bash(bash *stream-id.sh*) Bash(bash *streams-audit.sh*) Bash(bash *integration-wiring-check.sh*) Bash(bash hooks/scripts/consensus-run.sh*) mcp__sdlc-engine__sdlc_get_state mcp__sdlc-engine__sdlc_start_cycle mcp__sdlc-engine__sdlc_record_consensus mcp__sdlc-engine__sdlc_advance_phase
---

# Integrate — the merge point for parallel work-streams (Sprint 60)

With `streams.enabled`, two developers build two features as **independent**
work-streams: `acme__feature-auth` and `acme__feature-pay` each walk REQUIREMENTS
→ … → DEPLOYMENT in their own isolated `.vibeflow/state/<streamId>/`, on their own
branch/worktree, never clobbering each other. That isolation is the point — but it
means **the combined product was never seen running as one**. Each stream proved
*its* slice; nobody proved auth + pay together.

`integrate` is the reconciliation step. Streams reconcile in two places, both
here: in the **code** (the git merge of the feature branches into the integration
branch) and in **one integration gate** (this skill). It does NOT merge shared
SDLC state — there is none to merge; each stream's state stays its own audit
trail.

## Phase Contract

Runs on the **integration/release branch** — the branch feature branches merge
**into** (typically `main`, `develop`, or `release/*`), AFTER the merges. Not on a
feature branch (a feature branch is still its own in-progress stream — run
`/vibeflow:phase-runner` there). If you're on a feature branch, stop and say so.

## Step 0 — Resolve the integration stream + confirm the branch

```bash
bash "${CLAUDE_PLUGIN_ROOT:-.}/hooks/scripts/stream-id.sh"
```

The printed `streamId` is the **integration stream** (the integration branch's
own stream id — e.g. the bare project id when integrating on `main`, or
`acme__release-2-0` on a release branch). Use it as the `projectId` for every
`sdlc_*` call below, and the printed `lifecycle` path for this stream's cycle.

Confirm the branch is an integration target, not a feature branch — check it
against the feature streams in Step 1. If `streams.enabled` is **off**, there are
no parallel streams to integrate; say so and point at `/vibeflow:phase-runner`.

## Step 1 — Identify which feature streams landed

List the work-streams that exist locally and the branches merged into the current
branch:

```bash
bash "${CLAUDE_PLUGIN_ROOT:-.}/hooks/scripts/streams-audit.sh"
git branch --merged HEAD --format='%(refname:short)'
git log --merges --oneline -20
```

Cross-reference: a feature stream (`streams-audit.sh` → `streams[]`) whose
`branch` appears in `git branch --merged` is **being integrated** in this pass.
Name them explicitly:

> Integrating N feature streams into `<integration branch>`:
>   ▸ acme__feature-auth  (feature/auth, was at DEPLOYMENT)
>   ▸ acme__feature-pay   (feature/pay, was at TESTING)

If some merged feature stream had **not** reached its own TESTING/DEPLOYMENT
readiness, flag it — integrating a feature that never passed its own gates is a
risk worth naming (don't block; surface).

## Step 2 — Open the integration cycle

The integration pass is its own cycle on the integration stream. Reset the engine
for it and record the cycle in lifecycle:

```
mcp__sdlc-engine__sdlc_start_cycle { "projectId": "<integration streamId>", "note": "integration: <feature list>" }
```

Then write the integration stream's lifecycle file (the `lifecycle` path from
Step 0) with `kind: "increment"`, `title: "integration — <features>"`,
`status: "in-progress"`, the integration `branch`, and a `integrates[]` array of
the feature stream ids (provenance — which streams this pass combines).

## Step 3 — Verify the combined front↔back surface

The whole risk of parallel streams is that two independently-built slices don't
actually work **together**. Run the real end-to-end integration check over the
**merged** code (invoke via the **Skill tool**, not a general agent):

> Skill: `vibeflow:integration-verifier`

It classifies the boundary (`integration-wiring-check.sh`), boots the **real**
back-end locally, seeds deterministic data (test-data-manager), points the **real**
front-end at it off mocks, and drives the `SCN-UI-*-DATA-*` data-binding scenarios
(populated/loading/empty/error/offline) across the combined surface. A back-end
that won't boot, an endpoint that 404s, or a UI that errors on real data is a
**BLOCKED** finding — exactly the "two slices merged but never run together" trap.

(`single-tier`/`no-app` → integration-verifier self-skips; for a pure-backend or
pure-frontend product the merge risk is lower, but still run Step 4 consensus.)

## Step 4 — Cross-feature consensus

Run a cross-AI consensus verdict over the integrated result — not over one
feature's artifact, but over the combined increment (the integration-verifier
report + the merged diff range across all feature branches):

```bash
bash hooks/scripts/consensus-run.sh .vibeflow/reports/frontend-conformance.md
```

Record it on the integration stream:

```
mcp__sdlc-engine__sdlc_record_consensus {
  "projectId": "<integration streamId>",
  "phase":     "<currentPhase>",
  "status":    "<APPROVED|NEEDS_REVISION|REJECTED from verdict.json>",
  "agreement": <verdict.json .agreement>,
  "criticalIssues": <verdict.json .criticalTotal>
}
```

## Step 5 — Ship or breadcrumb

**Operator choice (mobile-friendly — see `docs/OPERATOR-CHOICES.md`).** Surface
the next step via the **`AskUserQuestion`** tool as tappable options, with each
description carrying the condensed result (verdict + the integration-verifier
outcome), so the operator can decide the merge point from a phone:

- **APPROVED + integration-verifier green** → the combined product is verified.
  Offer **Drive to DEPLOYMENT (Recommended)** — continue the integration stream
  toward DEPLOYMENT GO (`/vibeflow:phase-runner` on the integration branch).
  DEPLOYMENT GO on the **integration** stream is the real ship — not any single
  feature stream's local DEPLOYMENT.
- **BLOCKED / NEEDS_REVISION / REJECTED** → offer **Fix on feature stream**
  (name the offending feature(s) it traces to — the fix happens on that feature's
  own branch, then re-merge and re-run `/vibeflow:integrate`) and **Stop**.
  Deep rewrites stay operator-confirmed (the specialist→arbiter→apply chain), by
  design. "Other" lets the operator type a custom next step.

> ▶ Next: /vibeflow:phase-runner   (drive the integration stream to DEPLOYMENT GO)

## Read/track only for git

Like the rest of VibeFlow, `integrate` **tracks and breadcrumbs** git — it reads
merge state but does not run `git merge`/`push` for you (outward-facing git stays
the operator's). You merge the feature branches; `integrate` verifies the result.

## See also

- `docs/TEAM-WORK.md` — the parallel team-work model + the three reconciliation rungs.
- `docs/INTEGRATION-TESTING.md` — integration-verifier's local-boot mechanics.
- `/vibeflow:streams` — the per-stream dashboard.
