# Invariant Taxonomy

The `invariant-formalizer` skill classifies every candidate using
this taxonomy at Step 3 of its algorithm. The skill is forbidden
from inventing a class — if a candidate doesn't fit any entry here,
the skill emits a blocker with remediation "extend
invariant-taxonomy.md first".

Every class has six fields:

| Field | Meaning |
|-------|---------|
| `id` | Stable identifier (`INV-<CLASS>`) cited in the matrix |
| `definition` | What shape of statement matches the class |
| `signature` | Minimum fields the invariant needs to be checkable |
| `typical verbs` | Words that signal this class in the source text |
| `default confidence` | Baseline confidence on extraction |
| `counter-examples` | What looks similar but isn't this class |

---

## Base classes (all domains)

### INV-RANGE — Value lies in a bounded interval
- **id**: `INV-RANGE`
- **definition**: A single numeric or temporal value must satisfy
  `min ≤ value ≤ max`. Either bound may be implicit (e.g. "non-negative"
  implies `0 ≤ value`).
- **signature**: `{ value: number | Date; min?: ...; max?: ... }`
- **typical verbs**: "between", "at least", "at most", "non-negative",
  "not exceed", "within", "up to", "no more than"
- **default confidence**: 0.95 when both bounds are literal, 0.85 when
  one bound is implicit.
- **counter-examples**: "approximately 100" is an ambiguity
  (`prd-quality-analyzer` should have caught it); "roughly in the
  range" is not a range invariant — it's a style complaint.

### INV-EQUALITY — Two expressions must stay equal
- **id**: `INV-EQUALITY`
- **definition**: Two computed expressions must evaluate to the same
  value at every observable moment. Distinct from sum-style
  conservation (see INV-SUM): equality here is between two **named
  expressions**, not a total and its parts.
- **signature**: `{ left: expression; right: expression; tolerance?: number }`
- **typical verbs**: "equal to", "must match", "same as", "matches",
  "identical to"
- **default confidence**: 0.9 for exact equality, 0.8 when tolerance
  is required (floats, timestamps).
- **counter-examples**: "similar to" is not equality (that's a
  subjective match, not a predicate); "the same kind of" is a type
  statement, not an invariant.

### INV-SUM — Total equals the sum of parts (conservation law)
- **id**: `INV-SUM`
- **definition**: A named aggregate value must equal a deterministic
  reduction over a collection. The defining property is
  *conservation*: moving value between parts must not change the
  total.
- **signature**: `{ total: value; parts: collection; reducer: "+"|"*" }`
- **typical verbs**: "total", "sum", "add up to", "equal to the
  sum of", "reconcile", "balance of"
- **default confidence**: 0.9 for explicit "sum", 0.85 for
  "reconcile".
- **counter-examples**: "average" is a derived value, not a
  conservation law — it's a range or equality depending on
  how the rule is phrased.

### INV-CARDINALITY — Collection size is constrained
- **id**: `INV-CARDINALITY`
- **definition**: The size of a collection must satisfy a constraint.
  Distinct from INV-RANGE because the value under test is derived
  from `|collection|`, not from a raw field.
- **signature**: `{ collection: expression; min?: number; max?: number; unique?: boolean }`
- **typical verbs**: "at most N", "no more than N", "at least N",
  "unique", "no duplicates", "exactly N"
- **default confidence**: 0.9 for literal counts, 0.8 for
  "unique"/"no duplicates".
- **counter-examples**: "many" / "few" are ambiguities (should have
  been caught upstream).

### INV-TEMPORAL — Event ordering or time-boxed window
- **id**: `INV-TEMPORAL`
- **definition**: Event A must precede / follow event B, possibly
  within a bounded window. The key is that the invariant holds
  across two observable points in time, not a single state.
- **signature**: `{ earlier: event; later: event; maxDelta?: duration }`
- **typical verbs**: "after", "before", "within N seconds",
  "no later than", "at least X before", "by the time"
- **default confidence**: 0.85 when the unit is named, 0.7 when
  only the ordering is stated without a bound.
- **counter-examples**: "soon" / "eventually" are ambiguities.
  "first" / "last" at the collection level is a cardinality
  invariant on the boundary element, not a temporal one.

### INV-REFERENTIAL — Foreign reference must resolve
- **id**: `INV-REFERENTIAL`
- **definition**: A pointer (foreign key, user id, session id) must
  resolve to an entity that exists at check time. Borrowed from
  relational databases' concept of referential integrity.
- **signature**: `{ ref: expression; target: collection; cardinality: "one"|"many" }`
- **typical verbs**: "must belong to", "must reference an existing",
  "owned by", "linked to", "associated with"
