# UAT Raw Report Schema

The shape of `uat-raw-report.md` is frozen here because three
downstream skills depend on it:

- `test-result-analyzer` — parses the Scenario results block into
  its classified failure set
- `observability-analyzer` — reads timing data from the per-step
  log to feed `ob_perf_trend`
- `release-decision-engine` — reads the Summary block's counts as
  hard blocker signals

Drift in this file is a breaking change. Schema version must bump
whenever a field is added, removed, or re-purposed, and every
downstream consumer must be updated in the same commit.

**Current schema version: 1**

---

## 1. File layout

Every `uat-raw-report.md` has exactly four sections, in this
order: Header, Summary, Scenario results, Notes. Downstream
parsers depend on the order. Do NOT reorder; add new sections only
at the end.

### 1.1 Header
```markdown
# UAT Raw Report — <runId>

## Header
- Run id: <runId>
- Env: <envName> (<envUrl>)
- Started: <ISO-8601>
- Finished: <ISO-8601>
- Operator: <user id or "ci">
- Scenario set: <scenario-set.md path>@<gitSha>
- Executor: uat-executor@<version>
- Schema version: 1
- Finalization: finalized | partial:<reason>
```

Every field is required. `Finalization` has exactly two forms:
`finalized` (gate-passing) or `partial:<reason>` where `<reason>`
is one of `evidenceMissing`, `p0NotExecuted`, `humanStepsSkipped`,
`halted`, or a free-form reason prefixed with a colon. Downstream
parsers fail hard on any other finalization string — drift there
would quietly let an unhealthy run sail through the gate.

### 1.2 Summary
```markdown
## Summary
- Scenarios executed: N
- P0 scenarios executed: a / b
- Passed: p
- Failed: f
- Blocked: b
- Not reached (halted): nr
- Skipped (non-interactive): sni
- evidenceMissing: <count>
- Duration total: <ms>
```

Count consistency invariant (enforced at write time):
`passed + failed + blocked + notReached + skippedNoninteractive == scenariosExecuted`.
If the numbers don't add up, the skill refuses to write the
report and prints a stack trace — arithmetic drift is always a
skill bug, not a data bug.

### 1.3 Scenario results

One `### <scenarioId>` subsection per scenario, in execution order.

```markdown
### SC-112: user completes checkout (P0) — PASSED
- Duration: 14.2s
- Steps: 7 passed, 0 failed, 0 blocked
- Halt: —
- Evidence: —

### SC-113: user sees error on expired coupon (P0) — FAILED
- Duration: 6.8s
- Steps: 2 passed, 1 failed, 4 not-reached
- Halt: scenario halted after step 3 (P0 failure)
- Failing step: #3 (automated) — "apply expired coupon"
  - Expected: `.coupon-error` visible
  - Actual: 404 on /api/coupons
  - Screenshot: screenshots/SC-113-3.png
  - Runner output: per-step.jsonl#L42-L58
```

Each scenario subsection has:
- A title line: `### <scenarioId>: <title> (<priority>) — <VERDICT>`
  where verdict is `PASSED | FAILED | BLOCKED | NOT-REACHED`
- Duration line
- Steps summary line with four counts: passed, failed, blocked,
  not-reached
- Halt line: either `—` or a reason string
- For failed scenarios: one `Failing step: #N (type) — "description"`
  line followed by indented evidence bullets

Parsers downstream use a regex on the title line and key-value
pairs on the bullet lines. Keep the column layout consistent — no
tabs, two-space indent on bullet continuations.

### 1.4 Notes
```markdown
## Notes
- <free-text operator note>
- <additional context>
```

Free-form, optional. Parsers ignore this section — it exists for
humans reading the report and shouldn't encode machine-readable
state.

---

## 2. `per-step.jsonl`

One JSON object per line, UTF-8, newline-terminated. Written
incrementally during the run so a crash leaves a parseable log.

```json
{
  "schemaVersion": 1,
  "runId": "20260413-120000-abc1234",
  "scenarioId": "SC-113",
  "stepIndex": 3,
  "stepType": "automated",
  "startedAt": "2026-04-13T12:03:15.120Z",
  "finishedAt": "2026-04-13T12:03:18.400Z",
  "durationMs": 3280,
  "status": "failed",
  "expected": ".coupon-error visible",
  "actual": "404 on /api/coupons",
  "evidence": {
    "screenshot": "screenshots/SC-113-3.png",
    "stdoutTailLines": 40,
    "stdoutPath": "per-step/SC-113-3.stdout",
    "stderrPath": "per-step/SC-113-3.stderr"
  },
  "note": null
}
```

