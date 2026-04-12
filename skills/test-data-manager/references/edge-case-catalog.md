# Edge Case Catalog

The `test-data-manager` skill draws **every** edge-case preset from
this file. The skill is forbidden from inventing new edge cases — if
a type has no entry here, the generator emits a `pending:` comment
and the skill's run report surfaces it as a finding. Missing entries
are a prompt to extend this file, not a prompt to guess.

Every category has the same structure:

- **id** — stable identifier cited in generated preset comments
- **type** — the CanonicalType kind it applies to
- **value / strategy** — the literal value or how to construct it
- **rationale** — the class of bug this case catches
- **when to skip** — cases where the preset doesn't apply

---

## Strings

### EC-STR-001 — Empty string
- **type**: `string`
- **value**: `""`
- **rationale**: The off-by-one of string handling. Parsers that use
  `s.length > 0` as a guard miss empty. URL builders, slugifiers,
  regex matchers, and hash functions all have different failure
  modes on `""`.
- **skip when**: Field has `minLength >= 1` — violates the schema.

### EC-STR-002 — Single ASCII character
- **type**: `string`
- **value**: `"a"`
- **rationale**: Minimum-length-above-zero boundary.
- **skip when**: `minLength > 1`.

### EC-STR-003 — Maximum declared length
- **type**: `string`
- **strategy**: repeat an ASCII character up to `maxLength`.
- **rationale**: Clients that stored length in smaller integer types
  truncate here.
- **skip when**: No `maxLength` declared.

### EC-STR-004 — `maxLength + 1`
- **type**: `string`
- **strategy**: `maxLength + 1` repeated character.
- **rationale**: Intentionally invalid — used by tests that assert
  the rejection path.
- **skip when**: Field is used as a fixture for happy-path tests
  only (emit via the `<schema>EdgeCases.tooLong` preset, never in
  the base factory).

### EC-STR-005 — Leading/trailing whitespace
- **type**: `string`
- **value**: `"  padded  "`
- **rationale**: Catches trim-bugs and hash-of-input bugs.

### EC-STR-006 — Only whitespace
- **type**: `string`
- **value**: `"   "`
- **rationale**: Empty-after-trim; different from EC-STR-001.

### EC-STR-007 — Unicode BMP
- **type**: `string`
- **value**: `"Μουσταφά 山田 αβγ"`
- **rationale**: Most servers are fine here; some databases default
  to latin1 collation.

### EC-STR-008 — Unicode astral (4-byte utf-8)
- **type**: `string`
- **value**: `"Hello 🌍 world"`
- **rationale**: MySQL `utf8` (not `utf8mb4`) crashes here. Regex
  engines that use code-unit indexing miscount here.

### EC-STR-009 — Right-to-left override
- **type**: `string`
- **value**: `"user\u202Egnp.exe"`
- **rationale**: RTL override is a classic phishing vector; any
  field that renders to HTML must handle it.

### EC-STR-010 — NUL byte
- **type**: `string`
- **value**: `"hello\u0000world"`
- **rationale**: C-string truncation in any native bridge; also
  breaks many JSON parsers.

### EC-STR-011 — Newline in middle
- **type**: `string`
- **value**: `"line1\nline2"`
- **rationale**: CSV encoders and single-line validators miss this.

### EC-STR-012 — SQL injection shape
- **type**: `string`
- **value**: `"Robert'); DROP TABLE students; --"`
- **rationale**: Not a security test, a string-handling test. If any
  layer concatenates this into SQL, the fixture breaks.
- **skip when**: The test is explicitly a security test (use a
  security-focused fixture instead).

### EC-STR-013 — HTML/script injection shape
- **type**: `string`
- **value**: `"<script>alert(1)</script>"`
- **rationale**: Same as EC-STR-012 for HTML output paths.

---

## Numbers

### EC-NUM-001 — Zero
- **type**: `number`
- **value**: `0`
- **rationale**: The "identity" boundary — signed/unsigned divides,
  division-by-zero, log(0), sqrt(0).
- **skip when**: `min > 0` excludes it.

### EC-NUM-002 — Negative one
- **type**: `number`
- **value**: `-1`
- **rationale**: Classic sentinel value; unsigned comparisons treat
  it as a very large positive.
- **skip when**: `min >= 0`.

### EC-NUM-003 — Min integer
- **type**: `number`, integer
- **value**: `Number.MIN_SAFE_INTEGER`
- **rationale**: Arithmetic near the boundary overflows to float.

### EC-NUM-004 — Max integer
- **type**: `number`, integer
- **value**: `Number.MAX_SAFE_INTEGER`
- **rationale**: Same as above on the positive side; also catches
  `id+1` overflows.

### EC-NUM-005 — Declared minimum
- **type**: `number`
- **value**: the field's `constraints.min`
- **rationale**: Boundary inclusion check.
- **skip when**: No `min` declared.

