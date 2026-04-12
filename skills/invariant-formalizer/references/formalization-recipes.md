# Formalization Recipes

This file is the source of truth for Step 4 of the
`invariant-formalizer` skill. Each taxonomy class maps to a recipe
for every supported target format. The skill copies these templates
verbatim — if the template is wrong, every future invariant inherits
the bug.

## Target formats

| Id | Output | When to use |
|----|--------|-------------|
| `zod` | Zod schema or `.refine()` | Default runtime checking; included in every run unless disabled |
| `runtime` | Plain TS predicate returning `boolean` | Invariants that don't fit Zod (cross-record, stateful) |
| `smt` | SMT-LIB 2.6 file for Z3 | Proof obligations that need offline solving |
| `pbt` | fast-check arbitrary + property | Property-based mutation oracle |

**Rule of thumb:** simple shape constraints ship in `zod`. Cross-record
or computed-sum invariants ship in `runtime`. Proof obligations ship
in `smt`. Generator-backed mutation checks ship in `pbt`. Each format
is orthogonal — emit as many as the skill was asked for.

---

## INV-RANGE

### zod
```ts
// INV-RANGE-<hash> — "<NL statement>"
// Source: <BR-NNNN> / <PRD anchor>
export const INV_RANGE_<hash> = z
  .number()
  .min(<MIN>, { message: "invariant INV-RANGE-<hash> violated (min)" })
  .max(<MAX>, { message: "invariant INV-RANGE-<hash> violated (max)" });
```

If `min` is implicit at `0`, use `.nonnegative()` for clarity. If
only one bound exists, emit only that bound — do not invent the
other.

### runtime
```ts
export function INV_RANGE_<hash>(v: number): boolean {
  return v >= <MIN> && v <= <MAX>;
}
```

### smt
```
; INV-RANGE-<hash>
(declare-const value Int)
(assert (and (>= value <MIN>) (<= value <MAX>)))
(check-sat)
```

For floats, switch `Int` → `Real` and use the corresponding Z3 logic.

### pbt
```ts
export const INV_RANGE_<hash>_arb = fc.integer({ min: <MIN>, max: <MAX> });
export const INV_RANGE_<hash>_prop = fc.property(
  INV_RANGE_<hash>_arb,
  (v) => INV_RANGE_<hash>(v),
);
```

---

## INV-EQUALITY

### zod
Zod does not express cross-field equality directly — use
`.refine()` on the enclosing object:

```ts
export const <Schema>_INV_EQ_<hash> = <Schema>.refine(
  (x) => x.<left> === x.<right>,
  { message: "invariant INV-EQUALITY-<hash> violated" },
);
```

When the equality is across **two objects** (not two fields), use
the `runtime` format instead.

### runtime
```ts
export function INV_EQ_<hash>(
  left: <T>,
  right: <T>,
  tolerance = <TOL>,
): boolean {
  if (typeof left === "number" && typeof right === "number") {
    return Math.abs(left - right) <= tolerance;
  }
  return JSON.stringify(left) === JSON.stringify(right);
}
```

Always declare the tolerance explicitly. `0` is fine — what isn't
fine is leaving it implicit.

### smt
```
; INV-EQUALITY-<hash>
(declare-const left Real)
(declare-const right Real)
(assert (= left right))
(check-sat)
```

### pbt
```ts
export const INV_EQ_<hash>_prop = fc.property(
  fc.tuple(<arbLeft>, <arbRight>),
  ([l, r]) => INV_EQ_<hash>(l, r),
);
```

---

## INV-SUM (conservation laws)

### zod
```ts
export const <Schema>_INV_SUM_<hash> = <Schema>.refine(
  (x) => {
    const computed = x.<parts>.reduce(
      (acc, p) => acc + <reducer-expr>,
      0,
    );
    return Math.abs(x.<total> - computed) < 1e-9;
  },
  { message: "invariant INV-SUM-<hash> violated" },
);
```

### runtime
```ts
export function INV_SUM_<hash>(
  total: number,
  parts: readonly <PartT>[],
): boolean {
  const computed = parts.reduce((acc, p) => acc + <reducer-expr>, 0);
  return Math.abs(total - computed) < 1e-9;
}
```

Rationale for the explicit `1e-9` tolerance: adding floats accumulates
error. Tests that check conservation with `===` break on any non-
trivial input. Declaring the tolerance is the only way to be honest
about the precision.

### smt
```
; INV-SUM-<hash>
(declare-const total Real)
(declare-const part1 Real)
(declare-const part2 Real)
...
(assert (= total (+ part1 part2 ...)))
(check-sat)
```

Variable-arity SMT: when the collection size isn't known at
formalization time, emit a parameterized template with a placeholder
`<N>` and let the caller fill it in per instance.

### pbt
```ts
export const INV_SUM_<hash>_prop = fc.property(
  fc.array(<partArb>, { minLength: 0, maxLength: 20 }),
  (parts) => {
    const total = parts.reduce((a, p) => a + <reducer-expr>, 0);
    return INV_SUM_<hash>(total, parts);
  },
);
```

---

## INV-CARDINALITY

### zod
```ts
// Collection size bounds:
z.array(<ItemSchema>).min(<MIN>).max(<MAX>)
// Uniqueness:
z.array(<ItemSchema>).refine(
  (xs) => new Set(xs.map(<keyFn>)).size === xs.length,
  { message: "invariant INV-CARDINALITY-<hash> violated (uniqueness)" },
);
```

