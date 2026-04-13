---
name: test-result-analyzer
description: Classifies test failures into bug / flaky / environment / test-defect, links each failure back to its RTM requirement, and generates ready-to-import backlog tickets for the real bugs. Consumes uat-raw-report.md or raw runner JSON via ob_collect_metrics. Gate contract — every failure is classified (no UNCLASSIFIED leaks to downstream), every 'bug' classification has a confidence ≥ 0.7, every generated ticket traces back to a scenario id. PIPELINE-5 step 4 / PIPELINE-6 step 3.
allowed-tools: Read Write Grep Glob
context: fork
agent: Explore
---

# Test Result Analyzer

An L2 Truth-Execution skill. Where `regression-test-runner` tells
you **whether** tests failed and `cross-run-consistency` tells you
**whether they agree with themselves**, this skill tells you
**why** each failure happened and **what to do about it**. It
turns a pile of red into a classified pile, and the classification
is what downstream tools (`release-decision-engine`,
`learning-loop-engine`) use to decide if a failure is a ship-
blocker or an operational nuisance.

The most common failure mode of a result analyzer is silently
dropping failures into a "we'll figure it out later" bucket. This
skill's gate contract is specifically designed to prevent that —
**no failure leaves the classification step without a label**, and
every label with low confidence is surfaced for human triage
rather than auto-ticketed as a bug.

## When You're Invoked

- **PIPELINE-5 step 4** — after `regression-test-runner` and
  `uat-executor` have produced their raw outputs, before
  `release-decision-engine` computes its verdict. The decision
  engine reads the classified failure set from this skill's
  output, not the raw reports.
- **PIPELINE-6 step 3** — same position in the release-track
  pipeline, after the full regression + chaos runs.
- **On demand** as
  `/vibeflow:test-result-analyzer <report-path-or-glob>`.

## Input Contract

| Input | Required | Notes |
|-------|----------|-------|
| Primary report | yes | Exactly ONE of: `uat-raw-report.md` / `regression-report.md` / `chaos-report.md` / a raw runner JSON path. Mixed inputs are NOT supported in a single run — the skill refuses a glob that resolves to multiple formats. |
| `scenario-set.md` | optional but preferred | Drives the scenario-id → PRD anchor mapping. Without it, failures can still be classified but can't be RTM-linked and the report flags the RTM gap. |
| `rtm.md` | optional but preferred | The Requirements Traceability Matrix. When present, the skill walks scenario → PRD requirement → downstream ticket field. |
| `regression-baseline.json` | optional | Supplies priority tags (P0/P1/…) used for the ticket severity mapping. |
| `observability` MCP | optional | `ob_track_flaky` is consulted during classification — a failure that historically flakes is classified `flaky` with higher confidence than a one-shot test. |
| `test-strategy.md` | optional | Declares project-specific classification overrides (e.g. "timeouts > 30s on integration tests default to `environment`, not `bug`"). |

**Hard preconditions** — refuse rather than emit classifications
downstream should not trust:

1. At least one failure must be parseable from the primary
   report. A report with zero failures → "clean run, nothing to
   analyze" — the skill emits an empty `test-results.md` with a
   banner and exits 0. This is NOT a block, just a no-op.
2. Every failure must have an identifiable `testId` (`<file>::<name>`
   convention). A failure with no stable id blocks the run with
   remediation "runner output missing test id; check the
   reporter config".
3. The taxonomy must have at least one class with a matching
   signature for every failure. See §Step 3 for the
   handling of the UNCLASSIFIED class.

## Algorithm

### Step 1 — Ingest the primary report
Detect the format from the input path / extension / first line:

- `.md` starting with `# UAT Raw Report` → `uat-raw-report.md`
  parser (see `uat-executor/references/report-schema.md` for
  the frozen shape)
