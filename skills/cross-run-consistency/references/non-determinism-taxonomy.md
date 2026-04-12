# Non-Determinism Taxonomy

`cross-run-consistency` classifies every inconsistency finding
against this file at Step 5 of its algorithm. The classification
is deterministic: walk the classes in order, pick the first
match. Inventing a class at prompt time is forbidden; an
`UNKNOWN` finding is a prompt to extend this file, not to
improvise.

Every class has five fields:

- **id** — stable identifier cited in the report (`TIMING`,
  `ORDERING`, …)
- **signature** — the pattern that identifies the class: a
  specific diff shape, a specific file type, a specific
  metric
- **confidence hints** — what pushes confidence above or below
  0.6 for this class
- **typical causes** — concrete code patterns that produce
  this class of inconsistency
- **remediation** — how to make the test deterministic again

---

## Walk order

The skill walks classes in this exact order and picks the first
that matches. Ordering matters because a single finding can fit
multiple classes (e.g. a test that reads the system clock
could be TIMING or EXTERNAL-STATE) — the walk decides which
lens is primary.

1. `TIMING`
2. `ORDERING`
3. `SEED-DRIFT`
4. `EXTERNAL-STATE`
5. `RESOURCE-CONTENTION`
6. `UNKNOWN`

---

## 1. `TIMING`

- **id**: `TIMING`
- **signature**:
  - The diff contains a substring that parses as an ISO-8601
    timestamp, a Unix epoch (10–13 digit number inside a
    reasonable range), or a duration field (`durationMs`,
    `elapsed`) that differs across runs
  - OR the test's output references `Date`, `performance`, or
    `process.hrtime` in its stderr / debug output
- **confidence hints**:
  - 1.0 — a literal ISO timestamp differs in the diff
  - 0.8 — duration field differs but the value is within a
    small window (<5% drift)
  - 0.5 — the diff contains a number that LOOKS like an epoch
    but has no context; still classified TIMING but flagged
    "probable" in the report
- **typical causes**:
  - `toString()` on a `Date` inside an assertion
  - Logging a duration in test output without fixing the
    clock
  - Sorting by "most recent" in test data
  - Using `Date.now()` in a generated id / token / hash
- **remediation**:
  - Pin the clock with the test runner's fake-timers API
    (vitest `vi.useFakeTimers()`, jest `jest.useFakeTimers()`)
  - Mock `Date.now` / `performance.now` where the test
    runner's fake timers don't cover them
  - Strip timestamps from test output before asserting
  - Assert structural properties instead of the literal
    timestamp

---

## 2. `ORDERING`

- **id**: `ORDERING`
- **signature**:
  - The diff contains the SAME set of elements in a different
    order (each line appears the same number of times in both
    runs but not at the same indices)
  - OR the test exercises a `Set` / `Map` / `Object.keys` /
    `readdir` without an explicit sort
- **confidence hints**:
  - 1.0 — the diff literally matches "same lines, different
    order" (sorted lines from both runs are byte-identical)
  - 0.7 — the diff is in an array field whose source is
    `Object.keys` / `Object.entries`
  - 0.5 — probable ordering issue but the data is large enough
    that we can't verify "same multiset" quickly; flagged
    probable
