# Auto-Satisfy Criteria Matrix

> **One-command alternative (Sprint 19-F):** `/vibeflow:phase-runner`
> runs the current phase's analyzer(s) + consensus-orchestrator +
> specialist/arbiter + apply + `sdlc_advance_phase` in sequence.
> The per-skill entry points below are what phase-runner composes;
> invoke them individually when you want manual control.


Every SDLC phase in VibeFlow has exit criteria that must be
satisfied before `/vibeflow:advance` lets the project move to the
next phase. Sprint 17.2 and Sprint 18 make the bulk of these
criteria auto-satisfied by the skills that produce the
authoritative evidence. A few remain operator-driven — this page
enumerates exactly which is which.

## Matrix

| Phase | Criterion | Who satisfies | Condition |
|---|---|---|---|
| REQUIREMENTS | `prd.approved` | `prd-quality-analyzer` | unconditional on successful report |
| REQUIREMENTS | `testability.score>=60` | `prd-quality-analyzer` | only when score ≥ 60 |
| REQUIREMENTS | `consensus.requirements.approved` | `consensus-orchestrator` | on any terminal verdict |
| DESIGN | `design.approved` | **OPERATOR** | manual sign-off (see below) |
| DESIGN | `accessibility.verified` | **OPERATOR** | manual sign-off (see below) |
| DESIGN | `consensus.design.approved` | `consensus-orchestrator` | on any terminal verdict |
| ARCHITECTURE | `adr.recorded` | `architecture-validator` | only when verdict ≠ BLOCKED |
| ARCHITECTURE | `consensus.architecture.approved` | `consensus-orchestrator` | on any terminal verdict |
| PLANNING | `test-strategy.approved` | `test-strategy-planner` | unconditional on successful report |
| PLANNING | `sprint.planned` | **OPERATOR** | manual (Linear/Jira ritual) |
| PLANNING | `consensus.planning.approved` | `consensus-orchestrator` | on any terminal verdict |
| DEVELOPMENT | `code.reviewed` | `consensus-orchestrator` | only on DEVELOPMENT + APPROVED / HUMAN_APPROVAL_REQUIRED |
| DEVELOPMENT | `quality.gates.passed` | `quality-gates` | only when lint + typecheck + tests all exit 0 |
| TESTING | `coverage.met` | `coverage-analyzer` | only when verdict == PASS |
| TESTING | `mutation.score.acceptable` | `mutation-test-runner` | only when verdict == PASS |
| TESTING | `consensus.testing.approved` | `consensus-orchestrator` | on any terminal verdict |
| DEPLOYMENT (entry) | `release.decision.go` | `release-decision-engine` | **only when verdict == GO** (Sprint 26-A); CONDITIONAL/BLOCKED leave it unsatisfied so the opt-in `gates.enforceEntryCriteria` can block DEPLOYMENT entry |
| DEPLOYMENT | `deployment.verified` | `deploy-verifier` | only when overall verdict == PASS |
| DEPLOYMENT | `health.checks.passed` | `deploy-verifier` | only when overall verdict == PASS |
| DEPLOYMENT | `consensus.deployment.approved` | `consensus-orchestrator` | on any terminal verdict |

## Why some criteria stay manual

### `design.approved` (DESIGN)

Design approval is product/UX judgment — what "approved" means
here involves user-research results, stakeholder alignment,
trade-off acceptance. None of those are observable to a skill.
The `design-bridge` MCP can validate Figma-to-spec fidelity and
`visual-ai-analyzer` can flag a11y drifts, but the "yes, this is
what we're building" signal belongs to the designer + product
owner.

### `accessibility.verified` (DESIGN)

`visual-ai-analyzer` + checklist-generator produce **evidence**
(contrast violations, keyboard-nav gaps, ARIA label drift). But
"verified" means a human (typically an a11y specialist or the
engineer who did the remediation pass) has reviewed the findings
and signed off. Auto-satisfying on clean static output would
skip that review.

### `sprint.planned` (PLANNING)

