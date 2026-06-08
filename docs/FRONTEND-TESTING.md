# Front-end testing — the UI-conditional battery

When an increment touches the UI, "are the tests good?" (coverage + mutation) is
not enough — you also need "is the **UI** right?": every field matches the
design, every input is validated, every function works end-to-end and meets its
requirement. VibeFlow runs a **front-end battery** in TESTING for UI-facing
increments, on top of the default coverage + mutation gates.

## When it runs

phase-runner's TESTING walk runs the battery **only when the active increment is
UI-facing** — its change-type classification (from `brownfield-intake` /
`design-bootstrap`) is `ui` or `mixed`, or `design/design-spec.md` exists for the
cycle. A **backend / infra** increment skips it entirely (coverage + mutation
only).

## What it covers (mapped to the concerns)

| Concern | Skill | What it guarantees |
|---|---|---|
| Each field matches the design | `visual-ai-analyzer` (+ `design-bridge db_compare_impl` when Figma exists) | layout / typography / spacing / a11y vs `design-spec.md` |
| Data validation (numeric / alphanumeric / boundary / format) | **`input-validation-matrix`** | per field: required, type, boundary (value + length), format, type-mismatch, injection-safety, output-formatting |
| Input / output controls | `input-validation-matrix` + `e2e-test-writer` | accept/reject + the displayed/formatted value (currency precision, masking) |
| Functions work | `e2e-test-writer` (Playwright web / Detox mobile) + `regression-test-runner` | end-to-end functional flows actually run green |
| Functions meet requirements | `business-rule-validator` + `traceability-engine` | each PRD rule has a test; every UI requirement maps to a test (no untested requirement / orphan) |
| End-to-end on a real environment | `uat-executor` | UAT scenarios on staging (when a staging URL is configured) |

## Why it's a *gate*, not a side report

The validation + E2E tests are written **into the project's own test suite**, so
the existing gates enforce them automatically: they must pass
(`regression-test-runner` / `quality-gates`) and they count toward `coverage.met`.
The battery's reports (`validation-matrix.md`, `rtm.md`, the visual findings)
become **evidence** for `consensus.testing.approved`. So a UI increment can't
reach a GO without the front-end battery being green — that's the guarantee.

## The validation matrix in detail

`input-validation-matrix` builds, **for every input field**, cases across every
applicable category:

- **Required / presence** — empty / whitespace / missing → the field's message shows.
- **Type** — alpha in a numeric field, decimals in an integer, letters in a date → rejected.
- **Boundary** — `min`, `min-ε`, `max`, `max+ε`, zero, negative-where-disallowed; `minLength`/`maxLength` ± 1.
- **Format** — valid vs malformed (email, IBAN checksum, phone shape, currency decimals/separator).
- **Enum / allowed set** — each allowed value accepted; out-of-set rejected.
- **Injection / safety** — `<script>…`, `' OR 1=1`, unicode/RTL, oversized → escaped or rejected, never executed/stored raw (weighted up for `financial` / `healthcare`).
- **Output control** — the accepted value is formatted/masked as the spec says.
- **Cross-field** — "end ≥ start", "amount ≤ balance", "confirm == value".

A rule with **no wired validation** is reported as a **defect** (not merely a test
gap), and an executed/stored injection case is a hard **BLOCKED** for regulated
domains.

## A/B and experiments

A/B testing is a **production experiment** (two variants measured live), not a
pre-release gate — it lives with the `observability` MCP (metrics/conversion),
not this battery. The battery guarantees both variants are *correct and
validated* before they ship; choosing the winner is a runtime measurement.

## Running it

It's part of the one-command walk:

```
/vibeflow:phase-runner        # TESTING: coverage + mutation + (UI) the battery
```

Or invoke a lane directly, e.g. `/vibeflow:input-validation-matrix` or
`/vibeflow:visual-ai-analyzer`.
