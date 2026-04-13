---
name: observability-analyzer
description: Parses HAR files, Playwright traces, browser console logs, and Chrome DevTools Protocol exports, detects anomalies against a fixed catalog, and emits observability-report.md. Complementary to the observability MCP (which tracks cross-run metrics) — this skill looks at the artifacts a single run produced. Gate contract — zero critical anomalies in P0 scenarios, no console errors above the severity threshold, web vitals meet the domain budget. PIPELINE-5 step 6 / PIPELINE-6 step 5.
allowed-tools: Read Write Grep Glob
context: fork
agent: Explore
---

# Observability Analyzer

An L2 Truth-Execution skill. Where the `observability` MCP is a
**cross-run** tracker (flakiness over time, metric trends, pass
rate history), this skill is the **per-run** complement — it
opens one run's artifacts (HAR files, Playwright traces,
browser console dumps, CDP exports) and produces a report that
points at specific anomalies: slow requests, failed dependencies,
console errors, performance-budget breaches.

Per-run observability is where release decisions catch the
"yeah the tests passed but look at the network waterfall"
class of regression. The cross-run tool wouldn't see that — it
only watches pass/fail + duration.

## When You're Invoked

- **PIPELINE-5 step 6** — after `uat-executor` has driven a
  scenario set against staging and left trace artifacts; the
  skill reads the traces + surfaces the anomalies before
  `release-decision-engine` weighs them.
- **PIPELINE-6 step 5** — pre-release, same position.
- **On demand** as
  `/vibeflow:observability-analyzer <artifact-path>`.
- **From `release-decision-engine`** when a CONDITIONAL
  verdict needs fresh observability signals before shipping.

## Input Contract

| Input | Required | Notes |
|-------|----------|-------|
| Artifact path | yes | A directory, a file glob, or a single file. Must resolve to at least one supported source. |
| `scenario-set.md` | optional but preferred | Needed to map traces to scenarios for the P0 rule. Without it, anomalies still surface but can't be gate-linked to priorities. |
| Domain config | yes | `vibeflow.config.json → domain`. Drives the web-vitals budget + severity thresholds from `references/anomaly-rules.md`. |
| Performance budgets | optional | `test-strategy.md → performanceBudgets` — project-specific overrides for the domain defaults (strictly tighter, never looser). |
| Runtime context | optional | Which test run produced these traces (from the trace metadata or passed in via `--runId`). Used for reports that need to cross-link to `uat-raw-report.md`. |

**Hard preconditions** — refuse rather than emit anomalies that
downstream can't trust:

1. At least one artifact must parse cleanly. An input that
   resolves to zero parseable sources blocks with "no
   supported sources found at <path>; check HAR / trace /
   console / cdp extensions".
2. The scenario set (when present) must name at least one
   scenario the current traces could map to. A scenario set
   that references scenarios the traces don't cover is
   flagged as `traceScenarioDrift` in the report.
3. Domain-specific tight budgets (financial / healthcare) MUST
   have a `performanceBudgets` declaration. Those domains
   don't accept the default web-vitals budget because it's
   tuned for marketing pages; the skill blocks with "declare
   performance budgets in test-strategy.md".

## Algorithm

### Step 1 — Detect + parse each source
Walk every file the artifact path resolved to. For each,
detect the format and dispatch to the parser in
`references/source-parsers.md`:

- `.har` → HAR 1.2 parser (HTTP Archive format)
- `*.trace.zip` or `trace.json` → Playwright trace parser
- `console.json` / `console.log` → Browser console parser
- `*.cdp.json` → Chrome DevTools Protocol parser
- Other extensions → recorded as "unsupported source" and
  skipped (the file stays in the artifact directory but the
  report notes it; silently dropping unsupported files would
  hide data)

Every parsed source produces zero or more `TraceEvent` records
that feed the next step. Parser failures are NOT silent — a
malformed HAR produces a blocker finding for that file with
remediation "regenerate the HAR; the recorder truncated it".

### Step 2 — Normalize to TraceEvent
Every source format flattens into the same event shape:

