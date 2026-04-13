---
name: visual-ai-analyzer
description: Uses Claude vision to inspect screenshots for layout regressions, accessibility issues, typography drift, and design fidelity. Complementary to design-bridge's db_compare_impl (which does dimension + byte identity) — this skill actually SEES the images and describes what changed. Gate contract — zero critical visual regressions in P0 scenarios, accessibility findings require remediation, design-diff above tolerance needs human review. PIPELINE-5 step 7 / PIPELINE-6 step 6.
allowed-tools: Read Write Grep Glob
context: fork
agent: Explore
---

# Visual AI Analyzer

An L2 Truth-Execution skill. Where `db_compare_impl` answers
"are these two images byte-identical or different dimensions"
(structural compare), this skill answers "what visually changed
and does it matter" (semantic compare). The two are
complementary: the pixel compare catches things the vision
model might miss, and the vision model catches things the
pixel compare can't describe.

**Vision is not deterministic.** Every finding carries a
confidence score, and the gate rules are tuned so low-
confidence findings get flagged for human review rather than
auto-blocking. The worst failure mode of a vision skill is
gating on hallucinations; the second-worst is ignoring real
regressions because the model was uncertain.

## When You're Invoked

- **PIPELINE-5 step 7** — after `uat-executor` has captured
  screenshots during UAT runs, before the release decision.
- **PIPELINE-6 step 6** — pre-release, same position.
- **On demand** as
  `/vibeflow:visual-ai-analyzer <screenshot-path> [--mode <m>]`.
- **From `e2e-test-writer`'s generated specs** when a test
  wants AI-assisted visual assertion instead of a pixel
  compare.

## Input Contract

| Input | Required | Notes |
|-------|----------|-------|
| Screenshot | yes | PNG / JPEG. A folder path works when it contains `current.png` + optional `baseline.png` + `metadata.json`. |
| Baseline screenshot | optional | When present, enables the `baseline-diff` mode. Without it, the skill falls back to `standalone` mode. |
| Figma reference | optional | Via `design-bridge` MCP (`db_fetch_design`). When present, enables the `design-comparison` mode. |
| UI requirements | optional | A plain-text description of what the screen is supposed to show. When present, the skill validates the screenshot against the requirements — useful when there's no baseline. |
| Scenario id | optional | `SC-xxx` from `scenario-set.md`. Drives the priority inheritance for the P0 rule. |
| Domain config | yes | `vibeflow.config.json → domain`. Drives contrast standards (WCAG AA for general, AAA for healthcare). |

**Hard preconditions** — refuse rather than emit findings that
can't be acted on:

1. The screenshot must be readable. An empty file / corrupt
   image / wrong magic bytes → block with "image cannot be
   loaded; re-capture and retry".
2. If `baseline.png` is provided, it must have the same
   dimensions as `current.png` OR differ by ≤ 5%.
   Dimension mismatch → the skill delegates to
   `db_compare_impl` first (structural decision), and only
   proceeds with vision analysis if the pixel compare
   verdict is `same-dimensions`. Dimension drift isn't a
   vision problem, it's a geometry problem.
3. If the domain is `healthcare` or `financial`, the
   screenshot's captured metadata must include the viewport
   size. Regulated domains require reproducible viewport
   anchors — a screenshot captured at an unknown width is
   not a valid input for those gates.

## Algorithm

### Step 1 — Resolve the inspection mode
Three modes from `references/inspection-modes.md`:

- **`baseline-diff`** — a baseline screenshot is available.
  The skill compares current vs baseline and reports
  regressions.
- **`standalone`** — no baseline. The skill inspects the
  screenshot against universal UI quality rules (contrast,
  readability, overflow, broken states).
- **`design-comparison`** — a Figma reference is available
  via `design-bridge`. The skill compares current vs design
  and reports drift.

If multiple modes are applicable, the skill runs them ALL
and the report consolidates findings. Modes are additive,
not exclusive — a baseline diff can still surface standalone
issues (e.g. a contrast problem that exists in both the
baseline AND the current and therefore is NOT a regression,
but IS a bug).

Record the chosen mode set in the run metadata so the report
can explain which findings came from which mode.

### Step 2 — Delegate to `db_compare_impl` first (when baseline exists)
Before calling the vision model, the skill calls
`db_compare_impl` with the current + baseline images. The
compare_impl result categorizes the pair:

- `identical` → no findings; the report is empty; skill
  exits with `PASS` immediately
- `same-dimensions` → proceed to vision analysis; pixel
  drift is expected and the model should describe it
- `size-mismatch` → the skill stops here and emits a single
  finding `LAYOUT-DIMENSION-DRIFT` with severity `critical`.
  Dimension drift is a structural regression, not a visual
  one, and the vision model would produce noisy findings
  trying to describe it.
