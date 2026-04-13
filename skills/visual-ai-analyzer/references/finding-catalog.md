# Visual Finding Catalog

Every visual finding `visual-ai-analyzer` is allowed to
emit. The vision model's raw output is normalized into one
of these categories at Step 4 of the skill's algorithm.
Unclassifiable findings land in `UNCLASSIFIED-VISUAL` and
get flagged for human triage — a run with > 20% of findings
unclassified blocks the run (taxonomy gap).

Every finding has seven fields:

- **id** — stable identifier cited in the report
- **category** — `layout` / `typography` / `color` /
  `contrast` / `alignment` / `overflow` / `broken-state`
- **signature** — the vision-model description pattern the
  skill matches against
- **severity** — `critical` / `warning` / `info`
- **confidence hints** — what pushes confidence above the
  0.8 / 0.6 thresholds for this finding
- **remediation** — what the report should suggest
- **applicable modes** — which inspection modes produce this
  finding type

---

## 1. Layout findings

### LAYOUT-ELEMENT-OVERLAP
- **category**: layout
- **signature**: two or more elements' bounding boxes
  overlap when the baseline shows them as adjacent
- **severity**: `critical`
- **confidence hints**:
  - 1.0 — the model explicitly describes both elements AND
    the overlap is visible in the screenshot
  - 0.85 — the model describes the overlap without naming
    both elements
  - 0.65 — the model says "looks crowded" without a
    specific overlap description (demoted to warning)
- **remediation**: restore the flexbox gap / padding the
  baseline used; check for a removed CSS rule
- **modes**: baseline-diff, standalone

### LAYOUT-ELEMENT-MOVED
- **category**: layout
- **signature**: an element is present in both baseline
  and current but at a different position (> 4px delta on
  any axis)
- **severity**: `warning`
- **confidence hints**:
  - 0.9 — the model names the element + the old and new
    positions
  - 0.7 — the model says "something moved" without naming
    the element
- **remediation**: check the CSS cascade for what might
  have changed; consider a layout shift regression test
- **modes**: baseline-diff

### LAYOUT-ELEMENT-MISSING
- **category**: layout
- **signature**: an element present in the baseline is not
  visible in the current screenshot
- **severity**: `critical`
- **confidence hints**:
  - 0.95 — the model names the missing element and the
    baseline position
  - 0.7 — the model says "something is missing" without
    specifics
- **remediation**: investigate the rendering path; the
  element may be behind another element (z-index), hidden
  by a conditional, or deleted entirely
- **modes**: baseline-diff

### LAYOUT-ELEMENT-APPEARED
- **category**: layout
- **signature**: an element visible in the current was NOT
  in the baseline
- **severity**: `warning`
- **confidence hints**:
  - 0.9 — a specific new element is described
  - 0.6 — vague "more stuff on the page" (demoted to info)
- **remediation**: if intentional (new feature), update
  the baseline; if unintentional, investigate as a
  rendering bug
- **modes**: baseline-diff

### LAYOUT-DIMENSION-DRIFT
- **category**: layout
- **signature**: emitted by the skill itself (not the
  model) when `db_compare_impl` returns `size-mismatch`
- **severity**: `critical`
- **confidence hints**: always 1.0 (measured structurally)
- **remediation**: viewport or DPR drift between baseline
  and current; re-capture with matching settings
- **modes**: baseline-diff (preflight)

---

## 2. Typography findings

### TYPOGRAPHY-SIZE-DRIFT
- **category**: typography
- **signature**: the model describes a font-size change
  on a text element
- **severity**: `warning`
- **confidence hints**:
  - 0.9 — model names the element + old and new sizes
  - 0.7 — model says "text looks bigger/smaller"
- **remediation**: check the CSS font-size tokens; likely
  a design-token override drifted
- **modes**: baseline-diff, design-comparison

### TYPOGRAPHY-WEIGHT-DRIFT
- **category**: typography
- **signature**: same text rendered at a different
  font-weight than the baseline
