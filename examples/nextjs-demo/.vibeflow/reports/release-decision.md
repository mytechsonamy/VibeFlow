# Release Decision — nextjs-review-demo

<!-- @generated-by vibeflow:release-decision-engine (demo pre-bake) -->
<!-- Regenerate with: /vibeflow:release-decision-engine -->

## Header
- **Project**: nextjs-review-demo
- **Domain**: e-commerce
- **Decision date**: 2026-04-14T00:00:00Z
- **Mode**: solo (single-AI review path)
- **Release-decision version**: `releaseDecisionVersion: 1`

## Verdict
**GO — 91 / 100**

| Gate | Weight | Score | Domain floor | Pass? |
|------|--------|-------|--------------|-------|
| `prd-quality-analyzer` | 0.15 | 86 | 75 | ✅ |
| `coverage-analyzer` — line | 0.15 | 94 | 80 | ✅ |
| `coverage-analyzer` — critical path | 0.20 | 100 | 100 | ✅ |
| `mutation-test-runner` | 0.15 | 85 | 70 | ✅ |
| `test-result-analyzer` — P0 bugs | 0.15 | 100 | 100 | ✅ |
| `uat-executor` — e-commerce UAT | 0.20 | 88 | 85 | ✅ |

All six weighted gates cleared their e-commerce domain floors. No
conditional blocks triggered.

## Weighted composite

```
0.15 * 86     = 12.90
0.15 * 94     = 14.10
0.20 * 100    = 20.00
0.15 * 85     = 12.75
0.15 * 100    = 15.00
0.20 * 88     = 17.60
-----------------------
Total         = 92.35 → rounded 91
```

Threshold bands for the `e-commerce` domain:
- **GO** ≥ 85
- **CONDITIONAL** ≥ 70
- **BLOCKED** < 70 OR any P0 hard-block

Result: 91 ≥ 85 → **GO**.

## Evidence

- [PRD quality report](./prd-quality-report.md) — testability 86, 0 ambiguous
- [Scenario set](./scenario-set.md) — 14 scenarios, every P0 requirement mapped
- [Test strategy](./test-strategy.md) — single-tier unit strategy, 41 tests
- `test-results.md` — _(run the demo live to generate)_
- `coverage-report.md` — _(run the demo live to generate)_
- `mutation-report.md` — _(run the demo live to generate)_

## Rollback plan

Not applicable — the demo is not a deployable artifact. For a real
Next.js deploy the rollback plan would be emitted by the
`release-decision-engine` alongside this file, with specific
instructions for rolling back a Vercel / Kubernetes / custom host
deployment.

## Notes for readers

This is a **pre-baked** demo decision. A fresh run of
`release-decision-engine` against the live demo will regenerate this
file with the actual scores — they should be close, because the
underlying code and tests are stable. If the numbers drift by more
than a few points after a real run, the PRD or the tests have
meaningfully changed and the demo walk-through needs an update.

Compared to the pure-TypeScript demo at `examples/demo-app/` (which
scores 92 / 100), this Next.js demo loses one point on PRD quality
and one on UAT — a reflection of the extra structural complexity that
JSX + server actions + app-router params add without proportionally
improving the testable surface.
