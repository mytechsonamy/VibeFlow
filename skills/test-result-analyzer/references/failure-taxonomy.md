# Failure Taxonomy

`test-result-analyzer` classifies every failure against this
taxonomy at Step 3 of its algorithm. The classification is
deterministic: walk in the declared order and pick the first
matching class. Inventing a class at prompt time is forbidden.

Every class has five fields:

- **id** — stable identifier cited in reports
- **signature** — the pattern that identifies the class: specific
  error text, specific context (retries, cross-run agreement),
  specific source
- **confidence hints** — what pushes confidence above or below
  0.7 (the BUG threshold for ticket generation)
- **typical causes** — concrete code / test patterns that
  produce this class
- **remediation** — what the classification implies the team
  should do next

---

## Walk order

The skill walks in this exact order:

1. `FLAKY`
2. `ENVIRONMENT`
3. `TEST-DEFECT`
4. `BUG`
5. `UNCLASSIFIED`

**Why FLAKY is first.** A failure that's historically flaky or
cross-run-inconsistent is almost certainly not a deterministic
bug — classifying it as `BUG` would generate a ticket against
the wrong root cause. We'd rather miss the rare "real bug in a
flaky test" case than mass-produce tickets for flakes.

**Why BUG is fourth, not first.** Bugs are the RESIDUAL —
what's left after ruling out the other explanations. A failure
that matches the `BUG` signature but also matches `FLAKY`
classifies as `FLAKY`. The walk order encodes the priority of
"most likely root cause" experience: flakes and infra break
tests far more often than product code does.

---

## 1. `FLAKY`

- **id**: `FLAKY`
- **signature**: at least one of the following is true —
  - The failure's `historicalFlake.classification == "flaky"`
    from `ob_track_flaky` (primary signal)
  - `cross-run-consistency` has classified this test as
    non-deterministic in a recent run (stored at
    `.vibeflow/artifacts/consistency/`)
  - The test has `retries > 0` in its runner config AND the
    failure shows `retries > 0` in the result (it took more
    than one attempt to fail)
  - The error message contains a timing-related keyword
    (`timeout`, `deadline exceeded`, `waited N ms`) and the
    baseline duration doesn't normally hit the timeout
- **confidence hints**:
  - 0.95 — both `ob_track_flaky` AND cross-run signal agree
  - 0.85 — one of the two tool signals + retries > 0 evidence
  - 0.70 — only the tool signal, no retries
  - 0.50 — only the timing-keyword heuristic; flagged
    "probable flaky" in the report
- **typical causes**:
  - Timing races with real network / file system
  - Shared mutable state across test files
  - Test data that depends on `Date.now()` / PRNG without
    a pinned seed
  - Resource contention in CI (see the equivalent class in
    `cross-run-consistency/references/non-determinism-taxonomy.md`)
- **remediation**:
  - Run `cross-run-consistency` on the test to confirm and
    classify the root cause
  - If genuinely flaky, tag `@quarantined` in
    `test-strategy.md` and open a human-owned ticket for
    the stability fix (the SKILL won't auto-generate one —
    see `ticket-template.md` §4 for the no-ticket rule)
  - Don't silently add runner retries; retries hide flake

---

## 2. `ENVIRONMENT`

- **id**: `ENVIRONMENT`
- **signature**: at least one of the following is true —
  - The error message contains infrastructure keywords
    (`ECONNREFUSED`, `ENOTFOUND`, `ETIMEDOUT`, `connection
    reset`, `DNS lookup failed`, `no such container`, `port
    already in use`)
  - The failure's source is `chaos-report.md` AND the failure
    corresponds to a component the chaos run was explicitly
    targeting (the failure was caused by the chaos, by
    design, not by a bug)
  - Preflight from `uat-executor` recorded an unhealthy
    component, AND the failure occurred against that
    component
- **confidence hints**:
  - 0.95 — error message names a specific infrastructure
    failure (ECONNREFUSED on a specific port)
  - 0.85 — preflight unhealthy + failure hits same component
  - 0.70 — source is a chaos report + target component
    matches
  - 0.50 — only keyword match; flagged "probable environment"
- **typical causes**:
  - Local dev env out of date
  - Shared dev environment where another engineer is running
    a destructive operation
  - CI runner resource limits
  - Expired credentials
  - DNS / network glitches
- **remediation**:
  - Retry ONCE in the manual path to confirm the environment
    is transient (the skill does NOT auto-retry — the
    retry is for the human investigating)
  - Stand up a fresh environment via `environment-orchestrator`
  - File a NOTE in the backlog ("env is fragile around X")
    rather than a bug ticket
  - Never silently mark an environment failure as "bug" —
    that's how real bugs hide behind infra noise

---

## 3. `TEST-DEFECT`

- **id**: `TEST-DEFECT`
- **signature**: at least one of the following —
  - Error mentions `fixture file not found`, `could not
    parse fixture`, or the test's own imports failing
  - Error is a type error in the test file itself (TypeScript
    compilation error in a `.test.ts` file)
  - Error message contains `unexpected undefined` AND the
    stack trace points into the test body (not the SUT)
  - The test's expected value is hardcoded in a way that
    clearly reflects the current system state (e.g. an
    absolute date "2025-01-01" as an expected value)
  - The test is newly added in the current PR (from `git diff`)
    AND has never passed in the baseline → "new test, not a
    regression"