- **severity**: `warning`
- **confidence hints**:
  - 0.9 — explicit weight change described (regular →
    semibold)
  - 0.6 — "text looks thinner/thicker"
- **remediation**: check the font stack (the weight may
  have fallen back), OR the CSS weight value itself
- **modes**: baseline-diff, design-comparison

### TYPOGRAPHY-READABILITY
- **category**: typography
- **signature**: text at a size below the domain floor
  (12px for general, 14px for healthcare)
- **severity**: `warning`
- **confidence hints**: 0.9 when the model explicitly
  notes small text; 0.6 for "hard to read"
- **remediation**: bump the font-size; consider the
  domain's minimum text size as a hard floor
- **modes**: standalone

### TYPOGRAPHY-TRUNCATION
- **category**: typography
- **signature**: text ends with `...` or is visibly cut
  off mid-word
- **severity**: `warning`
- **confidence hints**: 0.95 for explicit `...` observed;
  0.7 for "text appears cut"
- **remediation**: check CSS `overflow` / `text-overflow`
  rules; longer text may need a tooltip
- **modes**: standalone, baseline-diff

---

## 3. Color + contrast findings

### COLOR-BRAND-DRIFT
- **category**: color
- **signature**: a color used for a brand element (primary
  button, logo, brand link) doesn't match
  `test-strategy.md → brandColors`
- **severity**: `warning`
- **confidence hints**:
  - 0.95 — the model explicitly compares the colors
  - 0.6 — "colors feel off"
- **remediation**: check the brand-color tokens; this often
  indicates a design-token override without updating the
  component
- **modes**: standalone (with brandColors declared),
  design-comparison

### CONTRAST-BODY-TEXT
- **category**: contrast
- **signature**: body text with measured contrast below
  the domain's WCAG minimum (4.5 for AA, 7.0 for AAA)
- **severity**: `critical`
- **confidence hints**:
  - 0.9 — the model reports specific hex codes and a
    measured ratio
  - 0.7 — "this text is hard to read against the background"
- **remediation**: darken the text OR lighten the
  background; never "make it bolder" — contrast is a
  function of color, not weight
- **modes**: standalone

### CONTRAST-INTERACTIVE
- **category**: contrast
- **signature**: interactive element (button, link) with
  contrast below the minimum for its size class
- **severity**: `critical`
- **confidence hints**: same shape as body-text
- **remediation**: same as CONTRAST-BODY-TEXT, but
  interactive elements often have additional hover /
  focus states that must ALSO meet contrast — check all
  states
- **modes**: standalone

---

## 4. Alignment findings

### ALIGNMENT-GRID-DRIFT
- **category**: alignment
- **signature**: elements that were grid-aligned in the
  baseline are off-grid in the current (> 2px from the
  grid line)
- **severity**: `warning`
- **confidence hints**:
  - 0.85 — the model describes the specific grid
    misalignment
  - 0.6 — "elements look uneven"
- **remediation**: check the CSS grid / flexbox
  `gap` / `align-items` values
- **modes**: baseline-diff, design-comparison

### ALIGNMENT-BASELINE-DRIFT
- **category**: alignment
- **signature**: text elements in adjacent columns no
  longer share a baseline
- **severity**: `info`
- **confidence hints**:
  - 0.8 — explicit baseline comparison
  - 0.5 — "text columns look staggered" (demoted to
    low-confidence filter)
- **remediation**: baseline alignment is usually a
  `vertical-align` or `line-height` issue
- **modes**: standalone, baseline-diff

---

## 5. Overflow findings

### OVERFLOW-CONTENT-CLIPPED
- **category**: overflow
- **signature**: a visible element's content extends
  beyond its container's border (clipped right edge,
  clipped bottom)
- **severity**: `warning`
- **confidence hints**:
  - 0.9 — the model identifies the clipped element
    specifically
  - 0.65 — "something looks cut off"
- **remediation**: check the container's `width` / `max-height`
  / `overflow` rules; consider whether the content should
  wrap or scroll