- `unknown` → vision analysis proceeds but the report
  carries a degraded-signal flag

This keeps the vision model off the critical path for the
cases where a cheaper signal is definitive.

### Step 3 — Call the vision model
The skill invokes Claude vision with a structured prompt:

- The current screenshot
- The baseline screenshot (when baseline-diff mode)
- The Figma export as PNG (when design-comparison mode)
- The plain-text requirements (when standalone + requirements
  present)
- Domain context (WCAG AA or AAA standards, brand colors
  from `test-strategy.md → brandColors`)

The prompt asks for findings in a structured JSON shape
(see `finding-catalog.md` for the exact shape). The skill
enforces the schema: responses that don't parse as valid
JSON against the expected shape are rejected with a
WARNING in the report "vision model returned malformed
output; retrying once" and re-asked. A second malformed
response blocks.

### Step 4 — Classify each finding
For every raw finding from the model, walk
`references/finding-catalog.md` and assign the finding to
a category:

- `LAYOUT-*` — geometry regressions (element moved,
  overlapping, clipped)
- `TYPOGRAPHY-*` — text rendering (size, weight, color)
- `COLOR-*` — palette drift, brand-color deviation
- `CONTRAST-*` — WCAG contrast violations (AA or AAA based
  on domain)
- `ALIGNMENT-*` — visual alignment issues (gutter,
  baseline, grid)
- `OVERFLOW-*` — content cut off / scrollbar issues
- `BROKEN-STATE-*` — an obvious error state (missing image,
  empty placeholder, loader stuck visible)

Each category has an entry in `finding-catalog.md` with
severity + confidence hints. A finding with no matching
category classifies as `UNCLASSIFIED-VISUAL` (same shape as
the other taxonomy gaps — a few are fine, > 20% blocks).

### Step 5 — Filter by confidence
Every finding carries a `confidence` in `[0, 1]`. The skill
applies a confidence filter to avoid acting on
hallucinations:

- `confidence >= 0.8` → retained at its declared severity
- `0.6 <= confidence < 0.8` → severity demoted one level
  (`critical → warning`, `warning → info`); surfaced in
  the report but with a "probable" prefix in the finding
  title
- `confidence < 0.6` → recorded in the run artifact as
  `low-confidence` but NOT in the human-readable report.
  The artifact is available for auditing; the report is
  kept signal-dense.

This is the main structural rule that keeps the vision
model from gate-blocking on uncertain findings. A finding
can be re-elevated later when the model's confidence rises
(subsequent runs confirm it), but the skill never auto-
elevates within a single run.

### Step 6 — Apply domain contrast rules
Contrast findings (`CONTRAST-*`) are evaluated against the
domain's required WCAG level:

| Domain | WCAG level | Text contrast min | Large-text min |
|--------|-----------|--------------------|----------------|
| `healthcare` | **AAA** | 7.0 | 4.5 |
| `financial` | **AA** | 4.5 | 3.0 |
| `e-commerce` | **AA** | 4.5 | 3.0 |
| `general` | **AA** | 4.5 | 3.0 |

Healthcare requires AAA because patient data is read under
low-light conditions in real-world clinical use. The other
three use AA as the baseline. Domains can only TIGHTEN via
`test-strategy.md → contrastOverride` — loosening is
rejected at config load.

### Step 7 — Aggregate + score
Compute:

```
criticalFindings  = findings where severity == "critical"
warningFindings   = findings where severity == "warning"
infoFindings      = findings where severity == "info"
p0Critical        = findings where severity == "critical" && priority == "P0"
lowConfidenceFindings = findings where confidence < 0.6
```

### Step 8 — Apply the gate

| Condition | Verdict |
|-----------|---------|
| Zero critical findings AND zero P0 warnings AND contrast rule met | PASS |
| Zero critical findings AND at most 1 P0 warning AND contrast rule met | NEEDS_REVISION |
| Any critical finding OR ≥ 2 P0 warnings OR contrast rule failed | BLOCKED |
| > 20% of findings are UNCLASSIFIED-VISUAL | BLOCKED (taxonomy gap) |

**Gate contract: zero critical visual regressions in P0
scenarios, accessibility findings require remediation,
design-diff above tolerance needs human review.**

No override flag on critical findings. A team that wants to
accept a visual regression must suppress the specific finding
by id in `test-strategy.md → visualSuppressions` with a
mandatory text rationale — same discipline as the other
skills' suppression blocks.

### Step 9 — Write outputs

1. **`.vibeflow/reports/visual-report.md`** — human-readable
   summary with findings grouped by category + severity
2. **`.vibeflow/artifacts/visual/<runId>/findings.json`** —
   every finding including low-confidence ones, for audit