- **typical causes**:
  - Iterating a `Set` or `Map` without sorting
  - `Object.keys(obj)` in output (insertion order is stable in
    modern engines but file-system-derived keys aren't)
  - `fs.readdir` without sort — order is platform-dependent
  - Database query without `ORDER BY`
  - Concurrent `Promise.all` results reassembled as they
    resolve
- **remediation**:
  - Sort deterministically before asserting (lexicographic on
    id, etc.)
  - Use a sorted container (`[...set].sort()`)
  - Add `ORDER BY` to SQL queries
  - `Promise.all` results are already ordered; the fix is to
    not re-order them

---

## 3. `SEED-DRIFT`

- **id**: `SEED-DRIFT`
- **signature**:
  - The diff contains generated IDs (UUIDs, factory ids, hash
    values) that differ between runs
  - OR the test uses `test-data-manager` factories and the
    generated fixture differs across runs
- **confidence hints**:
  - 1.0 — UUID v4 literally differs in the diff (UUIDs are
    random by construction, so a UUID in the output that's
    not pinned is always SEED-DRIFT)
  - 0.9 — a value obviously derived from a hash function
    differs (fixed-length base64 / hex string)
  - 0.7 — a factory-generated field (email, phone, address)
    differs in a way that matches the factory's randomization
- **typical causes**:
  - `crypto.randomUUID()` or `Math.random()` at test time
    without a pinned PRNG
  - `test-data-manager` factory missing a `seed` argument, so
    it defaults to the module-level seed AND the module-level
    seed advanced between runs
  - Third-party factories (`faker`, `chance`) without a fixed
    seed
  - `process.pid`-based tokens (test isolation bug)
- **remediation**:
  - Pin the PRNG via `test-data-manager`'s deterministic
    generator (see `test-data-manager/references/generator-patterns.md`)
  - Inject a fixed seed into every factory call
  - Stub `crypto.randomUUID()` to return a stable value
  - Use a deterministic id derived from the test name instead
    of a random one

---

## 4. `EXTERNAL-STATE`

- **id**: `EXTERNAL-STATE`
- **signature**:
  - The test reads from a network endpoint, a shared database,
    or a file outside the test's own workspace
  - OR the diff contains data that doesn't appear in any
    fixture the test bundles
- **confidence hints**:
  - 1.0 — the test's stderr shows an HTTP request that differs
    between runs (different response body, same request)
  - 0.8 — the test reads from `/tmp` or another directory
    outside the test's workspace
  - 0.6 — the diff contains data that looks like it came from
    a real DB (e.g. an incrementing id that matches a shared
    sequence)
  - 0.4 — probable external state but no direct evidence;
    flagged probable
- **typical causes**:
  - The test hits a real API ("this never changes, trust me")
    — until the third-party changes their response
  - Shared `/tmp` state left behind by another test
  - A database connection that shares state across test runs
  - A mock HTTP server that persists state across runs
    (`wiremock` without `resetScenarios` between runs)
- **remediation**:
  - Wrap external calls in a mock (`wiremock`, `nock`,
    `msw`) with a fixed response fixture
  - Give the test its own workspace (`mktemp -d`-per-test)
  - Reset the mock server between runs (the
    `environment-orchestrator` profile may already do this)
  - Use an in-memory database clone per run

---

## 5. `RESOURCE-CONTENTION`

- **id**: `RESOURCE-CONTENTION`
- **signature**:
  - The diff is exclusively in duration fields AND the
    variance across runs exceeds 3× the baseline
  - OR the test's output differs in retry counts / backoff
    counts but the actual logical result is the same
- **confidence hints**:
  - 0.9 — wall-clock duration differs by >3× but the output
    content is otherwise identical
  - 0.7 — retry count differs but the retry was for an
    internal timeout
  - 0.5 — hard to distinguish from TIMING without runtime
    profiling data; flagged probable when the other classes
    don't match
- **typical causes**:
  - CI runner memory pressure pushing the test into swap
  - Other tests running in parallel stealing CPU time
  - GC pauses in languages with unpredictable garbage
    collection
  - Network latency fluctuation (overlaps with EXTERNAL-STATE
    — the walk order puts EXTERNAL-STATE first because it's
    more specific)
- **remediation**:
  - Run the test in isolation (serialize against other tests
    with the `@serial` tag)
  - Increase the assertion's timing budget when the difference
    is genuinely in the "it takes longer when the machine is
    slower" direction
  - Add a retry budget at the runner level ONLY if the
    underlying system is genuinely flaky and can't be fixed
    — this is a last resort; retries hide flake
  - Profile under load to find the actual bottleneck

---

## 6. `UNKNOWN`

- **id**: `UNKNOWN`
- **signature**: none of the above match
- **confidence hints**: always 0.0
- **typical causes**: a class this file doesn't yet cover
- **remediation**:
  - Surface the finding in the report with full diff context
  - File a PR to extend this taxonomy with a new class (see
    §7 below)
  - Do NOT silently absorb the finding into one of the other
    classes — a wrong classification is worse than
    "unknown"

**UNKNOWN is not a failure state**, it's a signal that the
taxonomy has a gap. A run with a few UNKNOWN findings is still
a valid run; the skill flags them for human triage. A
CONSISTENCY report where most findings are UNKNOWN means the
taxonomy is out of date and blocks the run with remediation
"most findings unclassified; the taxonomy needs an update
before this report can be trusted".

---

## 7. Adding a new class

1. Pick a stable id. SCREAMING-SNAKE-CASE, noun, specific.
2. Write the signature in terms that a grep or a simple
   diff-walker can implement. If the signature needs a parser,
   the class is too vague.
3. Document confidence hints for at least three values
   (high / medium / low).
4. List at least three typical causes with real code patterns.
5. Provide concrete remediation — no "improve the test".
6. Update the walk order in §Walk Order. New classes are
   inserted in specificity order (more specific → earlier).
7. Update the integration harness sentinel that counts
   taxonomy classes.
8. Retrospective on at least 5 historical findings that would
   have been classified under the new class. No retrospective
   → no class.

---

## 8. Deprecation

Never delete a class. Old reports reference these ids.
Deprecate with a `deprecated: true` header and stop emitting
it forward; old reports stay interpretable.

No deprecated classes yet — this is the first version.
