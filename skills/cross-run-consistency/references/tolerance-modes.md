# Tolerance Modes

The skill evaluates every per-run diff in exactly one of two
modes: `strict` or `tolerant`. This file defines both modes,
the per-type tolerance declarations `tolerant` allows, and the
override discipline that keeps the P0 strict rule from being
weakened at config time.

---

## 1. Mode semantics

### `strict`

- **Meaning**: byte-for-byte identity. Every output field
  must match the baseline exactly.
- **Comparison**: literal equality on the raw output (exit
  code, stdout, stderr, per-artifact file bytes).
- **Tolerance**: none. A single byte difference is an
  inconsistency.
- **Applicable to**: **every P0 test, always**; non-P0 tests
  that explicitly opt in.
- **Use when**: the test is load-bearing, the test is in a
  regulated domain (financial / healthcare), or you suspect
  the test might be drifting and you want to pin it.

### `tolerant`

- **Meaning**: "the same within a declared fuzziness". Every
  diff that exceeds the fuzziness for the corresponding output
  type is still an inconsistency; diffs within the fuzziness
  are accepted.
- **Comparison**: type-aware. The test's output is parsed into
  typed fields (numbers, timestamps, strings, image pixels)
  and each type uses its own tolerance rule.
- **Tolerance**: comes from the test's declaration (see §2
  and §3). A test in `tolerant` mode with no declared
  tolerances is rejected — tolerant without tolerances is
  meaningless.
- **Applicable to**: non-P0 tests only. Applying `tolerant`
  to a P0 test is a config error the skill refuses to execute.
- **Use when**: the test has known sources of non-determinism
  the team has explicitly decided to live with (pixel-diff UI
  tests, ML model outputs within a confidence band, timing
  benchmarks with a budget).

---

## 2. The `test-strategy.md` tolerance declaration shape

```yaml
crossRunTolerance:
  defaults:
    strict: true                    # default for P0 always
    numericRelative: 0.02           # ±2% on numbers without context
    durationMs: 50                  # ±50ms on duration fields
    pixelDiff: 0.01                 # ±1% of pixels may differ on images
  perTest:
    "src/pricing.test.ts::discount": # test id (`<file>::<name>`)
      mode: tolerant
      numericRelative: 0.05         # looser for this specific test
    "src/ui/button.spec.ts::colors":
      mode: tolerant
      pixelDiff: 0.005              # tighter than default (design is stable)
```

Rules:

- **The `defaults` block only applies to non-P0 tests.** P0
  tests ignore every declared default and use pure `strict`.
- **`perTest` overrides** compose with the defaults — a test
  with `mode: tolerant` and no explicit `numericRelative`
  inherits the default `0.02`.
- **Every declared tolerance must have a numeric value** (no
  `tolerance: "lax"`). Un-bounded looseness is rejected at
  config load.
- **No negative tolerances**. `numericRelative: -0.01` is
  rejected as "negative tolerance has no meaning".
- **No `tolerance: Infinity`**. A tolerance that accepts
  anything is the same as "disable this test"; the skill
  blocks at config load with remediation "remove the test or
  mark it `@quarantined` if you don't want it gating".

---

## 3. Per-type tolerance rules (when mode is `tolerant`)

### 3.1 Numeric fields

- **`numericAbsolute`** — the baseline and current values
  must satisfy `|baseline - current| ≤ numericAbsolute`
- **`numericRelative`** — the two values must satisfy
  `|baseline - current| / max(|baseline|, 1) ≤ numericRelative`
- Both can be declared; if both are declared, **the TIGHTER
  of the two applies** (the test has to meet both). Loosening
  is additive is a common misconception; we use intersection
  here to keep the strict-er bar.
- Applies to any field that looks numeric, including duration
  fields (see 3.4).

### 3.2 Pixel-diff (images)

- **`pixelDiff`** — percentage of pixels that may differ
  between the baseline image and the current image, using a
  perceptual diff (not raw pixel-equals)
- Range: `[0.0, 0.1]`. A declaration above `0.1` is rejected
  as "pixel tolerance too loose — the test isn't testing the
  image any more".
- The perceptual diff uses the same shape as
  `design-bridge`'s image comparison (see
  `mcp-servers/design-bridge/src/compare.ts`), extended with
  per-pixel color-distance thresholds.

### 3.3 String fields

- **`ignoreLines`** — a regex; matching lines in stdout /
  stderr are removed before comparison. Used to strip known
  noisy lines (deprecation warnings, debug timestamps)
