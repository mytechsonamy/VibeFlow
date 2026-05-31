# Primary-Artifact Excerption (Sprint 21-A)

When a primary artifact exceeds `consensus.excerptTokenBudget`
(default 30 000 tokens ≈ 120 KB), the orchestrator excerpts it for the
reviewer prompt. The specialist/arbiter path always receives the full
file — excerption only shapes what the **reviewers** read.

`consensus.excerptStrategy` selects the algorithm:

- `semantic` (default) — section-scored selection (below).
- `headtail` — the legacy positional excerpt.

`semantic` falls back to `headtail` whenever the document has **fewer
than 2 detectable sections**, so it is never worse than the legacy path.

## Section split

Split the primary on:

- markdown headings — lines matching `^#{1,6} `
- form-feed / page breaks (`\f`) — for `.docx`-derived plain text

Each section runs from one boundary to the next. Section 1 is the
title/overview block before the first heading (or the first heading's
block).

## Scoring

Each section `s` gets `score(s) = w_e·E(s) + w_m·M(s) + w_k·K(s)` with
default weights `w_e = 0.5`, `w_m = 0.3`, `w_k = 0.2`:

| Term | Meaning | Computation |
|---|---|---|
| `E(s)` evidence-finding density | how many evidence findings land in `s` | count of evidence `criticalIssues[]` / `suggestions[]` whose `target.line_range` falls within `s`'s line span (or whose quoted `title` text appears in `s`), normalised by section length |
| `M(s)` reviewer-memory hits | is `s` a previously-contested area | count of prior `criticals` from this artifact's Sprint 20-D memory store (`reviewer-memory/<reviewer>.jsonl`) whose title words overlap `s` (Jaccard ≥ 0.4), summed across reviewers |
| `K(s)` evidence-keyword overlap | topical relevance to the analyzer's concerns | `Jaccard(words(s), words(distilled evidence summaries))` |

All three terms are normalised to `[0, 1]` before weighting. Reuse the
aggregator's `jaccard_title` idiom (`consensus-aggregator.sh`) for the
word-overlap computations — same tokenisation (lowercase, strip
non-alphanumerics, drop words ≤ 2 chars, unique).

## Selection

1. **Always include section 1** (title/overview) for context, charged
   against the budget.
2. Sort the remaining sections by `score` descending; walk the list
   adding sections until the next one would exceed `maxchars`
   (`excerptTokenBudget × 4`).
3. **Emit the selected sections in document order** (not score order) so
   reviewers read a coherent document, with a `[… N sections omitted …]`
   marker between non-adjacent kept sections.
4. Append **findings-anchored ±20-line windows** for any top-priority
   evidence finding whose section was *not* selected — a high-severity
   finding is never dropped, even if its section scored low.

## `headtail` (and fallback)

First 40% of the document (head) + last 15% (tail) + the same
findings-anchored ±20-line windows. This is the pre-Sprint-21 behaviour,
preserved verbatim for `excerptStrategy: headtail` and for documents
with no detectable section structure.

## Helpers

`excerpt_if_large()` (in `SKILL.md`) dispatches on size + strategy to:

- `vf_excerpt_semantic <file> <maxchars>` — the section-scored path above
- `vf_excerpt_headtail <file> <maxchars>` — head/tail + anchors

Both emit the excerpt to stdout; `build_review_prompt` inlines the
result under `PRIMARY ARTIFACT UNDER REVIEW`.

## Why lexical, not embeddings

Sprint 21 scores with finding-density + Jaccard overlap — no embeddings
dependency, deterministic, and reproducible in the test harness.
Vector/embedding scoring is a Sprint 22+ candidate (see
`docs/SPRINT-21.md` Out of Scope).