```ts
interface TraceEvent {
  id: string;                 // "<source-file>::<index>"
  source: "har" | "playwright" | "console" | "cdp";
  kind: "request" | "response" | "console" | "js-task" | "paint" | "navigation" | "exception";
  timestamp: string;          // ISO-8601
  durationMs: number | null;
  request: { url: string; method: string; size: number } | null;
  response: { status: number; size: number; mimeType: string } | null;
  message: string | null;     // for console / exception
  level: "debug" | "info" | "warn" | "error" | null;
  stackTrace: string | null;
  metricName: string | null;  // for paint/navigation: LCP, FCP, CLS, etc.
  metricValue: number | null;
  scenarioId: string | null;  // resolved from scenario-set.md when possible
  priority: "P0" | "P1" | "P2" | "P3" | "unknown";
}
```

The `scenarioId` + `priority` fields are filled in Step 4;
the parser leaves them null.

### Step 3 — Build the network waterfall (when HAR is present)
HAR sources get a waterfall reconstruction:

1. Sort requests by `startedDateTime`
2. Identify the longest chain via `dependsOn` (the request
   that can only start after another completes)
3. Surface the total duration of the critical path AS the
   page's observed load time
4. Flag requests on the critical path whose individual
   duration > `p95` for their content type (CSS/JS/image/etc.)

The waterfall is recorded in the report as a hierarchical
table — the longest chain is named explicitly, and branching
requests are listed by content type.

### Step 4 — Link events to scenarios
For every TraceEvent, attempt to resolve:

- `scenarioId` — from the Playwright trace metadata (where
  each spec declares which SC-xxx it maps to), from the HAR
  filename pattern (`SC-112-har.har`), or from a
  per-artifact `scenario-map.json` index file
- `priority` — from the scenario set, once the `scenarioId`
  is known; P0 for P0 scenarios, etc. Unresolved `priority`
  defaults to `unknown` (score 0.3 in gap rollups)

Events that can't be linked to a scenario are NOT dropped;
they appear in the report under `Unlinked events` so they're
still auditable. The report surfaces the unlinked count as
a signal ("N% of events couldn't be linked") so operators
know how much context is missing.

