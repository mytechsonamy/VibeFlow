# Decision Type Catalog

Every decision type the `decision-recommender` skill can
frame. The skill walks this catalog at Step 1 of its
algorithm. Inventing a type at prompt time is forbidden;
findings that don't match any type land in
`UNCLASSIFIED-DECISION` and the skill blocks with remediation
"extend decision-types.md with a new type for this input
shape".

Every type has seven fields:

- **id** — stable identifier cited in the decision package
- **detectionSignature** — the pattern in findings that
  indicates "this is the decision this type handles"
- **requiredInputs** — fields that must be present
- **optionGenerator** — which generator in
  `option-generators.md` produces options
- **tradeoffDimensions** — axes the options are scored
  along (not all options use every dimension)
- **typicalConfidence** — the confidence level the skill
  usually achieves for this type (operators calibrate
  against this)
- **examples** — concrete example questions this type
  answers

---

## 1. `release-go-no-go`

### When it fires

A release is pending AND `release-decision-engine` has
produced a `CONDITIONAL` verdict, OR a team explicitly asks
"should we ship this?".

### Fields

- **id**: `release-go-no-go`
- **detectionSignature**: findings include at least one
  entry from `release-decision.md` with
  `verdict: "CONDITIONAL"` OR the caller passes `--type
  release-go-no-go`
- **requiredInputs**: `release-decision.md`, all the
  gates' verdict summaries
- **optionGenerator**: `release-options`
- **tradeoffDimensions**: risk / speed / team-fit
- **typicalConfidence**: 0.7 — CONDITIONAL decisions are
  usually well-bounded; the skill tends to converge
- **examples**:
  - "We have 1 flaky P0 test and a 0.03 coverage gap. Ship?"
  - "Mutation score dropped 4% on the payment module. Ship?"
  - "Web vitals are within budget but chaos resilience
    dropped by 8 points. Ship?"

### Options this type typically generates

- **OPT-0**: Do nothing (delay the release until the
  conditions clear)
- **OPT-1**: Ship with a feature flag for the affected path
- **OPT-2**: Ship with extra monitoring + rollback plan
- **OPT-3**: Ship a subset of the release (exclude the
  affected feature)

---

## 2. `gate-adjustment`

### When it fires

The team is considering changing a gate threshold, adding
a new gate, or removing an existing one. Usually driven by
a `learning-loop-engine` recommendation that a specific
gate is either too loose or causing friction.

### Fields

- **id**: `gate-adjustment`
- **detectionSignature**: findings reference `gate`,
  `threshold`, or `suppression` in their descriptions;
  OR `--type gate-adjustment`
- **requiredInputs**: the current gate's configuration
  (from the relevant `references/*.md`) AND at least one
  finding showing the gate's current behavior on real
  runs
- **optionGenerator**: `gate-options`
- **tradeoffDimensions**: risk / effort / team-fit
- **typicalConfidence**: 0.6 — gate adjustments have
  significant unknowns (team reaction, historical
  baseline impact)
- **examples**:
  - "Coverage gate has been NEEDS_REVISION for 4 sprints;
    tighten or accept?"
  - "Mutation test threshold is blocking 40% of PRs;
    adjust or pay the cost?"
  - "Should we add a gate for visual regression above
    X confidence?"

### Options this type typically generates

- **OPT-0**: Do nothing (keep the gate as-is)
- **OPT-1**: Tighten the gate (stricter threshold)
- **OPT-2**: Loosen the gate (looser threshold)
- **OPT-3**: Add an escape hatch (suppression list with
  audit trail)
- **OPT-4**: Remove the gate entirely (rare, usually
  wrong, but always an option)

---

## 3. `priority-change`

### When it fires

A test, scenario, or requirement is a candidate for
priority promotion or demotion. Usually driven by
`LEARNING-PRIORITY-DRIFT` from learning-loop-engine.

### Fields

- **id**: `priority-change`
- **detectionSignature**: findings reference `@priority`
  tags, `P0 list`, or `scenario priority`; OR
  `--type priority-change`
- **requiredInputs**: the scenario / test / requirement's
  current priority AND the findings justifying a change
- **optionGenerator**: `priority-options`
- **tradeoffDimensions**: risk / effort / team-fit
- **typicalConfidence**: 0.65 — priority changes affect
  the whole gate chain
- **examples**:
  - "SC-112 is flaky and P0; demote to P1 or fix?"
  - "This new feature passed UAT but has no P0 tag; promote?"
  - "P0 list has grown 30% in 2 sprints; which to demote?"

### Options this type typically generates

- **OPT-0**: Do nothing (keep current priority)
- **OPT-1**: Promote to a higher priority tier
- **OPT-2**: Demote to a lower priority tier
- **OPT-3**: Mark as `@quarantined` (priority-neutral,
  removed from gates entirely)

