# Gap Prioritization

How `coverage-analyzer` ranks uncovered code at Step 5 of its
algorithm. The goal is that the first gap in the report is the
one most likely to produce a real bug — not the biggest one,
not the newest one, the RISKIEST one.

The formula is deterministic and each component is auditable
in the output. If a gap ranks surprisingly high or low, the
contributing-factors column in the report should explain
why.

---

## 1. The formula

```
gapScore(file) =
    w_p * priorityComponent
  + w_c * criticalityComponent
  + w_x * churnComponent
  + w_r * requirementLinkComponent
```

Weights sum to 1.0:

| Component | Weight | Rationale |
|-----------|--------|-----------|
| `priorityComponent` (`w_p`) | **0.40** | Priority is the strongest structural signal — a P0 uncovered file is always higher leverage than a P3 one |
| `criticalityComponent` (`w_c`) | **0.30** | Critical-path membership is the closest proxy for "bug here = customer incident" |
| `churnComponent` (`w_x`) | **0.20** | A file under active development with low coverage is where regressions are about to happen |
| `requirementLinkComponent` (`w_r`) | **0.10** | RTM linkage captures "this code serves a documented requirement", which is a different axis from the other three |

The output `gapScore` is in `[0, 1]`. The report sorts
descending; the highest-leverage uncovered code surfaces first.

---

## 2. Component definitions

### 2.1 `priorityComponent`

```
priorityComponent(file) = {
  P0 → 1.00
  P1 → 0.70
  P2 → 0.40
  P3 → 0.15
  unknown → 0.30
}
```

Priority resolution chain (first match wins):

1. Explicit `@priority` comment in the source file header
2. Max priority of tests in the file's direct
   `component-test-writer`-generated test file, via the
   test's `it()` titles (which prefix the scenario id)
3. Max priority of scenarios mapped to the file via the RTM
4. Default `unknown` (score 0.30)

A file with no priority information gets a middle-of-the-road
score — we don't want to drown it in the noise floor AND we
don't want to promote it above everything else. The 0.30
default is intentionally neither.

### 2.2 `criticalityComponent`

```
criticalityComponent(file) = {
  file in vibeflow.config.json.criticalPaths → 1.00
  file in a parent directory listed in criticalPaths      → 0.80
  otherwise                                                → 0.50
}
```

- **Exact match** — the full file path appears in
  `criticalPaths`. Highest criticality.
