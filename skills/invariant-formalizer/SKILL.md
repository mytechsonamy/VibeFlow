---
name: invariant-formalizer
description: Turns natural-language invariants from business-rules.md / the PRD into machine-checkable predicates (Zod refinements, runtime guards, Z3 SMT constraints, property-based generators). Emits invariant-matrix.md + invariants.ts. Gate contract — zero unformalized P0 invariants. PIPELINE-3 step 2.
allowed-tools: Read Grep Glob Write
context: fork
agent: Explore
---

# Invariant Formalizer

An L1 Truth-Validation skill. Its job is to eliminate the layer of
"we all understand what the rule means" between the PRD and the
test suite. Every invariant becomes a predicate that code can
check and a proof obligation that `release-decision-engine` can
count — prose-only invariants are not acceptable for P0.

## When You're Invoked

- During PIPELINE-3 step 2, in parallel with risk-weighted coverage
  passes.
- On demand as `/vibeflow:invariant-formalizer [path]`.
- Re-runs automatically when `business-rule-validator` emits a new
  `business-rules.md` or `test-data-manager` needs an updated
  `invariant-matrix.md`. The three must move together.

## Input Contract

| Input | Required | Notes |
|-------|----------|-------|
| `business-rules.md` | yes (preferred) | Output of `business-rule-validator`. Rules with a measurable condition become invariant candidates. |
| PRD | fallback | `.vibeflow/artifacts/prd.md`. Used only when `business-rules.md` is absent — surfaces a WARNING because the extraction step is duplicated work in that case. |
| Domain config | yes | `vibeflow.config.json` → `domain`. Drives the domain-specific pass in the taxonomy. |
| Existing `invariants.ts` | scanned | Any file with the `@generated-by vibeflow:invariant-formalizer` banner is rewritten in place; hand-written invariants outside the marked region are preserved. |
| Target format | optional | `zod` (default), `runtime`, `smt`, `pbt`. Multiple formats can be requested in one run. |

**Hard preconditions** — refuse to run rather than emit a matrix that
hides the hard questions:

1. Every P0 rule in `business-rules.md` must be readable (no parse
   errors, no ambiguity filter collisions). Refuse and point at
   `business-rule-validator` when blocked upstream.
2. The domain must be one of `{ financial | e-commerce | healthcare
   | general }`. Any other value blocks the run — the domain pass
   cannot silently degrade to `general`.
3. If a requested target format is `smt`, the Z3 binary must be
   resolvable via `which z3`. Absent Z3 → drop the format with a
   recorded limitation, never silently emit unchecked SMT.

## Algorithm

### Step 1 — Load the taxonomy
Read `./references/invariant-taxonomy.md`. It defines seven
invariant classes plus the domain-specific overlays:

1. **Range** — a value must lie in `[min, max]`
2. **Equality** — two expressions must stay equal
3. **Sum / conservation** — a total must match the sum of parts
4. **Cardinality** — a collection's size must satisfy a constraint
5. **Temporal ordering** — event A must precede event B
6. **Referential** — foreign reference must resolve
7. **Domain-specific** — see the taxonomy for financial,
   e-commerce, and healthcare overlays

Every class has an `id` pattern (`INV-RANGE-*`, `INV-SUM-*`, …) that
the matrix report cites verbatim.

### Step 2 — Extract invariant candidates
Walk the input. For each rule:

- **If the rule has a measurable comparison** (`<`, `≤`, `=`, `≥`, `>`,
  `==`, `!=`, `IN`, `BETWEEN`) → candidate.
- **If the rule names a sum or cardinality** ("total", "count",
  "at most N", "no duplicates") → candidate.
- **If the rule encodes temporal ordering** ("after", "before",
  "within N seconds") → candidate.
