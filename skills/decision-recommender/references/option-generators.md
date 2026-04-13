# Option Generators

How `decision-recommender` produces the option set at Step 2
of its algorithm. Every decision type from `decision-types.md`
names a generator here; the generator knows how to turn the
findings + context into a structured option list.

**The load-bearing rules for every generator:**

- **Option 0 is ALWAYS "do nothing".** No exceptions, no
  overrides, no configuration. Every generator's first
  output is "no change". This is the skill's single most
  important structural rule.
- **Every option has at least one positive AND one negative
  trade-off.** An option with only upsides is a rephrased
  "do nothing"; an option with only downsides is a
  strawman. Both are rejected at generation time.
- **Every option cites at least one finding.** An option
  without a supporting finding is a gut call; the skill
  refuses to emit gut calls.
- **`unknown` is a first-class field.** Every option must
  list at least one thing the skill can't answer. Zero-
  unknowns options are flagged for review because they're
  usually confidently wrong.

---

## 1. `release-options` (for `release-go-no-go`)

### Inputs

- The release's findings (the CONDITIONAL verdict's reason
  list)
- `release-decision.md` with the weighted score breakdown
- `vibeflow.config.json` for domain + risk tolerance
- `team-context.md` for team velocity (when present)

### Option template

The generator produces between 4 and 6 options, always
including these four:

1. **OPT-0 — Do nothing (delay the release)**
   - Positive: no release risk introduced
   - Negative: scheduled release date slips; whatever
     opportunity the release was capturing is lost
   - Unknown: whether the delay will expose new problems

