---
name: traceability-engine
description: Maps PRD requirements to test scenarios to source code. Detects untested requirements, orphan tests, and stale traces. Maintains live Requirements Traceability Matrix (RTM). Use for coverage gap analysis, requirement validation, and audit trails.
allowed-tools: Read Grep Glob
context: fork
agent: Explore
---

# Traceability Engine

Ensures that PRD == Architecture == Code == Tests. Every requirement must be traceable through implementation to validation.

## Input
- PRD content (required): The requirements document
- scenario-set.md (optional): From test-strategy-planner
- Source code folder (optional): Project source directory
- Test files folder (optional): Project test directory
- $ARGUMENTS: Path to PRD or "trace current project"

## Three-Way Mapping Principle
```
PRD Requirement <---> Test Scenario <---> Source Code
     FR-001      <--->  SCN-1-001   <--->  @implements FR-001
```
A broken link in any direction = Traceability gap.

## Gap Types

| Gap Type | Description | Severity |
|----------|-------------|----------|
| UNTESTED_REQ | Requirement exists, no test scenario covers it | Critical (P0 req) / High (P1+) |
| UNLINKED_TEST | Test exists but maps to no requirement (orphan) | Medium |
| DEAD_REQ | Requirement has tests but no `@implements` annotation in code | Medium |
| PARTIAL_COVERAGE | Only happy path tested, missing error/edge cases | High |
| STALE_TRACE | Requirement changed since test was written | High |

## Algorithm

### Step 1: Source Analysis

**Requirement Extraction:**
Parse PRD for requirement identifiers (FR-XXX, NFR-XXX, or any REQ-XXX pattern).
Extract: { id, description, priority, type (functional/non-functional), source_line }

**Test Annotation Extraction:**
Scan test files for scenario IDs matching pattern: SCN-X-XXX-[H|N|E]-XX
Map each test file to the requirements it covers.

**Code Annotation Extraction:**
Scan source files for `@implements FR-XXX` or `// implements: FR-XXX` annotations.
Map each source file to the requirements it implements.

### Step 2: Gap Calculation
For each requirement:
1. Check if any test scenario references it -> if not: UNTESTED_REQ
2. Check if tests cover happy + error + edge paths -> if not: PARTIAL_COVERAGE
3. Check if any source file implements it -> if not: DEAD_REQ
4. Check if requirement was modified after test was last updated -> if so: STALE_TRACE

For each test:
1. Check if it maps to a valid requirement -> if not: UNLINKED_TEST

### Step 3: Traceability Score
```
traceabilityScore = (testedRequirements / totalRequirements) * 100
```
Adjusted by gap severity:
- Each UNTESTED P0 req: -10 points
- Each PARTIAL_COVERAGE: -5 points
- Each STALE_TRACE: -3 points

### Step 4: Priority-Aware Impact
P0 gaps are weighted 3x, P1 gaps 2x, P2 gaps 1x, P3 gaps 0.5x.

## Output Files

### 1. traceability-report.md
```markdown
# Traceability Report

## Summary
- Total Requirements: XX
- Tested Requirements: XX (XX%)
- Traceability Score: XX/100
- Untested P0 Requirements: XX (BLOCKER if > 0)

## Metrics
| Metric | Count | Impact |
|--------|-------|--------|
| UNTESTED_REQ | X | [Critical/High] |
| UNLINKED_TEST | X | Medium |
| DEAD_REQ | X | Medium |
| PARTIAL_COVERAGE | X | High |
| STALE_TRACE | X | High |

## Critical Gaps (P0 Requirements)
[Each with: requirement, why untested, impact, recommendation]

## All Gaps
[Full list organized by severity]

## Orphan Tests
[Tests that don't map to any requirement]
```

### 2. rtm-updated.md
Updated Requirements Traceability Matrix with current status:

| REQ-ID | Priority | Scenarios | Code Files | Status | Gaps |
|--------|----------|-----------|------------|--------|------|
| FR-001 | P0 | SCN-1-001-H-01 | auth.ts | COVERED | None |
| FR-002 | P0 | - | - | UNTESTED | No scenarios |

## Downstream Dependencies
- release-decision-engine (uses traceability score)
- coverage-analyzer (uses RTM for requirement coverage)
- learning-loop-engine (uses gap patterns for improvement)

## Annotation Conventions
To improve traceability, recommend teams use these annotations:

In source code:
```typescript
// @implements FR-001
// @implements FR-002, FR-003
```

In test files:
```typescript
describe('SCN-1-001-H-01: User login happy path', () => { ... })
// @covers FR-001
```
