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

### Step 2b: UI Scenario Enumeration (Sprint 57 — UI increments only)

The per-requirement scenarios above (Step 2) are **functional** — they
say *what* must work, not *how each screen renders*. For a UI increment
that leaves the per-field visual + data-binding test surface unspecified
until TESTING, so it never gets AI-reviewed up front and the front-end
battery has nothing concrete to implement against. Close that gap **here,
in PLANNING**, so UI scenarios are part of the AI-reviewed
`scenario-set.md` / `test-strategy.md` deliverable, RTM-traced, and
picked up by the TESTING front-end battery.

**UI-condition (run this step only when BOTH hold):**
1. Platform is `web` or `all` (from `$ARGUMENTS`), **and**
2. A design spec exists — `design/design-spec.md` (or any
   `design/**/design-spec.md`). Use Glob to check.

If either is false, skip this step entirely and note in the strategy doc
*"UI scenario enumeration skipped — non-UI increment (platform=`<p>`,
design-spec present=`<bool>`)."* Backend/infra increments are unchanged.

When it runs: read `design/design-spec.md` (+ its token file and any
`design/**/mockups/` if present) and, **for each hero screen and each
field/control on it**, enumerate three dimensions of scenario — these
become the concrete contract the TESTING front-end battery implements:

| Dimension | Naming | What it asserts | Implemented in TESTING by |
|---|---|---|---|
| **Visual conformance** | `SCN-UI-<screen>-V-NN` | The rendered field matches the design spec: color, typography, spacing, layout position, and each declared **state** (default / hover / focus / disabled / error / loading) | `frontend-render-check`, `visual-ai-analyzer` |
| **Field validation** | `SCN-UI-<screen>-VAL-NN` | Per-field input rules: required, type, min/max boundary, format/pattern, cross-field — the input-validation-matrix dimensions | `input-validation-matrix`, `uat-executor` |
| **Backend-data binding** | `SCN-UI-<screen>-DATA-NN` | The field renders the **correct server value**, and the screen handles each data state: loading, populated, empty, error, offline/stale | `frontend-render-check`, `uat-executor` |

Rules:
- **One screen = one `### UI: <screen>` block** in `scenario-set.md`
  (see Output format below), listed after the functional `FR-*` blocks.
- Tag every UI scenario `[WEB]` (or `[WEB]`+`[E2E]`) and assign a priority
  — visual-conformance of a P0 flow's primary action is P0; cosmetic
  spacing on a secondary screen is P3.
- **Trace every UI scenario back to the functional requirement(s)** the
  screen serves, so the RTM (Step 3) shows the `FR-*` → screen → UI
  scenario chain. A screen with no backing requirement is a finding for
  the coverage gap analysis (Step 5), not a silent addition.
- If `design-spec.md` lists screens/fields the PRD's requirements don't
  cover (or vice-versa), record it as a **design↔requirement gap** in
  Step 5 — do not invent a requirement to cover it.

This keeps the up-front, AI-reviewed scenario doc honest about the UI
surface instead of deferring all per-field visual/data checks to TESTING.

### Step 3: RTM Generation
Create Requirements Traceability Matrix:

| REQ-ID | Requirement | Scenarios | Test Type | Priority | Status |
|--------|-------------|-----------|-----------|----------|--------|
| FR-001 | User login | SCN-1-001-H-01, SCN-1-001-N-01 | [E2E], [UNIT] | P0 | Planned |
| FR-001 | User login (UI: LoginScreen) | SCN-UI-LoginScreen-V-01, SCN-UI-LoginScreen-VAL-01, SCN-UI-LoginScreen-DATA-01 | [WEB], [E2E] | P0 | Planned |

For a UI increment the RTM **must** carry the `FR-* → screen → UI
scenario` chain so the per-field visual/validation/data scenarios are
traceable to the requirement they serve (not orphaned UI checks).

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

For a UI increment (Step 2b ran), also identify:
- Design-spec screens/fields with no UI scenario (UI_UNTESTED)
- Screens with visual-conformance scenarios but no data-binding scenarios — pretty but unverified against real server data (UI_DATA_GAP)
- A `design-spec.md` screen with no backing functional requirement, or an `FR-*` with a UI it serves but no screen in the design spec (DESIGN_REQ_GAP)

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
- UI scenarios: XX (enumerated: yes|no — non-UI increment)

## Scenarios
### FR-001: [Requirement Title]
- SCN-1-001-H-01 [E2E] [P0]: User successfully logs in with valid credentials
- SCN-1-001-N-01 [E2E] [P0]: Login fails with invalid password, shows error
- SCN-1-001-E-01 [UNIT] [P1]: Login with expired session token triggers re-auth

## UI Scenarios (Sprint 57 — web/all + design-spec only)
### UI: LoginScreen  (serves: FR-001)
- SCN-UI-LoginScreen-V-01   [WEB] [P0]: Email field matches design — token color/font/spacing, default + focus + error states
- SCN-UI-LoginScreen-V-02   [WEB] [P1]: "Sign in" button matches design in default/hover/disabled/loading states
- SCN-UI-LoginScreen-VAL-01 [WEB] [P0]: Email field — required + RFC-format validation, inline error copy per spec
- SCN-UI-LoginScreen-VAL-02 [WEB] [P1]: Password field — required + min-length boundary, masked input
- SCN-UI-LoginScreen-DATA-01 [WEB] [E2E] [P0]: On submit, the screen binds the server auth result; error state renders the API error
- SCN-UI-LoginScreen-DATA-02 [WEB] [P2]: Screen renders loading state during the auth call and empty/offline state when the API is unreachable
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

The **UI Scenarios** block (Step 2b) is the contract the TESTING
front-end battery implements:
- frontend-render-check (visual conformance + backend-data binding — boots the UI, screenshots, compares to design)
- input-validation-matrix (per-field validation scenarios)
- visual-ai-analyzer (visual conformance scoring)
- uat-executor (data-binding + validation as UAT steps)

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
