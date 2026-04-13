# Release Decision — demo-catalog

<!-- @generated-by vibeflow:release-decision-engine (demo pre-bake) -->
<!-- Regenerate with: /vibeflow:release-decision-engine -->

## Header
- **Project**: demo-catalog
- **Domain**: e-commerce
- **Decision date**: 2026-04-13T00:00:00Z
- **Mode**: solo (single-AI review path)
- **Release-decision version**: `releaseDecisionVersion: 1`

## Verdict
**GO — 92 / 100**

| Gate | Weight | Score | Domain floor | Pass? |
|------|--------|-------|--------------|-------|
| `prd-quality-analyzer` | 0.15 | 87 | 75 | ✅ |
| `coverage-analyzer` — line | 0.15 | 95 | 80 | ✅ |
| `coverage-analyzer` — critical path | 0.20 | 100 | 100 | ✅ |
| `mutation-test-runner` | 0.15 | 85 | 70 | ✅ |
| `test-result-analyzer` — P0 bugs | 0.15 | 100 | 100 | ✅ |
| `uat-executor` — e-commerce UAT | 0.20 | 90 | 85 | ✅ |

All six weighted gates cleared their e-commerce domain floors. No
conditional blocks triggered.

## Weighted composite

```
0.15 * 87     = 13.05
0.15 * 95     = 14.25
0.20 * 100    = 20.00
0.15 * 85     = 12.75
0.15 * 100    = 15.00
0.20 * 90     = 18.00
-----------------------
Total         = 93.05 → rounded 92
```

Threshold bands for the `e-commerce` domain:
- **GO** ≥ 85
- **CONDITIONAL** ≥ 70
- **BLOCKED** < 70 OR any P0 hard-block

Result: 92 ≥ 85 → **GO**.

## Evidence

- [PRD quality report](./prd-quality-report.md) — testability 87, 0 ambiguous
- [Scenario set](./scenario-set.md) — 16 scenarios, every P0 requirement mapped
- [Test strategy](./test-strategy.md) — single-tier unit strategy, 42 tests
- `test-results.md` — _(run the demo live to generate)_
- `coverage-report.md` — _(run the demo live to generate)_
- `mutation-report.md` — _(run the demo live to generate)_

## Rollback plan

Not applicable — the demo is not a deployable artifact. For a real
project the rollback plan would be emitted by the
`release-decision-engine` alongside this file.

## Notes for readers

This is a **pre-baked** demo decision. A fresh run of
`release-decision-engine` against the live demo will regenerate this
file with the actual scores — they should be close, because the
underlying code and tests are stable. If the numbers drift by more
than a few points after a real run, the PRD or the tests have
meaningfully changed and the demo walk-through needs an update.
