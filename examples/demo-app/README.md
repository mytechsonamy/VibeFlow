# VibeFlow Demo — E-commerce Product Catalog

A small, self-contained sample project that showcases a full VibeFlow
SDLC loop: PRD → scenarios → tests → coverage → release decision. The
entire project fits in one reading session and lands at a **GO**
verdict when the demo pipeline runs.

## What's inside

- `docs/PRD.md` — sample PRD written to high-testability standards
- `src/` — TypeScript business logic (catalog / pricing / inventory)
- `tests/` — vitest unit tests, one file per source module
- `.vibeflow/reports/` — pre-baked artifacts showing what each VibeFlow skill emits
- `docs/DEMO-WALKTHROUGH.md` — step-by-step reading or live-run guide
- `vibeflow.config.json` — pre-initialized for solo mode, e-commerce domain

## Quick start

```bash
cd examples/demo-app
npm install        # first time only — installs vitest + typescript
npm test           # run the demo's own vitest suite
```

Then read `docs/DEMO-WALKTHROUGH.md` and walk through the six VibeFlow
commands in order (`prd-quality-analyzer` → `test-strategy-planner` →
`advance` → `release-decision-engine`).

## What this demo is NOT

- Not a Next.js app. The PRD goal in `docs/PRD.md` §1 is "an in-process
  catalog that a backend service can embed" — there's no HTTP layer,
  no database, no UI. The demo shows the VibeFlow workflow, not
  production web architecture.
- Not a mock. The `src/` code and `tests/` cases are real and passing.
  When you run `npm test`, 42+ vitest cases actually execute against
  the source.
- Not a full production pipeline. The `.vibeflow/reports/*.md`
  artifacts are checked in as pre-baked examples so the walkthrough
  makes sense without forcing every reader through every skill run.

## Regenerating the pre-baked artifacts

If you want to run every VibeFlow skill live (instead of reading the
pre-baked reports), delete the `.vibeflow/reports/` directory and
follow `docs/DEMO-WALKTHROUGH.md` step by step. Each skill will
recreate its artifact. The generated files should match the
pre-baked versions within a few percentage points.
