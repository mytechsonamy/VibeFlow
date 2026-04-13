---
name: decision-recommender
description: Produces structured decision packages (problem statement + options + trade-offs + recommendation + effort estimate) from any findings report. Used when a decision needs framing, not auto-gating. Consumes learning-loop-engine recommendations + L2 skill reports + team context, and emits decision-package.md. Gate contract — every recommendation cites specific findings, every option has trade-offs in both directions, every recommendation carries an effort estimate, 'do nothing' is always included as option zero. PIPELINE-4 step 2 (conditional).
allowed-tools: Read Write Grep Glob
context: fork
agent: Explore
---

# Decision Recommender

An L3 Truth-Evolution skill. Where `learning-loop-engine`
surfaces patterns across time, this skill turns a specific
question — "should we ship this? should we add this gate?
should we accept this risk?" — into a document the team can
read, argue with, and decide on. The output is NEVER a single
answer. It's **always** a set of options with their real
trade-offs, including "do nothing" as option zero, and a
recommendation with an explicit confidence level.

The failure mode this skill is designed against: AI-assisted
decision tools that confidently produce one "correct" answer
and make the human feel bad for questioning it. That's not a
decision, that's an opinion delivered with extra steps. Real
decisions involve trade-offs, and a recommendation without
trade-offs is either obvious (in which case the human didn't
need help) or wrong (in which case the tool made it harder).

## When You're Invoked

- **PIPELINE-4 step 2 (conditional)** — only when a decision
  is explicitly requested by a human or another skill. Not
  auto-invoked on every run. This is slow-loop, high-context,
  human-in-the-loop territory.
- **On demand** as
  `/vibeflow:decision-recommender <findings-path> [--type <t>]`.
- **From `learning-loop-engine`** when a pattern has
  escalated to `urgent` and the team needs an options-based
  framing, not just a one-liner recommendation.
- **From `release-decision-engine`** when the release verdict
  is `CONDITIONAL` and the team needs to decide which
  condition to accept.

## Input Contract

| Input | Required | Notes |
|-------|----------|-------|
| Findings report | yes | Any `*-report.md` or `findings.json` from an L2 / L3 skill. A decision without findings is a gut call; the skill refuses. |
| Decision type | optional | `--type <t>` where `t` is one of the catalog entries (see `decision-types.md`). Auto-detected from the findings when absent. |
| Team context | optional | `.vibeflow/team-context.md` — team size, sprint velocity, risk tolerance, known constraints. When present, recommendations are tuned to the team's actual capacity; when absent, the skill uses the domain default. |
| Decision history | optional | Previous `decision-package.md` files under `.vibeflow/artifacts/decisions/`. Used to detect "we've decided this before" situations — re-asking is sometimes the right answer, but the skill flags it. |

**Hard preconditions** — refuse rather than emit a decision
package the team shouldn't trust:

1. At least one finding in the input must be actionable.
   A findings report with zero actionable entries → block
   with "nothing to decide on; run the upstream analysis
   first". The upstream skill is responsible for producing
   actionable signals.
2. The decision type must resolve. Auto-detection walks the
   findings' categories against `decision-types.md`; if no
   type matches with confidence ≥ 0.6, the skill asks the
   caller to pass `--type` explicitly.
3. When a `team-context.md` exists, it must be valid — a
   malformed team context silently biases every
   recommendation, and that's worse than not reading it at
   all. A parse error blocks with "team-context.md is
   malformed; fix it or delete it for this run".

## Algorithm

### Step 1 — Detect the decision type
Read `references/decision-types.md`. Every type declares:

- `id` — stable identifier cited in the decision package
- `detectionSignature` — the pattern in the findings that
  indicates "this is the decision this type handles"
- `requiredInputs` — which fields must be present in the
  findings
- `optionGenerator` — which generator in
  `references/option-generators.md` produces options for
  this type
- `tradeoffDimensions` — the axes along which options are
  compared (risk / effort / cost / speed / team-fit)

The skill walks the catalog and picks the first type whose
signature matches. Multiple matches are possible — the
caller can pass `--type` to disambiguate, or the skill picks
the most specific type (the catalog orders them from
specific to general, same rule as the other catalog skills).

**UNCLASSIFIED-DECISION** is the fallback. A findings set
that doesn't match any type lands here, and the skill
blocks with remediation "extend decision-types.md with a
new type for this input shape".

### Step 2 — Generate options
Hand the findings + type to the `optionGenerator` named by
the catalog entry. Every generator produces AT LEAST TWO
options, AND option 0 is ALWAYS "do nothing / no change".
No exceptions. "Do nothing" is a real option; omitting it
makes every decision feel forced, which is how teams make
bad choices under AI pressure.

