---
name: release-decision-engine
description: Aggregates all quality signals into a deterministic release decision (GO/CONDITIONAL/BLOCKED). Uses domain-specific weighted scoring. Always runs LAST in staging-uat and release-decision pipelines. Use when deciding whether a release is safe.
allowed-tools: Read Write Grep Glob AskUserQuestion
context: fork
---

# Release Decision Engine

## Phase Contract

This skill runs in **DEPLOYMENT** only. Before any other step, read
`vibeflow.config.json`'s `currentPhase`. If it is not DEPLOYMENT, emit:

> release-decision-engine is for DEPLOYMENT phase; current is
> `<phase>`. Complete TESTING gates (coverage, mutation, UAT) and run
> `/vibeflow:advance` first.

…and stop. The engine is read-only by design (no Write tool), so the
hook never sees it, but a phase-mismatched invocation would produce a
misleading verdict on incomplete inputs — the self-check catches that
before any file is read.

The final gate in the VibeFlow pipeline. Produces an explainable, deterministic release decision.

## Input
Required:
- coverage-report.md (from coverage-analyzer)
- uat-raw-report.md (from uat-executor)
- test-results.md (from test-result-analyzer)
- Domain config (from vibeflow.config.json)
- Risk tolerance (from vibeflow.config.json)

Optional (improve decision quality):
- invariant-matrix.md (from invariant-formalizer)
- chaos-report.md (from chaos-injector)
- traceability-report.md (from traceability-engine)
- business-rules.md (from business-rule-validator)

## Algorithm

### Step 1: Hard Blocker Check
These conditions result in IMMEDIATE BLOCKED decision (no scoring needed):

1. Any P0 requirement has < 100% test coverage
2. Any UAT P0 scenario failed
3. Any critical invariant violation exists
4. Self-contradiction detected in business rules
5. Double-entry accounting violation (financial domain)
6. Traceability score < 50% (too many untested requirements)
7. P0 regression test failure

If ANY hard blocker is found: decision = BLOCKED, stop processing.

### Step 2: Weighted Risk Scoring
Apply domain-specific weights:

| Signal | Financial | E-Commerce | Healthcare | General |
|--------|-----------|------------|------------|---------|
| Coverage | 30% | 25% | 30% | 25% |
| Invariants | 25% | 20% | 25% | 15% |
| UAT | 20% | 25% | 20% | 25% |
| Chaos/Resilience | 15% | 10% | 10% | 10% |
| Traceability | 5% | 5% | 10% | 5% |
| Business Rules | 5% | 15% | 5% | 20% |

For each signal, compute a 0-100 score, then apply weights.

### Step 3: Decision Matrix

| Domain | GO | CONDITIONAL | BLOCKED |
|--------|-----|-------------|---------|
| Financial | >= 90 | >= 75 | < 75 |
| E-Commerce | >= 85 | >= 70 | < 70 |
| Healthcare | >= 95 | >= 85 | < 85 |
| General | >= 80 | >= 65 | < 65 |

### CONDITIONAL Rules
CONDITIONAL means "can release with mitigations":
- Feature flags for risky areas
- Enhanced monitoring for first 24h
- Rollback plan documented and tested
- Specific test gaps documented with risk acceptance

## Output: release-decision.md

```markdown
# Release Decision Report

## Decision: [GO | CONDITIONAL | BLOCKED]
## Risk Score: XX/100
## Domain: [financial | e-commerce | healthcare | general]
## Date: YYYY-MM-DD

## Hard Blockers
[List any hard blockers found, or "None"]

## Risk Score Breakdown
| Signal | Score | Weight | Weighted |
|--------|-------|--------|----------|
| Coverage | XX | XX% | XX |
| Invariants | XX | XX% | XX |
| ... | ... | ... | ... |
| **Total** | | | **XX** |

## Findings
### Critical (must fix)
[Each with: finding, why it matters, impact if ignored, confidence level]

### High (should fix)
[...]

### Medium (consider fixing)
[...]

## Next Steps
### If GO:
- Proceed with deployment
- Enable monitoring dashboard

### If CONDITIONAL:
- [Specific mitigations required]
- [Feature flags to enable]
- [Monitoring thresholds to set]

### If BLOCKED:
- [Specific items to fix]
- [Which skills to re-run after fixes]
- [Estimated effort to unblock]
```