### Step 5 — Detect anomalies via the catalog
Walk `references/anomaly-rules.md` in declared order. For
every TraceEvent, check each rule's signature against the
event (and the event's surrounding context when needed):

- `NET-FAIL-*` — request/response failure rules
- `NET-SLOW-*` — request taking too long
- `CONSOLE-*` — console.error / console.warn with severity
  classification
- `JS-LONG-TASK` — main-thread blocking above the budget
- `WEB-VITALS-*` — LCP / CLS / FID / INP breaches
- `SECURITY-*` — mixed content, CSP violations, insecure
  cookies
- `THIRD-PARTY-*` — failures in third-party resources that
  block the main thread

Every finding records:
- `rule` — the catalog rule id
- `severity` — `critical / warning / info` (from the catalog
  entry)
- `confidence` — 0..1
- `scenarioId` + `priority` — inherited from the TraceEvent
- `evidence` — pointer back to the source file + event index

### Step 6 — Apply the gate

| Condition | Verdict |
|-----------|---------|
| Zero `critical` findings AND no P0 `warning` findings breach the budget AND web vitals meet the domain budget | PASS |
| Zero `critical` findings AND no P0 `warning` findings breach the budget BUT a web-vital is within the close-miss band | NEEDS_REVISION |
| Any `critical` finding OR any P0 `warning` finding OR any web-vital below the close-miss floor | BLOCKED |

**Gate contract: zero critical anomalies in P0 scenarios, no
console errors above the severity threshold, web vitals meet
the domain budget.** Critical anomalies always block; web
vital close-misses escalate to NEEDS_REVISION.

Close-miss band: within 10% of the budget. A LCP budget of
2.5s puts the close-miss floor at 2.75s — above that, BLOCKED.

### Step 7 — Aggregate + dedupe findings
Findings from the same rule against the same scenarioId +
resource + error shape dedupe into one entry with an
`occurrences` counter. The report shows each unique finding
once with its occurrence count, not one row per repetition.

Dedup key: `rule :: scenarioId :: resource :: errorSignature`
where `errorSignature` is the first line of the message with
numbers and UUIDs masked (same pattern as
`test-result-analyzer`).

### Step 8 — Write outputs

1. **`.vibeflow/reports/observability-report.md`** — the
   human-readable report with waterfall + anomaly sections +
   summary verdict
2. **`.vibeflow/artifacts/observability/<runId>/events.jsonl`**
   — every normalized TraceEvent, append-only for post-mortem
3. **`.vibeflow/artifacts/observability/<runId>/findings.json`**
   — deduplicated anomaly findings with severity + priority
4. **`.vibeflow/artifacts/observability/<runId>/waterfall.json`**
   — per-scenario waterfall reconstruction

## Output Contract

### `observability-report.md`
```markdown
# Observability Report — <runId>

## Header
- Run id: <runId>
- Sources parsed: N (HAR: a, Playwright: b, console: c, CDP: d)
- Unsupported sources: u
- Events normalized: E
- Scenarios linked: S / unlinked: U
- Domain: financial
- Verdict: PASS | NEEDS_REVISION | BLOCKED

## Summary
- Critical findings: c (gate-blocking if > 0)
- Warning findings: w (gate-blocking on P0 scenarios)
- Info findings: i
- Web vitals: LCP=X.Xs CLS=X.X INP=X.Xms
- Web vitals verdict: PASS / NEEDS_REVISION / BLOCKED

## Critical findings
### NET-FAIL-401 on SC-112 (P0)
- Priority: P0
- Scenario: SC-112
- Evidence: uat-har/SC-112.har#request-42
- Message: 401 Unauthorized on /api/profile
- Occurrences: 3 (deduplicated)
- Rule: NET-FAIL-401 (catalog)
- Suggestion: authentication drifted mid-scenario; check token refresh

## Web vitals
| Metric | Value | Budget | Verdict |
|--------|-------|--------|---------|
| LCP | 2.8s | 2.5s | close-miss (NEEDS_REVISION) |
| CLS | 0.05 | 0.1 | PASS |
| INP | 250ms | 200ms | close-miss |

## Network waterfall (longest chain)
| Depth | Request | Duration | Status |
|-------|---------|----------|--------|
| 0 | GET / | 400ms | 200 |
| 1 | GET /api/bootstrap | 1200ms | 200 |
| 2 | GET /api/user | 800ms | 200 |

Critical path total: 2.4s

## Unlinked events
- N events had no resolvable scenarioId
  - Usually means the trace doesn't carry scenario metadata
  - Suggestion: emit SC-xxx in Playwright's `testInfo.annotations`
```

## Gate Contract
**Zero critical anomalies in P0 scenarios, no console errors
above the severity threshold, web vitals meet the domain
budget.** Three ways to violate:

1. Any finding with `severity: critical` → BLOCKED regardless
   of priority (critical = it broke, not "it was slow")
2. Any finding with `severity: warning` + `priority: P0` →
   BLOCKED (warnings on non-P0 are NEEDS_REVISION)
3. A web-vital value below the close-miss floor (>10% over
   budget) → BLOCKED. Within the close-miss band (5-10%) →
   NEEDS_REVISION. Within budget → PASS.

No override flag on P0 critical findings. A team that wants
to accept one must either fix the source, re-classify the
scenario out of P0 in `scenario-set.md`, or suppress the
rule with a mandatory justification in
`test-strategy.md → observabilitySuppressions`.

## Non-Goals
- Does NOT fix performance issues. It detects + ranks them.
- Does NOT replace the `observability` MCP. That one does
  cross-run time-series; this one does per-run artifact
  analysis.
- Does NOT track anomalies over time. That's
  `learning-loop-engine`'s job — the skill emits a snapshot;
  the loop correlates snapshots.
- Does NOT record video or replay. It reads the artifacts
  someone else already recorded.
- Does NOT auto-open issues. Findings go into the report;
  `test-result-analyzer` is the ticket-generating skill.

## Downstream Dependencies
- `release-decision-engine` — reads `findings.json` as a
  weighted quality-score input. `critical` findings contribute
  to the hard-blocker list; web-vital verdicts feed the
  perf-budget signal.
- `learning-loop-engine` — ingests `events.jsonl` +
  `findings.json` over time to spot "this anomaly shape keeps
  showing up after deploy X".
- `test-result-analyzer` — reads `findings.json` to enrich
  bug tickets with observability context (network waterfall
  evidence attached to BUG-class failures).
