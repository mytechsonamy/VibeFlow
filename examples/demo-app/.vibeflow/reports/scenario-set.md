# Scenario Set — demo-catalog

<!-- @generated-by vibeflow:test-strategy-planner (demo pre-bake) -->
<!-- Regenerate with: /vibeflow:test-strategy-planner docs/PRD.md -->

- **Project**: demo-catalog
- **Source PRD**: docs/PRD.md
- **Generated**: 2026-04-13T00:00:00Z
- **Total scenarios**: 16 (15 requirement-mapped + 1 invariant sweep)

## Catalog scenarios

### SC-CAT-001 — Add a product and read it back
- **Priority**: P0
- **Maps to**: CAT-001
- **Given**: empty catalog with a seeded `shirts` category
- **When**: `addProduct({ id: "p1", sku: "SKU-001", name: "Cotton Tee", priceMinor: 2499, currency: "USD", categoryId: "shirts" })`
- **Then**: `getProduct("p1")` returns the full product
- **Verify**: all 6 fields round-trip identically

### SC-CAT-002 — Reject duplicate SKU
- **Priority**: P0
- **Maps to**: CAT-002
- **Given**: catalog with one product at `SKU-DUP`
- **When**: `addProduct({ id: "p2", sku: "SKU-DUP", ... })`
- **Then**: raises `CatalogError` mentioning "sku SKU-DUP already exists"

### SC-CAT-003 — Reject depth-4 category
- **Priority**: P1
- **Maps to**: CAT-003
- **Given**: root → L1 → L2 (3 levels including root)
- **When**: `addCategory({ id: "L3", parentId: "L2" })`
- **Then**: raises `CatalogError` mentioning "depth limit"

### SC-CAT-004 — Case-insensitive name search
- **Priority**: P1
- **Maps to**: CAT-004
- **Given**: products with names "Cotton Tee", "Linen Tee", "Oxford Shirt"
- **When**: `search("cotton")`
- **Then**: returns exactly `[p1]`

### SC-CAT-005 — Default pagination is 25
- **Priority**: P1
- **Maps to**: CAT-005
- **Given**: 30 seeded products
- **When**: `listProducts()`
- **Then**: `pageSize === 25`, `items.length === 25`, `total === 30`

## Pricing scenarios

### SC-PRC-001 — Integer subtotal
- **Priority**: P0
- **Maps to**: PRC-001
- **Given**: cart `[{ unit: 199, qty: 3 }, { unit: 500, qty: 1 }]`
- **When**: `subtotal(cart)`
- **Then**: returns `1097` (exact integer)

### SC-PRC-002 — Half-down percentage rounding
- **Priority**: P0
- **Maps to**: PRC-002
- **Given**: subtotal `199`, discount `{ kind: "percentage", value: 15 }`
- **When**: `applyDiscount(199, discount)`
- **Then**: returns `29` (not `30`)

### SC-PRC-003 — Fixed discount clamps at subtotal
- **Priority**: P0
- **Maps to**: PRC-003
- **Given**: subtotal `500`, discount `{ kind: "fixed", value: 999 }`
- **When**: `applyDiscount(500, discount)`
- **Then**: returns `500` (clamped — never 999)

### SC-PRC-004 — Tax on post-discount only
- **Priority**: P0
- **Maps to**: PRC-004
- **Given**: 1 line at 1000, 200 fixed discount, 1000 bps tax
- **When**: `quote(...)`
- **Then**: `totalMinor === 880` (800 taxable + 80 tax, NOT 1100)

### SC-PRC-005 — Quote has all five integer fields
- **Priority**: P1
- **Maps to**: PRC-005
- **Given**: realistic cart
- **When**: `quote(cart, discount, taxRate)`
- **Then**: result has `subtotalMinor`, `discountMinor`, `taxableMinor`, `taxMinor`, `totalMinor`, all passing `Number.isInteger`

## Inventory scenarios

### SC-INV-001 — Seed and read onHand
- **Priority**: P0
- **Maps to**: INV-001
- **Given**: `setOnHand("p1", "wh-east", 50)`
- **When**: `get("p1", "wh-east")`
- **Then**: `onHand === 50`, `reserved === 0`, `available === 50`

### SC-INV-002 — Reserve decrements available only
- **Priority**: P0
- **Maps to**: INV-002
- **Given**: onHand 10
- **When**: `reserve(..., 3)`
- **Then**: `available === 7`, `onHand === 10`, `reserved === 3`

### SC-INV-003 — Commit decrements both onHand and reserved
- **Priority**: P0
- **Maps to**: INV-003
- **Given**: onHand 10, reserved 4
- **When**: `commit(..., 4)`
- **Then**: `onHand === 6`, `reserved === 0`, `available === 6`

### SC-INV-004 — Release returns availability without touching onHand
- **Priority**: P1
- **Maps to**: INV-004
- **Given**: onHand 10, reserved 5
- **When**: `release(..., 3)`
- **Then**: `onHand === 10`, `reserved === 2`, `available === 8`

### SC-INV-005 — InsufficientStockError carries detail
- **Priority**: P0
- **Maps to**: INV-005
- **Given**: onHand 2
- **When**: `reserve(..., 5)`
- **Then**: raises `InsufficientStockError` with `requested === 5`, `available === 2`

## Invariant sweep

### SC-INV-SWEEP — Invariants hold across a 100-op mixed workload
- **Priority**: P0
- **Maps to**: INV-TOTAL-GTE-RESERVED + INV-AVAILABLE-NON-NEGATIVE + INV-MONEY-INTEGER
- **Given**: a seeded inventory and a randomized but deterministic 100-op script
- **When**: each op runs in sequence
- **Then**: after every op, all three invariants hold
