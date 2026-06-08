---
name: input-validation-matrix
description: For every input field in the UI, generates and runs a systematic data-validation test matrix — required/presence, type (numeric vs alphanumeric vs email/date/currency), boundary (min/max value + length, just-inside/just-outside), format (regex/IBAN/phone/precision), type-mismatch, and injection-safety (XSS/SQL-ish strings escaped or rejected) — plus output-control checks (formatting/masking of the displayed value). Writes real framework tests into the suite and a validation-matrix.md report. Use in TESTING for any UI-facing change; pairs with e2e-test-writer + visual-ai-analyzer in the front-end battery.
disable-model-invocation: false
allowed-tools: Read Write Bash(mkdir *) Bash(jq *) Bash(ls *) Bash(npm *) Bash(npx *) Bash(pnpm *) Bash(yarn *) Bash(pytest *) Bash(dotnet *) Bash(vitest *) Bash(jest *) Bash(playwright *)
---

# Input Validation Matrix

When the UI grows a form or an input, "does it validate?" is not one test — it's
a *matrix*: every field × every class of bad (and good) input × the expected
control. This skill builds that matrix systematically so no field ships with an
unchecked validation path. It's the dedicated data-validation lane of the
front-end test battery (functional flow is `e2e-test-writer`; design conformance
is `visual-ai-analyzer`).

## Phase Contract

Runs in **TESTING** (it generates + runs tests). If `currentPhase` is not
TESTING, emit a one-line note and stop. UI-facing changes only — if the active
increment's change-type classification is `backend`/`infra` (from
`brownfield-intake` / `design-bootstrap`), say "no UI inputs in this increment —
skipping" and stop. Writes test files into the project's test dir +
`.vibeflow/reports/validation-matrix.md`.

## Step 1: Enumerate the fields + their rules

Build the field inventory from three sources (cross-check, don't trust one):

1. **Design spec** (`design/design-spec.md` + tokens) — the fields, their types,
   labels, placeholders, required-ness, and the **validation messages** the
   design promises.
2. **Requirements** (the PRD / increment requirements + `business-rule-validator`
   output) — the *rules* (limits, formats, allowed sets, cross-field rules).
3. **Source** — the actual form components / schema (Zod / Yup / form library /
   server DTO). This is ground truth for what's wired; gaps between source and
   the spec are themselves findings.

For each field record: `name`, `type` (numeric / integer / decimal-currency /
alphanumeric / email / phone / date / enum / free-text), `required`, `min`/`max`
(value), `minLength`/`maxLength`, `format` (regex / IBAN / TCKN / etc.),
`allowedSet`, and any cross-field rule.

## Step 2: Generate the matrix (per field)

For each field, derive cases across **all applicable** categories — skip a
category only when it cannot apply (and say so):

- **Required / presence** — empty, whitespace-only, missing → the field's
  validation message shows; submit is blocked.
- **Type** — wrong type rejected: alpha in a numeric field, decimals in an
  integer field, letters in a date.
- **Boundary (value)** — `min`, `min-ε`, `max`, `max+ε`, zero, negative where
  disallowed, and a very large value.
- **Boundary (length)** — `minLength`, `minLength-1`, `maxLength`, `maxLength+1`.
- **Format** — a valid example **and** malformed ones (bad email, wrong IBAN
  checksum, wrong phone shape, currency with too many decimals / wrong
  separator).
- **Enum / allowed set** — each allowed value accepted; an out-of-set value
  rejected.
- **Injection / safety** — `<script>alert(1)</script>`, `' OR 1=1 --`, unicode /
  RTL overrides, oversized payload → **escaped or rejected, never executed or
  stored raw** (security-adjacent; weight up for `financial`/`healthcare`).
- **Output control** — the accepted value is **displayed/formatted** as the spec
  says: currency precision + thousands separator, date format, masking of
  sensitive fields (card/PAN/IBAN), trimming.
- **Cross-field** — rules like "end ≥ start", "amount ≤ balance", "confirm ==
  value".

Each case: `{ field, category, input, expected (accepted|rejected+message|formatted-as), source-of-rule }`.

## Step 3: Write the tests (into the real suite)

Emit **runnable** tests in the project's framework (detect from
`vibeflow.config.json.tech.*` / config files — never assume):

- **Component/unit level** (vitest / jest / RTL / pytest) — drive the field /
  validator directly: render, type the input, assert the message / accept /
  formatted output. The bulk of the matrix lives here (fast, deterministic).
- **Form-submit E2E** (Playwright web / Detox mobile) — a thin layer per form:
  the required + a couple of boundary + one injection case through the real
  submit, asserting the user-visible control. (Coordinate with `e2e-test-writer`
  — extend, don't duplicate, its scenarios.)

Use `test-data-manager` factories for valid baselines so only the field under
test varies. Put files alongside the project's existing tests so coverage +
`regression-test-runner` + `quality-gates` pick them up — that's what makes the
matrix an enforced gate, not a side report.

## Step 4: Run + report

Run the new tests. Write `.vibeflow/reports/validation-matrix.md`:

- A **field × category** table: cases generated, passed, failed, **not-applicable
  (with reason)**, and **uncovered** (a rule with no wired validation — a real
  defect, not a test gap).
- Per finding: `{ finding, why, impact, confidence }`.
- **Verdict**: `PASS` (every applicable category covered and green) /
  `NEEDS_REVISION` (gaps or soft failures) / `BLOCKED` (a rule has no validation,
  or an injection case is executed/stored raw — non-negotiable for
  financial/healthcare).

## Final Step: Auto-Consensus Marker (only on PASS — Sprint 43 arm-on-pass)

Write `.vibeflow/state/consensus-needed.json` (primaryArtifact
`.vibeflow/reports/validation-matrix.md`, createdBy `input-validation-matrix`)
**only if `VERDICT == "PASS"`**. On `NEEDS_REVISION`/`BLOCKED`, do **not** write
the marker — emit the gap advisory naming the uncovered/failed fields + a
`▶ Next:` to wire the missing validation, and stop, so `consensus-gate` doesn't
block the fix.

## Output

- validation test files in the project test dir (component + form-submit E2E)
- `.vibeflow/reports/validation-matrix.md` (the field × category matrix + verdict)
