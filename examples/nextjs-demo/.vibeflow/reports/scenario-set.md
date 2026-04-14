# Scenario Set — nextjs-review-demo

<!-- @generated-by vibeflow:test-strategy-planner (demo pre-bake) -->
<!-- Regenerate with: /vibeflow:test-strategy-planner docs/PRD.md -->

- **Project**: nextjs-review-demo
- **Source PRD**: docs/PRD.md
- **Generated**: 2026-04-14T00:00:00Z
- **Total scenarios**: 14 (12 requirement-mapped + 2 structural page checks)

## Catalog scenarios

### SC-PROD-001 — Seed products have the six-field shape
- **Priority**: P0
- **Maps to**: PROD-001
- **Given**: fresh import of `lib/catalog.ts`
- **When**: iterate `listProducts()`
- **Then**: every product has `id`, `name`, `priceMinor` (integer),
  `currency` ∈ {USD, EUR, GBP}, `description` (10-500 chars)

### SC-PROD-002 — Unknown id returns undefined
- **Priority**: P0
- **Maps to**: PROD-002
- **Given**: catalog is loaded
- **When**: `getProduct("no-such-id")`
- **Then**: returns `undefined` and does not throw

### SC-PROD-003 — Stable alphabetical ordering
- **Priority**: P1
- **Maps to**: PROD-003
- **Given**: the seeded catalog
- **When**: `listProducts()` twice in a row
- **Then**: both calls return the same sequence of ids, sorted by
  `name` via `localeCompare`

### SC-PROD-004 — Currency filter narrows the result
- **Priority**: P1
- **Maps to**: PROD-004
- **Given**: the seeded catalog contains at least one product per
  supported currency
- **When**: `listProducts({ currency: "USD" })`
- **Then**: every returned product has `currency === "USD"`

## Review validation scenarios

### SC-REV-001 — Rating must be an integer 1..5
- **Priority**: P0
- **Maps to**: REV-001
- **Given**: a valid review text
- **When**: `validateReview({ rating: 0|6|4.5|"5", text })`
- **Then**: returns `{ ok: false, error: "rating must be integer 1-5" }`

### SC-REV-002 — Text bounds 10..500 after trim
- **Priority**: P0
- **Maps to**: REV-002
- **Given**: a valid rating
- **When**: `validateReview({ rating, text: "   short   " })` or
  `validateReview({ rating, text: "x".repeat(501) })`
- **Then**: returns `{ ok: false, error: "text too short" | "text too long" }`

### SC-REV-003 — Profanity filter is case-insensitive substring
- **Priority**: P0
- **Maps to**: REV-003
- **Given**: `FORBIDDEN_WORDS` contains `"forbidden"`
- **When**: `validateReview({ rating: 3, text: "this is FORBIDDEN content indeed" })`
- **Then**: returns `{ ok: false, error: "text contains forbidden words" }`

### SC-REV-004 — Persisted review shape + trimmed text + monotonic id
- **Priority**: P1
- **Maps to**: REV-004 + INV-REV-TEXT-TRIMMED + INV-REV-ID-STABLE
- **Given**: two `persistReview(...)` calls with whitespace around text
- **When**: the second call runs
- **Then**: both reviews have `id` matching `rev-<productId>-<n>`
  where `n` is strictly increasing, and `text` has no edge whitespace

## Server action scenarios

### SC-ACT-001 — Missing FormData field rejects with a stable error
- **Priority**: P0
- **Maps to**: ACT-001
- **Given**: a `FormData` missing one of `productId`, `rating`, `text`
- **When**: `submitReviewAction(formData)`
- **Then**: returns `{ ok: false, error: "missing field <name>" }`

### SC-ACT-002 — Unknown productId rejects
- **Priority**: P0
- **Maps to**: ACT-002
- **Given**: `FormData` with `productId = "p-does-not-exist"`
- **When**: `submitReviewAction(formData)`
- **Then**: returns `{ ok: false, error: "unknown product" }`

### SC-ACT-003 — Happy path returns a fully-formed review
- **Priority**: P0
- **Maps to**: ACT-003 + REV-004
- **Given**: a well-formed `FormData` for `p-headphones`
- **When**: `submitReviewAction(formData)`
- **Then**: returns `{ ok: true, review }` with matching `productId`,
  `rating`, trimmed `text`, `rev-p-headphones-<n>` id, ISO `createdAt`

### SC-ACT-004 — Validation failure never throws
- **Priority**: P1
- **Maps to**: ACT-004
- **Given**: malformed input (rating=10, empty text, profane text,
  non-numeric rating)
- **When**: `submitReviewAction(formData)`
- **Then**: returns `{ ok: false, error }` — no exception surfaces

## Page scenarios (structural — validated by sprint-5.sh [S5-D])

### SC-PAGE-001 — /products renders one list entry per product
- **Priority**: P1
- **Maps to**: PAGE-001
- **Given**: `app/products/page.tsx` imports `listProducts`
- **When**: the harness greps the file for `listProducts()`
- **Then**: the import + call site are both present (structural)

### SC-PAGE-002 — /products/[id] calls notFound() for unknown products
- **Priority**: P1
- **Maps to**: PAGE-002
- **Given**: `app/products/[id]/page.tsx` imports `notFound` from
  `next/navigation`
- **When**: the harness greps the file for `notFound()` usage
- **Then**: the file contains `if (!product)` followed by a
  `notFound()` call

## Invariants

All three invariants (`INV-MONEY-INTEGER`, `INV-REV-TEXT-TRIMMED`,
`INV-REV-ID-STABLE`) are asserted inline within the SC-PROD-* and
SC-REV-* scenarios — no dedicated sweep is needed for a demo of this
size because each invariant has exactly one write-path.