- `.md` starting with `# Regression Report` → `regression-report.md`
  parser (from `regression-test-runner`'s output contract)
- `.md` starting with `# Chaos Report` → `chaos-report.md`
  parser (from `chaos-injector`'s output contract)
- `.json` → raw runner JSON, parsed via
  `ob_collect_metrics` into `NormalizedRun` shape

**Mixed inputs are rejected.** A glob that resolves to an
`uat-raw-report.md` + a `chaos-report.md` blocks with remediation
"run the analyzer once per report; mixing is not supported in
v1". The reason is classification — different report formats
expose different signals, and a unified failure set would
silently prefer one format's signals over another.

### Step 2 — Normalize to `Failure` records
Every ingested failure becomes a canonical record:

```ts
interface Failure {
  id: string;                  // `<file>::<name>::<runId>`
  testId: string;              // `<file>::<name>` — the RTM key
  scenarioId: string | null;   // SC-xxx when resolvable
  priority: "P0" | "P1" | "P2" | "P3" | "unknown";
  status: "failed" | "error" | "timeout" | "not-reached";
  errorMessage: string | null;
  stackTrace: string | null;
  duration: number | null;
  retries: number;             // 0 if runner doesn't track
  source: {                    // where the failure came from
    report: "uat" | "regression" | "chaos" | "runner-json";
    path: string;
    line: number | null;
  };
  historicalFlake: {           // from ob_track_flaky when available
    score: number;             // 0..1
    classification: "flaky" | "stable" | "regressing" | "unknown";
  } | null;
}
```

**Every field is resolved at ingest time, not lazily.** A field
that can't be resolved (e.g. `scenarioId` when the primary report
doesn't reference scenario ids) is set to `null` explicitly. No
implicit defaults.

### Step 3 — Classify each failure
Walk `references/failure-taxonomy.md` in the declared order for
every `Failure` record:

1. `BUG` — the system under test produced a wrong answer
2. `FLAKY` — the test sometimes passes and sometimes fails
   without a code change
3. `ENVIRONMENT` — the test failed because the environment
   was in a bad state (db down, network partition, clock skew)
4. `TEST-DEFECT` — the test itself is wrong (bad assertion,
   stale fixture, broken setup)
5. `UNCLASSIFIED` — none of the above match

Every classification carries:
- `class` — the id above
- `confidence` — `[0, 1]`
- `rationale` — plain text (≤ 200 chars) explaining why
- `signals` — the specific evidence pointers that matched

**Low-confidence `BUG` classifications are downgraded.** A
failure classified as `BUG` with `confidence < 0.7` is
re-classified as `NEEDS_HUMAN_TRIAGE` for the purposes of
ticket generation — the report still shows `probable BUG
(confidence 0.62)` in the label, but the skill doesn't auto-
generate a ticket for it. This is the gate-relevant downgrade
(see §Gate Contract).

**`UNCLASSIFIED` is a taxonomy-gap signal.** A single
`UNCLASSIFIED` finding is acceptable — it goes into the report
with full context for human triage. More than 20% of failures
classifying as `UNCLASSIFIED` blocks the run with "taxonomy
needs extension before this report can be trusted".

### Step 4 — Link failures to RTM requirements
When `scenario-set.md` and `rtm.md` are both present, walk every
failure and resolve:

- `testId` → `scenarioId` (via `scenario-set.md`'s `tests:`
  field on each scenario)
- `scenarioId` → PRD requirement id (via `rtm.md`'s linkage
  matrix)

Failures without a resolvable requirement are NOT silently
dropped. They're recorded with `requirement: null` and a
`rtmGap: true` flag so the report surfaces them as "no
requirement coverage recorded". A P0 failure with no
requirement link is a SECOND gate signal (see §Gate Contract
point 3).

### Step 5 — Apply `test-strategy.md` overrides
Some projects have structural knowledge that individual
failures can't encode. `test-strategy.md` can declare:

```yaml
testResultAnalyzer:
  overrides:
    - pattern: "*.test.ts::*"
      when: "duration > 30000"
      classification: environment
      rationale: "integration tests timing out past 30s always reflect env pressure here"
```

Rules:

- Overrides are applied AFTER the base classification, so a
  reviewer can see both what the skill would have said and
  what the override did. Both are in the report.
- Overrides can only demote a `BUG` classification to
  `FLAKY` / `ENVIRONMENT` / `TEST-DEFECT`. They cannot PROMOTE
  a `TEST-DEFECT` to `BUG` — that's a human decision, not a
  config one.
- Overrides must include a `rationale` field. Unmotivated
  overrides are rejected at config load.

### Step 6 — Compute per-report aggregates
```
totalFailures            = failures.length
byClass                  = { BUG: N, FLAKY: N, ENVIRONMENT: N, TEST-DEFECT: N, UNCLASSIFIED: N }
p0Bugs                   = failures where class == "BUG" && priority == "P0"
bugsWithLowConfidence    = failures where class == "BUG" && confidence < 0.7
failuresWithoutRtmLink   = failures where requirement == null
unclassifiedPercent      = byClass.UNCLASSIFIED / totalFailures
```

### Step 7 — Generate tickets for real bugs
For every failure classified `BUG` with `confidence >= 0.7`:

1. Load `references/ticket-template.md` for the ticket shape.
2. Fill in every field from the normalized `Failure` record.
3. Set `severity` from the failure's `priority`: P0 → `critical`,
   P1 → `high`, P2 → `medium`, P3 → `low`.
4. Emit the ticket to `.vibeflow/reports/bug-tickets.md` with a
   stable id (`BUG-<date>-<short-hash>`) so re-runs don't
   duplicate existing tickets — see §8 for dedup.

Failures classified as `FLAKY`, `ENVIRONMENT`, `TEST-DEFECT`,
`UNCLASSIFIED`, or `NEEDS_HUMAN_TRIAGE` do NOT produce tickets.
They appear in `test-results.md` but the backlog integration
only sees real bugs. This is the main reason classification
matters — it's how "red in CI" turns into "tickets the team
should actually work on".

### Step 8 — Deduplicate tickets across runs
Load `.vibeflow/artifacts/test-results/ticket-history.jsonl` if
it exists. For every candidate new ticket:

1. Hash the (testId + classification + error signature) into a
   stable `dedupKey`.
2. If the `dedupKey` matches an existing ticket's first 16 chars
   of `dedupKey`, do NOT create a new ticket — append the new
   run id to the existing ticket's `occurrences` list instead.
3. Record every new ticket (and every occurrence update) in
   the history file.

**Tickets are append-only in history.** Closing a ticket is a
human action in the backlog tool; the history just remembers
"we observed this on these runs". A closed ticket that
reappears generates a NEW ticket with a `supersedes: <old-id>`
link, so the team can tell the difference between "regression"
and "we forgot to close this".

### Step 9 — Write outputs

1. **`.vibeflow/reports/test-results.md`** — human + machine-
   readable classified failure set (see output contract below)
2. **`.vibeflow/reports/bug-tickets.md`** — append-only backlog
   file with `dedupKey` headers per ticket; consumed by
   `learning-loop-engine` and by a human bot that imports into
   the real backlog tool
3. **`.vibeflow/artifacts/test-results/<runId>/failures.json`**
   — the full normalized `Failure` set including classification
   metadata, for `release-decision-engine` to read
4. **`.vibeflow/artifacts/test-results/ticket-history.jsonl`**
   — append-only dedup history

## Output Contract

### `test-results.md`
```markdown
# Test Results — <runId>

## Header
- Run id: <runId>
- Source: uat-raw-report.md | regression-report.md | chaos-report.md | runner-json
- Source path: <path>
- Scenarios matched: S
- Total failures: T

## Classification summary
| Class | Count | % |
|-------|-------|---|
| BUG | a | X% |
| FLAKY | b | Y% |
| ENVIRONMENT | c | Z% |
| TEST-DEFECT | d | W% |
| UNCLASSIFIED | e | V% |
| NEEDS_HUMAN_TRIAGE (low-confidence BUG) | f | U% |

## Gate signals
- P0 bugs (confidence ≥ 0.7): N
- Low-confidence bug candidates: M
- Unclassified percentage: P% (threshold: 20%)
- P0 failures without RTM link: Q
- Verdict: PASS | NEEDS_REVISION | BLOCKED

## Bug failures (tickets auto-generated)
### <testId>
- Failure id: <id>
- Priority: P0
- Scenario: SC-112
- Requirement: PRD-§3.2
- Class: BUG (confidence 0.88)
- Rationale: "same test deterministic-fails across N runs with the same error; not flaky"
- Ticket: BUG-2026-04-13-a4c9
- Error: <first 200 chars>

## Non-bug failures (no tickets)
<same shape grouped by class>

## NEEDS_HUMAN_TRIAGE (low-confidence bugs)
### <testId>
- Class: probable BUG (confidence 0.62)
- Rationale: "error message looks like an assertion but the test has retry=2 in its config"
- Suggested next step: run cross-run-consistency on this test
```

### `bug-tickets.md` (excerpt)
```markdown
# Bug Tickets — generated by vibeflow:test-result-analyzer

## BUG-2026-04-13-a4c9
- **dedupKey**: `<hash>`
- **Title**: Login fails with 404 on /api/session for expired tokens
- **Severity**: critical
- **Priority**: P0
- **Scenario**: SC-112
- **Requirement**: PRD-§3.2
- **Occurrences**: runId=20260413-120000 (first), runId=20260413-140000

### Steps to reproduce
1. POST /api/session with an expired token
2. Observe the response

### Expected
404 with `{ "error": "token_expired" }` body

### Actual
404 with empty body; client crashes on response parse

### Evidence
- `uat-raw-report.md#SC-112`
- `.vibeflow/artifacts/uat/20260413-120000/screenshots/SC-112-3.png`
- Stack trace: <captured>
```

## Gate Contract
**Three invariants:**

1. **No `UNCLASSIFIED` leaks to downstream.** A run with more
   than 20% of failures classifying as `UNCLASSIFIED` is
   BLOCKED — the taxonomy has a gap and trusting the report
   would bury real bugs.
2. **Every `BUG` classification has `confidence >= 0.7`.** Lower-
   confidence bug candidates are auto-downgraded to
   `NEEDS_HUMAN_TRIAGE` and surfaced in the report but NOT
   auto-ticketed. This is a structural rule — the tickets file
   is only allowed to contain classifications the skill is
   sure enough about to ship to a human backlog.
3. **Every generated ticket traces back to a scenario id.** A
   `BUG`-classified failure with no `scenarioId` blocks ticket
   generation for THAT failure (the failure still appears in
   the results report with an RTM-gap flag), AND if more than
   one P0 failure lacks RTM coverage the whole run is BLOCKED
   with reason `rtmGap`. The point is that bugs in load-bearing
   paths must be linkable to the requirement they violate.

Verdict:

| Condition | Verdict |
|-----------|---------|
| `unclassifiedPercent <= 20% && p0BugsWithoutRtm <= 0` | PASS |
| `unclassifiedPercent <= 20% && p0BugsWithoutRtm > 0` | NEEDS_REVISION (or BLOCKED if `p0BugsWithoutRtm > 1`) |
| `unclassifiedPercent > 20%` | BLOCKED |

No override flag. A project that genuinely has a class of
failures the taxonomy can't classify must extend
`failure-taxonomy.md`, not flag around this skill.

## Non-Goals
- Does NOT fix bugs.
- Does NOT run tests (`regression-test-runner` / `uat-executor`).
- Does NOT write real backlog API calls (it emits tickets to a
  file; a separate bot imports them into Linear / Jira / GitHub
  Issues).
- Does NOT deduplicate across different `testId`s. A flaky test
  that presents as two different error messages is still
  classified as one flake — but if the TESTS are different,
  they get different tickets.
- Does NOT promote classifications. Overrides can only demote
  `BUG` → `FLAKY/ENVIRONMENT/TEST-DEFECT` — promoting a
  `TEST-DEFECT` to `BUG` is a human decision.

## Downstream Dependencies
- `release-decision-engine` — reads `failures.json` for the
  `p0Bugs` count and `unclassifiedPercent` as hard blocker
  signals; feeds the weighted quality score.
- `learning-loop-engine` — ingests `bug-tickets.md` history to
  spot recurring failure shapes across runs / branches / time.
- `traceability-engine` — uses the requirement-link field to
  keep the RTM current ("these scenarios have a known failure").
- `test-priority-engine` — uses the classified-flake set to
  exclude `flaky`-classified tests from the `known-good` pool
  when computing affected-set risk.