Each option has:

```ts
interface DecisionOption {
  id: string;                // "OPT-1", "OPT-2", ...
  name: string;              // short title
  description: string;       // one paragraph
  tradeoffs: {
    positive: readonly string[]; // at least one, must be specific
    negative: readonly string[]; // at least one, must be specific
    unknown: readonly string[];  // things the data can't answer
  };
  effortEstimate: {
    sizing: "XS" | "S" | "M" | "L" | "XL"; // T-shirt size
    reasoning: string;                       // one-line "why this size"
  };
  riskScore: number;          // 0..1 — how risky is this option
  supportingFindings: readonly string[]; // finding ids this option addresses
}
```

**`tradeoffs.positive.length >= 1 && tradeoffs.negative.length >= 1`** is enforced — an option with only upsides is usually a rephrased "do nothing" in disguise, and an option with only downsides is usually a strawman. The skill rejects options that fail this check and records them in the run metadata as "generator bug, please report".

**`unknown` is not optional**. Every option must list at
least one thing the skill can't answer about it (future
regulatory changes, team preference, hard-to-predict user
reaction). Zero-unknowns options are suspicious — usually
the generator is confidently wrong.

### Step 3 — Score each option
For every option, score on the decision type's `tradeoffDimensions`:

- **`risk`** — probability × blast radius of things going
  wrong, derived from the findings' evidence
- **`effort`** — scaled from the T-shirt sizing, influenced
  by `team-context.md → velocity`
- **`cost`** — direct cost of the change (infra cost, tool
  cost, hiring cost) when applicable; `null` otherwise
- **`speed`** — how quickly the change can ship,
  independent of effort (effort is "how much work", speed
  is "wall-clock until done")
- **`team-fit`** — how well the option matches the team's
  current stack / skills / values, from `team-context.md`.
  `null` when no team context

Scores are in `[0, 1]`. Higher means "more of this
dimension". **The skill NEVER computes a single weighted
composite score.** Weighting is a team judgment — the
recommendation section names the option the skill would
pick, but the raw scores are preserved so the team can
re-weight.

### Step 4 — Compute the recommendation
The skill picks ONE option as its recommendation based on:

- The option's `riskScore` vs the domain's risk tolerance
  (`vibeflow.config.json.riskTolerance`)
- The option's `effortEstimate.sizing` vs the team's
  velocity (`team-context.md.velocity`, when present)
- The option's `supportingFindings.length` relative to
  the other options

Every recommendation carries:

- `optionId` — which option was picked
- `confidence` — `[0, 1]`, honest
- `reasoning` — one paragraph explaining the pick
- `alternatives` — 1-2 other options the skill would be
  comfortable with, with a one-line "why not this one"
  note

**When confidence < 0.7, the recommendation is downgraded
to `human-judgment-needed`** and the report's top-level
section says "the data does not conclusively favor any
option; the team should decide". This is the structural
honesty rule — a vague recommendation is worse than "we
can't tell you".

### Step 5 — Decision history cross-check
Walk `.vibeflow/artifacts/decisions/` for previous packages
on the same problem. A decision on the same problem within
the last 30 days produces a `repeat-decision` warning:

- The previous decision is cited in the report
- The new options are cross-referenced with the old to
  show what changed
- If nothing material has changed (same findings, same
  team context, same domain), the skill recommends
  "re-read the previous decision; the inputs haven't
  changed" instead of re-deciding

This is the structural rule that keeps the team from
churning on decisions that are already made.

### Step 6 — Write the decision package

1. **`.vibeflow/reports/decision-package.md`** — the
   structured output (see contract below)
2. **`.vibeflow/artifacts/decisions/<timestamp>-<slug>.md`**
   — archived copy for history cross-check in Step 5
3. **`.vibeflow/artifacts/decisions/<timestamp>-<slug>.json`**
   — machine-readable form with every option + score + the
   recommendation, for downstream consumers

## Output Contract