### runtime
```ts
export function INV_CARD_<hash><T>(
  xs: readonly T[],
  keyFn: (t: T) => string = (t) => JSON.stringify(t),
): boolean {
  if (xs.length < <MIN> || xs.length > <MAX>) return false;
  return new Set(xs.map(keyFn)).size === xs.length;
}
```

### smt
Cardinality under SMT is typically expressed over a fixed-size array
or a set-valued theory. For simple size bounds:

```
; INV-CARDINALITY-<hash>
(declare-const size Int)
(assert (and (>= size <MIN>) (<= size <MAX>)))
(check-sat)
```

For uniqueness, use Z3's `distinct`:

```
(assert (distinct x1 x2 x3 ... xN))
```

### pbt
```ts
export const INV_CARD_<hash>_arb = fc.array(<itemArb>, {
  minLength: <MIN>,
  maxLength: <MAX>,
});
// Uniqueness:
export const INV_CARD_<hash>_unique_arb = fc.uniqueArray(<itemArb>, {
  minLength: <MIN>,
  maxLength: <MAX>,
});
```

---

## INV-TEMPORAL

### zod
```ts
export const <Schema>_INV_TEMPORAL_<hash> = <Schema>.refine(
  (x) => x.<earlier>.getTime() <= x.<later>.getTime(),
  { message: "invariant INV-TEMPORAL-<hash> violated (ordering)" },
).refine(
  (x) => x.<later>.getTime() - x.<earlier>.getTime() <= <MAX_DELTA_MS>,
  { message: "invariant INV-TEMPORAL-<hash> violated (window)" },
);
```

Two `.refine()` calls on purpose: ordering failure and window
failure should produce distinct messages so the operator knows
which one actually broke.

### runtime
```ts
export function INV_TEMPORAL_<hash>(
  earlier: Date,
  later: Date,
  maxDeltaMs?: number,
): boolean {
  const e = earlier.getTime();
  const l = later.getTime();
  if (e > l) return false;
  if (maxDeltaMs !== undefined && l - e > maxDeltaMs) return false;
  return true;
}
```

### smt
```
; INV-TEMPORAL-<hash>
(declare-const earlier Int)
(declare-const later Int)
(declare-const max_delta Int)
(assert (<= earlier later))
(assert (<= (- later earlier) max_delta))
(check-sat)
```

### pbt
```ts
export const INV_TEMPORAL_<hash>_arb = fc
  .tuple(fc.date(), fc.integer({ min: 0, max: <MAX_DELTA_MS> }))
  .map(([e, delta]) => [e, new Date(e.getTime() + delta)] as const);
```

---

## INV-REFERENTIAL

Referential integrity is almost always checked at runtime — it needs
a live collection to resolve against. SMT and PBT formats are
recorded as `not applicable` unless the collection is small enough
to encode literally.

### runtime
```ts
export function INV_REF_<hash><T, U>(
  ref: T,
  target: readonly U[],
  matcher: (t: T, u: U) => boolean,
): boolean {
  return target.some((u) => matcher(ref, u));
}
```

### zod
```ts
export const <Schema>_INV_REF_<hash> = <Schema>.refine(
  (x) => INV_REF_<hash>(x.<ref>, <collectionLookup>(), <matcher>),
  { message: "invariant INV-REFERENTIAL-<hash> violated" },
);
```

The `collectionLookup` is a closure over the test fixture or DB
stub; the skill emits it as a placeholder comment the caller
must fill in.

---

## INV-IMPLICATION (A → B)

### zod
```ts
export const <Schema>_INV_IMPL_<hash> = <Schema>.refine(
  (x) => !<antecedent>(x) || <consequent>(x),
  { message: "invariant INV-IMPLICATION-<hash> violated" },
);
```

The `!A || B` shape is the standard logical-implication encoding —
when A is false, the implication holds trivially. Do NOT use
`A && B`; that's an AND, not an implication.

### runtime
```ts
export function INV_IMPL_<hash>(x: <T>): boolean {
  if (!<antecedent>(x)) return true;
  return <consequent>(x);
}
```

### smt
```
; INV-IMPLICATION-<hash>
(declare-const ant Bool)
(declare-const cons Bool)
(assert (=> ant cons))
(check-sat)
```

### pbt
```ts
export const INV_IMPL_<hash>_prop = fc.property(
  <inputArb>,
  (x) => INV_IMPL_<hash>(x),
);
```

---

## Domain overlays

Overlays inherit their base class's recipe and add a comment banner
that cites the overlay id AND the base class id. Example:

```ts
// INV-FIN-NONNEG — "account balance MUST NOT go below zero"
// Base class: INV-RANGE
// Source: BR-0017 / §3.2 ¶4
export const INV_FIN_NONNEG_<hash> = z
  .number()
  .nonnegative({ message: "invariant INV-FIN-NONNEG-<hash> violated" });
```

The overlay never emits different code from its base class — it only
changes the identifier used in the matrix and the banner. This keeps
the runtime predicate library small and audit-friendly while
preserving the regulatory citation.

---

## Recipe maintenance

- **Every base class has a recipe in every supported format.** If a
  format is fundamentally impossible for a class (e.g. referential
  under SMT without a literal collection), say so explicitly
  ("not applicable — emit WARNING in matrix") rather than leaving
  the recipe blank.
- **Templates are verbatim.** The skill does string substitution on
  `<placeholder>` fields; anything that varies in non-trivial ways
  belongs in a new class, not in a parameter.
- **Confidence defaults live in `invariant-taxonomy.md`.** The recipe
  file is about *how* to encode; confidence is about *how sure* we
  are, which is a classification concern.
