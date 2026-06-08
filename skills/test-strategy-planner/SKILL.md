---
name: test-strategy-planner
description: Creates comprehensive test strategy, scenario set, and requirements traceability matrix from PRD. Writes .vibeflow/reports/scenario-set.md (universal input for ALL downstream test skills) and .vibeflow/reports/test-strategy.md. Must run before any test writing skill.
allowed-tools: Read Write Grep Glob
context: fork
---

# Test Strategy Planner

## Phase Contract

This skill runs in **PLANNING** only. Before any other step, read
`vibeflow.config.json`'s `currentPhase`. If it is not PLANNING, emit:

> test-strategy-planner is for PLANNING phase; current is `<phase>`. In
> REQUIREMENTS, run `/vibeflow:prd-quality-analyzer` first; advance
> through DESIGN and ARCHITECTURE with `/vibeflow:advance`; only then
> plan the test strategy.

…and stop. The scenario-set.md this skill produces feeds every
downstream test-writer — generating it with a stale or un-approved PRD
poisons the rest of the pipeline.

This is the KEYSTONE skill in the VibeFlow testing pipeline. scenario-set.md produced here is required by 80% of downstream test skills.

## Input
- PRD content (required): The product requirements document
- Platform (required via $ARGUMENTS): web, ios, android, or all
- prd-quality-report.md (optional): Output from prd-quality-analyzer

## Algorithm

### Step 1: Document Analysis
Extract from the PRD:
- Functional requirements (FR-XXX)
- Non-functional requirements (NFR-XXX)
- User roles and permissions
- Critical business flows
- Integration points
- Ambiguities flagged by prd-quality-analyzer (if available)

### Step 2: Scenario Set Creation
For EACH requirement, generate minimum 3 scenarios:

| Scenario Type | Naming Convention | Purpose |
|--------------|-------------------|---------|
| Happy Path | SCN-X-XXX-H-01 | Normal successful flow |
| Edge Case | SCN-X-XXX-E-01 | Boundary values, limits, unusual inputs |
| Negative Case | SCN-X-XXX-N-01 | Invalid input, unauthorized access, failures |

Platform discrimination tags:
- `[WEB]` - Web browser only
- `[MOB]` - Mobile (iOS/Android) only
- `[UNIT]` - Unit test level
- `[INT]` - Integration test level
- `[E2E]` - End-to-end test level
- `[MANUAL]` - Requires manual testing

Priority levels:
- **P0 (Blocker)**: Core business flow, data integrity, security. MUST pass for release.
- **P1 (Critical)**: Important features, performance requirements
- **P2 (Important)**: Secondary features, edge cases
- **P3 (Low)**: Cosmetic, nice-to-have, low-impact scenarios

### Step 3: RTM Generation
Create Requirements Traceability Matrix:

| REQ-ID | Requirement | Scenarios | Test Type | Priority | Status |
|--------|-------------|-----------|-----------|----------|--------|
| FR-001 | User login | SCN-1-001-H-01, SCN-1-001-N-01 | [E2E], [UNIT] | P0 | Planned |

### Step 4: Strategy Document
Structure the test strategy with these sections:
1. Scope and objectives
2. Out-of-scope items
3. Risk areas and mitigation
4. Test environments needed
5. Dependencies and prerequisites
6. Acceptance criteria
7. Scenario summary (total count by type, priority, platform)
8. RTM
9. Coverage gap analysis

### Step 5: Coverage Gap Analysis
Identify:
- Requirements with no scenarios (UNTESTED)
- Requirements with only happy-path scenarios (PARTIAL)
- Ambiguous requirements that cannot be tested (UNTESTABLE)
- Scenarios that require manual testing only (MANUAL_ONLY)

## Output Files

**Every run MUST write both files below to `.vibeflow/reports/` on disk.
Never print them to chat only — downstream skills read from the report
path. Create the directory if it doesn't exist.**

Target paths:
- `.vibeflow/reports/test-strategy.md`
- `.vibeflow/reports/scenario-set.md`

### 1. .vibeflow/reports/test-strategy.md
The full test strategy document with all 9 sections.

### 2. .vibeflow/reports/scenario-set.md (CRITICAL OUTPUT)
This is the universal input for downstream skills. Format:

