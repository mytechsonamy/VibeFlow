# Demo Product Catalog — PRD

**Project**: `demo-catalog`
**Domain**: `e-commerce`
**Mode**: `solo`
**Owner**: VibeFlow demo
**Status**: Approved for DEVELOPMENT

This PRD is the sample input for the VibeFlow demo. It is deliberately
written to score high on `prd-quality-analyzer` (testability ≥ 80,
zero ambiguous terms, every requirement measurable and bounded) so the
demo walks the happy path all the way to a GO release decision.

Do not treat this PRD as a reference for real-world e-commerce
architecture. It is minimal on purpose: a walk-through must fit in one
reading session.

---

## 1. Goal

Build a small in-process product catalog that a backend service can
embed to serve three related concerns: listing products, pricing carts,
and tracking stock. The catalog is not a database and does not talk to
the network — its single responsibility is to be the **source of truth
for catalog state** that higher layers (HTTP handlers, job runners)
call into.

## 2. Non-goals

- Persisting state across process restarts
- Multi-tenancy
- Currency conversion
- Shipping / fulfillment logistics
- Promotion engine beyond a single percentage / fixed discount per quote

## 3. Requirements

Every requirement below is numbered with a stable id (`CAT-*`, `PRC-*`,
`INV-*`). Each is written in the "MUST/REJECTS" active-voice form the
`prd-quality-analyzer` expects, with a single measurable outcome.

### 3.1 Catalog requirements

- **CAT-001** (P0) The catalog MUST store products with the fields
  `id` (string), `sku` (string), `name` (string), `priceMinor`
  (non-negative integer, minor currency units), `currency` (one of
  `USD` / `EUR` / `GBP`), and `categoryId` (string).
- **CAT-002** (P0) The catalog MUST reject adding a product whose
  `sku` already exists on another product.
- **CAT-003** (P1) The catalog MUST reject a category whose depth
  below `root` would exceed 3 levels.
- **CAT-004** (P1) The catalog's `search` MUST be case-insensitive
  and MUST match on substring of `name` OR prefix of `sku`.
- **CAT-005** (P1) The catalog's `listProducts` MUST default to
  `pageSize = 25` and MUST reject `pageSize > 100` or `page < 1`.

### 3.2 Pricing requirements

- **PRC-001** (P0) All prices and line totals MUST be stored and
  computed in minor units (integers). Float arithmetic on prices is
  forbidden.
- **PRC-002** (P0) A percentage discount MUST round half-down so a
  15% discount on 199 minor units yields 29 (not 30).
- **PRC-003** (P0) A fixed-amount discount MUST never push a line
  total below zero. Over-sized fixed discounts MUST clamp at the
  subtotal.
- **PRC-004** (P0) Tax MUST be applied to `(subtotal − discount)`,
  never to the pre-discount subtotal.
- **PRC-005** (P1) The quote response MUST include `subtotalMinor`,
  `discountMinor`, `taxableMinor`, `taxMinor`, `totalMinor` as
  integer fields.

### 3.3 Inventory requirements

- **INV-001** (P0) Stock MUST be tracked per `(productId, warehouseId)`
  pair, with two counters `onHand` and `reserved`. `available` is
  defined as `onHand − reserved`.
- **INV-002** (P0) `reserve(productId, warehouseId, quantity)` MUST
  decrement `available` by `quantity` and leave `onHand` unchanged.
- **INV-003** (P0) `commit(productId, warehouseId, quantity)` MUST
  decrement both `onHand` and `reserved` by `quantity`.
- **INV-004** (P1) `release(productId, warehouseId, quantity)` MUST
  decrement `reserved` by `quantity` and leave `onHand` unchanged.
- **INV-005** (P0) Attempting to reserve a quantity greater than the
  current `available` MUST throw an `InsufficientStockError` with
  fields `productId`, `warehouseId`, `requested`, `available`.

## 4. Invariants

- **INV-TOTAL-GTE-RESERVED** — at every commit point, `onHand` must be
  greater than or equal to `reserved`.
- **INV-AVAILABLE-NON-NEGATIVE** — `available` must never be less
  than zero.
- **INV-MONEY-INTEGER** — every money field in every public API must
  pass `Number.isInteger`.

## 5. Acceptance (how the demo scores this PRD)

When `prd-quality-analyzer` runs on this file:

| Dimension | Expected | Reason |
|-----------|----------|--------|
| `testabilityScore` | ≥ 80 | every requirement is numbered + measurable + bounded |
| `ambiguousTerms` | 0 | no "fast", "easy", "intuitive", "scalable", "robust" |
| `missingAcceptanceCriteria` | 0 | each requirement states its exact outcome |
| `domainFit` | e-commerce | SKU / catalog / inventory / quote vocabulary |

When `test-strategy-planner` runs on this file, the expected plan
covers:
- 5 CAT-* requirements → unit tests against `ProductCatalog`
- 5 PRC-* requirements → unit tests against `subtotal`/`applyDiscount`/
  `applyTax`/`quote`
- 5 INV-* requirements → unit tests against `Inventory`
- 3 invariants → property-based or integration checks

That matches what `examples/demo-app/tests/*.test.ts` actually
contains, so the demo's coverage signal lands at a GO verdict.
