# Source Parsers

The `observability-analyzer` skill loads every supported
source format through the parsers documented here. Each parser
produces zero or more `TraceEvent` records in the shared
normalized shape. Adding a new format means adding a new
section to this file AND updating the skill's Step 1 detection
table AND the integration harness sentinel.

---

## Normalized `TraceEvent` shape

Every parser emits records of this shape. Fields that don't
apply to a specific source are `null` explicitly — never
defaulted to zero, never dropped.

```ts
interface TraceEvent {
  id: string;                 // "<source-file>::<index>"
  source: "har" | "playwright" | "console" | "cdp";
  kind: "request" | "response" | "console" | "js-task" | "paint" | "navigation" | "exception";
  timestamp: string;          // ISO-8601, always
  durationMs: number | null;
  request: { url: string; method: string; size: number } | null;
  response: { status: number; size: number; mimeType: string } | null;
  message: string | null;
  level: "debug" | "info" | "warn" | "error" | null;
  stackTrace: string | null;
  metricName: string | null;
  metricValue: number | null;
  scenarioId: string | null;    // filled in Step 4 of the skill
  priority: "P0" | "P1" | "P2" | "P3" | "unknown";  // filled in Step 4
}
```

**Fields added after parsing.** `scenarioId` and `priority`
are set by Step 4 of the skill's algorithm, not by the
parser. Parsers always leave them null. This keeps the parser
layer stateless.

---

## 1. HAR 1.2 (HTTP Archive)

### Detection

- Extension: `.har`
- Content: top-level object with `log.version == "1.2"` and a
  `log.entries` array
- Content-Type (if known): `application/json`

### Parsing

Walk `log.entries`. For each entry:

- Emit one `request` event:
  - `kind: "request"`
  - `timestamp: entry.startedDateTime`
  - `request: { url, method, size: request.headersSize + request.bodySize }`
  - `response: null` (the request event doesn't describe the
    response)
- Emit one `response` event linked to the same index:
  - `kind: "response"`
  - `timestamp: <startedDateTime + totalTime>` (reconstructed
    from `time` field)
  - `durationMs: entry.time`
  - `response: { status, size: response.content.size, mimeType }`

Request + response pairs share the same `id` suffix (e.g.
`my.har::42-req` and `my.har::42-res`) so downstream analysis
can pair them.

### Parser failure modes

- Missing `log.entries` → blocker finding "HAR file has no
  entries; regenerate with a recorder that produces valid
  HAR 1.2"
- Entry with no `time` field → the event is emitted with
  `durationMs: null`; the report flags "HAR entry missing
  duration"
- Entry with `response.status == 0` → this is a HAR-level
  signal for "request never completed" (network error). The
  event's `response.status` stays 0 and the anomaly rules
  catch it as `NET-FAIL-NO-RESPONSE`

---

## 2. Playwright trace (`trace.json` inside `trace.zip`)

### Detection

- Extension: `.zip` containing a top-level `trace.json`, OR
  a bare `trace.json` file
- Content: top-level object with `version` field AND an
  `events` array where each event has a `type` field from a
  known Playwright set

### Parsing

Playwright traces are richer than HAR — they carry DOM
snapshots, console events, network requests, and test-runner
metadata. The parser extracts:

- **Network events** → same shape as HAR (request + response
  pair), with `source: "playwright"`
- **Console events** → `kind: "console"`, `level` from the
  event's severity, `message`, `stackTrace` when captured
- **Page events** → `kind: "paint"` for `LCP` / `FCP` / `CLS`
  / `INP` with `metricName` and `metricValue`
- **Navigation events** → `kind: "navigation"` with the page
  URL and load-state timestamps
- **Exception events** → `kind: "exception"` with the error
  message + stack

### Scenario metadata

Playwright traces often carry the test file name + title in
the metadata. When present, the parser records them so Step 4
of the skill can resolve `scenarioId` without needing a
separate map file. The convention: tests that annotate
themselves with `test.info().annotations.push({ type: 'scenario', description: 'SC-112' })`
get their events linked automatically.

### Parser failure modes

- Trace zip missing `trace.json` → blocker "not a valid
  Playwright trace archive"