Sprint planning is a team ritual — Linear/Jira ticket creation,
story-point estimates, capacity planning, dependency sequencing.
None of that lives inside VibeFlow's state machine. The criterion
exists to gate advance behind a real planning session.

## Operator path for manual criteria

For each manual criterion, run:

```
mcp__sdlc-engine__sdlc_satisfy_criterion {
  "projectId": "<from vibeflow.config.json.project>",
  "criterion": "<the criterion name>"
}
```

Examples:

```
mcp__sdlc-engine__sdlc_satisfy_criterion { "projectId": "FlowBridge_TR", "criterion": "design.approved" }
mcp__sdlc-engine__sdlc_satisfy_criterion { "projectId": "FlowBridge_TR", "criterion": "accessibility.verified" }
mcp__sdlc-engine__sdlc_satisfy_criterion { "projectId": "FlowBridge_TR", "criterion": "sprint.planned" }
```

The engine records a `criterion_satisfied` event in the event log
so the action is auditable.

## Troubleshooting

### "`/vibeflow:advance` blocks with `<criterion> not satisfied`"

Check `/vibeflow:flow-status` first — it lists every unsatisfied
criterion. Then:

1. **Auto-satisfiable criterion**: run the owning skill from the
   matrix above. If the skill ran recently but the criterion
   didn't get satisfied, check the skill's output for the gating
   condition (e.g. `coverage.met` didn't satisfy because the
   coverage verdict was NEEDS_REVISION).

2. **Manual criterion**: call `sdlc_satisfy_criterion` directly
   per the operator path above.

3. **MCP unavailable**: if the skill reported
   "sdlc-engine MCP unavailable — satisfy manually:", the
   state write didn't happen. Restart Claude Code so MCP
   servers re-register, then either re-run the skill or call
   the satisfy command directly.

### "Criterion was satisfied, `/vibeflow:advance` still blocks"

The validator ALSO checks `lastConsensus` for
`consensus.<phase>.approved` criteria (Sprint 15-C). If
`lastConsensus.phase` doesn't match the `from` phase, the check
fails even if the criterion text is present in
`satisfiedCriteria`. Fix: re-run `/vibeflow:consensus-orchestrator`
on the phase's primary artifact so the orchestrator records a
fresh phase-scoped consensus.

### "Orchestrator APPROVED but no auto-record happened"

Look for the line:
```
could not record consensus to project state; run
mcp__sdlc-engine__sdlc_record_consensus manually with ...
```

in the orchestrator's output. That means sdlc-engine MCP was
unreachable. Options:
- Restart Claude Code (MCP path substitution happens on session
  start; if `.mcp.json` is using `${CLAUDE_PLUGIN_ROOT}` it should
  work post-restart — see release notes for v2.5.3).
- Call `sdlc_record_consensus` by hand with the values the
  orchestrator's output printed.

### "Verdict says PASS but criterion wasn't satisfied"

Check the skill's Final Step section — the MCP call is inside
the skill prose, which means Claude has to follow the instruction.
If the operator interrupted the skill or the output was trimmed,
the call may have been skipped. Re-run the skill or call the
satisfy command directly.

## Audit trail

Every `sdlc_satisfy_criterion` call — whether from a skill or the
operator — writes a `criterion_satisfied` event into
`.vibeflow/state/<projectId>/events/NNNN-criterion_satisfied.json`.
The event includes `actor` (e.g. `sdlc_satisfy_criterion` from
the MCP tool), `criterion`, `phase`, and `alreadyPresent` (true
on idempotent re-satisfy).

Grep for a criterion across the event log:

```bash
grep -l "\"criterion\":\"prd.approved\"" \
  .vibeflow/state/*/events/*criterion_satisfied*.json
```

## See also

- `docs/PHASE-BOUNDARIES.md` — per-phase allowed write paths
- `docs/CONSENSUS-FLOW.md` — how consensus-orchestrator records
  verdicts
- `docs/CONSENSUS-ITERATION.md` — HUMAN_APPROVAL_REQUIRED flow
- `mcp-servers/sdlc-engine/src/phases.ts` — authoritative source
  for exit-criterion definitions
