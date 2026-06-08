---
name: prd-quality-analyzer
description: Analyzes PRD documents for ambiguity, conflicts, and missing flows. Produces testability score (0-100). Writes a report to .vibeflow/reports/prd-quality-report.md and a cost-avoidance breakdown to .vibeflow/reports/prd-cost-avoidance.md. Use when reviewing requirements, validating PRDs, or before starting development. Blocks development if testability score < 60.
allowed-tools: Read Write Grep Glob
context: fork
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

**Every run MUST write the two files below to disk under
`.vibeflow/reports/` — never print the report to chat only. The
report path is the contract; downstream skills read from it. If the
directory doesn't exist, create it.**

Target paths:
- `.vibeflow/reports/prd-quality-report.md`
- `.vibeflow/reports/prd-cost-avoidance.md`

### 1. .vibeflow/reports/prd-quality-report.md
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

### 2. .vibeflow/reports/prd-cost-avoidance.md
Estimate the cost of NOT fixing each finding (based on the "1:10:100 rule" - fixing in requirements costs 1x, in dev 10x, in production 100x).

## Downstream Dependencies
This skill's output feeds into:
- test-strategy-planner (uses quality report to adjust strategy)
- architecture-validator (uses findings for design validation)
- traceability-engine (uses requirement list for RTM baseline)

## Auto-satisfy REQUIREMENTS criteria (Sprint 17.2 — MANDATORY)

After the quality report is written, **auto-satisfy the criteria
this skill is authoritative for** by calling the sdlc-engine MCP
tool. This removes the manual `sdlc_satisfy_criterion` step the
operator used to have to do before `/vibeflow:advance` would
work.

Read the config + score:
```bash
PROJECT_ID="$(vf_config_get '.project')"
SCORE="$(jq -r '.scores.total // .testabilityScore // 0' \
  .vibeflow/reports/prd-quality-report.md.json 2>/dev/null || echo 0)"
# Score is also in the markdown header if JSON sidecar is absent —
# grep for "Testability Score: NN/100" and extract NN.
```

Then call:

```
mcp__sdlc-engine__sdlc_satisfy_criterion {
  "projectId": "<project id>",
  "criterion": "prd.approved"
}
```

**`testability.score>=60`** is conditional: only satisfy this
criterion when the measured score is ≥ 60. Otherwise the gate
correctly blocks REQUIREMENTS → DESIGN advance until the PRD
improves.

```
if SCORE >= 60:
  mcp__sdlc-engine__sdlc_satisfy_criterion {
    "projectId": "<project id>",
    "criterion": "testability.score>=60"
  }
```

Emit a one-line confirmation so the operator sees the state
write:

```
Recorded: prd.approved (and testability.score>=60 with score=<N>).
```

If the MCP tool isn't reachable, emit a visible
"sdlc-engine MCP unavailable — satisfy manually:
`mcp__sdlc-engine__sdlc_satisfy_criterion {projectId:…, criterion:'prd.approved'}`"
and continue (the quality report is still on disk; the criterion
registration is the only thing missing).

The **third** REQUIREMENTS exit criterion —
`consensus.requirements.approved` — is not the analyzer's job.
The consensus-orchestrator records that automatically on
APPROVED/HUMAN_APPROVAL_REQUIRED verdicts (Sprint 17.2).

## Final Step: Auto-Consensus Marker (MANDATORY — Sprint 15-B / 16-C)

After you have written `prd-quality-report.md` **and**
`prd-cost-avoidance.md` to `.vibeflow/reports/`, your **final action**
is to Write the auto-consensus marker at
`.vibeflow/state/consensus-needed.json` with this JSON body:

```json
{
  "primaryArtifact": "<PRD path from $ARGUMENTS, e.g. docs/FlowBridge_TR_SRS_v1_1.docx>",
  "evidence": [
    ".vibeflow/reports/prd-quality-report.md",
    ".vibeflow/reports/prd-cost-avoidance.md"
  ],
  "artifact": ".vibeflow/reports/prd-quality-report.md",
  "requiredCommand": "/vibeflow:consensus-orchestrator <PRD path>",
  "createdAt": "<current UTC ISO-8601 timestamp>",
  "createdBy": "prd-quality-analyzer"
}
```

**Sprint 19-A — primaryArtifact + evidence (marker v2).** The
orchestrator reviews `primaryArtifact` (the PRD itself); the
`evidence[]` array carries analyzer reports that give the
reviewer panel context. `artifact` stays as the legacy single-
file field for `consensus-gate.sh` back-compat — no hook change
needed.

Sprint 16-A's `consensus-gate` hook reads this marker on every
`Bash | Write | Edit` tool call and refuses the call with a stderr
message naming `requiredCommand`, until the operator runs the
consensus-orchestrator — which drains the marker on APPROVED /
NEEDS_REVISION / REJECTED (Sprint 16-B). That is how we close the
"forked subagent cannot invoke a slash command" gap. Marker-writing
is not optional; without it the chain is purely advisory.

After the marker is written, **also** emit the next-step breadcrumb so
the operator always knows the one command to run next. Use the
project-wide `▶ Next:` prefix and keep it as the **literal last lines**
of your output. Recommend `phase-runner` first (it walks
analyzers → consensus → advance in one command), with the manual
orchestrator as the alternative:

```
▶ Next: /vibeflow:phase-runner
   (or, to run consensus by hand: /vibeflow:consensus-orchestrator <PRD path>)
```

Either path triggers the Claude + codex + gemini multi-AI review, which
writes a verdict file and — if the verdict is NEEDS_REVISION —
chains the arbiter/specialist to produce diff-first patches the operator
can review and apply.

**Skip condition (only one)**: if `VF_SKIP_AUTO_CONSENSUS=1` is set in
the environment, do NOT write the marker. Log "auto-consensus
skipped by env (VF_SKIP_AUTO_CONSENSUS)" and stop. The phase-gate in
`sdlc-engine` (Sprint 15-C) still blocks the next `/vibeflow:advance`
until a fresh REQUIREMENTS consensus is recorded — the env bypass
is call-scoped, not phase-scoped.
