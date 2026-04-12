---
name: prd-quality-analyzer
description: Analyzes PRD documents for ambiguity, conflicts, and missing flows. Produces testability score (0-100). Use when reviewing requirements, validating PRDs, or before starting development. Blocks development if testability score < 60.
allowed-tools: Read Grep Glob
context: fork
agent: Explore
---

# PRD Quality Analyzer

You are the first gate in the VibeFlow SDLC pipeline. No development begins until the PRD passes quality analysis.

## Input
- PRD document (required): The product requirements document to analyze
- $ARGUMENTS: Path to PRD file or "analyze current requirements"

## Analysis Algorithm

### Step 1: Ambiguity Detection
Scan the PRD for these ambiguity types:

| Code | Type | Pattern Examples |
|------|------|-----------------|
| AMB-QUANTITATIVE | Vague quantities | "fast", "many", "approximately", "large number of" |
| AMB-CONDITIONAL | Unclear conditions | "if appropriate", "when necessary", "as needed" |
| AMB-SCOPE | Undefined boundaries | "etc.", "and so on", "similar things", "and more" |
| AMB-ACTOR | Unclear responsibility | "the system", "it should", passive voice without actor |
| AMB-FORMAT | Unspecified format | "proper format", "appropriate structure", "standard way" |
| AMB-TEMPORAL | Vague timing | "quickly", "in a timely manner", "soon", "periodically" |
| AMB-PRIORITY | Unclear importance | "should ideally", "might want to", "could consider" |
| AMB-REFERENCE | Missing cross-ref | "as mentioned before", "see above", "refer to the other" |

For each finding, report: { id, type, location, originalText, issue, suggestion, severity }

### Step 2: Conflict Detection
Cross-reference requirements for:
- **CONF-DIRECT**: Two requirements explicitly contradict (e.g., "must be public" vs "must require auth")
- **CONF-IMPLICIT**: Requirements that create impossible combinations at implementation
- **CONF-VERSION**: Requirement changed but dependent requirements not updated
- **CONF-EXAMPLE**: Example in PRD contradicts the stated rule

### Step 3: Missing Flow Detection
Check for these critical paths (mark as MISSING if absent):
1. Error/exception handling flows
2. Empty state / zero data scenarios
3. Concurrent access / race condition scenarios
4. Permission denied / unauthorized flows
5. Network failure / timeout handling
6. Data migration / backward compatibility
7. Rate limiting / abuse prevention

### Step 4: Testability Scoring
Score 0-100 across 5 dimensions:

| Dimension | Weight | Criteria |
|-----------|--------|----------|
| Somutluk (Concreteness) | 25 | Specific numbers, formats, examples provided |
| Netlik (Clarity) | 25 | Unambiguous language, clear actors and actions |
| Tamlik (Completeness) | 25 | All paths covered (happy, error, edge) |
| Bagimsizlik (Independence) | 15 | Requirements can be tested in isolation |
| Onceliklendirme (Priority) | 10 | Clear P0/P1/P2/P3 or MoSCoW classification |

### Verdict Thresholds
- **>= 90 EXCELLENT**: PRD is development-ready
- **75-89 GOOD**: Minor improvements recommended, can proceed
- **60-74 ACCEPTABLE**: Significant gaps, proceed with caution
- **40-59 CRITICAL_GAPS**: Must fix before development
- **< 40 NOT_IMPLEMENTABLE**: PRD needs major rewrite

**HARD RULE**: If testability score < 60, output a BLOCK recommendation. Development MUST NOT start.

## Output Files
Generate two files:

### 1. prd-quality-report.md
```markdown
# PRD Quality Report
## Summary
- Testability Score: XX/100
- Verdict: [EXCELLENT|GOOD|ACCEPTABLE|CRITICAL_GAPS|NOT_IMPLEMENTABLE]
- Ambiguities Found: X
- Conflicts Found: X
- Missing Flows: X

## Detailed Findings
### Ambiguities
[List each with id, type, location, suggestion]

### Conflicts
[List each with conflicting requirements]

### Missing Flows
[List each missing critical path]

## Scoring Breakdown
| Dimension | Score | Notes |
|-----------|-------|-------|
| Concreteness | XX/25 | ... |
| Clarity | XX/25 | ... |
| Completeness | XX/25 | ... |
| Independence | XX/15 | ... |
| Prioritization | XX/10 | ... |

## Recommendations
[Prioritized list of improvements needed before development]
```

### 2. prd-cost-avoidance.md
Estimate the cost of NOT fixing each finding (based on the "1:10:100 rule" - fixing in requirements costs 1x, in dev 10x, in production 100x).

## Downstream Dependencies
This skill's output feeds into:
- test-strategy-planner (uses quality report to adjust strategy)
- architecture-validator (uses findings for design validation)
- traceability-engine (uses requirement list for RTM baseline)