- **default confidence**: 0.85.
- **counter-examples**: "should be connected to" without naming a
  target collection is prose, not an invariant.

### INV-IMPLICATION — Conditional predicate (A → B)
- **id**: `INV-IMPLICATION`
- **definition**: When predicate A holds, predicate B must hold.
  Captures rules that don't fit the simpler shapes because their
  truth depends on context.
- **signature**: `{ antecedent: predicate; consequent: predicate }`
- **typical verbs**: "if", "when", "unless", "whenever", "only if"
- **default confidence**: 0.8 (conditionals are the most common
  place natural language slips between "always" and "sometimes").
- **counter-examples**: "might" / "could" rules are not invariants;
  drop them.

---

## Domain overlays

Domain overlays are **more specific than** the base classes. A
candidate that matches both always takes the overlay id so the
matrix cites the load-bearing regulatory or business reason.

### Financial overlays

#### INV-FIN-NONNEG — Monetary value must not go below zero
- **id**: `INV-FIN-NONNEG`
- **base class**: `INV-RANGE` with `min = 0`
- **applies to**: balances, available credit, reserves, liquidity
- **why the overlay**: This is the single most load-bearing rule in
  financial systems. Citing `INV-FIN-NONNEG` in the matrix makes
  the audit trail explicit.

#### INV-FIN-DOUBLE-ENTRY — Credits equal debits at every commit
- **id**: `INV-FIN-DOUBLE-ENTRY`
- **base class**: `INV-SUM` over a ledger
- **applies to**: ledger postings, transaction batches, reconciliation
- **signature**: `{ credits: collection; debits: collection }`
- **confidence**: 1.0 — the rule is unambiguous by construction.

#### INV-FIN-PRECISION — Monetary precision declared and enforced
- **id**: `INV-FIN-PRECISION`
- **base class**: `INV-RANGE` on the smallest representable unit
- **applies to**: every money-carrying field
- **why the overlay**: Float precision bugs are how real money goes
  missing. If the invariant uses `number`, the predicate must
  compare with a declared `tolerance` AND the matrix must surface
  a warning that the underlying storage should be `decimal` or
  `bigint cents`.

#### INV-FIN-AUTH-LIMIT — Transaction size requires dual control
- **id**: `INV-FIN-AUTH-LIMIT`
- **base class**: `INV-IMPLICATION` with `amount > threshold → dual_approvals`
- **applies to**: high-value transfers, manual journal entries
- **confidence**: 0.9.

### E-commerce overlays

#### INV-ECOM-STOCK — Stock never goes below zero
- **id**: `INV-ECOM-STOCK`
- **base class**: `INV-RANGE` with `min = 0`
- **applies to**: inventory counts, reserved stock, allocation ledger

#### INV-ECOM-IDEMPOTENT-ORDER — Order placement is idempotent by key
- **id**: `INV-ECOM-IDEMPOTENT-ORDER`
- **base class**: `INV-EQUALITY` between "order created for key X"
  and "existing order with key X"
- **applies to**: checkout flows, retry-prone payment integrations

#### INV-ECOM-PRICE-TOTAL — Cart total == sum(lineItem.price × qty)
- **id**: `INV-ECOM-PRICE-TOTAL`
- **base class**: `INV-SUM`
- **applies to**: cart aggregation, invoice generation

### Healthcare overlays

#### INV-HLTH-PHI-ACCESS — PHI access requires an authorized actor
- **id**: `INV-HLTH-PHI-ACCESS`
- **base class**: `INV-IMPLICATION` with `read(PHI) → actor.authorized`
- **applies to**: every read path through a PHI field

#### INV-HLTH-RETENTION — PHI retention window is respected
- **id**: `INV-HLTH-RETENTION`
- **base class**: `INV-TEMPORAL` with `age(record) ≤ retention_window`
- **applies to**: patient records, lab results, audit log

#### INV-HLTH-CONSENT — Data use requires recorded consent
- **id**: `INV-HLTH-CONSENT`
- **base class**: `INV-IMPLICATION` with `use(data) → consent.status == "granted"`
- **applies to**: analytics reads, third-party sharing

---

## Taxonomy maintenance

- **Never delete a class.** Old matrices reference these ids; deletion
  orphans historical reports.
- **Never change a class's `id`.** If the definition needs to evolve,
  add a new class with a fresh id.
- **Every new overlay must cite its base class.** Overlays are a
  specialization, not a parallel universe — if a candidate fits an
  overlay but not any base class, the taxonomy has a gap and the
  base class set should grow first.
- **One overlay per domain×shape.** Two overlays that both match the
  same shape in the same domain are a drift signal — merge them.
