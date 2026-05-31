# Primary-Artifact Excerption (Sprint 21)

When a primary artifact (PRD, ADR, test-strategy, …) is larger than the
reviewer budget, `consensus-orchestrator` excerpts it before sending it
to the reviewer panel. The specialist/arbiter path always receives the
**full** file — excerption only shapes what the reviewers read.

## Why it changed

Before v2.9.0 the excerpt was **positional**: first 40% + last 15% +
findings-anchored windows. On a long document the most-contested
section is often in the dropped middle, so reviewers reviewed the wrong
part of the doc. v2.9.0 makes excerption **relevance-based**.

## Strategies

`consensus.excerptStrategy` (default `semantic`):

- **`semantic`** — section-scored selection. The doc is split into
  sections (markdown headings / page breaks) and each section is scored
  by:
  1. **evidence-finding density** — how many analyzer findings anchor
     into it,
  2. **reviewer-memory hits** — whether it's an area reviewers have
     flagged before (reuses the Sprint 20 reviewer memory),
  3. **evidence-keyword overlap** — topical relevance to the analyzer's
     concerns.
  The first section (title/overview) is always included; the rest of
  the budget is filled with the highest-scored sections, emitted in
  document order. A high-severity finding whose section didn't make the
  cut still gets a ±20-line anchored window.
- **`headtail`** — the legacy positional excerpt (head 40% + tail 15% +
  anchors). `semantic` automatically falls back to this when a document
  has no detectable section structure, so it is never worse than the
  legacy behaviour.

## Configuration

```jsonc
// vibeflow.config.json
{
  "consensus": {
    "excerptTokenBudget": 30000,     // excerpt above this size (tokens)
    "excerptStrategy": "semantic"    // "semantic" | "headtail"
  }
}
```

Documents under `excerptTokenBudget` are sent whole.

## Internals

The scoring formula, weights, and the `vf_excerpt_semantic` /
`vf_excerpt_headtail` helpers are documented in
`skills/consensus-orchestrator/references/excerption.md`. Scoring is
**lexical** (finding-density + Jaccard overlap) — deterministic and
reproducible; embedding/vector scoring is a Sprint 22+ candidate.

## See also

- [REVIEWER-MEMORY.md](REVIEWER-MEMORY.md) — the memory the
  memory-hit score reuses.
- [CONSENSUS-FLOW.md](CONSENSUS-FLOW.md) — where excerption sits in the
  reviewer-prompt build.