### EC-NUM-006 — Declared minimum - 1
- **type**: `number`
- **value**: `min - 1`
- **rationale**: Intentionally invalid; lives in the `edgeCases`
  preset, not the base factory.
- **skip when**: No `min` declared.

### EC-NUM-007 — Declared maximum
- **type**: `number`
- **value**: the field's `constraints.max`
- **rationale**: Upper boundary inclusion check.
- **skip when**: No `max` declared.

### EC-NUM-008 — Fractional
- **type**: `number`, non-integer
- **value**: `0.1 + 0.2` (i.e. `0.30000000000000004`)
- **rationale**: Float arithmetic's famous lie; catches money
  fields that should be `bigint` cents or decimal strings.
- **skip when**: Field is declared integer.

### EC-NUM-009 — Infinity
- **type**: `number`
- **value**: `Number.POSITIVE_INFINITY`
- **rationale**: JSON serialization turns this into `null`; most
  serializers crash and most comparisons return false.

### EC-NUM-010 — NaN
- **type**: `number`
- **value**: `Number.NaN`
- **rationale**: `NaN !== NaN`, which breaks any equality-based
  cache or deduplication.

---

## Booleans

### EC-BOOL-001 — true
- **value**: `true`

### EC-BOOL-002 — false
- **value**: `false`

Nothing else. Booleans have no edge cases; "undefined" is not a
boolean and lives in the optional/null variants below.

---

## Dates

### EC-DATE-001 — Epoch
- **value**: `new Date(0)`
- **rationale**: `1970-01-01T00:00:00Z`. Lots of "is this date set?"
  checks treat this as "unset".

### EC-DATE-002 — Epoch + 1ms
- **value**: `new Date(1)`
- **rationale**: Off-by-one from the epoch sentinel.

### EC-DATE-003 — Far future
- **value**: `new Date(8640000000000000)`
- **rationale**: `+275760-09-13` — the JavaScript `Date` maximum.
  Anything that tries to format this into an ISO string still works
  but most localization libraries crash.

### EC-DATE-004 — Invalid date
- **value**: `new Date("not a date")`
- **rationale**: `isNaN(date.getTime())` boundary.
- **skip when**: Base factory only (emit only in edge-case preset).

### EC-DATE-005 — DST transition
- **value**: `new Date("2025-03-30T01:30:00+00:00")`
- **rationale**: European DST spring-forward moment; catches
  "add 1 hour" logic that ignores timezone rules.

### EC-DATE-006 — Leap-day
- **value**: `new Date("2024-02-29T00:00:00Z")`
- **rationale**: Naive "add 1 year" arithmetic breaks here.

---

## Arrays

### EC-ARR-001 — Empty array
- **value**: `[]`
- **rationale**: Off-by-one of iteration. Tests often miss the
  zero-length case.
- **skip when**: `minItems >= 1`.

### EC-ARR-002 — Single element
- **strategy**: wrap one generated item.
- **rationale**: Boundary above empty.

### EC-ARR-003 — Max-length array
- **strategy**: fill `maxItems` repetitions of a generated item.
- **rationale**: Client-side list virtualization breaks here; sort
  implementations with quadratic worst-case show up.
- **skip when**: No `maxItems` declared.

### EC-ARR-004 — Duplicated element
- **strategy**: two identical generated items.
- **rationale**: Set-vs-list confusion; `new Set(arr).size` equality
  comparisons.

### EC-ARR-005 — Reverse-sorted
- **strategy**: generate N items, then reverse.
- **rationale**: Catches sort implementations with O(n²) reverse
  runtime and "already sorted" optimization bugs.

---

## Objects / optional / nullable

### EC-OPT-001 — Optional field present
- **strategy**: generate a value per the field type.
- **rationale**: The "default" case the rest of the catalog covers.

### EC-OPT-002 — Optional field absent
- **strategy**: omit the field entirely from the object.
- **rationale**: Tests that use `field === undefined` vs
  `"field" in obj` behave differently; this preset catches both.
- **skip when**: Field is not optional.

### EC-NULL-001 — Nullable field set to null
- **strategy**: emit `null`.
- **rationale**: The primary nullable boundary; many serializers
  still emit `undefined` here.
- **skip when**: Field is not nullable.

---

## Catalog maintenance

- **Never delete an entry.** If an entry is obsolete, mark it
  `deprecated` in the rationale column and stop emitting it from
  new presets. Old generated files still reference the id, so
  deletion orphans historical fixtures.
- **Every entry needs a rationale.** If you can't explain the bug
  class in one sentence, you don't understand the edge case yet.
- **Reject "random" entries.** Every edge case is a specific class
  of bug. `Math.random()`-ish fuzzing belongs in a different
  tool, not in this catalog.