- **If the rule is a pure slogan** ("the system must be
  user-friendly") → NOT an invariant; record as a skipped
  candidate with reason `"no measurable outcome"` and let the
  gate-keeping happen upstream in `business-rule-validator` (this
  skill never blocks on GAP-010 — it's already handled).

Every candidate carries the source rule id (`BR-NNNN`) as evidence.
Invariants that do not trace back to a BR or a PRD anchor are a
bug — refuse to emit them.

### Step 3 — Classify
Match each candidate against the taxonomy. Classification rules:

- **One class per invariant.** If a candidate fits two classes
  (e.g. `balance >= 0` is both Range and domain-specific financial
  "non-negative balance"), pick the **more specific** class — the
  domain overlay always wins over the generic class so the report
  cites the load-bearing rule.
- **Ambiguous candidates abort classification.** If no class
  matches, emit a blocker finding with remediation: "extend
  invariant-taxonomy.md with a new class covering this shape".
  The skill never guesses.
- **Confidence is recorded per classification** (0..1). HIGH for
  explicit comparison verbs, MEDIUM for sum/cardinality phrases,
  LOW for temporal ordering without a named unit.

### Step 4 — Formalize per target format
For each classified invariant, consult `references/formalization-recipes.md`
to render it into the requested target format(s). Formats are
orthogonal — a single invariant can produce a Zod refinement AND a
Z3 constraint AND a property-based test generator in the same run.

Formalization rules:

- **Lossless.** The original NL statement stays attached as a
  comment in the emitted code. Readers should never need to open
  the PRD to understand what a predicate is checking.
- **Total.** The predicate must handle every reachable input. If
  an input shape is not covered (e.g. `balance` can be `null`
  because the type is `number | null`), emit an explicit branch
  — never default-pass.
- **Named.** Every formalized invariant gets an id
  `INV-<class>-<hash>` stable across runs for the same source
  rule. The id flows into `invariant-matrix.md` and the generated
  code so `release-decision-engine` can count violations.

### Step 5 — Emit outputs

1. **`.vibeflow/reports/invariant-matrix.md`** — the catalog
   (classification, source rule, target formats, confidence,
   formalization status).
2. **`src/invariants/invariants.ts`** (or per-module files when the
   project uses per-domain folders) — runtime/Zod predicates. Uses
   the `@generated-by` banner + `@generated-start`/`@generated-end`
   markers so re-runs preserve human-added helpers.
3. **`.vibeflow/artifacts/invariants/<id>.smt2`** (per invariant,
   only when the `smt` target was requested and Z3 was available)
   — one SMT-LIB file that Z3 can check in isolation.
4. **`src/invariants/pbt.ts`** (only when the `pbt` target was
   requested) — fast-check-compatible property generators, one
   per invariant. Each generator imports its inputs from the
   `test-data-manager` factories — never builds its own fixtures.

### Step 6 — Cross-check with test-data-manager
Every invariant emitted as a runtime predicate MUST be satisfiable
by the corresponding schema in `test-data-manager`. The skill runs
a shallow dry check:

1. For each `INV-*`, locate the CanonicalSchema it constrains.
2. Invoke the schema's factory (`make<Schema>()`) N times (default
   10).
3. Assert the predicate returns `true` for every sample.

If any sample fails, the skill records a CROSS-CHECK finding with
severity `critical`. Remediation: either widen the factory's range
to cover the invariant, or tighten the invariant's constraints to
match the domain.

This is the step that makes the three L1 skills
(`business-rule-validator`, `test-data-manager`,
`invariant-formalizer`) mutually consistent — drift in any one of
them surfaces here as a blocker.

### Step 7 — Compute the verdict
```
unformalizedP0 = invariants
  .filter(i => i.priority === "P0" && i.formalizationStatus !== "formalized")
  .length

crossCheckFailures = invariants
  .filter(i => i.crossCheckStatus === "failed")
  .length

taxonomyGaps = candidates
  .filter(c => c.classification === "unknown")
  .length
```

Verdict rules:

| Condition | Verdict |
|-----------|---------|
| `unformalizedP0 == 0 && crossCheckFailures == 0 && taxonomyGaps == 0` | APPROVED |
| `unformalizedP0 == 0 && crossCheckFailures == 0` but `taxonomyGaps > 0` | NEEDS_REVISION |
| `unformalizedP0 > 0 \|\| crossCheckFailures > 0` | BLOCKED |

**Gate contract: zero unformalized P0 invariants and zero cross-check
failures.** Nothing else produces BLOCKED, nothing else suppresses it.

## Output Contract

### `invariant-matrix.md`
```markdown
# Invariant Matrix — <ISO timestamp>

## Summary
- Verdict: [APPROVED|NEEDS_REVISION|BLOCKED]
- Invariants extracted: N
- Formalized: F
- Unformalized P0 (gate-blocking): X
- Cross-check failures (gate-blocking): Y
- Taxonomy gaps (info): Z
- Target formats: zod, runtime, smt, pbt

## Invariants
| id | class | source | priority | formats | status | confidence |
|----|-------|--------|----------|---------|--------|------------|
| INV-RANGE-ab12 | range | BR-0017 | P0 | zod, pbt | formalized | 1.0 |
| INV-SUM-cd34   | sum   | BR-0042 | P0 | zod, smt | formalized | 0.95 |

## Detail
### INV-RANGE-ab12 — balance non-negative
- **Source**: BR-0017 / §3.2 ¶4
- **Class**: range
- **NL statement**: "account balance MUST NOT go below zero"
- **Predicate (Zod)**: `z.number().nonnegative()`
- **Predicate (PBT)**: `fc.integer({ min: 0, max: 1e9 })`
- **Cross-check**: passed (10/10 samples)
- **Confidence**: 1.0
- **Evidence**: BR-0017 quote; §3.2 ¶4 PRD anchor
```

### `invariants.ts` (excerpt)
```ts
// @generated-by vibeflow:invariant-formalizer
// @generated-start
import { z } from "zod";

// INV-RANGE-ab12 — "account balance MUST NOT go below zero"
// Source: BR-0017 / §3.2 ¶4
export const INV_RANGE_ab12 = z
  .number()
  .nonnegative({ message: "invariant INV-RANGE-ab12 violated" });

// INV-SUM-cd34 — "order total MUST equal sum(lineItems.price * qty)"
// Source: BR-0042 / §4.1 ¶2
export function INV_SUM_cd34(order: { total: number; lineItems: Array<{ price: number; qty: number }> }): boolean {
  const computed = order.lineItems.reduce((s, l) => s + l.price * l.qty, 0);
  return Math.abs(order.total - computed) < 1e-9; // float tolerance declared explicitly
}
// @generated-end
```

## Explainability Contract
Every invariant in the matrix MUST carry
`finding / why / impact / confidence / evidence`. "why" cites the
taxonomy class id; "evidence" cites the source rule id AND the
PRD anchor. Undocumented classifications are forbidden; if a shape
doesn't fit the taxonomy, extend `invariant-taxonomy.md` first.

## Non-Goals
- Does NOT generate fixtures — `test-data-manager` owns that path.
- Does NOT execute Z3 as part of the gate. Z3 files are emitted
  for downstream proof obligations; actual solving happens in
  Sprint 3 (`decision-recommender`).
- Does NOT rewrite business rules. If a rule lacks a measurable
  outcome, the fix belongs in the PRD, not in this skill.

## Downstream Dependencies
- `release-decision-engine` — reads `unformalizedP0` and
  `crossCheckFailures` as hard-blocker signals.
- `test-data-manager` — re-runs when `invariant-matrix.md`
  changes so factories stay compliant.
- `mutation-test-runner` — uses the property-based generators
  (when the `pbt` target is active) as a mutation oracle.
- `traceability-engine` — links `INV-*` ↔ `BR-*` ↔ scenario ids.
