# Mutation Operator Catalog

`mutation-test-runner` applies operators from this file — and
**only** from this file — at Step 2 of its algorithm. Inventing
operators in prompt time is forbidden; the whole point of the
catalog is that the set is auditable and stable across runs.

Every operator has four fields:

- **id** — the stable identifier cited in the report
- **mutation** — what the operator actually changes
- **bugClass** — the class of real bug this catches (the whole
  reason for its existence)
- **equivalent filter** — conditions under which the mutation is
  known to be semantically equivalent to the original, and
  therefore must be skipped (otherwise the mutant will "survive"
  forever and never be killable)

Sets:

- **`default`** — the standard set applied when `--operators` is
  not given. Covers the 80% of bugs this skill is built for.
- **`paranoid`** — the default set plus operators that tend to
  produce more equivalent mutants; use for release pre-flight only.
- **`boundary-only`** — useful when debugging off-by-one regressions.

---

## 1. Arithmetic operators

### ARITH_OP_REPLACE
- **mutation**: replace `+` with `-`, `-` with `+`, `*` with `/`,
  `/` with `*`, `%` with `*`
- **bugClass**: silent-but-wrong arithmetic; financial calculation
  errors; "we swapped the sign" bugs
- **equivalent filter**:
  - skip when the left and right operands are both literal zero
    (`0 + 0` ≡ `0 - 0`)
  - skip when the whole expression is under an
    `/* eslint-disable */` block tagged `no-math-equivalence`
- **set**: `default`

### ARITH_COMPOUND_ASSIGN
- **mutation**: replace `+=` with `-=`, `-=` with `+=`, `*=` with
  `/=`, `/=` with `*=`
- **bugClass**: compound arithmetic in loops (accumulators,
  running totals)
- **equivalent filter**:
  - skip when the lhs is never read before the statement
  - skip on `x *= 1` / `x /= 1` (trivial no-op)
- **set**: `default`

### ARITH_UNARY
- **mutation**: replace unary `+` with `-` and vice versa
- **bugClass**: sign-flip bugs in signed numeric computation
- **equivalent filter**: skip on literal 0 operands
- **set**: `default`

### ARITH_INCREMENT_DECREMENT
- **mutation**: replace `++` with `--`, `--` with `++`
- **bugClass**: off-by-one in iteration
- **equivalent filter**: none — if the test allows `++` or `--` on
  the same slot interchangeably, that's a bug worth catching
- **set**: `default`

---

## 2. Conditional / boundary operators

### CONDITIONAL_BOUNDARY
- **mutation**: `<` → `<=`, `>` → `>=`, `<=` → `<`, `>=` → `>`
- **bugClass**: the canonical off-by-one — the #1 bug class this
  skill catches, because it's the one line coverage lies about
  the most
- **equivalent filter**:
  - skip when the operand is a literal that makes `< 0` and `<= 0`
    equivalent (floats at the boundary)
  - skip inside a `// @mutation-equivalent-ok` comment marker that
    the developer added intentionally
- **set**: `default`

### CONDITIONAL_NEGATE
- **mutation**: wrap the condition in `!`
- **bugClass**: flipped branches; "we forgot to invert the check"
- **equivalent filter**: skip on `if (!x) return; /* else ... */`
  patterns where the inversion flips return order — hard to
  filter in general, but the report lists survivors for audit
- **set**: `default`

### CONDITIONAL_REPLACE_TRUE_FALSE
- **mutation**: replace a condition expression with literal `true`,
  then again with literal `false`
- **bugClass**: "the condition never runs the else branch" — the
  mutant fires if the tests don't cover both branches
- **equivalent filter**:
  - skip on `while (true)` / `do {} while (false)` patterns
    (infinite loop or no-op)
- **set**: `default`

### LOGICAL_OP_REPLACE
- **mutation**: `&&` → `||`, `||` → `&&`
- **bugClass**: short-circuit drift; "we meant AND but wrote OR"
- **equivalent filter**:
  - skip when both operands are literal `true` or both literal
    `false`
- **set**: `default`

### EQUALITY_OP
- **mutation**: `===` → `!==`, `==` → `!=`, and vice versa
- **bugClass**: inverted equality checks
- **equivalent filter**: skip inside `if (x == null)` / `if (x === undefined)`
  null-check idioms, because the negation would break runtime
  safety rather than test assertion
- **set**: `default`

---

## 3. Literal + value operators

### LITERAL_NUMBER
- **mutation**: replace a numeric literal with 0, then with 1,
  then with -1, then with the literal × 2
- **bugClass**: "the magic number changed and the test still
  passed"
- **equivalent filter**:
  - skip when the literal is in a test-data fixture file (those
    are intentional data, not logic)
  - skip when the literal is part of a color hex / iso timestamp
    (changing 0xff to 0 silently breaks UI, but we don't want to
    mutate color values here — a visual regression test is the
    right tool)
- **set**: `default`

