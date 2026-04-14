# VibeFlow Next.js Demo

A second VibeFlow demo, parallel to `examples/demo-app/`, targeted
at a Next.js 14 app-router project. This demo validates that
VibeFlow skills handle JSX, React Server Components, and server
actions — not just pure TypeScript business logic.

See [`docs/NEXTJS-DEMO-WALKTHROUGH.md`](./docs/NEXTJS-DEMO-WALKTHROUGH.md)
for the full walkthrough.

## Layout

```
examples/nextjs-demo/
├── app/                        — Next.js 14 app router
│   ├── layout.tsx
│   ├── page.tsx                — redirects to /products
│   └── products/
│       ├── page.tsx            — RSC listing (uses listProducts())
│       └── [id]/
│           └── page.tsx        — product detail + review form (server action)
├── actions/
│   └── submit-review.ts        — "use server" action wrapping lib/reviews
├── lib/
│   ├── catalog.ts              — in-memory catalog (PROD-*)
│   └── reviews.ts              — validation + persistence (REV-*)
├── tests/                      — vitest (node env, no Next runtime needed)
├── docs/
│   ├── PRD.md
│   └── NEXTJS-DEMO-WALKTHROUGH.md
├── .vibeflow/reports/          — pre-baked skill artifacts
├── vibeflow.config.json
├── package.json
├── next.config.mjs
├── tsconfig.json
└── vitest.config.ts
```

## Running the tests (no Next runtime needed)

```bash
cd examples/nextjs-demo
npm install
npm test
```

vitest runs the pure-TypeScript suites in `tests/` — no React,
no Next dev server. The `.tsx` files exist so the demo looks like
a real Next.js 14 project, but none of them are imported by the
test suites.
