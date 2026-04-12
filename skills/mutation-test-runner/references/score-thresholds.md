# Score Thresholds

The domain-specific mutation score targets `mutation-test-runner`
applies at Step 5 of its algorithm. The thresholds here are the
single source of truth. Changing them requires a retrospective
and a review (see §5 below) — they are not "just a config knob".

---

## 1. Domain thresholds

| Domain | Threshold | NEEDS_REVISION band (threshold − 5%) | BLOCKED band |
|--------|-----------|--------------------------------------|--------------|
| `financial` | **0.85** | 0.80 – 0.85 | < 0.80 |
| `healthcare` | **0.85** | 0.80 – 0.85 | < 0.80 |
| `e-commerce` | **0.75** | 0.70 – 0.75 | < 0.70 |
| `general` | **0.70** | 0.65 – 0.70 | < 0.65 |

**Why the gap between financial/healthcare and e-commerce:**
financial and healthcare bugs tend to be expensive in
non-reversible ways (money lost, compliance exposure, patient
harm). A 15% tolerance between tiers isn't "e-commerce is less
important", it's "the cost of a missed mutation is different".

**Why `general` is the lowest:** `general` is the escape hatch
for projects that genuinely don't map onto the other three.
Using it to get a lower bar for a project that really is
financial is a config anti-pattern; the skill surfaces a WARNING
when a `general`-domain project imports anything from a financial
package, so the mis-classification is at least visible.

---

## 2. P0 zero-survivor rule

**This rule runs parallel to the score threshold.** Even a
run that meets the overall score must ALSO have zero P0
survivors. The two rules compose:

- `p0Survivors == 0 && score >= threshold(domain)` → PASS
- `p0Survivors == 0 && score in [threshold − 5%, threshold)` → NEEDS_REVISION
- `p0Survivors == 0 && score < threshold − 5%` → BLOCKED
- `p0Survivors > 0` → BLOCKED (regardless of overall score)

**There is no override flag.** A team that wants to accept a P0
survivor must move the source file OUT of P0 in
`test-strategy.md`. That's a human decision with an audit trail;
a flag would let the same decision happen invisibly.

### How priority is inherited by a mutant

The mutant's priority is the MAX priority of any test file that
would execute the source file at the mutation's line. Resolution:

1. If the source file has an explicit `@priority P0` header
   comment, inherit that.
2. Otherwise, walk the dependency graph (via `codebase-intel`
   MCP) to find every test file that imports the source, read
   their priorities from `regression-baseline.json.tests`, and
   take the max.
3. Otherwise, default to `P2`. Defaulting to `P0` would make
   every file under this skill's strictest rule — the default
   is intentionally conservative so the rule bites where it was
   intended to.

---

## 3. `no-coverage` mutants

A mutant classified `no-coverage` (no test file touches the
line) counts as SURVIVED. This is the single most important
design choice in the whole scoring scheme. The reason:

> Excluding `no-coverage` mutants from the score would let a
> repo with 20% line coverage report a perfect 100% mutation
> score on its tiny executed set. That's the opposite of what
> we want.

So: `noCoverage` counts as survived, AND the report lists every
no-coverage mutant separately so the operator can point at the
exact lines to write tests for. The `weak-assertions.md` output
names them as the highest-leverage fixes.

The practical consequence is that a repo with low line coverage
cannot pass the mutation gate until line coverage improves. This
is intentional — mutation testing without coverage is a lie.

---

## 4. Timeout + runtime-error handling

A mutant whose test hit a timeout or caused a runtime error is
classified as **killed** (see main SKILL.md §3). This is a trust
decision: if the mutation broke the world enough for the test
runner to abort, the test DID observe a change. The alternative
— classifying timeout as survived — would be worse, because it
lets pathological mutants (infinite loops, out-of-memory) drag
the score down without representing a real weakness in the
tests.

But: timeouts and runtime-errors are separately tracked in the
report. A large count (>5% of executed mutants) is a signal that
the operator catalog needs a tighter equivalent filter. The
skill surfaces the count in the header so operators can act on
it.

---

## 5. Threshold change discipline

Changing a threshold in this file is a structural change, not a
knob. To land a new threshold:

1. **Retrospective on ≥20 real runs**. Show the change would
   have improved gate accuracy (fewer bugs slipping through
   without more false positives). An untested proposal is
   rejected at review.
2. **Version bump**. The skill records the
   `thresholdConfigVersion` in every report. Downstream
   consumers (especially `release-decision-engine` and
   `learning-loop-engine`) use the version to bucket historical
   decisions — a silent change would poison the learning-loop
   dataset.
3. **Migration note**. PR description names old threshold → new
   threshold → example affected runs.
4. **Harness sentinel update**. The integration harness asserts
   the current threshold values (see the skill's integration
   guards). A silent table edit fails CI.

The four disciplines are the same ones `test-priority-engine`'s
risk model uses. Different files, same cultural rule — "don't
change the gate without showing the gate gets better".

---

## 6. Overrides

`test-strategy.md` can override the domain threshold via:

```yaml
mutation:
  thresholdOverride: 0.90       # must be STRICTER than the domain default
  reason: "payment flow carries extra regulatory burden"
```

Rules:

- Overrides can only TIGHTEN the threshold. A configuration that
  reads `financial + thresholdOverride: 0.60` is rejected at
  load time as "override weakens the domain threshold".
- The `reason` field is mandatory. An override without a
  reason is rejected — we want a paper trail for why this
  project is stricter than its peer group.
- Overrides cannot touch the P0 zero-survivor rule. It's not a
  threshold; it's a structural invariant.

---

## 7. What thresholds do NOT do

- They don't set runner timeouts. That's in the runner config.
- They don't pick operators. The default operator set is in
  `mutation-operators.md` §1–§5 and is independent of domain.
- They don't weight operators differently by domain. All
  operators contribute equally to the numerator of
  `mutationScore`; the domain only changes the pass threshold.
  A previous draft of this skill tried per-operator weights and
  they drifted into "whatever felt right today" — the flat
  formula keeps the decisions auditable.
- They don't correlate with line coverage. `coverage-analyzer`
  is a separate skill with its own thresholds; mutation score
  is not a substitute for line coverage and vice versa.

---

## 8. Current threshold config version

**Version: 1**

Bump rules: see §5. Every run records the version in the report
header so historical reports stay interpretable.