2. **OPT-1 — Ship behind a feature flag**
   - Positive: release lands on time; risk is isolated to
     the flagged path; rollback is a flag flip
   - Negative: engineering overhead to build and maintain
     the flag; flag removal deferred
   - Unknown: how long the flag will live (the generator
     flags this specifically — feature flags that "live
     forever" are an anti-pattern)

3. **OPT-2 — Ship with extra monitoring**
   - Positive: release lands on time; real user data
     informs the next decision
   - Negative: the monitoring has to be set up AND read
     by on-call in the release window
   - Unknown: whether the extra monitoring will actually
     catch the specific risk

4. **OPT-3 — Ship a subset of the release**
   - Positive: risky feature is excluded; the rest ships
     on time
   - Negative: subset release is more work to package
     and document; the excluded feature delays anyway
   - Unknown: whether the dependencies between features
     allow a clean subset

Optional additional options (when the findings support
them):

5. **OPT-4 — Ship after a specific remediation**
   - Used when the CONDITIONAL verdict names a specific
     gate the team could fix inside the release window
6. **OPT-5 — Ship with a co-deploy of a rollback plan**
   - Used when the rollback itself is the risk (complex
     deploys where "rolling back" is as scary as "rolling
     forward")

### Scoring

- `risk` — from the finding's severity + blast radius
- `speed` — from the option's "ships this week" vs
  "delays the release" stance
- `team-fit` — from `team-context.md.releaseExperience`
  when present; `null` otherwise

---

## 2. `gate-options` (for `gate-adjustment`)

### Inputs

- The current gate's configuration (from the relevant
  `references/*.md`)
- Historical runs showing the gate's actual behavior
- `learning-loop-engine` findings about the gate

### Option template

4 options, always:

1. **OPT-0 — Do nothing (keep the gate as-is)**
   - Positive: no downstream disruption
   - Negative: the gate's current behavior persists
     (whatever friction or gap motivated the decision)
   - Unknown: whether the gate's behavior will change on
     its own as the codebase evolves

2. **OPT-1 — Tighten the gate**
   - Positive: catches more of whatever the findings
     showed it was missing
   - Negative: more PR blocks, more team friction
   - Unknown: the false-positive rate of the tightened
     threshold on the current suite

3. **OPT-2 — Loosen the gate**
   - Positive: fewer PR blocks, less friction
   - Negative: accepts some of the signal the gate was
     previously catching
   - Unknown: whether the loosened bar will catch
     tomorrow's regression
   - **NOTE: VibeFlow convention is that gates only
     tighten via config overrides.** This option exists
     for decisions about the DEFAULT threshold change in
     the `references/*.md` files themselves, which IS a
     governance move. The generator flags this option
     with a `governance: true` marker so the team treats
     it as a "change the default for everyone" decision,
     not a "loosen for this project" decision.

4. **OPT-3 — Add a suppression list entry**
   - Positive: targeted relief for specific cases without
     changing the overall gate
   - Negative: suppressions accumulate; future teams
     inherit the list
   - Unknown: whether the suppression will be revisited
     in a future sprint

### Scoring

- `risk` — what the gate was catching vs what the change
  would let through
- `effort` — usually XS for all options (it's a config
  edit), but `OPT-1` + governance options are S because
  they require review
- `team-fit` — from `team-context.md.gateFriction` when
  present

---

## 3. `priority-options` (for `priority-change`)

### Inputs

- The scenario / test / requirement's current priority
- The findings justifying a change
- `regression-baseline.json` for the P0 list
- `scenario-set.md` for priority definitions

### Option template

4 options, always:

1. **OPT-0 — Do nothing**
2. **OPT-1 — Promote one tier** (P2 → P1, P1 → P0, etc.)
3. **OPT-2 — Demote one tier**
4. **OPT-3 — Mark as `@quarantined`**
   - Removes the test from gates entirely
   - Positive: stops the friction immediately
   - Negative: future failures go unnoticed
   - Unknown: whether the quarantine will ever be lifted
     (quarantined tests that stay quarantined for > 2
     sprints are a `learning-loop-engine` finding)

### Scoring

- `risk` — the cost of the wrong priority
  (too-high = friction, too-low = missed regression)
- `effort` — XS for all options (a tag change)
- `team-fit` — `null` (priority changes apply uniformly)

---

## 4. `risk-options` (for `risk-acceptance`)

### Inputs

- The finding being accepted, including its full context
- Any previous remediation attempts documented in the
  history
- Domain (financial + healthcare decisions are harder to
  accept than e-commerce / general)

### Option template

4 options, always:

1. **OPT-0 — Do nothing (keep trying to fix)**
   - Positive: the underlying problem eventually gets
     addressed
   - Negative: effort is spent on a problem that may be
     irreducible
   - Unknown: whether the next attempt will succeed

2. **OPT-1 — Accept with full suppression**
   - Positive: stops recurring noise immediately
   - Negative: the problem persists; the suppression list
     grows; suppression creep is a
     `learning-loop-engine` pattern
   - Unknown: regulatory implications (`domain-specific`)

3. **OPT-2 — Accept with partial mitigation**
   - Positive: some risk reduction without full fix
   - Negative: more complex than full suppression;
     ongoing maintenance cost
   - Unknown: whether the mitigation will hold under
     load / edge cases

4. **OPT-3 — Escalate to external owner**
   - Positive: the real fix happens where it should
     (vendor, upstream, regulator)
   - Negative: timeline is not under the team's control
   - Unknown: how long the escalation will take

### Scoring

- `risk` — weighted heavily toward DOMAIN (financial +
  healthcare acceptances are riskier than e-commerce +
  general)
- `cost` — the direct cost of each option (support
  contracts, vendor fees, ongoing monitoring)
- `team-fit` — how well the team handles acceptance
  decisions (some teams are uncomfortable, others thrive)

---

## 5. `scope-options` (for `scope-change`)

### Inputs

- The current sprint scope + velocity
- Findings that motivated the scope question
- `team-context.md` for team size + pace

### Option template

5 options, always:

1. **OPT-0 — Do nothing (keep current scope)**
2. **OPT-1 — Cut scope (drop a feature or defer work)**
3. **OPT-2 — Add resources (temporary expansion)**
4. **OPT-3 — Extend the timeline**
5. **OPT-4 — Swap priorities (do X instead of Y)**

### Scoring

- `risk` — the cost of missing the deadline vs the cost
  of shipping with reduced scope
- `effort` — usually M for all options (they all involve
  replanning)
- `cost` — direct costs for adding resources or extending
  timelines
- `team-fit` — from `team-context.md.planningCulture`

---

## 6. Shared scoring rules

### Risk score computation

All generators derive `riskScore` from the findings:

```
riskScore = mean(
  finding.confidence * finding.severity_weight
  for each finding in option.supportingFindings
)
```

Severity weights:

- `urgent` / `critical` → 1.0
- `investigate` / `warning` → 0.6
- `recommend` / `info` → 0.3

Risk score is on `[0, 1]` but the skill never presents a
single "overall score" — the option card shows the raw
`riskScore` alongside the other dimensions for the human
to weigh.

### Effort sizing

T-shirt sizes map to rough ranges, interpreted against the
team's velocity from `team-context.md`:

| Size | Range | Without team context |
|------|-------|---------------------|
| XS | < 1 hour | minimal |
| S  | 1 day or less | small |
| M  | 2-5 days | medium |
| L  | 1-2 sprints | large |
| XL | > 2 sprints | very large |

The generator uses the size + the team's declared
velocity to compute a concrete "percentage of sprint
hours" number in the decision package's effort roll-up
section.

### Trade-off rules

- Every `positive` entry must be specific. "Fast" is not
  a trade-off; "ships 3 days earlier" is.
- Every `negative` entry must be specific. "Some risk"
  is not a trade-off; "adds a feature flag that will
  live for N sprints before removal" is.
- `unknown` entries CANNOT be things the skill could have
  figured out from the findings. They are questions the
  data genuinely can't answer — "will the regulators
  like this" is a valid unknown; "is the coverage score
  above 80%" is not, because the finding answers it.

---

## 7. Validation rules

Before a generated option is accepted, the skill validates:

- `positive.length >= 1` — rejected if empty
- `negative.length >= 1` — rejected if empty
- `unknown.length >= 1` — rejected if empty
- `supportingFindings.length >= 1` for OPT-1 through
  OPT-N (OPT-0 is allowed to cite zero findings — "do
  nothing" addresses no findings by definition)
- Every cited finding ID must exist in the input findings

An option that fails any validation is dropped from the
generated set AND recorded in the run metadata as a
generator bug. A run where > 30% of proposed options
fail validation blocks the skill with "generator produced
mostly-invalid options; check the catalog configuration".

---

## 8. Adding a new generator

1. Pick a stable name matching a decision type's
   `optionGenerator` field.
2. Document the input requirements.
3. Define the template options (at least 3, including
   OPT-0 Do Nothing).
4. Name the `tradeoffDimensions` the generator populates.
5. Document any generator-specific scoring rules.
6. Retrospective on at least 5 real decision packages the
   new generator would produce. "Looks reasonable" is
   not enough — the packages have to have been useful.

---

## 9. Current version

**`optionGeneratorVersion: 1`**

- 5 generators (one per decision type in
  `decision-types.md`)
- Shared risk + effort rules
- 4 mandatory validation rules at acceptance time

Version bumps: retrospective + version bump + migration
note + harness sentinel update.
