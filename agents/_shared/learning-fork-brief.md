# Learning-Fork Brief (Sprint 27 — shared specialist input)

The six phase-specialist agents (prd-rewriter, design-spec-refiner,
adr-author, test-strategy-refiner, coverage-gap-filler, runbook-editor)
are normally forked from a **consensus session** — they read
`verdict.json` + reviewer `suggestions[]`.

Sprint 27 adds a second, equivalent trigger: **`learning-apply` may fork
a specialist with a *learning-fork brief*** when
`learningApply.autoForkSpecialist` is on and the learning loop found a
`recurring-suggestion-theme` (a structural gap that recurs across ≥3
artifacts/sprints — see `docs/TEMPLATE-AUTONOMY.md`). There is no consensus
session in this path; the brief stands in for the reviewer feedback.

## Brief format

`learning-apply` writes the brief to the fork directory it created:

```
.vibeflow/state/patches/learning-fork-<ts>/brief.md
```

```markdown
# Learning-Fork Brief (Sprint 27)
- theme: <recurring suggestion theme title>
- primaryArtifact: <affected artifact path>
- seenCount: <how many artifacts/sprints the theme recurred across>
- rationale: <one line — why this is a systemic gap, not a one-off>
- evidence: .vibeflow/reports/consensus-learning-report.md
```

## What the specialist does with it

Identical contract to the consensus-driven path, with the brief as the
finding source:

1. **Read** the `brief.md`, then the named `primaryArtifact`, then the
   `consensus-learning-report.md` evidence.
2. **Treat the `theme` as the structural gap to resolve** in
   `primaryArtifact` (the same way it treats reviewer-flagged structural
   gaps). Scope the rewrite to the theme — do not rewrite unrelated
   sections.
3. **Emit ONE diff-first patch** into the **same fork directory**
   (`.vibeflow/state/patches/learning-fork-<ts>/`), never writing the
   artifact directly. The Sprint 17-D diff-first / never-write-source
   contract is unchanged.

## Apply path (unchanged)

The patch is **propose-only**: `learning-apply` does not apply it. The
operator applies via `/vibeflow:apply-arbiter-patch` after preview +
confirmation — exactly as with a consensus-driven specialist patch.

## See also

- `docs/TEMPLATE-AUTONOMY.md` — the end-to-end template-route lane.
- `skills/learning-apply/references/lanes.md` — the phase→specialist map.