```markdown
# Scenario Set
## Metadata
- PRD Version: X.X
- Platform: [web|ios|android|all]
- Total Scenarios: XX
- P0: XX | P1: XX | P2: XX | P3: XX

## Scenarios
### FR-001: [Requirement Title]
- SCN-1-001-H-01 [E2E] [P0]: User successfully logs in with valid credentials
- SCN-1-001-N-01 [E2E] [P0]: Login fails with invalid password, shows error
- SCN-1-001-E-01 [UNIT] [P1]: Login with expired session token triggers re-auth
```

### 3. rtm.md
The requirements traceability matrix.

## Downstream Dependencies
scenario-set.md is consumed by:
- component-test-writer (generates unit/integration tests)
- contract-test-writer (generates API contract tests)
- business-rule-validator (validates business rules)
- e2e-test-writer (generates end-to-end tests)
- test-data-manager (generates test fixtures)
- coverage-analyzer (measures requirement coverage)
- uat-executor (UAT scenarios)
- regression-test-runner (regression baseline)

**CRITICAL**: This skill MUST run before any skill that consumes scenario-set.md.

## Auto-satisfy PLANNING criteria (Sprint 18-B — MANDATORY)

After the test strategy is written, auto-satisfy the
`test-strategy.approved` exit criterion via the sdlc-engine MCP
tool. This skill is **generative** (it doesn't compute a
pass/fail verdict — it produces a strategy document), so the
satisfy call is **unconditional**: if the report is on disk, the
strategy is authored. The orthogonal `consensus.planning.approved`
criterion is still gated by the multi-AI review on the same
document.

```bash
PROJECT_ID="$(vf_config_get '.project')"
```

Then call:

```
mcp__sdlc-engine__sdlc_satisfy_criterion {
  "projectId": "<project id>",
  "criterion": "test-strategy.approved"
}
```

Emit a one-line confirmation:

```
Recorded: test-strategy.approved.
```

Fallback on MCP unavailability:

```
sdlc-engine MCP unavailable — satisfy manually:
mcp__sdlc-engine__sdlc_satisfy_criterion {projectId:…, criterion:'test-strategy.approved'}
```

The other PLANNING exit criterion, `sprint.planned`, is operator-
driven and documented in `docs/AUTO-SATISFY.md` — it's a team
ritual (Linear/Jira ticket creation, capacity planning) outside
VibeFlow's scope.

## Final Step: Auto-Consensus Marker (MANDATORY — Sprint 15-B / 16-C)

After your output files are written to `.vibeflow/reports/`, your
**final action** is to Write the auto-consensus marker at
`.vibeflow/state/consensus-needed.json` with:

```json
{
  "primaryArtifact": ".vibeflow/reports/test-strategy.md",
  "evidence": [
    ".vibeflow/reports/scenario-set.md",
    ".vibeflow/reports/rtm.md",
    ".vibeflow/reports/prd-quality-report.md"
  ],
  "artifact": ".vibeflow/reports/test-strategy.md",
  "requiredCommand": "/vibeflow:consensus-orchestrator .vibeflow/reports/test-strategy.md",
  "createdAt": "<current UTC ISO-8601 timestamp>",
  "createdBy": "test-strategy-planner"
}
```

Sprint 16-A's `consensus-gate` hook blocks every `Bash|Write|Edit`
tool call while the marker is present, surfacing the
`requiredCommand` to the operator until they run the orchestrator —
which drains the marker on APPROVED / NEEDS_REVISION / REJECTED
(Sprint 16-B). This is the mandatory layer; the prose invocation
below is best-effort for the main-agent case:

```
/vibeflow:consensus-orchestrator .vibeflow/reports/test-strategy.md
```

It triggers the Claude + codex + gemini review and — if verdict is
NEEDS_REVISION — auto-chains `/vibeflow:consensus-arbiter` for
diff-first patches.

**Skip condition (only one)**: if `VF_SKIP_AUTO_CONSENSUS=1` is set,
do NOT write the marker. Log "auto-consensus skipped by env
(VF_SKIP_AUTO_CONSENSUS)" and stop. The phase-gate in `sdlc-engine`
(Sprint 15-C) still blocks the next `/vibeflow:advance` until a
fresh consensus record exists — the env bypass is call-scoped,
not phase-scoped.
