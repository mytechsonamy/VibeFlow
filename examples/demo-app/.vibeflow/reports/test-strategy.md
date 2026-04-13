# Test Strategy — demo-catalog

<!-- @generated-by vibeflow:test-strategy-planner (demo pre-bake) -->
<!-- Regenerate with: /vibeflow:test-strategy-planner docs/PRD.md -->

## Context
- **Project**: demo-catalog
- **Domain**: e-commerce
- **Mode**: solo (single-AI review)
- **Test runner**: vitest
- **Critical paths**: `src/pricing.ts`, `src/inventory.ts`

## Strategy

The demo is small enough that a single testing tier (unit via vitest)
covers every requirement. No integration, UI, or contract tests are
needed — the catalog has no network boundary, no UI, and no external
contract.

### Tiers

| Tier | Skill | Count | Reason |
|------|-------|-------|--------|
| Unit | `component-test-writer` | 16 scenarios | every P0/P1 requirement in §3 of the PRD |
| Integration | — | 0 | no process boundary |
| E2E | — | 0 | no UI / endpoint |
| Contract | — | 0 | no external API |
| Chaos | — | 0 | single-process, no external dependencies |
| Mutation | `mutation-test-runner` | ~50 mutants | exercises `pricing.ts` + `inventory.ts` (critical paths) |

### Coverage budget

- **Line coverage**: ≥ 90% (e-commerce domain threshold 0.80 + demo-stricter 0.90 — the demo is small enough to fully cover)
- **Branch coverage**: ≥ 85%
- **Critical-path coverage**: 100% (both `pricing.ts` and `inventory.ts` must be zero-uncovered in P0 code)
- **Mutation score**: ≥ 0.80 on `src/pricing.ts` + `src/inventory.ts`

### Priority mapping

Every scenario in `scenario-set.md` carries a priority tag matching its
source requirement in `docs/PRD.md`. The P0/P1 split:

| Priority | Count | Scenarios |
|----------|-------|-----------|
| P0 | 12 | CAT-001/002 + all 5 PRC + 4 INV + INV-SWEEP |
| P1 | 4  | CAT-003/004/005 + INV-004 |

### Risk notes

- **Money arithmetic drift** — the whole point of the `priceMinor`
  integer rule is to keep `Number` floats out of the pricing path.
  Any PR that introduces `parseFloat` / `*` / `/` on a currency value
  must be reviewed as a critical change. The mutation-test-runner's
  `integer-arithmetic` catalog already targets this.
- **Concurrent reserve/commit** — not a concern in the demo because
  everything runs single-threaded. A production deploy would add
  reconciliation-simulator coverage on the reserve → commit → release
  sequence.

## Expected outcomes

After running the full strategy against `src/**` + `tests/**`, the
demo's artifacts land at:

- `test-results.md` — 42 tests run, 42 passed (15 + 16 + 11 for catalog / pricing / inventory respectively)
- `coverage-report.md` — line 95%+, branch 90%+, critical-path 100%
- `mutation-report.md` — mutation score 0.85 on critical paths, 0 surviving P0 mutants
- `release-decision.md` — **GO** (e-commerce domain threshold cleared)
