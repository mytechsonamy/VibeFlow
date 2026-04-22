# Sprint 15 — MyVibe Closed Loop: Auto-Consensus + Arbiter + Specialists ✅ COMPLETE

Shipped: v2.3.0 on 2026-04-20
Branch: `feature/sprint15-auto-consensus-arbiter` (merged)
Baseline change: sdlc-engine unit tests 136 → 141 (+5 from
phase-scoped consensus validation); new `sprint-15.sh` at 82
assertions; total baseline ~1793.

## Context

VibeFlow v2.2.0 orchestrated multi-AI review but the output was
purely observational — reports landed in `.vibeflow/reports/`
and the SDLC engine had no idea consensus had happened. Operators
had to manually call `sdlc_record_consensus`, and any
`/vibeflow:advance` attempt blocked because `lastConsensus` was
null. MyVibe's original promise was a **closed loop**: reviewers
produce verdicts, those verdicts feed the phase-gate, failed
reviews chain into a remediation path automatically.

Sprint 15 closes that loop. Orchestrator appends CLI verdicts
directly into the session jsonl (fixes the 600s timeout
demotion bug where raw codex/gemini subprocesses didn't emit
SubagentStop), analysis skills auto-invoke consensus, the
phase-gate gains scoped `consensus.<phase>.approved` exit
criteria, and two new skills (`consensus-arbiter` +
`apply-arbiter-patch`) turn reviewer feedback into diff-first
patches the operator can review and apply in a single command.

## Tickets shipped

- [x] S15-A — orchestrator CLI output contract: explicit jsonl
  append per CLI verdict (`append_cli_verdict`), per-CLI 90s
  timeout, session_id handling (commit `b134853`)
- [x] S15-B — auto-consensus boilerplate on 6 analysis skills
  (commit `b221171`)
- [x] S15-C — phase-scoped consensus exit criteria in `phases.ts`
  (every phase except DEVELOPMENT) + validator scope check
  (`lastConsensusPhase` must match) + 5 new unit tests (commit
  `5d01649`)
- [x] S15-D — `load-sdlc-context.sh` drains `review-pending.json`
  marker on SessionStart + surfaces `VF_SKIP_AUTO_CONSENSUS=1`
  advisory (commit `ca990b4`)
- [x] S15-E — structured reviewer suggestion schema (id, type,
  target.{file,line_range}, rationale, proposed_change,
  priority, phase_relevance) pinned in
  `agents/claude-reviewer.md` (commit `e9b4a4d`)
- [x] S15-F — `consensus-arbiter` skill: reads jsonl + verdict
  + phase + domain, emits diff-first patches. 10-rule decision
  matrix. Diff-first contract — never writes to source (commit
  `148774b`)
- [x] S15-G — `apply-arbiter-patch` skill: diff preview → y/n →
  `git apply` → optional `--run-tests`. Flags `--yes`,
  `--dry-run`. Rollback recipe (commit `ecf5fc3`)
- [x] S15-H — `tests/integration/sprint-15.sh` (82 assertions)
  + `docs/CONSENSUS-FLOW.md` + `docs/ARBITER.md` (commit
  `01cd8e5`)
- [x] S15-I — v2.3.0 release: plugin + marketplace 2.2.0 →
  2.3.0, sdlc-engine 1.2.0 → 1.3.0, CHANGELOG, release-notes,
  tarball, tag, push (commit `0550f15`)

## Outcome

- Every `/vibeflow:advance` between phases now honours a
  `consensus.<phase>.approved` gate. Stale REQUIREMENTS
  consensus no longer carries through to DESIGN advance.
- `consensus-orchestrator` closes the CLI plumbing gap: codex
  and gemini verdicts actually reach the aggregator within 90s
  per CLI; the pre-Sprint-15 600s global demotion is gone.
- NEEDS_REVISION verdicts auto-chain to `consensus-arbiter`
  which emits 1 patch per reviewer `suggestion[]` entry after
  phase/domain filtering. Operator reviews the manifest + patch
  set, then runs `/vibeflow:apply-arbiter-patch` to land them.
- New marker files keep the loop visible:
  `.vibeflow/state/review-pending.json` (post-commit) +
  `.vibeflow/state/consensus-needed.json` (post-analyzer).

## Known follow-ups

Sprint 15 shipped v2.3.0 with several usability gaps that got
patched as v2.5.x in Sprint 17:

- **`/vibeflow:advance` slash command didn't exist** (fixed in
  v2.5.1 / Sprint 17.1 — `skills/advance/SKILL.md` shipped).
- **`/vibeflow:advance` default-to-next** (v2.5.2 / Sprint 17.2
  — argument made optional, infers next phase from
  currentPhase).
- **`.mcp.json` used bare `./` paths**; MCP tools failed to
  surface in consumer projects (v2.5.3 / Sprint 17.3 — switched
  to `${CLAUDE_PLUGIN_ROOT}/`).
- **Manual `sdlc_record_consensus` + `sdlc_satisfy_criterion`
  still required** (v2.5.4 / Sprint 17.4 — orchestrator auto-
  records consensus + prd-quality-analyzer auto-satisfies
  REQUIREMENTS criteria).

## See also

- release-notes/2.3.0.md
- CHANGELOG.md `[2.3.0]` entry
- Git tag `v2.3.0`
