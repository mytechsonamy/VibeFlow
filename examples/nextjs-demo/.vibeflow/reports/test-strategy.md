# Test Strategy — nextjs-review-demo

<!-- @generated-by vibeflow:test-strategy-planner (demo pre-bake) -->
<!-- Regenerate with: /vibeflow:test-strategy-planner docs/PRD.md -->

## Context
- **Project**: nextjs-review-demo
- **Domain**: e-commerce
- **Mode**: solo (single-AI review)
- **Framework**: Next.js 14 app router + React Server Components + server actions
- **Test runner**: vitest (node environment)
- **Critical paths**: `lib/reviews.ts`, `lib/catalog.ts`, `actions/submit-review.ts`

## Strategy

The demo is small enough that a single testing tier (unit via vitest)
covers every logic branch. No integration, UI, or contract tests are
needed because every business rule lives in pure-TypeScript modules
under `lib/` and `actions/`. The JSX surface (`app/**/*.tsx`) is
deliberately thin and is validated structurally by the Sprint 5
integration harness (`tests/integration/sprint-5.sh [S5-D]`), not by
vitest.

### Tiers

| Tier | Skill | Count | Reason |
|------|-------|-------|--------|
| Unit | `component-test-writer` | 14 scenarios | every PROD/REV/ACT requirement + 2 structural PAGE checks |
| Integration | — | 0 | no process boundary |
| E2E | — | 0 | demo does not boot Next in tests |
| Contract | — | 0 | no external API |
| Chaos | — | 0 | single-process, no external dependencies |
| Mutation | `mutation-test-runner` | ~55 mutants | exercises `lib/reviews.ts` + `actions/submit-review.ts` (critical paths) |

### Coverage budget

- **Line coverage**: ≥ 90% (e-commerce domain threshold 0.80 + demo-stricter 0.90)
- **Branch coverage**: ≥ 85%
- **Critical-path coverage**: 100% (`lib/reviews.ts`, `lib/catalog.ts`, and
  `actions/submit-review.ts` must have zero uncovered P0 code)
- **Mutation score**: ≥ 0.80 on the three critical-path files

### Priority mapping

Every scenario in `scenario-set.md` carries a priority tag matching
its source requirement in `docs/PRD.md`. The P0/P1 split:

| Priority | Count | Scenarios |
|----------|-------|-----------|
| P0 | 9  | PROD-001/002 + REV-001/002/003 + ACT-001/002/003 + (PAGE-002 is P1 structural) |
| P1 | 5  | PROD-003/004 + REV-004 + ACT-004 + PAGE-001 (PAGE-002 too — structural) |

### Risk notes

- **Server action input trust** — because server actions receive
  `FormData` straight from the browser, every field must be treated
  as unknown. The action's `typeof` + `Number()` guards address this;
  mutation testing on `actions/submit-review.ts` must cover every
  guard.
- **Profanity filter bypass** — the filter is a substring match, not
  a tokenizer. Real-world moderation would need a tokenizer + a
  sanction model; this demo intentionally stops short because the
  filter is a proxy for "content validation exists" not "content
  moderation is production-ready".
- **In-memory review store** — `SEQ` is a module-level counter. A
  real deploy would use a database. Tests reset the store via
  `__resetReviewsForTests()` in a `beforeEach` hook so the invariant
  `INV-REV-ID-STABLE` holds across suites.

## Expected outcomes

After running the full strategy against `lib/**` + `actions/**` +
`tests/**`, the demo's artifacts land at:

- `test-results.md` — 41 tests run, 41 passed (14 catalog + 18 reviews + 9 action)
- `coverage-report.md` — line 95%+, branch 90%+, critical-path 100%
- `mutation-report.md` — mutation score 0.85 on critical paths, 0 surviving P0 mutants
- `release-decision.md` — **GO** (e-commerce domain threshold cleared)