- **Directory match** — a parent directory of the file
  appears in `criticalPaths`. A file two levels deep inherits
  at 0.80 instead of 1.00 to reflect the uncertainty (the
  critical-path intent was probably more specific than "this
  whole subtree").
- **No match** — default 0.50, not 0.0. A non-critical file
  is not the same as an empty file; it still has coverage
  value.

The skill refuses to compute `criticalityComponent` when
`criticalPaths` is empty in the config — if the project has
no critical paths declared, the whole criticality signal is
meaningless and the component is recorded as `null`. The
overall `gapScore` is re-normalized to ignore the null
component, so a project without critical paths still gets a
valid ranking from the other three signals.

### 2.3 `churnComponent`

```
churnComponent(file) = clamp01(
  git_log_count_30d(file) / 30
)
```

- Commit count in the past 30 days, normalized by 30. One
  commit a day = 1.0; cold file = ~0.
- Source: `codebase-intel` MCP's `ci_find_hotspots` tool when
  available, else `git log --since=30.days.ago --oneline
  -- <file> | wc -l` as a fallback.
- When neither is available (disconnected env), the component
  is `null` and the overall score is re-normalized. The
  report's `degradedSignals` field lists `"no churn data"`.

**Why 30 days, not 60 or 90:** 30 days catches "recent
active development", which is the window where coverage gaps
most often become bugs. Longer windows dilute the signal
with old hotspots that have since stabilized.

### 2.4 `requirementLinkComponent`

```
requirementLinkComponent(file) = {
  linked to a P0 requirement via RTM → 1.00
  linked to a P1 requirement via RTM → 0.70
  linked to a P2 requirement via RTM → 0.40
  linked to a P3 requirement via RTM → 0.15
  unlinked                            → 0.30
}
```

Different from `priorityComponent` because it's about
traceability, not about the code's own priority tag. A file
can be tagged P1 in its own header but link to a P0
requirement in the RTM — the two components capture those
two axes independently.

An unlinked file (no RTM entry at all) gets 0.30 — the same
"middle of the road" default as unknown priority. An unlinked
file with high churn and high criticality still surfaces in
the report; the lack of requirement linkage just means one
axis isn't helping promote it.

---

## 3. Tie-breakers

When two gaps end up with identical scores:

1. Higher `criticalityComponent` wins
2. Higher churn wins
3. Lexicographic file path — deterministic final break

The same three-rule shape as
`test-priority-engine/references/risk-model.md` §3.
Consistency across skills matters for "reading the output is
easy" more than it matters for local optimization.

---

## 4. Per-file vs per-line ranking

The skill ranks UNCOVERED FILES, not uncovered lines. A file
with 50 uncovered lines scattered across the codebase and a
file with a tight 50-line block both get one entry in the
ranking. The per-file view is the one operators act on —
"which file needs tests" — and pretending the ranking is
per-line would produce a flood of single-line entries that
aren't actionable.

The report DOES show the specific uncovered lines inside
each file's entry, so a reader who wants the line detail can
see it without getting drowned in it.

---

## 5. Interaction with exclusions

Excluded lines (see `coverage-metrics.md` §5) are NOT
counted as uncovered, and a file that's fully excluded doesn't
appear in the gap ranking at all — it has no uncoverage to
rank.

**But excluded lines inside a file with other uncoverage are
recorded in the report's per-file entry so the reviewer can
see them.** A file that's 80% covered, 10% excluded, and 10%
uncovered is ranked on the 10% uncoverage alone, but the
excluded 10% is noted so the reader can decide whether the
exclusions are reasonable.

---

## 6. What gap prioritization does NOT do

- **Doesn't predict failures.** Same rule as
  `test-priority-engine`'s risk model: we score likelihood of
  being worth testing, not likelihood of breaking. Historical
  + structural signals, not a failure oracle.
- **Doesn't model semantic importance.** An uncovered utility
  function is not intrinsically less important than an
  uncovered business logic function; what matters is the
  four measurable signals above. Trying to model "semantic
  importance" would encode superstition as a weight.
- **Doesn't deduplicate overlapping gaps.** Two files with
  uncoverage that exercise the same underlying bug path each
  get their own gap entry. Deduplication would require
  tracing the path through both, which is out of scope.
- **Doesn't re-weight by how much coverage is missing.** A
  file that's 10% covered and a file that's 40% covered get
  equal treatment in the ranking — the quantitative
  difference is in the per-file row, not in the score. A file
  with MORE uncoverage doesn't automatically rank higher,
  because a small number of uncovered lines in a critical P0
  file is still more important than a big number of
  uncovered lines in a non-critical P3 file.

---

## 7. Override discipline

Weights can be overridden via
`test-strategy.md → coverageAnalyzer.weights`. Rules:

- Weights must renormalize to 1.0 (±0.001)
- `w_p >= 0.3` floor — priority must always dominate
- Override requires a retrospective on ≥10 historical runs
  showing the change captures a real weakness the defaults
  missed
- `gapPrioritizationVersion` bumps and is recorded in every
  report
- Harness sentinel asserts the current weight values; silent
  edits fail CI

Same discipline as every other weight override in VibeFlow.
"Don't change the gate without showing the gate gets better."

---

## 8. Current gap prioritization version

**`gapPrioritizationVersion: 1`**

- Weight defaults: `w_p 0.40 / w_c 0.30 / w_x 0.20 / w_r 0.10`
- Floor: `w_p >= 0.3`
- Normalization: null components drop from the denominator,
  remaining components renormalize to 1.0

Every report writes the version so historical reports stay
interpretable after a bump.
