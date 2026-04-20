# Arbiter — Decision Matrix and Apply Workflow

The `consensus-arbiter` skill is the bridge between the three
reviewers (Claude + codex + gemini) and the files on disk. It reads
their `suggestions[]` from the session jsonl, decides per-suggestion
whether the change belongs **in this phase, in this domain, right
now**, and produces diff-first patches the operator applies with
`apply-arbiter-patch`.

Arbiter never writes to source files. That separation is the
diff-first contract we chose in the Sprint 15 plan.

## Decision matrix

Arbiter walks each suggestion in order. The first rule that matches
wins.

| Condition | Decision | Rationale |
|---|---|---|
| `phase_relevance` doesn't contain current phase | **DEFER** | Forward to the target phase log — apply when we get there |
| `type == "question"` | **DEFER** | Answer belongs in the artifact's reply section, not in a patch |
| Domain policy conflict (financial: weakens an invariant weight, loosens a threshold, drops audit; healthcare: reduces coverage target; e-commerce: skips UAT evidence) | **REJECT** | Domain policy is non-negotiable |
| `proposed_change` < 30 chars or obviously vague | **DEFER** | Not enough signal to synthesise a correct patch |
| ≥ 2 reviewers propose overlapping changes at ≥ medium priority | **APPLY** (consolidated) | Cross-model agreement is the arbiter's highest confidence signal |
| Single reviewer, `priority == "low"` | **DEFER** | One-vote low-priority isn't worth a diff |
| Single reviewer, `priority >= "medium"` AND `type == "fix"` | **APPLY** | Fixes are obligations, not preferences |
| Single reviewer, `type == "enhancement"` at `riskTolerance == "low"` | **DEFER** | Low-tolerance projects don't auto-apply optional improvements |
| Single reviewer, `type == "enhancement"` otherwise | **APPLY** | Enhancements land by default when risk tolerance permits |
| Two reviewers disagree on the same target | **DEFER** + "manual resolution needed" | Don't merge contradicting intents automatically |
| Anything else | **DEFER** | Default safe |

## Iteration guard

Each arbiter run increments a counter in
`.vibeflow/state/patches/<session>/manifest.json`:

```json
{ "sessionId": "...", "iteration": 1, "apply": [...] }
```

If the manifest already exists at iteration 3 and the session is
about to be re-arbitrated (orchestrator → arbiter → apply →
orchestrator → NEEDS_REVISION → arbiter loop), the skill stops
emitting patches and marks the session `deferred_for_human_review`.
This is the loop-limiter from Sprint 15's risk list.

## Outputs (every arbiter run writes these)

- `.vibeflow/reports/arbiter-decisions.md` — human-readable audit
  trail. Every suggestion appears with its decision + rationale.
  The APPLY entries carry `Applied: false`, which
  `apply-arbiter-patch` flips to `Applied: true (appliedAt: <ISO>,
  patch: NN-<slug>.patch)` after a successful apply.
- `.vibeflow/state/patches/<session>/manifest.json` — machine-
  readable version of the APPLY set (for apply-arbiter-patch and
  the learning-loop candidate).
- `.vibeflow/state/patches/<session>/NN-<slug>.patch` — one
  `git apply`-compatible unified diff per APPLY. Filenames sort in
  the order the skill intends them to land.

Arbiter **does not** modify the files named in `target.file`. Those
are apply-arbiter-patch's to touch.

## Apply workflow

```
/vibeflow:apply-arbiter-patch [session]
```

The skill:

1. Resolves the session (arg or the most recent patch directory).
2. Computes `+N/-N` counts via `git apply --numstat <patch>`.
3. Emits a summary block. Example:

   ```
   Arbiter patch preview — session 1101628e-1f1f-…
     Iteration: 1
     Phase: REQUIREMENTS
     Patches: 3 (targeting 2 files)
     Total: +48 -12

     01-error-flows-section.patch
       target: docs/PRD.md (+20 -2)
       sources: claude-3, codex-1
       rationale: Adds missing error-handling flow section 4.2
     ...

   Apply all 3? [y/N]
   ```

4. Asks for `y`/`yes` (case-insensitive) — unless `--yes` or
   `--dry-run`.
5. For each patch: `git apply --check` first; abort the remainder
   on conflict with a regenerate hint. A clean apply lands the
   patch via `git apply`.
6. Updates `arbiter-decisions.md` in place: each APPLY's
   `Applied: false` becomes `Applied: true (appliedAt: <ISO>, patch:
   NN-<slug>.patch)`.
7. With `--run-tests`, runs the project's test command (picked up
   from `tech.testRunner` in `vibeflow.config.json`). On failure,
   prints the `git checkout` rollback command — no auto-revert.
8. Writes `applied/<session>.json` for audit.

## Rollback

Every patch is a plain `git apply`, no commit. Revert options:

```
# revert one file
git checkout HEAD -- docs/PRD.md

# nuke all uncommitted changes (careful)
git reset --hard HEAD

# keep them for later
git stash
```

If you want to re-arbitrate after a rollback, delete the manifest
(`.vibeflow/state/patches/<session>/manifest.json`) and re-run
`/vibeflow:consensus-arbiter <session>`. The iteration counter
resets.

## Domain policies that auto-REJECT

These are the current hard rules. Domain-specific invariants can
loosen arbiter's tolerance elsewhere, but never bypass these:

- `financial`: no suggestion may loosen an invariant weight, soften
  an audit requirement, or reduce the MASAK-equivalent compliance
  metric.
- `healthcare`: no suggestion may reduce coverage targets below
  domain-default 95 / 85.
- `e-commerce`: no suggestion may skip UAT evidence collection.
- `general`: no rejects by default — domain overrides via
  `vibeflow.config.json.arbiter.rejects[]` (Sprint 16+ adds a
  config-driven override list).

## Examples

### Example 1 — PRD gap, two-reviewer overlap (APPLY)

- claude-3: "Missing error-handling flow for rate limiting. Priority
  high. target: docs/PRD.md:45-52. type: fix."
- codex-1: "No circuit-breaker spec for external API timeouts.
  Priority high. target: docs/PRD.md:50-55. type: fix."

Overlap on docs/PRD.md around lines 45-55, both at high priority →
APPLY. Arbiter produces one consolidated patch `01-error-flows.patch`
citing both sources.

### Example 2 — Single reviewer enhancement, medium tolerance (APPLY)

- gemini-2: "Consider adding a section on rate limiting token bucket
  semantics. Priority medium. target: docs/PRD.md. type: enhancement."
- No overlap with the other reviewers. riskTolerance: medium →
  enhancement APPLY rule matches → one patch.

### Example 3 — Out-of-phase suggestion (DEFER)

- codex-4: "Add a unit test for the token bucket. target:
  tests/rate-limit.test.ts. priority: medium. type: fix.
  phase_relevance: [TESTING]."
- Current phase: REQUIREMENTS. phase_relevance doesn't contain
  REQUIREMENTS → DEFER. arbiter-decisions.md logs "deferred to
  TESTING — target tests/rate-limit.test.ts".

### Example 4 — Domain conflict (REJECT)

- gemini-5: "Lower the MASAK recall target to 0.95 to cut latency."
  target: docs/PRD.md. priority: medium.
- Project domain: financial. This would loosen a compliance
  metric → REJECT with rationale "financial domain: recall ≥ 0.995
  is non-negotiable."