- **`ignoreTokens`** — a regex; matching substrings are
  replaced with a sentinel before comparison. Used for the
  "UUID present but value doesn't matter" pattern
- Both are last-resort hammers; preferring `strict` after
  fixing the actual cause of the noise is better. The report
  flags every test that uses these as "has ignore-rules"
  so the team audits them periodically.

### 3.4 Duration fields

- **`durationMs`** — ±N ms absolute tolerance
- **`durationRelative`** — relative tolerance with the same
  shape as `numericRelative`
- Duration tolerances are SEPARATE from `numericRelative`
  because timing is the thing you almost always want to
  forgive first; mixing them into `numericRelative` is how
  a 2% number tolerance accidentally becomes a 2% duration
  tolerance, which is absurd on a 100ms assertion.

### 3.5 Exit code

- Exit code is ALWAYS compared strictly, even in `tolerant`
  mode. A test that exits 0 on one run and 1 on another is
  not "close enough". There is no per-test override for this.

---

## 4. Domain thresholds (overall consistency, non-P0)

The skill's overall consistency threshold for non-P0 tests
comes from the project's domain:

| Domain | Non-P0 overall threshold |
|--------|--------------------------|
| `financial` | **0.98** |
| `healthcare` | **0.98** |
| `e-commerce` | **0.93** |
| `general` | **0.90** |

**Why financial and healthcare are the same here:** the cost
of a non-deterministic test slipping through is the cost of
flake in production, which is roughly the same in both
domains (people notice; audits happen; post-mortems are
expensive). The e-commerce and general gaps exist because
those domains have more visual / UX-driven tests where pixel
tolerance legitimately softens the numerator.

**P0 rule is independent.** Even in `general`, P0 tests must
score 1.0 — there's no "90% good enough" at the P0 level.

---

## 5. Override discipline

### 5.1 Per-test overrides

- Declared in `test-strategy.md → crossRunTolerance.perTest`
- Can loosen the defaults for NON-P0 tests only
- Cannot flip a P0 test into `tolerant` mode — the skill
  ignores any `mode: tolerant` override on a P0 test and
  records a WARNING

### 5.2 Domain threshold overrides

- Declared in `test-strategy.md → crossRunTolerance.domainOverride`
- Can only TIGHTEN the domain threshold (a threshold that
  reads `financial: 0.99` is allowed; `financial: 0.95` is
  rejected at config load)
- Rationale is the same as every other override-tighten rule
  in VibeFlow: gate contracts only get stricter, never looser

### 5.3 Runtime overrides

- `--mode strict` runtime flag applies to non-P0 tests AND
  is additive (it makes them stricter — everyone goes strict).
- `--mode tolerant` runtime flag is REJECTED. You cannot
  loosen the whole run from the command line, because that's
  exactly the operator mistake the config-side overrides are
  designed to catch at review time.

---

## 6. What modes do NOT do

- **Modes don't apply to the baseline capture.** The first
  run is recorded as-is, regardless of mode. Mode only
  affects the comparison.
- **Modes don't retry.** A test that exceeds tolerance on the
  second run fails immediately — the skill doesn't run a
  third time hoping it'll come back within tolerance. Retries
  hide non-determinism; the skill exists to expose it.
- **Modes don't change the classification.** A `tolerant`
  finding still gets walked through the taxonomy in
  `non-determinism-taxonomy.md`. The report records both the
  mode and the classification so operators can tell "this
  was tolerated" from "this was classified".
- **Modes don't scale tolerances by the number of runs.** A
  test with `numericRelative: 0.02` uses 2% on every
  comparison, not "2% over 5 runs, averaged". Tolerance is
  pairwise (current vs baseline), not aggregate.

---

## 7. Versioning

**Current tolerance config version: 1**

Bump rules:

- Adding a new per-type tolerance rule (e.g. `jsonPathRelative`
  for numeric tolerances inside JSON paths) bumps the
  version
- Changing a domain threshold defaults in §4 bumps the
  version
- Renaming any field bumps the version

Every report writes `toleranceConfigVersion` in its header
so historical reports stay interpretable. Downstream
consumers (`learning-loop-engine`) bucket findings by version.

Threshold change discipline is the same as every other
VibeFlow governance file: retrospective on ≥10 runs, version
bump, migration note, harness sentinel update. Silent edits
fail CI.