## Operator choice (mobile-friendly — see `docs/OPERATOR-CHOICES.md`)

After writing `release-decision.md`, surface the next action via the
**`AskUserQuestion`** tool as tappable options keyed on the verdict, each
description carrying the condensed reason (top blocker / mitigation), so the
operator can act from a phone instead of reading the full report:

- **GO** → **Proceed to deploy (Recommended)** (`/vibeflow:deploy-verifier` /
  the deploy step) · **Review report**.
- **CONDITIONAL** → **Release with mitigations** (names the required mitigations)
  · **Fix first** · **Review report**.
- **BLOCKED** → **Fix blockers** (names the top blocker + which skill re-runs it)
  · **Review report**.

"Other" always lets the operator type. This is a *surfacing* of the deterministic
verdict — it does not change the GO/CONDITIONAL/BLOCKED decision or the
GO-only auto-satisfy below.

## Explainability Contract
Every finding MUST include:
- **finding**: What was detected
- **why**: Why this matters for the domain
- **impact**: What happens if ignored (quantified if possible)
- **confidence**: HIGH/MEDIUM/LOW based on data quality

## Auto-Satisfy: `release.decision.go` (Sprint 26-A — GO only)

`release.decision.go` is DEPLOYMENT's entry criterion. Before v2.14.0 the
release decision was computed but **never recorded** in project state, so
it never showed in `/vibeflow:flow-status` or the loop-audit and couldn't gate
deployment. Now: **when and only when your verdict is `GO`**, record it by
invoking the MCP tool (the main agent resolves this as a standard tool
call — same pattern as `deploy-verifier`):

```
mcp__sdlc-engine__sdlc_satisfy_criterion {
  "projectId": "<project id from vibeflow.config.json>",
  "criterion": "release.decision.go"
}
```

**CONDITIONAL and BLOCKED do NOT satisfy it** — leaving it unsatisfied is
what lets the opt-in entry-gate (`gates.enforceEntryCriteria`, Sprint
26-B) block DEPLOYMENT entry until a genuine GO is recorded. Do not
satisfy on CONDITIONAL "GO-with-mitigations"; that is a separate operator
decision, not an automatic GO.

## Final Step: Auto-Consensus Marker (MANDATORY — Sprint 15-B / 16-C)

After your output files are written to `.vibeflow/reports/`, your
**final action** is to Write the auto-consensus marker at
`.vibeflow/state/consensus-needed.json` with:

```json
{
  "primaryArtifact": ".vibeflow/reports/release-decision.md",
  "evidence": [
    ".vibeflow/reports/release-decision.md",
    ".vibeflow/reports/coverage-report.md",
    ".vibeflow/reports/mutation-report.md",
    ".vibeflow/reports/deploy-verification.md"
  ],
  "artifact": ".vibeflow/reports/release-decision.md",
  "requiredCommand": "/vibeflow:consensus-orchestrator .vibeflow/reports/release-decision.md",
  "createdAt": "<current UTC ISO-8601 timestamp>",
  "createdBy": "release-decision-engine"
}
```

Sprint 16-A's `consensus-gate` hook blocks every `Bash|Write|Edit`
tool call while the marker is present, surfacing the
`requiredCommand` to the operator until they run the orchestrator —
which drains the marker on APPROVED / NEEDS_REVISION / REJECTED
(Sprint 16-B). This is the mandatory layer; the prose invocation
below is best-effort for the main-agent case:

```
/vibeflow:consensus-orchestrator .vibeflow/reports/release-decision.md
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
