# Anomaly Rules

Every pattern `observability-analyzer` can flag in a run's
traces. The skill walks these rules at Step 5 of its algorithm.
Inventing a rule at prompt time is forbidden; unknown anomalies
get a fallback classification (`UNCLASSIFIED`) that gets
surfaced for human triage.

Every rule has six mandatory fields:

- **id** — stable identifier cited in reports (`NET-FAIL-401`,
  `WEB-VITALS-LCP`, …)
- **category** — `network` / `console` / `performance` /
  `security` / `third-party`
- **signature** — the exact pattern the skill checks against a
  `TraceEvent`
- **severity** — `critical` / `warning` / `info`
- **rationale** — one-sentence explanation of what the rule
  catches and why that's a problem
- **remediation** — concrete next step ("add retry", "tune
  cache headers", "fix the CSP")

---

## Severity semantics

- **`critical`** — it broke. Gate blocks regardless of
  priority. Critical = the observable behaviour failed (4xx,
  5xx, unhandled exception, security violation).
- **`warning`** — it didn't break, but the system is outside
  its declared budget. Gate blocks on P0 scenarios, escalates
  to NEEDS_REVISION on lower-priority scenarios.
- **`info`** — the rule fired but the team declared it's not
  a problem (third-party warning, expected 404 for probe
  endpoints). Recorded for audit, never blocks.

---

## 1. Network anomalies

### NET-FAIL-4XX
- **id**: `NET-FAIL-4XX`
- **category**: network
- **signature**: `response.status` in `[400, 499]` AND the
  request was NOT marked as expected-failure in
  `test-strategy.md → expectedFailures`
- **severity**: `critical`
- **rationale**: 4xx on a test run means a request that the
  test expected to succeed was rejected. Real bugs.
- **remediation**: trace the specific status — 401 → auth
  drift; 403 → permissions; 404 → wrong URL; 409 → state
  conflict; etc.

### NET-FAIL-5XX
- **id**: `NET-FAIL-5XX`
- **category**: network
- **signature**: `response.status` in `[500, 599]`
- **severity**: `critical`
- **rationale**: 5xx is always a problem; the server broke.
- **remediation**: check the server logs for the correlated
  request id; this is almost always a bug

### NET-FAIL-NO-RESPONSE
- **id**: `NET-FAIL-NO-RESPONSE`
- **category**: network
- **signature**: HAR entry with `response.status == 0` OR
  CDP event with `Network.loadingFailed`
- **severity**: `critical`
- **rationale**: the request never got a response at all —
  DNS, connection, or tls failure
- **remediation**: check infrastructure; often an env issue
  but occasionally a code issue (wrong host / port / cert)

### NET-SLOW-CRITICAL
- **id**: `NET-SLOW-CRITICAL`
- **category**: network
- **signature**: a request on the rendering critical path
  (same-origin HTML / CSS / JS loaded before first paint)
  with `durationMs > criticalRequestBudget` where the budget
  is `1500ms` (domain default) or the override from
  `test-strategy.md`
- **severity**: `warning`
- **rationale**: slow critical-path requests extend LCP and
  INP. This is the number that matters most for UX.
- **remediation**: tune cache headers, preload the resource,
  reduce payload size, or move it off the critical path

### NET-SLOW-API
- **id**: `NET-SLOW-API`
- **category**: network
- **signature**: a request with `mimeType` containing
  `application/json` AND `durationMs > apiBudget` where
  `apiBudget` defaults to `1000ms`
- **severity**: `warning`
- **rationale**: slow API calls make apps feel broken even
  when they technically work
- **remediation**: check server-side traces; often a DB
  query that needs an index

### NET-CACHE-MISS
- **id**: `NET-CACHE-MISS`
- **category**: network
- **signature**: a request whose response has no `cache-control`
  header AND whose URL is a static asset (image, font, CSS,
  JS bundle by extension)
- **severity**: `info`
- **rationale**: missing cache headers mean the resource is
  re-fetched on every navigation — wasted bandwidth but not
  a bug
- **remediation**: add `cache-control` headers; set a long
  max-age for fingerprinted assets

---

## 2. Console anomalies

### CONSOLE-ERROR
- **id**: `CONSOLE-ERROR`
- **category**: console
- **signature**: `TraceEvent.kind == "console"` AND `level ==
  "error"` AND the message is not in `test-strategy.md →
  expectedConsoleErrors`
- **severity**: `critical`
- **rationale**: console.error from the app is the developer's
  own "something is wrong" signal. Never acceptable in a
  release-track run.
- **remediation**: trace the error to its source file + line;
  fix the code

### CONSOLE-WARN-NOISY
- **id**: `CONSOLE-WARN-NOISY`
- **category**: console
- **signature**: `level == "warn"` with > 10 occurrences of
  the same message in a single run
- **severity**: `warning`
- **rationale**: repeated warnings mean the warning is firing
  every N frames or every interaction — a deprecation the
  app hasn't addressed, a missing prop, etc.
- **remediation**: either fix the underlying cause or
  suppress the specific warning via the framework's
  suppression API

### CONSOLE-UNHANDLED-REJECTION
- **id**: `CONSOLE-UNHANDLED-REJECTION`
- **category**: console
- **signature**: `kind == "exception"` AND the stack trace
  contains `unhandled promise rejection`
- **severity**: `critical`
- **rationale**: an unhandled promise rejection is a bug in
  async error handling. Modern runtimes will eventually
  make this a hard failure.
- **remediation**: add `.catch()` to the async chain or use
  `try/await` with a proper catch block

### CONSOLE-FETCH-TO-THROW
- **id**: `CONSOLE-FETCH-TO-THROW`
- **category**: console
- **signature**: exception whose message matches `TypeError:
  fetch failed` or `NetworkError when attempting to fetch`
- **severity**: `critical`
- **rationale**: a fetch that throws is distinct from a fetch
  that returns a bad status — it usually indicates CORS or
  DNS failure
- **remediation**: check CORS headers; check the URL; check
  the preflight OPTIONS response

---

## 3. Performance anomalies

### WEB-VITALS-LCP
- **id**: `WEB-VITALS-LCP`
- **category**: performance
- **signature**: paint event with `metricName == "LCP"` AND
  `metricValue > domainBudget`
- **severity**: `warning` (with a close-miss band)
- **rationale**: LCP is the canonical "does the page feel
  loaded" metric; over-budget LCP means real users perceive
  a slow page
- **remediation**: preload the LCP element, reduce render-
  blocking resources, fix server response time

### WEB-VITALS-CLS
- **id**: `WEB-VITALS-CLS`
- **category**: performance
- **signature**: paint event with `metricName == "CLS"` AND
  `metricValue > domainBudget`
- **severity**: `warning`
- **rationale**: layout shift beyond the budget means users
  see the page jumping around as they try to interact — one
  of the single most annoying bugs the tests can catch

### WEB-VITALS-INP
- **id**: `WEB-VITALS-INP`
- **category**: performance
- **signature**: paint event with `metricName == "INP"` AND
  `metricValue > domainBudget`
- **severity**: `warning`
- **rationale**: INP measures interaction responsiveness; over-
  budget INP means clicks and taps feel sluggish

### JS-LONG-TASK
- **id**: `JS-LONG-TASK`
- **category**: performance
- **signature**: `kind == "js-task"` with `durationMs > 50`
- **severity**: `warning` (with a close-miss band of 150ms)
- **rationale**: long tasks block the main thread. 50ms is
  the threshold at which Chrome starts logging them as
  janky.
- **remediation**: break the task up, move it to a worker,
  or use `requestIdleCallback`

---

## 4. Security anomalies

### SECURITY-MIXED-CONTENT
- **id**: `SECURITY-MIXED-CONTENT`
- **category**: security
- **signature**: HTTPS page with at least one HTTP request
  that isn't on `test-strategy.md → allowedMixedContent`
- **severity**: `critical`
- **rationale**: mixed content warns the user, breaks some
  features, and is a regulatory issue in several domains
- **remediation**: upgrade the request to HTTPS or host the
  resource on the same origin

### SECURITY-CSP-VIOLATION
- **id**: `SECURITY-CSP-VIOLATION`
- **category**: security
- **signature**: console event with message containing
  `Content Security Policy` AND level `error`
- **severity**: `critical`
- **rationale**: CSP violations mean the page is trying to
  load resources the policy denies — either the policy is
  wrong or the code is wrong
- **remediation**: tighten the policy or move the resource;
  never "relax the policy to make the warning go away"
  without a security review

### SECURITY-INSECURE-COOKIE
- **id**: `SECURITY-INSECURE-COOKIE`
- **category**: security
- **signature**: a cookie set with no `Secure` flag on an
  HTTPS origin OR no `HttpOnly` flag on a session cookie
- **severity**: `warning` (critical for financial/healthcare
  — see §Domain overrides below)
- **rationale**: insecure cookies are interceptable + can be
  read by XSS; must be `Secure; HttpOnly` for anything
  session-bound

---

## 5. Third-party anomalies

### THIRD-PARTY-BLOCKING
- **id**: `THIRD-PARTY-BLOCKING`
- **category**: third-party
- **signature**: a request to a host NOT in
  `vibeflow.config.json.ownedHosts` AND
  `kind == "request"` AND the request is on the render
  critical path
- **severity**: `warning`
- **rationale**: third-party scripts on the critical path
  are single points of failure — when the CDN is slow, so
  is your page
- **remediation**: move the third-party script below the
  fold or self-host it

### THIRD-PARTY-TIMEOUT
- **id**: `THIRD-PARTY-TIMEOUT`
- **category**: third-party
- **signature**: a third-party request with
  `durationMs > 5000` (fixed, not from budgets — timeouts
  are absolute)
- **severity**: `warning`
- **rationale**: a third party taking more than 5 seconds
  indicates an outage the test caught
- **remediation**: set up a fallback path; page the
  third-party owner

---

## 6. Domain overrides

Rules with `severity: warning` can be promoted to `critical`
in specific domains:

| Rule | Default | Financial | Healthcare | E-commerce | General |
|------|---------|-----------|------------|------------|---------|
| `SECURITY-INSECURE-COOKIE` | warning | **critical** | **critical** | warning | warning |
| `THIRD-PARTY-BLOCKING` | warning | **critical** | warning | warning | warning |
| `NET-SLOW-API` | warning | **critical** (on payment paths) | warning | warning | warning |

Domain overrides are declared INSIDE the rule's signature
with a per-domain override block. They are NOT declared in
a separate rules file. A per-domain override can only make
a rule MORE strict, never less — e.g. demoting `CONSOLE-ERROR`
to `warning` in `general` is rejected at load time.

---

## 7. Catalog rules

- **Never delete a rule.** Old reports reference these ids;
  deletion orphans them. Mark `deprecated: true` in the
  header instead.
- **No rule without remediation.** "Bad thing detected" is
  not a rule — a rule tells the reader how to fix the
  problem it surfaced.
- **Signatures must be mechanically checkable.** A rule that
  needs "read the context and decide" is not a rule; it's a
  wish. If a check needs a model in the loop, add it to a
  separate skill (e.g. `visual-ai-analyzer`).
- **Severity changes require a retrospective.** Bumping a
  rule from `warning` to `critical` across the board needs
  evidence that the bump catches real bugs the old severity
  let through. Same discipline as the other governance
  files (≥10 runs, version bump, migration note, harness
  sentinel update).

---

## 8. Current anomaly catalog version

**`anomalyCatalogVersion: 1`**

- Categories: 5 (network / console / performance / security
  / third-party)
- Rules: 16 total
- Default severity distribution: 6 critical, 8 warning, 2
  info, 3 with domain-promoted severity

Every report writes `anomalyCatalogVersion` in its header so
historical reports stay interpretable across updates.
