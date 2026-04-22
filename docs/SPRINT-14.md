# Sprint 14 — Consensus Flow Unification + Mode Retirement ✅ COMPLETE

Shipped: v2.2.0 on 2026-04-20
Branch: `feature/sprint14-consensus-mode-retire` (merged)
Baseline change: hook tests bumped from ~72 to 75; integration from ~1225 to 1260 (sprint-14.sh at 36 assertions).

## Context

Two related process defects emerged during field testing. First,
the `solo`/`team` mode switch silently gated whether codex and
gemini CLI reviews ran at all — operators in "solo" saw only
claude-reviewer on every consensus cycle even when codex and
gemini were on PATH and they wanted the full panel. Second,
the consensus-aggregator fired on every `SubagentStop` event
regardless of whether the stopping subagent was a reviewer,
producing spurious `reviewer=unknown` verdicts that poisoned the
panel count and demoted genuine APPROVED batches.

Sprint 14 retires `mode` entirely (state is filesystem-only
since Sprint 11; the mode field only gated consensus behaviour
and nothing else) and makes the aggregator reviewer-class
aware.

## Tickets shipped

- [x] S14-A/B — consensus flow mode-independent + claude-reviewer
  `reviewer=unknown` fix (commit `5242704`)
- [x] S14-C — retire the `mode` concept entirely (vf_mode helper
  removed from `_lib.sh`, every hook + config + doc cleaned)
  (commit `024ea84`)
- [x] S14-D — skill output contract fix: four analysis skills
  had `allowed-tools` missing `Write` and no explicit
  `.vibeflow/reports/` path, so reports never landed on disk.
  Standardised on "Write + explicit path" (commit `c5c6a8b`)
- [x] S14-E — `tests/integration/sprint-14.sh` harness + doc
  cleanup (commit `fee5dac`)
- [x] S14-F — v2.2.0 release (plugin + marketplace bumps, CHANGELOG,
  release-notes, tarball, tag, push, GitHub release) (commit
  `8f31932`)

## Outcome

- Consensus now runs codex + gemini whenever their CLIs are on
  `PATH`, regardless of any mode-like setting. Operators can
  override the reviewer count via `consensus.quorum` in
  `vibeflow.config.json`.
- `consensus-aggregator.sh` filters subagent names through a
  reviewer-class allow-list (`claude-reviewer`, `*-reviewer`,
  `consensus-*`). Non-reviewer SubagentStop events (Explore,
  test-analyst, codebase-explorer, etc.) no longer create
  verdict lines.
- `mode` deleted from `vibeflow.config.json`, `_lib.sh`, every
  skill reference, every hook, every doc. Nothing reads the
  field anymore.
- Four analysis skills (prd-quality-analyzer, architecture-
  validator, test-strategy-planner, traceability-engine) fixed
  their Write-allowed-tools + explicit report paths so the
  `.vibeflow/reports/*.md` artifacts actually materialise.

## See also

- release-notes/2.2.0.md (full user-facing notes)
- CHANGELOG.md `[2.2.0]` entry
- Git tag `v2.2.0`