3. **`.vibeflow/artifacts/visual/<runId>/annotated/`** —
   annotated PNG(s) with finding markers overlaid when
   position data was returned (some categories like
   LAYOUT-* include bounding boxes; others don't)
4. **`.vibeflow/artifacts/visual/<runId>/compare-impl.json`**
   — the structural compare result from Step 2, for the
   post-mortem chain

## Output Contract

### `visual-report.md`
```markdown
# Visual AI Report — <runId>

## Header
- Run id: <runId>
- Modes: baseline-diff + standalone (additive)
- Screenshot: path
- Baseline: path
- Design reference: — | figma://... (via design-bridge)
- Domain: financial (contrast: WCAG AA)
- Structural compare: same-dimensions (via db_compare_impl)
- Findings: N (critical: c, warning: w, info: i)
- Low-confidence filtered: L
- Verdict: PASS | NEEDS_REVISION | BLOCKED

## Critical findings (gate-blocking)
### LAYOUT-ELEMENT-OVERLAP on SC-112 (P0)
- Priority: P0
- Mode: baseline-diff
- Confidence: 0.92
- Description: "The Submit button overlaps the cancel link
  at the bottom of the form; baseline shows 16px gap, current
  shows negative 4px overlap"
- Suggested region: `(128,480)-(280,520)`
- Rationale from catalog: buttons overlapping links make
  the wrong action easy to tap accidentally
- Remediation: restore the form-footer flexbox gap
- Evidence: annotated/SC-112-overlap.png

## Contrast findings
### CONTRAST-BODY-TEXT on SC-114 (P1)
- Priority: P1
- Mode: standalone
- Confidence: 0.85
- Domain rule: WCAG AA (4.5 minimum for body text)
- Measured contrast: 3.8
- Text: "Terms and conditions"
- Color pair: `#9ca3af on #f9fafb`
- Remediation: darken the text color or lighten the background

## Probable findings (demoted from higher severity)
### LAYOUT-MARGIN-DRIFT (probable) on SC-115
- Priority: P2
- Original severity: warning → demoted to info (confidence 0.68)
- Description: "Card margins appear slightly different; 16px in
  baseline vs ~18px in current, but may be a rounding artifact"

## Design drift (design-comparison mode)
- Drift score: 0.14 (threshold: 0.10)
- Within tolerance: no — NEEDS_REVISION
- Primary drift: "Hero headline font weight differs: design uses
  semibold, current renders regular"
```

## Gate Contract
**Zero critical visual regressions in P0 scenarios,
accessibility findings require remediation, design-diff above
tolerance needs human review.** Three ways to violate:

1. Any `critical` finding with `confidence >= 0.8` on a P0
   scenario → BLOCKED regardless of the overall run's other
   state. Critical = "the user will see this and it's wrong"
2. More than 1 `warning` finding on P0 OR any contrast
   violation below the domain minimum → BLOCKED. Accessibility
   isn't NEEDS_REVISION territory; WCAG violations are legal
   risks in most domains
3. `lowConfidenceFindings / totalFindings > 50%` is a
   degraded-signal state and downgrades a PASS to
   NEEDS_REVISION (the model wasn't sure about most of what
   it said)

Suppression path: `test-strategy.md → visualSuppressions`
with a mandatory `rationale` field per suppressed finding
id. Suppression without a rationale is rejected at load
time. Suppressions can only DEMOTE a finding's severity or
remove it entirely; they cannot elevate a finding to
critical (that's never needed — the skill does that itself).

## Non-Goals
- Does NOT replace `db_compare_impl`. Structural compare
  handles dimension + byte-identity; visual compare handles
  everything else.
- Does NOT run the app under test. The screenshots come
  from `e2e-test-writer`'s specs or `uat-executor`'s traces.
- Does NOT tell you what the correct design is. It measures
  drift from an existing reference — the team decides the
  reference is correct.
- Does NOT auto-fix layouts. The report points at problems;
  humans fix them.
- Does NOT generate alt text or other accessibility fixes.
  Contrast is one narrow slice of accessibility; the rest
  lives in `checklist-generator`'s accessibility context
  and the e2e skill's `a11y-*` rules.
- Does NOT gate on the model's agreement with the Figma
  design to pixel perfection. Design drift has its own
  tolerance (Step 8 rule 3) and small drift is expected
  between design and implementation.

## Downstream Dependencies
- `release-decision-engine` — reads `findings.json` as a
  weighted quality signal. Critical findings feed the
  hard-blocker list alongside `coverage.p0Uncovered` and
  `mutation.p0Survivors`.
- `learning-loop-engine` — ingests `findings.json` over time
  to spot systematic visual weaknesses ("this screen keeps
  drifting from design").
- `checklist-generator` — reads contrast findings to enrich
  accessibility checklists with specific remediation
  suggestions.
- `test-result-analyzer` — reads critical findings to enrich
  bug tickets with visual evidence for affected scenarios.
