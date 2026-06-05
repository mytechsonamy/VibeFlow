# Self-Correcting Auto-Apply (Sprint 24)

Sprint 23 made config auto-apply *autonomous* (allowlisted tunes apply
without a prompt, auto-revert on regression). Sprint 24 makes it
*self-correcting*: the loop learns from its **own** auto-tuning outcomes
and stops auto-applying keys that never stick.

## The meta-loop

```
auto-apply a key  ──▶  next round judges it  ──▶  outcome row in history.jsonl
      ▲                  (aggregator)              {auto-apply, auto-revert, auto-apply-held}
      │                                                      │
      │                                                      ▼
  learning-apply  ◀── self-demote ◀── revert count ◀── learning-loop detector
  (proposes instead)                                   (auto-tune-ineffective)
```

Every auto-tune now leaves a queryable trail in
`.vibeflow/state/consensus/history.jsonl`:

| Row `type` | Written by | Meaning |
|---|---|---|
| `auto-apply` | `learning-apply` (Step 7) | a key was auto-applied |
| `auto-revert` | `consensus-aggregator.sh` | the next round regressed → reverted |
| `auto-apply-held` | `consensus-aggregator.sh` | the next round held → the tune stuck |

## The detector — `auto-tune-ineffective`

`learning-loop-engine --mode consensus-history` adds a detector
(`LEARNING-AUTO-TUNE-INEFFECTIVE`): a key whose `auto-apply` rows are
followed by `auto-revert` rather than `auto-apply-held` in ≥ 3 attempts
*and* at a revert rate ≥ 0.5 is surfaced with the recommendation
**"remove `<key>` from `autoApply.keys` — tuning it doesn't move
agreement."** It feeds `consensus-learning-report.md` like any other
finding (and `decision-recommender` can frame it).

## The enforcement — self-demote

The detector *recommends* removing the key; `learning-apply` *protects*
in the meantime. Before auto-applying an allowlisted key, it counts that
key's `auto-revert` rows in `history.jsonl`. If the count ≥
`autoApply.demoteAfterReverts` (default 3), the key is **demoted to
propose-only for the run** even though it stays allowlisted —
`Applied: demoted (N reverts ≥ threshold) — proposing instead`.

Two horizons:

- **cooldown** (Sprint 23) — per-sprint; a just-reverted key skips the
  rest of the sprint.
- **self-demote** (Sprint 24) — lifetime; a key with a chronic revert
  count stops auto-applying for good until the operator removes it.

## Transactional revert (Sprint 24-D)

With `autoApply.transactional` (default true), a single
`learning-apply` run that auto-applies several keys takes **one**
pre-batch snapshot and arms **one** watch over the whole set
(`watch.json.keys[]`). If the next round regresses, the aggregator
restores that one snapshot — reverting the **whole set atomically** — and
cools down every key in it. The set holds or reverts as a unit, so a good
tune isn't kept while a bad one in the same batch is rolled back (which
would leave an inconsistent config the baseline was never measured
against). `transactional: false` restores the Sprint-23
one-key-at-a-time behaviour.

## Configuration

```jsonc
{
  "learningApply": {
    "autoApply": {
      "enabled": false,
      "keys": [],
      "revertOnRegression": true,
      "regressionDelta": 0.05,
      "demoteAfterReverts": 3,   // Sprint 24-C lifetime self-demote threshold
      "transactional": true      // Sprint 24-D atomic multi-key revert
    }
  }
}
```

All defaulted; `autoApply` stays OFF by default, so none of this engages
until a project opts in.

## Seeing it

The per-key revert rate this meta-loop computes is surfaced live in
`/vibeflow:status`'s **Autonomous Loop** section — a key crossing
`revertRate ≥ 0.5` is flagged there too. See [LOOP-AUDIT.md](LOOP-AUDIT.md).

## See also

- [AUTO-APPLY.md](AUTO-APPLY.md) — the bounded auto-apply + auto-revert base.
- [LEARNING-LOOP.md](LEARNING-LOOP.md) — the detector lives in the
  consensus-history mode.
- [LOOP-AUDIT.md](LOOP-AUDIT.md) — the operator-facing audit surface.