- **modes**: standalone, baseline-diff

### OVERFLOW-HORIZONTAL-SCROLL
- **category**: overflow
- **signature**: a horizontal scrollbar appears on a
  container that shouldn't have one (full-width layout
  sections)
- **severity**: `critical`
- **confidence hints**: 0.85 for explicit scrollbar
  observation; 0.6 for "page feels too wide"
- **remediation**: track down the element overflowing
  the viewport; often a CSS `min-width` or an image
  without a max-width
- **modes**: standalone, baseline-diff

---

## 6. Broken-state findings

### BROKEN-STATE-LOADER-STUCK
- **category**: broken-state
- **signature**: a loading spinner / skeleton / progress
  bar is visible in the final screenshot (after the test
  declared the scenario complete)
- **severity**: `critical`
- **confidence hints**:
  - 0.95 — the model explicitly names a loader
  - 0.7 — "something is still loading"
- **remediation**: investigate the async operation that
  didn't complete; this usually indicates a promise
  chain that resolved in a way the UI didn't listen for
- **modes**: standalone

### BROKEN-STATE-EMPTY-PLACEHOLDER
- **category**: broken-state
- **signature**: an empty-state placeholder visible on a
  page that the scenario expected to have data
- **severity**: `critical`
- **confidence hints**:
  - 0.9 — explicit empty-state illustration / text
  - 0.65 — "looks empty" (demoted to warning)
- **remediation**: check the data fetching for the page;
  often an auth drift or a missing seed
- **modes**: standalone (with scenario context)

### BROKEN-STATE-MISSING-IMAGE
- **category**: broken-state
- **signature**: a broken-image icon / 1px blank image
  where the scenario expected a rendered image
- **severity**: `warning`
- **confidence hints**:
  - 0.9 — explicit broken-image icon observed
  - 0.6 — "image area looks empty"
- **remediation**: check the image URL + CORS headers;
  also verify CDN availability
- **modes**: standalone

### BROKEN-STATE-ERROR-BANNER
- **category**: broken-state
- **signature**: a user-facing error banner / toast /
  modal is visible at the end of the scenario run
- **severity**: `critical`
- **confidence hints**:
  - 0.95 — the model quotes the error text
  - 0.7 — "there's a red banner"
- **remediation**: the scenario hit a failure path; check
  the api calls and server logs for the correlated
  request
- **modes**: standalone, baseline-diff

---

## 7. UNCLASSIFIED-VISUAL

- **category**: none
- **signature**: the model produced a finding that doesn't
  match any of the categories above
- **severity**: `info`
- **confidence**: always 0.0 (the skill can't reason
  about a finding it doesn't understand)
- **remediation**: surface the finding in the report under
  "unclassified" for human triage; extend the catalog with
  a new entry if the shape recurs

A single UNCLASSIFIED finding is acceptable. > 20% of
findings unclassified blocks the run (taxonomy gap, same
rule as `test-result-analyzer` and `cross-run-consistency`).

---

## 8. Confidence-based filtering

Summary of the filter rules from SKILL.md Step 5:

- `confidence >= 0.8` → retained at declared severity
- `0.6 <= confidence < 0.8` → severity demoted one level
  (prefix "probable")
- `confidence < 0.6` → recorded in the artifact only, not
  the human report

These thresholds are versioned with the catalog. Changing
them requires a retrospective on ≥10 real runs showing the
new thresholds catch more real issues without inflating
false positives, plus `findingCatalogVersion` bump +
migration note + harness sentinel.

---

## 9. Current finding catalog version

**`findingCatalogVersion: 1`**

- Categories: 7 (layout / typography / color / contrast /
  alignment / overflow / broken-state)
- Findings: 17 classified + 1 UNCLASSIFIED-VISUAL fallback
- Confidence thresholds: `0.6 / 0.8`
- Severity distribution: 6 critical, 8 warning, 3 info
  (before confidence demotion)