Field rules:

- **schemaVersion** — always `1` for this version. Downstream
  parsers hard-fail on unexpected versions; there is no implicit
  upgrade path.
- **runId** — same `runId` for every line in the file.
- **scenarioId + stepIndex** — stable within a scenario; index
  is 0-based and refers to the scenario's `steps` list in
  `scenario-set.md`.
- **stepType** — one of `automated | human | probe`.
- **status** — one of
  `passed | failed | blocked | not-reached | skipped-noninteractive | cancelled`.
- **expected / actual** — strings, both required for `failed`,
  required for `passed` on automated steps (you must name the
  assertion that passed), optional for `passed` on human steps.
- **evidence** — object whose shape depends on stepType; see §3
  below. Absent on human-passed steps.
- **note** — operator-supplied free text; mandatory for failed
  human steps, null otherwise.
- **Mid-run corrections**: if a step needs correction after write
  (operator re-runs manually, amends a note), a new line is
  appended with `"supersedes": <original stepIndex>` and a
  timestamp. Lines are NEVER edited in place.

---

## 3. Evidence shapes per step type

### 3.1 Automated step
```json
"evidence": {
  "screenshot": "<relative path or null>",
  "stdoutPath": "<relative path>",
  "stderrPath": "<relative path>",
  "stdoutTailLines": <number, 0 on success if no tail captured>,
  "runnerExitCode": <int>
}
```

`screenshot` is required on failed status, null on passed.

### 3.2 Human step
```json
"evidence": {
  "prompt": "<the prompt text shown to the operator>",
  "operatorId": "<user id>",
  "responseTimeMs": <number>,
  "attachments": ["<optional screenshot path>"]
}
```

Operator note (mandatory on failed) lives at the top-level
`note` field, not inside `evidence`, so downstream parsers can
cheaply inspect the note without pulling evidence.

### 3.3 Probe step
```json
"evidence": {
  "probeType": "http|json|metric",
  "url": "<probed url>",
  "rawOutputPath": "<truncated 2KB>",
  "decisionReason": "<why the assert passed or failed>"
}
```

Probes never carry screenshots (nothing to screenshot) or operator
notes (nobody to ask).

---

## 4. Schema evolution

- **Bumping `schemaVersion`**:
  1. Update this file (every §1, §2, §3 table edit) and bump
     the "Current schema version" line at the top.
  2. Update the consumer skills — every parser must support the
     new version before any producer writes it.
  3. Update `uat-executor/SKILL.md` to write the new version in
     the `run-metadata.json` + `schemaVersion` field.
  4. Update the integration harness sentinel to expect the new
     version string.
- **Additive-only fields**: new fields must be optional, with a
  documented default, so existing reports stay readable.
- **Never reuse a field name.** If a field is removed, the name
  stays reserved forever.
- **Never silently coerce types.** A parser that sees a string
  where it expected a number must error, not coerce.

---

## 5. Downstream consumer contracts

### test-result-analyzer
- Reads `## Summary` counts for its classified failure tally.
- Reads `### <scenarioId>` titles and `Failing step:` lines for
  its failure detail view.
- Depends on: Header `Finalization`, Summary counts, Scenario
  title line, Failing step line.

### observability-analyzer
- Reads `per-step.jsonl` line-by-line, filtering for
  `stepType=automated && status in (passed,failed)` to build the
  duration distribution that feeds `ob_perf_trend`.
- Depends on: `durationMs`, `scenarioId`, `stepIndex`,
  `schemaVersion`.

### release-decision-engine
- Reads `## Summary` for `evidenceMissing`, `P0 scenarios
  executed`, and the `Finalization` state.
- Hard-blocks a GO verdict on `Finalization != finalized` OR
  `evidenceMissing > 0` OR `P0 scenarios executed != P0 total`.
- Depends on: Header `Finalization`, Summary three counts above.

### traceability-engine
- Reads scenario ids from the Scenario results block and joins
  them to PRD anchors via `scenario-set.md`.
- Depends on: Scenario title line's `<scenarioId>:` prefix.

---

## 6. Breaking-change checklist

Before changing this file, confirm:

- [ ] Every downstream consumer listed in §5 has been updated.
- [ ] The schemaVersion is bumped (and the bump is in THIS
      commit, not a follow-up).
- [ ] The integration harness sentinel for the schema version
      is updated.
- [ ] A migration note lands in the PR description (not just
      "bumped schema" — include an example old/new report).
- [ ] The old version stays readable — if a parser needs to
      handle both versions, that's encoded in the consumer, not
      in this file.
