# VibeFlow Demo Walkthrough

This walkthrough takes a reader from zero to a GO release decision on
the sample e-commerce product catalog. Every step points at a real
file in this directory so you can inspect what each VibeFlow skill
produces — even if you choose not to run the full pipeline live.

Estimated time:
- **Reading-only**: 15 minutes
- **Live run** (install + execute every skill): 45 minutes

## 0. Prerequisites

- VibeFlow plugin installed (`claude --plugin-dir ./` from the repo root, or installed via `claude plugin install vibeflow`)
- `node` 18+ and `npm` for the demo's own test runner
- Open this directory in Claude Code as the working project

```bash
cd examples/demo-app
claude
```

## 1. Inspect the project layout

```
examples/demo-app/
├── docs/
│   ├── PRD.md                    ← §1 — the sample PRD
│   └── DEMO-WALKTHROUGH.md       ← this file
├── src/
│   ├── catalog.ts                ← §3.1 in the PRD (CAT-*)
│   ├── pricing.ts                ← §3.2 in the PRD (PRC-*)
│   └── inventory.ts              ← §3.3 in the PRD (INV-*)
├── tests/
│   ├── catalog.test.ts           ← 16 vitest cases covering CAT-*
│   ├── pricing.test.ts           ← 16 vitest cases covering PRC-*
│   └── inventory.test.ts         ← 11 vitest cases covering INV-*
├── .vibeflow/
│   └── reports/
│       ├── prd-quality-report.md ← §2 output
│       ├── scenario-set.md       ← §3 output
│       ├── test-strategy.md      ← §3 output
│       └── release-decision.md   ← §5 output
├── vibeflow.config.json          ← pre-initialized for solo / e-commerce
├── package.json
├── tsconfig.json
└── vitest.config.ts
```

The `.vibeflow/reports/*.md` files are **pre-baked**: they were
generated once from a clean run and are checked in so the walkthrough
makes sense without requiring every reader to run every skill.

## 2. Analyze the PRD

Run the PRD quality analyzer against the sample PRD:

```
/vibeflow:prd-quality-analyzer docs/PRD.md
```

Expected output: a report that matches `.vibeflow/reports/prd-quality-report.md`:
- `testabilityScore` = 87 (above the e-commerce 75 threshold)
- `ambiguousTerms` = 0
- `missingAcceptanceCriteria` = 0
- Verdict: **APPROVED**

**Why 87 and not 100**: the score subtracts a few points for
requirements that don't specify units on timing-adjacent phrasing
(e.g. CAT-005's `page` / `pageSize` fields could tighten their bounds
further). The point of the demo is to show a high but not-perfect
PRD passing the gate — most real PRDs land in the 70-90 range.

## 3. Plan the test strategy

```
/vibeflow:test-strategy-planner docs/PRD.md
```

Expected output matches `.vibeflow/reports/test-strategy.md`:
- 16 unit scenarios mapped to the 15 requirements + 1 invariant sweep
- Single-tier plan (vitest only; no integration/e2e/contract tests)
- Critical paths: `src/pricing.ts`, `src/inventory.ts`
- Coverage budget: 90% line, 85% branch, 100% critical-path

Then run the scenario generator:

```
/vibeflow:scenario-generator docs/PRD.md
```

This emits `.vibeflow/reports/scenario-set.md` (pre-baked) with 16
scenarios. Every scenario has a stable id, a priority, a
requirement map (`Maps to: CAT-001`), and a Given / When / Then.

## 4. Advance the phase

At this point the PRD is approved and the strategy is planned. Move
from `REQUIREMENTS` to `DESIGN`, and then all the way to
`DEVELOPMENT`:

```
/vibeflow:advance DESIGN
/vibeflow:advance ARCHITECTURE
/vibeflow:advance PLANNING
/vibeflow:advance DEVELOPMENT
```

Each `advance` call triggers the sdlc-engine's phase-gate check. For
the demo, the phase gates are lightly seeded — every criterion is
already satisfied (`prd.approved`, `testability.score>=60`, etc.) so
the advances succeed without review cycles.

You can see the current phase at any time with:

```
/vibeflow:status
```

## 5. Run the tests

The demo's own vitest suite is live:

```bash
cd examples/demo-app
npm install                 # first time only; installs vitest + typescript
npm test
```

Expected:

```
 Test Files  3 passed (3)
      Tests  43 passed (43)
```

(The exact count may tick up as the demo evolves; 42-44 is in range.)

## 6. Run the release decision

```
/vibeflow:release-decision-engine
```

Expected output matches `.vibeflow/reports/release-decision.md`:
- Weighted composite: **92 / 100**
- Every gate above its e-commerce domain floor
- Verdict: **GO**

If you want to see what a CONDITIONAL verdict looks like, delete one
of the tests in `tests/pricing.test.ts` (say the `half-down rounding`
case), re-run vitest, then re-run the decision engine. You should see
the coverage score drop and the verdict downgrade to CONDITIONAL
(typically 70-80 range). Put the test back to restore GO.

## 7. What's next

This demo deliberately does NOT cover:

- **Team mode** — needs PostgreSQL set up; see `docs/TEAM-MODE.md`
  (Sprint 4 ticket S4-04)
- **Chaos injection** — the demo has no external dependencies
- **Reconciliation simulator** — the demo is e-commerce not financial

Each of those surfaces are documented in the main VibeFlow `docs/`
directory. For a deeper dive, point `codebase-intel` at the
`mcp-servers/` directory to see how the orchestration layer is wired.
