# Sprint 17 — Iterative Consensus + Phase Specialists + HUMAN_APPROVAL_REQUIRED ✅ COMPLETE

Shipped: v2.5.0 on 2026-04-20 + patches v2.5.1 → v2.5.4 on 2026-04-21
Branch: `feature/sprint17-iterative-consensus` (merged)
Baseline change: sdlc-engine 142 → 157 (+15 from S17-C + S17-F
config tests); hooks 86 → 110 (+24); new `sprint-17.sh` at 98
assertions; total baseline 1969 → ~2106.

## Context

FlowBridge_TR canvasing on v2.4.0 surfaced three related
architectural gaps:

1. Consensus ran as a single round. With 3 reviewers voting
   NEEDS_REVISION, agreement = 0 (since 0 approved / 3 total)
   and the `agreement < 0.5 → REJECTED` rule fired, promoting
   the verdict to REJECTED despite no reviewer actually voting
   reject. Iteration never got a chance.
2. `criticalIssues` was a bare integer per reviewer. Three
   reviewers flagging the same finding summed to 3 and tripped
   the `criticalTotal >= 2 → REJECTED` rule even though only
   one distinct issue existed.
3. The arbiter's mechanical `proposed_change` → patch path
   worked for surgical fixes but struggled with "this whole
   section needs a rewrite" feedback. No deep-rewrite path
   existed.

Sprint 17 addresses all three plus ships user-driven polish
patches (v2.5.1 → v2.5.4) that land MyVibe's original promise
end-to-end: a single `/vibeflow:prd-quality-analyzer` command
now cascades through consensus → verdict recording → phase-gate
unlock without manual MCP tool calls.

## Tickets shipped (v2.5.0 core)

- [x] S17-A — iterative consensus rounds: aggregator is round-
  aware (reads `<sid>.current-round.txt` marker), orchestrator
  Step 5 loop runs up to `consensus.maxIterations` (default 5)
  rounds with prior-round verdicts embedded in round-2+
  prompts. `verdict.json` gains a `rounds[]` array (commit
  `203afef`)
- [x] S17-B — critical dedup + rejected-majority rule.
  Reviewer schema: `criticalIssues` becomes an array of
  `{id, target:{file, line_range}, title, rationale}`.
  Aggregator dedups cross-reviewer by `{file, line_range}`
  equality OR Jaccard(title words) ≥ 0.6. Retired
  `agreement < 0.5 → REJECTED` rule; replaced with strict
  majority (`rejected * 2 > total`) (commit `34364f4`)
- [x] S17-C — `HUMAN_APPROVAL_REQUIRED` consensus status.
  Emitted when `maxIterations` rounds pass without reaching
  `approvalThreshold` but the run isn't a hard reject.
  Validator accepts it as valid (pass-with-audit).
  `sdlc_advance_phase` MCP tool gains optional
  `humanOverrideNote`. Event log records the override;
  `load-sdlc-context.sh` surfaces it on SessionStart. +7 unit
  tests (commit `26a63d1`)
- [x] S17-D — 6 phase-specialist agents: `prd-rewriter`
  (REQUIREMENTS), `design-spec-refiner` (DESIGN), `adr-author`
  (ARCHITECTURE), `test-strategy-refiner` (PLANNING),
  `coverage-gap-filler` (TESTING), `runbook-editor`
  (DEPLOYMENT). All `context: fork` + `model: opus` + diff-first
  contract; one patch per invocation (commit `ac2d3ac`)
- [x] S17-E — new `consensus-specialist` dispatcher skill:
  reads `currentPhase`, forks the matching specialist via
  `agent:` frontmatter. Routes the specialist's patch into
  `manifest.json` with `type: "specialist"` so
  `apply-arbiter-patch` processes arbiter + specialist patches
  in order (commit `9de80ba`)
- [x] S17-F — typed `ConsensusConfigSchema` in
  `mcp-servers/sdlc-engine/src/config.ts` with defaults
  (`maxIterations: 5`, `approvalThreshold: 0.9`,
  `iteration.enabled: true`). +8 unit tests. `phase-policy.json`
  registers `consensus-specialist` (commit `7462102`)
- [x] S17-G — `tests/integration/sprint-17.sh` (98 assertions),
  `docs/CONSENSUS-ITERATION.md`, `docs/SPECIALISTS.md` (commit
  `dcdcb48`)
- [x] S17-H — v2.5.0 release + dist rebuild (commits `0356066`
  + `1deda52`)

## Patch tickets (v2.5.1 → v2.5.4, 2026-04-21)

Rolled up under Sprint 17 because each closed a gap discovered
during FlowBridge_TR's first live run of v2.5.0:

- **v2.5.1** — new `skills/advance/SKILL.md`; `/vibeflow:advance`
  was documented in CLAUDE.md since v1.0 but never implemented
  as a skill. Shipped the wrapper around
  `sdlc_advance_phase` MCP tool with `humanOverrideNote`
  parsing + exit-criterion remediation hints.
- **v2.5.2** — `/vibeflow:advance` default-to-next: calling it
  with no target phase now infers from `currentPhase` using
  the canonical order.
- **v2.5.3** — **critical**: `.mcp.json` paths fixed from bare
  `./mcp-servers/...` to `${CLAUDE_PLUGIN_ROOT}/mcp-servers/...`.
  Before this fix, MCP servers silently failed in consumer
  projects because paths resolved against the wrong cwd — every
  `/vibeflow:advance` / `/vibeflow:status` / MCP-backed skill
  was inert after plugin install. Regression guard added to
  `tests/integration/run.sh` requiring `${CLAUDE_PLUGIN_ROOT}/`
  prefix.
- **v2.5.4** — orchestrator auto-records consensus
  (`sdlc_record_consensus`) on every terminal verdict;
  prd-quality-analyzer auto-satisfies `prd.approved` +
  conditionally `testability.score>=60`. Closes the last
  manual step in REQUIREMENTS → DESIGN advance. +7 regression
  tests in new `[S17.2]` section of sprint-17.sh.

## Outcome

- Reviewer panels iterate until convergence: round-1
  NEEDS_REVISION carries into round-2 with the previous
  reviewers' verdicts + top-3 critical findings embedded in
  the prompt. Up to 5 rounds (configurable).
- Structured `criticalIssues` enables real dedup. Three
  reviewers flagging "data residency missing" now count as 1,
  not 3.
- HUMAN_APPROVAL_REQUIRED + `humanOverrideNote` provides an
  explicit audit trail when the panel can't converge but the
  operator needs to move forward.
- Deep-rewrite path is available alongside mechanical arbiter
  patches. The orchestrator's NEEDS_REVISION prose offers both
  `/vibeflow:consensus-arbiter` and `/vibeflow:consensus-specialist`.
- MCP path bug (v2.5.3) is arguably Sprint 17's highest-impact
  fix — before it, the entire plugin was effectively broken in
  any project other than VibeFlow itself.

## See also

- release-notes/2.5.0.md (core Sprint 17)
- release-notes/2.5.1.md, 2.5.2.md, 2.5.3.md, 2.5.4.md (patches)
- CHANGELOG.md `[2.5.0]` → `[2.5.4]` entries
- Git tags `v2.5.0`, `v2.5.1`, `v2.5.2`, `v2.5.3`, `v2.5.4`