---

## 4. `risk-acceptance`

### When it fires

A finding or anomaly has surfaced that the team may
explicitly accept (document + move on) rather than fix.
Usually used for third-party dependencies, legacy code,
or irreducible bugs.

### Fields

- **id**: `risk-acceptance`
- **detectionSignature**: findings with `irreducible` or
  `third-party` classification, OR findings that have
  been `recurring` for ≥ 3 sprints without remediation;
  OR `--type risk-acceptance`
- **requiredInputs**: the finding's full context, any
  previous remediation attempts
- **optionGenerator**: `risk-options`
- **tradeoffDimensions**: risk / cost / team-fit
- **typicalConfidence**: 0.55 — acceptance decisions are
  judgment calls the skill can't conclusively make
- **examples**:
  - "This CSP violation is from a legitimate third-party
    script we can't move. Accept?"
  - "This known vendor library bug won't be fixed
    upstream; work around or accept?"
  - "We've tried to fix the flaky login test 4 times and
    the only cause is real network latency we can't
    control. Accept?"

### Options this type typically generates

- **OPT-0**: Do nothing (keep trying to fix)
- **OPT-1**: Accept with full suppression (add to
  `test-strategy.md` suppression list with rationale)
- **OPT-2**: Accept with partial mitigation (some
  countermeasure + suppression)
- **OPT-3**: Escalate to external owner (vendor ticket,
  upstream bug report)

---

## 5. `scope-change`

### When it fires

A sprint's scope is candidate for reduction or a feature's
scope is candidate for expansion, driven by findings that
suggest the current scope is mis-sized for the team or
the environment.

### Fields

- **id**: `scope-change`
- **detectionSignature**: findings reference effort
  estimates, team velocity, or sprint capacity; OR
  `--type scope-change`
- **requiredInputs**: the current scope, team velocity
  (from `team-context.md`), findings justifying the
  change
- **optionGenerator**: `scope-options`
- **tradeoffDimensions**: risk / effort / cost / team-fit
- **typicalConfidence**: 0.6 — scope changes are
  team-dependent
- **examples**:
  - "We're 3 sprints behind on coverage. Cut a feature
    or add a sprint?"
  - "Learning loop shows 5 recurring urgent findings.
    Fix them or defer for new work?"
  - "Chaos testing takes longer than expected. Drop
    chaos or slow the release?"

### Options this type typically generates

- **OPT-0**: Do nothing (keep current scope)
- **OPT-1**: Cut scope (drop features / defer work)
- **OPT-2**: Add resources (temporary team expansion)
- **OPT-3**: Extend timeline (slip the deadline)
- **OPT-4**: Swap priorities (do X instead of Y)

---

## 6. `UNCLASSIFIED-DECISION`

### When it fires

None of the above match.

### Fields

- **id**: `UNCLASSIFIED-DECISION`
- **detectionSignature**: fallback
- **requiredInputs**: —
- **optionGenerator**: — (skill blocks before generation)
- **tradeoffDimensions**: —
- **typicalConfidence**: 0.0
- **examples**: —

### What happens

The skill blocks with remediation "extend
decision-types.md with a new type for this input shape".
The blocker record includes the findings' categories so a
human can name what's missing.

A single `UNCLASSIFIED-DECISION` run is acceptable — it's
a signal to extend the catalog. Recurring unclassified
decisions suggest the skill's catalog is drifting from
reality.

---

## 7. Walk order

The skill walks the catalog from specific to general:

1. `release-go-no-go` (most specific)
2. `gate-adjustment`
3. `priority-change`
4. `risk-acceptance`
5. `scope-change`
6. `UNCLASSIFIED-DECISION` (fallback)

The first type whose detection signature matches wins.
Ties are broken by the specificity order above — a
finding that matches both `gate-adjustment` and
`risk-acceptance` classifies as `gate-adjustment`,
because that's the more concrete action.

---

## 8. Adding a new type

1. Pick a stable id (kebab-case, specific).
2. Declare the detection signature precisely — a regex or
   an explicit field check, not "it feels like this type".
3. Name an `optionGenerator` from
   `option-generators.md` (or add a new one first).
4. List tradeoff dimensions the generator uses.
5. Set a `typicalConfidence` based on retrospective data
   — not a guess.
6. Update the walk order in §7. New types are inserted in
   specificity order.
7. Update the integration harness sentinel that counts
   decision types.

---

## 9. Current catalog version

**`decisionTypeCatalogVersion: 1`**

- 5 active types + 1 fallback
- Walk order: specific-to-general
- Every type declares its own option generator

Version bumps follow the VibeFlow governance discipline
(retrospective on ≥ 5 real decision packages + version bump
+ migration note + harness sentinel).