### LITERAL_BOOLEAN
- **mutation**: `true` → `false`, `false` → `true`
- **bugClass**: flags that never flip because no test sets them
- **equivalent filter**: none
- **set**: `default`

### LITERAL_STRING
- **mutation**: replace a non-empty string literal with `""`
- **bugClass**: "the label text changed and the test kept
  passing" — catches tests that check the presence of an
  element but not its content
- **equivalent filter**:
  - skip in `import "..."` module path strings
  - skip in regex source strings
- **set**: `paranoid` only — string mutation is noisy; too many
  equivalent mutants in real code

---

## 4. Removal + replacement operators

### STATEMENT_REMOVE
- **mutation**: delete a single non-control statement
- **bugClass**: tests that run through a statement without
  asserting on its observable effect
- **equivalent filter**:
  - skip if the statement is a `console.log` / logger call (dead
    code from a testing standpoint)
  - skip if the statement is a `return` — removing return
    changes control flow, not just a value, and catches a
    different bug class via `CONDITIONAL_BOUNDARY`
- **set**: `default`

### RETURN_VALUE_REMOVE
- **mutation**: replace `return x` with `return` (returns
  undefined)
- **bugClass**: tests that check "did the function run" but not
  "what did it return"
- **equivalent filter**: skip on functions explicitly typed
  `:void` or `:Promise<void>`
- **set**: `default`

### METHOD_CALL_REMOVE
- **mutation**: delete a method call expression (when the call's
  return value isn't used)
- **bugClass**: side-effect calls that tests never observe
- **equivalent filter**:
  - skip on calls to `trace()` / `log()` / `debug()`
  - skip on calls whose method name matches `/^on[A-Z]/` (event
    handlers — removing them is a different bug class)
- **set**: `default`

---

## 5. Exception + promise operators

### THROW_EXPRESSION_REMOVE
- **mutation**: replace a `throw` statement with a no-op
- **bugClass**: error paths that no test exercises
- **equivalent filter**: none
- **set**: `default`

### PROMISE_REJECT_TO_RESOLVE
- **mutation**: replace `Promise.reject(x)` with `Promise.resolve(x)`
- **bugClass**: async error paths that no test catches
- **equivalent filter**: skip when the containing function is
  itself marked `never throws` via JSDoc
- **set**: `default`

### ASYNC_AWAIT_REMOVE
- **mutation**: drop an `await` keyword
- **bugClass**: race conditions; tests that await the return
  value but don't observe async effects
- **equivalent filter**: skip when the awaited expression's type
  is `Promise<void>` AND the result is discarded (it's a noop
  either way)
- **set**: `paranoid` only

---

## 6. Equivalent-mutant filter principles

Filters must be cheap and local. They scan only the immediate
AST neighborhood around the mutant — no cross-file reasoning, no
call-graph traversal. Cross-file equivalence is undecidable in
general; the skill accepts a small false-positive rate rather than
shipping a slow filter.

Filter false positives (real mutants mistakenly flagged
equivalent) are called out in the report so operators can audit.
If a specific idiomatic pattern keeps producing false-positive
filters, the fix lands here as a new filter condition — never as
a "just trust me" override.

---

## 7. Using the `// @mutation-equivalent-ok` comment

A source-code comment annotation that developers can use to mark
specific constructs as intentional equivalents. Syntax:

```ts
// @mutation-equivalent-ok CONDITIONAL_BOUNDARY: we accept this because ...
if (amount >= minThreshold) { ... }
```

Rules:

- The comment must cite a specific operator id. A bare
  `@mutation-equivalent-ok` without an operator is rejected —
  we don't silently swallow everything.
- The comment must include a reason after the colon. Empty
  reasons are rejected.
- The skill honors the annotation for the next statement only,
  not the whole file. Marking every line of a file as equivalent
  is a sign the whole file should move to `mutationIgnore` in
  `test-strategy.md`.
- The report's "Non-critical survivors" section lists every
  mutant that was skipped because of an annotation, so the
  decision stays auditable.

---

## 8. Adding a new operator

1. Pick a stable id in the `<CATEGORY>_<ACTION>` shape.
2. Describe the mutation precisely (what does the AST rewrite
   look like?).
3. Name the bug class. "Catches weird code" is not a bug class;
   "off-by-one in iteration" is.
4. Specify the equivalent filter. "None needed" is a valid
   answer when the mutation can't produce an equivalent.
5. Decide which set it belongs to. Default set is reserved for
   operators that produce <10% equivalent-mutant rate on the
   TruthLayer corpus; everything noisier goes into `paranoid`.
6. Update this file AND the integration harness sentinel that
   counts operators — silent additions are rejected at review.

---

## 9. Removed / deprecated operators

Never delete an operator id from this file. Old reports
reference these ids, and deletion orphans historical analyses.
Instead, mark an operator `deprecated: true` in the bug-class
field with a reason, and the skill stops generating it going
forward while old reports stay interpretable.

No entries yet — this is the first version.
