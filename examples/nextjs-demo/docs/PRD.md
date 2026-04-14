# Next.js Review Demo — PRD

**Project**: `nextjs-review-demo`
**Domain**: `e-commerce`
**Mode**: `solo`
**Framework**: Next.js 14 (app router, React Server Components, server actions)
**Status**: Approved for DEVELOPMENT

This PRD is the sample input for the **Next.js** VibeFlow demo. It
sits parallel to `examples/demo-app/docs/PRD.md` — the earlier demo
is a pure-TypeScript business-logic exercise, while this one proves
VibeFlow skills handle JSX, server components, and server actions.
It is deliberately written to score high on `prd-quality-analyzer`
(testability ≥ 80, zero ambiguous terms, every requirement measurable
and bounded) so the demo walks the happy path all the way to a GO
release decision.

Do not treat this PRD as a reference for real-world e-commerce
architecture. It is minimal on purpose: the walk-through must fit in
one reading session.

---

## 1. Goal

Build a small Next.js 14 app-router feature that ships two pages and
one server action, demonstrating end-to-end validation discipline:

1. `/products` — a React Server Component that lists the in-memory
   catalog.
2. `/products/[id]` — a React Server Component that renders a single
   product and a review form.
3. `submitReviewAction` — a `"use server"` action that validates
   review input and persists a `Review` to an in-memory store.

Every business rule lives in `lib/*.ts` so it can be unit-tested with
vitest in the `node` environment, without booting Next.

## 2. Non-goals

- Persisting state across process restarts
- Multi-tenancy or per-user review moderation queues
- Currency conversion
- Real image hosting / file uploads
- Rich-text formatting or markdown sanitization
- Server-side rendering benchmarks

## 3. Requirements

Every requirement below is numbered with a stable id (`PROD-*`,
`REV-*`, `ACT-*`, `PAGE-*`). Each is written in the "MUST/REJECTS"
active-voice form the `prd-quality-analyzer` expects, with a single
measurable outcome.

### 3.1 Catalog requirements

- **PROD-001** (P0) Every product MUST carry the fields `id` (string),
  `name` (string), `priceMinor` (non-negative integer, minor currency
  units), `currency` (one of `USD` / `EUR` / `GBP`), and `description`
  (string, 10–500 chars).
- **PROD-002** (P0) `getProduct(id)` MUST return `undefined` for an
  unknown id and MUST NOT throw.
- **PROD-003** (P1) `listProducts()` MUST return products in stable
  alphabetical order by `name`.
- **PROD-004** (P1) `listProducts({ currency })` MUST return only
  products whose `currency` field matches.

### 3.2 Review validation requirements

- **REV-001** (P0) `rating` MUST be an integer between 1 and 5
  inclusive. Non-integers, values outside that range, and non-numeric
  input MUST reject with `rating must be integer 1-5`.
- **REV-002** (P0) `text` MUST be between 10 and 500 characters after
  trim. Shorter MUST reject with `text too short`; longer MUST reject
  with `text too long`; non-strings MUST reject with
  `text must be a string`.
- **REV-003** (P0) `text` MUST NOT contain any word from the
  configured profanity list. The match is case-insensitive substring.
  Violations MUST reject with `text contains forbidden words`.
- **REV-004** (P1) A persisted `Review` MUST carry `id`
  (`rev-<productId>-<n>`), `productId`, `rating`, `text` (trimmed),
  and `createdAt` (ISO-8601 string).

### 3.3 Server action requirements

- **ACT-001** (P0) `submitReviewAction(formData)` MUST read
  `productId`, `rating`, `text` from the `FormData`. Any missing field
  MUST reject with `missing field <name>`.
- **ACT-002** (P0) A `productId` that does not exist in the catalog
  MUST reject with `unknown product`.
- **ACT-003** (P0) On success the action MUST return
  `{ ok: true, review }` where `review` satisfies REV-004.
- **ACT-004** (P1) On any validation failure the action MUST return
  `{ ok: false, error }` and MUST NOT throw.

### 3.4 Page requirements

- **PAGE-001** (P1) `/products` MUST render one list entry per product
  returned by `listProducts()`.
- **PAGE-002** (P1) `/products/[id]` MUST call `notFound()` when
  `getProduct(id)` returns `undefined`.

## 4. Invariants

- **INV-MONEY-INTEGER** — every money field in every public API
  must pass `Number.isInteger`.
- **INV-REV-TEXT-TRIMMED** — a persisted review's `text` has no
  leading/trailing whitespace.
- **INV-REV-ID-STABLE** — within a session, review ids are unique and
  monotonically increasing.

## 5. Acceptance (how the demo scores this PRD)

When `prd-quality-analyzer` runs on this file:

| Dimension | Expected | Reason |
|-----------|----------|--------|
| `testabilityScore` | ≥ 80 | every requirement is numbered + measurable + bounded |
| `ambiguousTerms` | 0 | no "fast", "easy", "intuitive", "scalable", "robust" |
| `missingAcceptanceCriteria` | 0 | each requirement states its exact outcome |
| `domainFit` | e-commerce | product / catalog / review / currency vocabulary |

When `test-strategy-planner` runs on this file, the expected plan
covers:
- 4 PROD-* requirements → unit tests against `lib/catalog.ts`
- 4 REV-* requirements → unit tests against `lib/reviews.ts`
- 4 ACT-* requirements → unit tests against `actions/submit-review.ts`
- 2 PAGE-* requirements → structural checks (the pages are RSCs and
  are not exercised by vitest directly — they are validated by the
  harness assertion that `notFound()` is imported and that
  `submitReviewAction` is wired as the form action)
- 3 invariants → assertions baked into the unit suites

That matches what `examples/nextjs-demo/tests/*.test.ts` actually
contains, so the demo's coverage signal lands at a GO verdict.
