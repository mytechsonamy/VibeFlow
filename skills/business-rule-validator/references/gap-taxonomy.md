# Semantic Gap Taxonomy

The `business-rule-validator` skill classifies every rule-to-test
relationship using this taxonomy at Step 5 of its algorithm. Every
classification the skill emits MUST cite a category id from this
file. If a new kind of gap appears in the wild, extend this file
before extending the skill.

A gap has five fields:

| Field | Meaning |
|-------|---------|
| `id` | Stable identifier (`GAP-XXX`) cited in report's `why:` |
| `definition` | When the gap applies — the condition the skill checks |
| `severity` | `critical` / `soft` / `info` |
| `impact` | What breaks in production if the gap stays |
| `remediation` | Concrete fix the report should suggest |

Severity semantics (same shape as architecture-validator so reviewers
only memorize one scale):

- **critical** — blocks merge. Combined with priority, drives the
  gate contract (P0 uncovered + contradiction = BLOCKED).
- **soft** — shows up in NEEDS_REVISION bucket; counts against the
  risk-tolerance budget.
- **info** — recorded for audit trail, never blocks.

---

## Gap catalog

### GAP-001 — Uncovered
- **id**: GAP-001
- **definition**: No test body contains the rule id, the normalized
  rule string, or any of the rule's related scenario ids.
- **severity**: critical if priority is P0; soft if P1; info if P2/P3.
- **impact**: The rule ships unexecuted. For P0 rules this is a
  deployment risk — a regression in the rule's action will not be
  caught by any suite.
- **remediation**: Generate a test via the normal Step 4 path of
  `business-rule-validator`. If the rule cannot be tested (no
  constructable fixture), block and fix `test-data-manager` first.

### GAP-002 — Weak coverage
- **id**: GAP-002
- **definition**: A test mentions the rule (by id or scenario) but
  its assertions do not check the rule's action. Example: the rule
  prohibits a state, but the test only asserts the happy path.
- **severity**: soft.
- **impact**: False-positive coverage — the test exists and the
  metric looks green, but a regression in the prohibition path is
  invisible.
- **remediation**: Add a negative-path assertion in the existing
  test. Do not duplicate the test.

### GAP-003 — Contradicted
- **id**: GAP-003
- **definition**: A test explicitly asserts the opposite of the rule.
  Example: rule says "amount MUST be positive", test asserts
  `toBeNegative()`.
- **severity**: critical, unconditionally — priority is irrelevant
  because one side of the codebase is always wrong.
- **impact**: Either the rule is wrong or the test is wrong; merging
  either as-is ships a latent inconsistency.
- **remediation**: Halt, escalate to a human, fix one side. Never
  silently adjust the test.

### GAP-004 — Orphan test
- **id**: GAP-004
- **definition**: A test file contains a `BR-NNNN` id that no longer
  exists in the rules catalog (e.g. the PRD removed the rule).
- **severity**: soft.
- **impact**: The test is checking a rule that no longer governs
  the system. Worst case it contradicts a newer rule.
- **remediation**: Delete the test OR remap it to the superseding
  rule if one exists (record the remapping in the rule's
  `source` evidence).

### GAP-005 — Stale scenario link
- **id**: GAP-005
- **definition**: A test references a scenario id (`SC-NNNN`) that no
  longer exists in `scenario-set.md`.
- **severity**: info.
- **impact**: Traceability chain is broken — the RTM cannot link
  test → scenario → PRD.
- **remediation**: Update the scenario id in the test, or remove
  the reference if the scenario was deliberately dropped.

### GAP-006 — Multi-rule collapse
- **id**: GAP-006
- **definition**: A single test covers multiple rules (`BR-001`,
  `BR-002`) and asserts on all of them at once. The rules are
  independent but share the same assertions.
- **severity**: info.
- **impact**: When one rule changes, the test needs edits that may
  accidentally weaken another rule's assertion.
- **remediation**: Split into one test per rule. Shared setup goes
  in a `beforeEach` or a helper.

### GAP-007 — Priority mismatch
- **id**: GAP-007
- **definition**: A test is tagged or grouped as a lower priority
  than the rule it covers (e.g. rule is P0 but the test lives in a
  "slow"/"nightly" tier).
- **severity**: soft.
- **impact**: The rule has technical coverage but the feedback
  loop is too slow for a P0 signal. Regressions land and sit.
- **remediation**: Move the test into the fast suite OR downgrade
  the rule's priority if the slow feedback is acceptable
  (usually it isn't for P0).

### GAP-008 — Flaky coverage
- **id**: GAP-008
- **definition**: The test that covers the rule appears in the
  flake tracker (see `test-result-analyzer` outputs).
- **severity**: soft.
- **impact**: The rule is technically covered but the coverage
  signal is unreliable — a flake looks like a regression or vice
  versa.
- **remediation**: Fix the flake (usually a timing or shared-state
  issue). Do not add a retry — retries hide the real symptom.

### GAP-009 — Ambiguity-filtered rule
- **id**: GAP-009
- **definition**: The rule was extracted but filtered out at Step 1
  because the PRD quality report flagged the source text as
  ambiguous.
- **severity**: info.
- **impact**: The rule exists in the PRD but is not enforceable in
  its current form.
- **remediation**: Tighten the PRD text and re-run
  `prd-quality-analyzer`. The rule will be re-extracted on the
  next run.

### GAP-010 — Rule without testable outcome
- **id**: GAP-010
- **definition**: The rule has no measurable outcome the test can
  assert on (e.g. "the system MUST be user-friendly").
- **severity**: critical if P0 — we cannot ship a P0 rule we cannot
  check. soft otherwise.
- **impact**: The rule is a slogan, not a requirement.
- **remediation**: Rewrite the rule in the PRD to name a measurable
  outcome. Escalate to the product owner — this is a product
  definition problem, not a testing problem.

---

## Adding a new gap

1. Pick the next free `GAP-NNN` id.
2. Fill all five fields above — never leave `severity` blank.
3. Update `business-rule-validator/SKILL.md` Step 5 if the new gap
   needs a new detection rule.
4. Update the integration harness sentinel that counts the minimum
   catalog size — we do not ship a taxonomy that can silently shrink.
