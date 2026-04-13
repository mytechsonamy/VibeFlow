# Inspection Modes

The `visual-ai-analyzer` skill supports three modes. A single
run can engage ANY subset of them — they are additive, not
exclusive. The skill picks modes based on which inputs are
available, and the run report documents which modes fired.

---

## 1. `baseline-diff`

### When it applies

A baseline screenshot is available at
`<screenshot-dir>/baseline.png` OR passed explicitly via
`--baseline <path>`.

### What it checks

- Regressions between the baseline and the current
  screenshot
- Elements that moved, appeared, or disappeared
- Typography changes (size, weight, color)
- Visual state changes (loader stuck, error state,
  unexpected modal)

### Prerequisites

- `db_compare_impl` must have reported `same-dimensions`
  OR `identical`. A `size-mismatch` verdict bypasses this
  mode and emits a single `LAYOUT-DIMENSION-DRIFT` finding
  (structural regression, not a visual one)
- The baseline must have been captured in the same
  viewport / DPR / browser as the current. A baseline
  captured on Chrome at 1280x720 vs current captured on
  Firefox at 1920x1080 is not a fair compare; the skill
  reads the metadata file and blocks if they don't match

### Output shape

Findings emitted by this mode carry `mode: "baseline-diff"`
and a `regression: true` marker. Downstream consumers can
filter for regression-class findings vs standalone quality
issues.

### Limitations

- Cannot catch issues that exist in BOTH the baseline and
  the current (both versions have the same bug). Those
  issues surface only from the `standalone` mode running
  alongside.
- Sensitive to anti-aliasing and sub-pixel rendering
  differences at the model layer. The confidence filter
  (Step 5 of the skill) handles most of this, but
  occasionally a low-confidence "this margin moved 1px"
  finding leaks into the report. The report flags
  sub-pixel-scale findings so the operator can discount
  them.

---

## 2. `standalone`

### When it applies

No baseline is provided. The skill runs pure quality
inspection against the current screenshot alone.

### What it checks

- Contrast violations against the domain's WCAG level
- Typography legibility (line-height, font-size floor,
  truncation on small breakpoints)
- Layout integrity (overlapping elements, clipped content,
  off-canvas absolute positioning)
- Broken-state heuristics (stuck loader, empty state
  placeholder when there should be data, 404 card in a
  flow that shouldn't have one)
- Visible error states the test didn't assert on explicitly

### Prerequisites

- Domain config must be readable (for the contrast level)
- When `test-strategy.md → brandColors` is declared, the
  model is told which colors are brand-authorized — this
  prevents noise from minor shade deviations that are
  intentional

### Output shape

Findings carry `mode: "standalone"` and are NOT marked as
regressions (they're current-state quality issues). The
report groups them separately from baseline-diff findings.

### When standalone is the ONLY mode

When there's no baseline AND no design reference, the skill
runs standalone alone. In that configuration:

- The run is useful but doesn't gate as tightly — without
  a reference, "this looks wrong" findings all rely on the
  model's own heuristics
- The run report carries a `referenceless: true` flag so
  `release-decision-engine` knows to weigh the visual
  signal less
- Contrast findings (objective, measurable) are still
  gate-blocking — lack of a reference doesn't make WCAG
  violations acceptable

---

## 3. `design-comparison`

### When it applies

A Figma reference is available via `design-bridge` MCP
(either through an explicit `--figma-node <node-id>` flag
or via scenario-set.md's `figmaReference` field on a
scenario).

### What it checks

- Drift between the current implementation and the
  intended design
- Brand color deviations (via `design-bridge db_extract_tokens`)
- Typography deviations (via `design-bridge db_extract_tokens`)
- Spacing/layout drift from the design tokens

### Prerequisites

- `design-bridge` MCP is loaded and has `FIGMA_TOKEN`
  configured
- The referenced Figma node exists and can be rendered
  as PNG by `db_fetch_design`
- The current screenshot's viewport matches the Figma
  frame's declared viewport (or is within a declared
  tolerance). Mismatched viewports don't block — they
  surface as `VIEWPORT-DRIFT` info findings so the
  operator knows to calibrate

### Output shape

Findings carry `mode: "design-comparison"` and include a
`driftScore` in `[0, 1]`. The drift score is a weighted
sum of color / typography / spacing / layout deltas,
NOT a single numeric "how different". The report shows
the per-component breakdown.

### Drift tolerance

The default drift tolerance is `0.10` — a drift score below
this passes without findings. Above `0.10` but below `0.15`
produces `warning` findings. Above `0.15` produces
`critical` findings.

`test-strategy.md → designDriftTolerance` can tighten these
values (smaller tolerance → stricter check) but NOT
loosen them. Same tighten-only discipline as every other
override in VibeFlow.

### Limitations

- Design changes that the PRD actually approved but the
  Figma file hasn't been updated to reflect yield false
  positives. The suppression path (by finding id in
  `test-strategy.md → visualSuppressions`) handles this,
  but it's a manual loop until the Figma is updated.
- The model is less reliable at quantitative color
  comparisons than at qualitative "these look different"
  observations. The skill cross-checks critical color
  findings against `db_extract_tokens` data before
  escalating to critical.

---

## 4. Mode interactions

A single run can engage multiple modes. The skill runs them
in parallel (from the caller's perspective — the vision
calls are batched within the same request) and merges
findings. Merge rules:

- A finding produced by multiple modes (same category, same
  region, same description) is deduplicated and the
  highest-confidence source is kept. The report shows
  `Modes: baseline-diff, standalone` to indicate both
  modes agreed.
- A finding produced by exactly ONE mode is kept with its
  original confidence and `modes` field showing the single
  source. No multi-mode agreement bonus.
- Contradictory findings (baseline-diff says "no
  regression" but standalone says "broken state") are
  BOTH kept. They represent different signals about
  different aspects — the baseline-diff is silent because
  the same broken state existed in the baseline (bug was
  pre-existing), while the standalone finding surfaces the
  actual current problem. This is the main reason to run
  modes additively instead of picking one.

---

## 5. Mode configuration

`test-strategy.md` can declare per-scenario mode
overrides:

```yaml
visualAiAnalyzer:
  defaultModes: ["baseline-diff", "standalone"]
  scenarioModes:
    "SC-design-drift-test":
      - baseline-diff
      - design-comparison
    "SC-a11y-audit":
      - standalone   # no baseline, no design — pure quality check
```

- `defaultModes` applies to every scenario not named in
  `scenarioModes`
- A scenario mode list can exclude modes that would
  otherwise apply (useful when the scenario doesn't have
  a baseline by design)
- The skill still runs the prerequisite checks on every
  listed mode — declaring `design-comparison` on a
  scenario with no Figma reference is a config error

---

## 6. Mode version

**`inspectionModesVersion: 1`**

- Baseline-diff requires same-dimensions from db_compare_impl
- Standalone uses domain-specific contrast levels
- Design-comparison default drift tolerance: 0.10
- Tighten-only override rules on all three

Version changes follow the same governance discipline as
every other `references/*.md` file in VibeFlow (retrospective,
version bump, migration note, harness sentinel update).
