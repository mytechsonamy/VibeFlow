# VibeFlow Next.js Demo Walkthrough

This walkthrough takes a reader from zero to a GO release decision on
the sample Next.js 14 review-submission feature. It is the second
VibeFlow demo — the first, at `examples/demo-app/`, proves VibeFlow
handles pure-TypeScript business logic. This one proves it also
handles JSX, React Server Components, and server actions. Every step
points at a real file in this directory so you can inspect what each
VibeFlow skill produces — even if you choose not to run the full
pipeline live.

Estimated time:
- **Reading-only**: 15 minutes
- **Live run** (install + run tests + run each skill): 45 minutes

## 0. Prerequisites

- VibeFlow plugin installed (`claude --plugin-dir ./` from the repo
  root, or installed via `claude plugin install vibeflow`)
- `node` 18+ and `npm` for the demo's own test runner
- Open this directory in Claude Code as the working project

```bash
cd examples/nextjs-demo
claude
```

## 1. Inspect the project layout

```
examples/nextjs-demo/
├── docs/
│   ├── PRD.md                        ← §1 — the sample PRD
│   └── NEXTJS-DEMO-WALKTHROUGH.md    ← this file
├── app/
│   ├── layout.tsx                    ← root layout (RSC)
│   ├── page.tsx                      ← / → redirects to /products
│   └── products/
│       ├── page.tsx                  ← §3.4 PAGE-001 (RSC listing)
│       └── [id]/
│           └── page.tsx              ← §3.4 PAGE-002 (RSC detail + form)
├── actions/
│   └── submit-review.ts              ← §3.3 ACT-* ("use server")
├── components/
│   └── rating-picker.tsx             ← "use client" — Sprint 6 / S6-04
├── lib/
│   ├── catalog.ts                    ← §3.1 PROD-*
│   ├── reviews.ts                    ← §3.2 REV-*
│   └── rating.ts                     ← pure helpers for the picker (S6-04)
├── tests/
│   ├── catalog.test.ts               ← 14 vitest cases covering PROD-*
│   ├── reviews.test.ts               ← 18 vitest cases covering REV-* + INV-*
│   ├── action.test.ts                ←  9 vitest cases covering ACT-*
│   └── rating.test.ts                ← 25 vitest cases covering lib/rating.ts (S6-04)
├── .vibeflow/
│   └── reports/
│       ├── prd-quality-report.md     ← §2 output
│       ├── scenario-set.md           ← §3 output
│       ├── test-strategy.md          ← §3 output
│       └── release-decision.md       ← §5 output
├── vibeflow.config.json              ← pre-initialized for solo / e-commerce
├── package.json
├── next.config.mjs
├── tsconfig.json
└── vitest.config.ts
```

The `.vibeflow/reports/*.md` files are **pre-baked**: they were
generated once from a clean run and are checked in so the walkthrough
makes sense without requiring every reader to run every skill.

### Why a separate demo?

`examples/demo-app/` intentionally has no UI. It is the shortest path
from a PRD to a GO verdict using only pure TypeScript. This demo adds
four surfaces that the first one cannot exercise:

1. **React Server Components** — `app/products/page.tsx` is a server
   component that imports directly from `lib/catalog.ts`.
2. **Server actions** — `actions/submit-review.ts` starts with the
   `"use server"` directive and is invoked from a `<form action={…}>`
   in a client-facing page.
3. **App-router route params** — `app/products/[id]/page.tsx` uses
   the file-based parameter shape Next.js 14 ships.
4. **Client components** — `components/rating-picker.tsx` starts
   with the `"use client"` directive and owns local React state
   (hover + click). It is imported by the RSC detail page, which is
   where the RSC/client boundary runs. (Sprint 6 / S6-04)

Every one of those still lands its business logic in a pure
`lib/*.ts` module — the rating picker's hover/click math lives in
`lib/rating.ts`, so vitest in the `node` environment covers every
branch without needing to mount the component or transpile JSX.

### The RSC/client boundary

The product detail page (`app/products/[id]/page.tsx`) is a React
Server Component: it runs on the server, reads from the in-memory
catalog, and emits HTML directly. It imports the `RatingPicker`
client component — the boundary runs at that import. Next.js 14
serializes the component's props (`name`, `max`, `defaultValue`) from
the server, delivers the component's code as a separate client
bundle, and hydrates it on the client.

The picker needs `"use client"` because it uses `useState` for:

- **Hover preview** — hovering a star previews that rating before
  committing, backed by `computeDisplay(rating, hover)` in
  `lib/rating.ts`. `hover === null` means "not hovering, show the
  committed rating"; any other value (including `0`) is an explicit
  preview override.
- **Click commit** — clicking a star calls
  `clampRating(star, max)` before setting state, so any out-of-range
  value (NaN, Infinity, negative) silently collapses to 0 rather
  than corrupting the form.