- Trace with a version the parser doesn't recognize → the
  parser tries best-effort but flags "Playwright trace
  version <x> is newer than supported <y>; some events may
  be missed" in the report
- Corrupt zip → blocker "cannot unpack trace archive"

---

## 3. Browser console (JSON export)

### Detection

- Extension: `console.json` or `console.log`
- Content for `.json`: top-level array of console entries
  with `type`, `message`, `timestamp` fields
- Content for `.log`: line-delimited text with a permissive
  format (`<timestamp> <level> <message>`)

### Parsing

Each console entry produces one `TraceEvent`:

- `kind: "console"` for `log`, `info`, `warn`, `error`,
  `debug`
- `kind: "exception"` for uncaught exceptions (when the
  console type is `assert` or `exception`)
- `level` mapped from the entry's type:
  - `log` / `info` → `info`
  - `warn` → `warn`
  - `error` → `error`
  - `debug` → `debug`
  - Unknown → `info` with a note in the report

### Parser failure modes

- Unparseable `.log` format → the parser tries each line
  individually and skips lines that don't match the pattern,
  reporting the skip count so operators know the parse was
  lossy
- `.json` that isn't an array → blocker "console.json must
  be a top-level array"

---

## 4. Chrome DevTools Protocol (CDP export)

### Detection

- Extension: `.cdp.json`
- Content: top-level object with a `messages` array where
  each entry has `method` and `params`

### Parsing

CDP is a superset of everything else — it has network,
console, performance, DOM, runtime events. The parser
extracts:

- `Network.requestWillBeSent` + `Network.responseReceived` →
  request + response events (same shape as HAR)
- `Runtime.consoleAPICalled` → console events
- `Runtime.exceptionThrown` → exception events
- `Performance.metrics` / `Page.metrics` → paint events with
  `metricName` and `metricValue`
- `Page.frameNavigated` → navigation events

CDP events that don't map to any of the above are RECORDED
with `kind: null` and flagged in the report under "unmapped
CDP events". We deliberately don't drop them — a class of
events we don't know how to classify is still data.

### Parser failure modes

- Missing `messages` array → blocker "CDP export missing
  messages; not a valid devtools trace"
- Incomplete event (method without params) → event flagged
  but not dropped — the report shows "partial CDP event" so
  the operator can audit

---

## 5. Adding a new source format

1. Pick a stable name for the source (`source: "<name>"` in
   `TraceEvent`).
2. Declare the detection rule (extension + content shape).
3. Describe the parsing — which events map to which
   `TraceEvent.kind`, which fields are null.
4. Document parser failure modes — what blocks, what gets
   flagged, what's recorded with partial data.
5. Update the skill's Step 1 dispatch to include the new
   source.
6. Update the integration harness sentinel that counts
   supported source formats.
7. Retrospective on at least 5 real artifact files showing
   the new parser captures the events the team cares about.

---

## 6. What parsers do NOT do

- **Don't classify.** Classification (Step 5 of the skill) is
  the anomaly-rules catalog's job. Parsers produce raw
  events; the classifier decides what's a problem.
- **Don't de-duplicate.** Parsers emit one event per source
  record. Deduplication happens at Step 7 of the skill after
  findings are generated.
- **Don't filter.** Every parseable event lands in the
  normalized stream. Low-noise events are filtered later, if
  at all, via the anomaly rules' `severity: info` band.
- **Don't cross-correlate sources.** A HAR request and a
  CDP request for the same URL are two separate events in
  the normalized stream. The cross-correlation (deciding
  "these are the same request seen from two angles") lives
  in the report-writing step, not in the parsers.

---

## 7. Parser version tracking

Each parser records its version in the emitted event's
metadata field when the source carries version info. The
skill records the parser versions it used in the report
header so reproducibility chains back to the parsing layer.

Current parser versions:

- HAR: 1.2 (the parser accepts 1.2 only; 1.1 blocks with
  upgrade message)
- Playwright: trace versions 1-8 (newer bests-effort with a
  warning)
- Console: no version (format-less)
- CDP: protocol 1.3 events (newer events under unmapped)
