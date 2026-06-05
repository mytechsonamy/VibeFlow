# Template-Route Autonomy (Sprint 27)

The learning loop's "act" stage has two lanes (see
[ACTION-GAP.md](ACTION-GAP.md)):

- **config-tune** — a `vibeflow.config.json` knob → a diff-first config
  patch, optionally **bounded auto-apply** with auto-revert
  ([AUTO-APPLY.md](AUTO-APPLY.md)).
- **template-route** — a `recurring-suggestion-theme` (the same theme
  across ≥3 artifacts — a systemic PRD/ADR/test-strategy gap, not a
  config knob) → a structural **rewrite**.

Before v2.15.0 the template lane was recommend-only: `learning-apply`
just wrote "run `/vibeflow:consensus-specialist` by hand". Sprint 27 makes
it **auto-fork the specialist** — but **propose-only**.

## The flow (opt-in)

```
recurring-suggestion-theme finding
        │  learningApply.autoForkSpecialist == true
        ▼
learning-apply writes a learning-fork brief
   .vibeflow/state/patches/learning-fork-<ts>/brief.md
        ▼  forks the matching phase specialist (phase→agent map)
prd-rewriter / adr-author / … reads the brief + artifact
        ▼  emits ONE diff-first patch into the fork dir (never writes source)
operator: /vibeflow:apply-arbiter-patch   ← preview + confirm + apply
```

With `autoForkSpecialist` **false** (the default) the lane is unchanged:
`learning-apply` only *recommends* the specialist invocation.

## Propose-only — and why templates stay confirm-only

`learning-apply` **never applies a template patch.** It forks the
specialist and stops; the diff-first patch sits under
`.vibeflow/state/patches/learning-fork-<ts>/` until the operator confirms
it via `/vibeflow:apply-arbiter-patch`.

This is deliberately stricter than config's bounded auto-apply (Sprint
23–24). Config tunes are small, schema-bounded, and **auto-reverted** if
the next consensus round regresses. A template/PRD/ADR rewrite is large,
unbounded, and not mechanically revertible against an agreement curve —
so it stays human-confirmed. Auto-fork removes the *manual dispatch*
toil; it does not remove the *human review* of the rewrite.

## Configuration

```jsonc
{
  "learningApply": {
    "autoForkSpecialist": false   // Sprint 27: opt-in template auto-fork (default OFF)
  }
}
```

## The brief

The specialist is normally driven by a consensus session (`verdict.json`
+ reviewer `suggestions[]`). In the auto-fork path there's no session, so
`learning-apply` writes a **learning-fork brief** (theme, affected
artifact, seenCount, rationale, evidence pointer) that the specialist
treats as the structural gap to resolve. Format + contract:
`agents/_shared/learning-fork-brief.md`. All six phase specialists accept
it; the diff-first / never-write-source contract is unchanged.

## See also

- [ACTION-GAP.md](ACTION-GAP.md) — the full observe → frame → act loop.
- [LEARNING-APPLY.md](LEARNING-APPLY.md) — the skill + its three lanes.
- [AUTO-APPLY.md](AUTO-APPLY.md) — the config lane's bounded auto-apply.
