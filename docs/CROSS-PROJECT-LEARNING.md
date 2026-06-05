# Cross-Project Meta-Learning (Sprint 28)

The meta-learning loop (Sprint 24) learns which config tunes stick — but
**per project**. A tune that reliably holds in five repos gets
re-discovered (and re-reverted on the bad ones) in the sixth. Sprint 28
lets a multi-project operator share that signal **across** repos —
**opt-in, privacy-safe, read-only**.

## Three guarantees

1. **Opt-in, default off.** `globalLearning.enabled` is `false`. Nothing
   leaves a project unless you turn it on.
2. **Privacy-safe.** Only `{key, outcome, phase, projectHash}` is written
   to the shared store. **No code, no content, no artifact/file names, no
   theme text.** `projectHash` is a one-way `sha256` of the project id
   (first 12 hex chars) — distinct repos can be *counted*, never
   *identified*.
3. **Read-only recommendation.** A new project *reads* the cross-project
   signal and surfaces it as a **recommendation** in the learning report.
   It **never** auto-allowlists or auto-applies. One repo's record can't
   change another's behaviour.

## The shared store

`$(vf_global_dir)/global-learning.jsonl` — default `~/.vibeflow/`,
overridable with `VIBEFLOW_GLOBAL_DIR` (tests point it at a temp dir).
Each row:

```json
{ "key": "consensus.maxIterations", "outcome": "held",
  "phase": "REQUIREMENTS", "projectHash": "a1b2c3d4e5f6", "recordedAt": "…" }
```

`outcome` is one of `applied` (learning-apply auto-applied a tune),
`held` (it survived the next consensus round), or `reverted` (it
regressed and was rolled back). That's the whole payload — compare it to
the per-project `history.jsonl`, which keeps the artifact names, themes,
and agreement curves *locally* and shares none of them.

## The recommendation

`learning-loop-engine --mode consensus-history` adds the
`cross-project-signal` detector. For a key seen in **≥ 3 distinct
projects**:

- hold-rate (`held / (held + reverted)`) **≥ 0.7** → *"consider adding
  `<key>` to `autoApply.keys` (held in N/M projects)"*;
- hold-rate **≤ 0.3** → *"avoid auto-applying `<key>` (reverted in N/M
  projects)"*.

The report states explicitly that this is advice only — your config and
domain may differ, and the loop will never change `autoApply.keys` for
you.

## Configuration

```jsonc
{ "globalLearning": { "enabled": false } }
```

## Wiping the store

It's a single local file:

```bash
rm ~/.vibeflow/global-learning.jsonl     # or $VIBEFLOW_GLOBAL_DIR/global-learning.jsonl
```

There is no server, no sync, no network — just an append-only local file
you fully control.

## See also

- [META-LEARNING.md](META-LEARNING.md) — the single-project meta-loop this
  extends.
- [AUTO-APPLY.md](AUTO-APPLY.md) — what produces the `applied` / `held` /
  `reverted` outcomes.
