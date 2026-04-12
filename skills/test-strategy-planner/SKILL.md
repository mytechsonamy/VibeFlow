---
name: test-strategy-planner
description: Creates comprehensive test strategy, scenario set, and requirements traceability matrix from PRD. Produces scenario-set.md which is the universal input for ALL downstream test skills. Must run before any test writing skill.
allowed-tools: Read Grep Glob
context: fork
agent: Explore
---

# Test Strategy Planner

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

### 1. test-strategy.md
The full test strategy document with all 9 sections.

### 2. scenario-set.md (CRITICAL OUTPUT)
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