- **confidence hints**:
  - 0.95 — TypeScript compile error in a test file
  - 0.9 — fixture file missing / malformed
  - 0.8 — test body is in the stack trace
  - 0.6 — new test that hasn't passed yet (could be a real
    bug the new test found, but more often it's a bad test)
- **typical causes**:
  - Refactor that broke a test's imports
  - Fixture file was renamed / moved
  - Test author hardcoded a volatile value
  - A new test that was never verified green before landing
- **remediation**:
  - Fix the test, not the SUT
  - If the test is supposed to catch a real bug, convert it
    to the `BUG` category manually (human decision — the
    skill won't auto-promote)
  - File a NOTE for "new test needs baseline verification"
    when the signal is a fresh test

---

## 4. `BUG`

- **id**: `BUG`
- **signature**: all of the following are true —
  - None of the above classes match
  - The failure is reproducible (same error across N runs OR
    the first run after a clean checkout)
  - The test's expected value is reasonable (not hardcoded to
    the current state)
  - The failure is NOT inside a test file's own code path
    (stack trace points into the SUT, not the test)
- **confidence hints**:
  - 0.95 — reproducible across baseline, test body is
    well-formed, error is in the SUT, matches a PRD rule
  - 0.85 — reproducible, error is in the SUT, no matching
    PRD rule (but the test has an assertion that's clearly
    about a product behaviour)
  - 0.75 — reproducible but only one data point; the scenario
    has been exercised ≥ 2 times with the same failure
  - **0.62 (below the 0.7 ticket threshold)** — the skill
    downgrades this to `NEEDS_HUMAN_TRIAGE` and flags it
    as "probable BUG"; this is the structural safety net
    that keeps low-confidence tickets from spamming the
    backlog
- **typical causes**:
  - The SUT has a real defect against a documented rule
  - A regression against a previously-passing baseline
  - An off-by-one in newly added code paths
- **remediation**:
  - Generate a ticket via `ticket-template.md`
  - Link to the PRD requirement + the failing scenario
  - Let `learning-loop-engine` track how often this recurs

### What the BUG class is NOT allowed to do

- It cannot be the first match. The walk order puts it fourth
  so everything else gets a chance to classify first.
- It cannot inherit confidence from a parent class. Confidence
  is computed fresh from the signature's evidence signals.
- It cannot be auto-promoted from another class via
  `test-strategy.md` overrides. Overrides can only demote
  `BUG` → one of the other classes (see
  `test-result-analyzer/SKILL.md` §Step 5).

---

## 5. `UNCLASSIFIED`

- **id**: `UNCLASSIFIED`
- **signature**: none of the above match
- **confidence hints**: always 0.0
- **typical causes**: a class this file doesn't yet cover
- **remediation**:
  - Surface the finding in the report with the full failure
    context
  - File a PR to extend this taxonomy
  - Do NOT silently absorb the finding into one of the other
    classes — wrong classification is worse than "unknown"

**`UNCLASSIFIED` is a taxonomy-gap signal, not a failure state.**
A few `UNCLASSIFIED` findings in an otherwise-classified run
are fine — the skill flags them and moves on. But if more than
20% of failures classify as `UNCLASSIFIED`, the whole run
blocks with "taxonomy needs extension". The 20% threshold is
the structural rule that keeps taxonomy drift from silently
accumulating.

---

## 6. Classification is walk-order-first, signature-match-first

The skill does NOT weigh evidence across all classes and pick
the "best match". It walks in order and picks the first match.
Two classes that both match a failure resolve to the earlier
class in the walk, not to whichever has higher confidence.

**Why:** this keeps classification stable across runs. A
failure that matches both `FLAKY` and `ENVIRONMENT` might
"obviously" feel like one or the other, but different runs
with slightly different evidence could flip the
confidence-weighted pick. Walk order is deterministic; the
cost is occasional suboptimal classification, the benefit is
that the team can trust "flaky = flaky" across the whole
history.

---

## 7. Adding a new class

1. Pick a stable id (SCREAMING-KEBAB-CASE, specific).
2. Write a signature that's mechanically checkable (grep or
   simple AST walk). If the signature needs a parser, the
   class is too vague.
3. Document confidence hints for at least three values.
4. List at least three typical causes.
5. Provide concrete remediation — never "improve the test".
6. Update the walk order in §Walk Order. New classes are
   inserted in specificity order (more specific → earlier).
7. Update the integration harness sentinel that counts
   taxonomy classes.
8. Retrospective on at least 5 historical failures that the
   new class would have classified differently. No
   retrospective → no class.

---

## 8. Deprecation

Never delete a class. Old reports reference these ids.
Deprecate with `deprecated: true` in the header; old reports
stay interpretable.

No deprecated classes yet — this is the first version.