- **Hidden input** — the picker emits `<input type="hidden" name={name} />`
  so the form action still sees the numeric value on submit. The
  server action at `actions/submit-review.ts` re-validates the value
  with `validateReview({ rating, text })` regardless of what the
  client says — defense in depth.

The logic above is covered by 25 vitest cases in `tests/rating.test.ts`
(5 `computeDisplay` + 9 `clampRating` + 5 `renderStars` + 6
`isValidSubmittedRating`). Every branch tests without touching React.

## 2. Analyze the PRD

Run the PRD quality analyzer against the sample PRD:

```
/vibeflow:prd-quality-analyzer docs/PRD.md
```

Expected output: a report that matches `.vibeflow/reports/prd-quality-report.md`:
- `testabilityScore` = 86 (above the e-commerce 75 threshold)
- `ambiguousTerms` = 0
- `missingAcceptanceCriteria` = 0
- Verdict: **APPROVED**

**Why 86 and not 100**: the analyzer subtracts a few points for
sections that don't name a numeric bound on every sub-field (for
example PROD-001 bounds `description` at 10–500 chars, but the
PAGE-* requirements bound structure rather than a measurement). The
point of the demo is to show a strong-but-not-perfect PRD clearing
the gate — most real PRDs land in the 70–90 range.

## 3. Plan the test strategy

```
/vibeflow:test-strategy-planner docs/PRD.md
```

Expected output matches `.vibeflow/reports/test-strategy.md`:
- 14 unit scenarios mapped to the 14 explicit requirements + invariant
  sweep hooks on the REV-* path
- Single-tier plan (vitest only; no integration/e2e/contract tests)
- Critical paths: `lib/reviews.ts`, `lib/catalog.ts`, `actions/submit-review.ts`
- Coverage budget: 90% line, 85% branch, 100% critical-path

Then run the scenario generator:

```
/vibeflow:scenario-generator docs/PRD.md
```

This emits `.vibeflow/reports/scenario-set.md` (pre-baked) with 14
scenarios. Every scenario has a stable id, a priority, a requirement
map (`Maps to: PROD-001`), and a Given / When / Then.

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
cd examples/nextjs-demo
npm install                 # first time only; installs next, react, vitest
npm test
```

Expected:

```
 Test Files  4 passed (4)
      Tests  66 passed (66)
```

(The exact count may tick up as the demo evolves; the breakdown is
14 catalog + 18 reviews + 9 action + 25 rating after Sprint 6 / S6-04.)

Note: **the vitest suite does not boot Next**. It imports directly
from `lib/*.ts` and `actions/*.ts`. The `app/**/*.tsx` files and the
`components/*.tsx` client component are part of the demo's surface
area but are covered structurally by the VibeFlow harness
(`tests/integration/sprint-5.sh [S5-D]` for the RSC pages,
`tests/integration/sprint-6.sh [S6-B]` for the `"use client"`
component), not by vitest.

### Optionally running `next build`

If you install the full dependency tree (`npm install` pulls Next,
React, and their transitive deps — ~500 MB of disk), you can also
run the production build:

```bash
cd examples/nextjs-demo
npm install
npm run build
```

`sprint-6.sh [S6-B]` picks this up automatically: when
`examples/nextjs-demo/node_modules/next` exists and
`VF_SKIP_NEXT_BUILD=1` is not set, the harness runs `npm run build`
and asserts a clean exit. Otherwise it skips gracefully. This means
day-to-day contributors do not have to install Next to keep the
gauntlet green.

## 6. Run the release decision

```
/vibeflow:release-decision-engine
```

Expected output matches `.vibeflow/reports/release-decision.md`:
- Weighted composite: **91 / 100**
- Every gate above its e-commerce domain floor
- Verdict: **GO**

If you want to see what a CONDITIONAL verdict looks like, delete one
of the tests in `tests/reviews.test.ts` (say the profanity case),
re-run vitest, then re-run the decision engine. You should see the
coverage and UAT scores drop and the verdict downgrade to
CONDITIONAL. Put the test back to restore GO.

## 7. What's next

This demo deliberately does NOT cover:

- **Team mode** — see `examples/demo-app/docs/DEMO-WALKTHROUGH.md`
  and the Sprint 4 team-mode docs
- **Chaos injection** — the demo has no external dependencies
- **Mutation on the UI layer** — the `app/**/*.tsx` files are not
  exercised by mutation testing because their business logic lives in
  `lib/`

For a deeper dive, point `codebase-intel` at the `mcp-servers/`
directory to see how the orchestration layer is wired. For the
earlier TypeScript-only demo, see
[`examples/demo-app/docs/DEMO-WALKTHROUGH.md`](../../demo-app/docs/DEMO-WALKTHROUGH.md).