### `decision-package.md`
```markdown
# Decision Package — <runId>

## Header
- Decision type: release-go-no-go | gate-adjustment | priority-change | risk-acceptance | scope-change
- Source findings: <path>
- Team context: <path or "domain default">
- Confidence: 0.82 | human-judgment-needed
- Decision history: no previous | repeat (see <path>)

## Problem statement
<Two or three paragraphs summarizing the specific question
the package answers. The problem is pulled from the
findings, not invented.>

## Findings cited
- <finding id 1> — <one-line summary>
- <finding id 2> — <one-line summary>
- ...
(Every option below must reference at least one of these by id.)

## Options

### Option 0: Do nothing (no change)
- **Description**: status quo — no gate change, no priority
  change, no scope change
- **Positive trade-offs**:
  - No implementation cost
  - No new risk introduced
- **Negative trade-offs**:
  - The findings that motivated this decision remain
    unaddressed
  - Recurring pattern will keep surfacing in future runs
- **Unknown**: whether the team will eventually act on the
  findings without this package
- **Effort**: XS (no work)
- **Risk score**: 0.35 (findings-dependent; "do nothing" is
  not always the lowest-risk option)
- **Supporting findings**: — (addresses none)

### Option 1: Tighten the P0 gate on file X
- **Description**: one-paragraph concrete action
- **Positive trade-offs**:
  - Catches 80% of the recurring failure pattern
  - Low effort (single config change)
- **Negative trade-offs**:
  - Increases PR friction for 2-3 unrelated test files
  - May produce false positives on legacy tests for 1-2
    sprints
- **Unknown**: whether the false positive rate will drop
  after the legacy cleanup sprint
- **Effort**: S (~1 day)
- **Risk score**: 0.2
- **Supporting findings**: LEARNING-RECURRING-FAILURE,
  LEARNING-SAME-FILE-BUG

### Option 2: (more options with same shape)

## Recommendation
- **Pick**: Option 1
- **Confidence**: 0.82
- **Reasoning**: The recurring-failure pattern has been
  escalating for 4 sprints without action. Option 1 is the
  smallest change that addresses the majority of the
  pattern. Option 0 (do nothing) loses because the learning
  loop will keep surfacing this.
- **Alternatives worth considering**: Option 2 is almost
  as good; it costs more effort but also fixes
  LEARNING-SAME-FILE-BUG more comprehensively.

## Repeat-decision warning
(only when step 5 found a previous decision on the same problem)
- Previous decision: <path>
- Decided on: <date>
- Previous outcome: <summary>
- What has changed since: <list of what's new>

## Effort roll-up (if the team context is present)
- Total sprint hours this decision commits: ~N
- Percentage of sprint velocity: X%
- Concurrent decisions in flight: K
- Conflicts with in-flight work: <list>
```

## Gate Contract
**Four invariants that keep the skill from producing
AI-confident nonsense:**

1. **Every option has at least one positive AND one
   negative trade-off.** Options with only upsides are
   rephrased "do nothing" in disguise; options with only
   downsides are strawmen. Enforced at generation.
2. **Option 0 is ALWAYS "do nothing", on every decision.**
   No exceptions. "Do nothing" is a real option and
   omitting it makes decisions feel forced.
3. **Every recommendation cites at least one finding by
   id.** A recommendation with no citation is a gut call,
   and the skill refuses to emit gut calls.
4. **Confidence < 0.7 → `human-judgment-needed`**. The
   skill does not ship vague recommendations dressed up as
   confident ones. The report's header clearly says "the
   data does not conclusively favor any option" and the
   recommendation section is empty.

These are enforcement rules, not soft guidelines — a
decision package that would violate any of them is rejected
before writing and the skill blocks with the specific
violation. `release-decision-engine` refuses to read a
package with `needs-human-review: true` as an authoritative
signal.

## Non-Goals
- Does NOT make decisions. It frames decisions for humans.
  The human reads the package, argues with it, and decides.
- Does NOT auto-open tickets. That's `test-result-analyzer`
  for bug tickets; decision packages are framing documents,
  not backlog entries.
- Does NOT replace sprint planning. The effort roll-up is
  advisory input; the team's planning still decides what
  fits.
- Does NOT try to predict the future. `unknown` is a
  first-class field, and options with many unknowns get
  low confidence automatically.
- Does NOT compute a single weighted score that "solves"
  the decision. Single-score framing is how AI tools make
  teams feel bad for disagreeing.

## Downstream Dependencies
- `release-decision-engine` — reads decision packages for
  CONDITIONAL verdicts. When the skill ships a
  recommendation with confidence ≥ 0.7, the engine treats
  the recommendation as "team's position" input; when
  confidence < 0.7, the engine refuses to read the package
  as authoritative and escalates to human review.
- `learning-loop-engine` — reads decision package history
  to detect "the team keeps making the same decision" as a
  pattern (`LEARNING-DECISION-CHURN` in future catalog
  versions).
- `traceability-engine` — links decision packages to the
  findings they address, so the RTM can show "these
  findings have a decision package".
