---
name: release-decision-engine
description: Aggregates all quality signals into a deterministic release decision (GO/CONDITIONAL/BLOCKED). Uses domain-specific weighted scoring. Always runs LAST in staging-uat and release-decision pipelines. Use when deciding whether a release is safe.
disable-model-invocation: true
allowed-tools: Read Grep Glob
context: fork
agent: Explore
---

# Release Decision Engine

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

## Explainability Contract
Every finding MUST include:
- **finding**: What was detected
- **why**: Why this matters for the domain
- **impact**: What happens if ignored (quantified if possible)
- **confidence**: HIGH/MEDIUM/LOW based on data quality
