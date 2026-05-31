# Cross-Session Reviewer Memory (Sprint 20)

Before Sprint 20, every consensus round started cold. A reviewer that
raised "the login flow is ambiguous" in round 1 had no memory of it in
round 2 — and certainly none next sprint when the same PRD came back.
Reviewers re-litigated resolved points and never escalated genuine
recurrences. Sprint 20 gives each reviewer a bounded memory of what it
said before, scoped to the artifact under review.

## The store

When a round finalises, `consensus-aggregator.sh` appends one entry per
reviewer that voted to `.vibeflow/state/consensus/reviewer-memory/<reviewer>.jsonl`
(`codex.jsonl`, `gemini.jsonl`, `claude-reviewer.jsonl`):

```json
{ "recordedAt": "…", "phase": "REQUIREMENTS",
  "primaryArtifact": "docs/PRD.md", "round": 2,
  "status": "NEEDS_REVISION",
  "criticals": ["Ambiguous login flow", "Missing acceptance criteria"] }
```

Only the **top-3 critical titles** are kept — the signal worth
remembering, not the full review. The store is **capped** to
`reviewerMemory.maxEntriesPerArtifact` (default 5) detail entries per
`(reviewer, primaryArtifact)`.

### Compaction (Sprint 21)

What happens to entries dropped past the cap is controlled by
`reviewerMemory.compaction`:

- **`theme-aware`** (default) — instead of discarding a dropped entry,
  its criticals fold into a per-artifact **recurrence summary** row kept
  at the head of the file:

  ```json
  { "type": "summary", "primaryArtifact": "docs/PRD.md",
    "recurringCriticals": [
      { "title": "Ambiguous login flow", "seenCount": 4,
        "firstSeen": "…", "lastSeen": "…" } ] }
  ```

  Titles are matched by Jaccard similarity (≥ 0.6), so a critical that
  keeps coming back accrues a `seenCount` instead of silently aging out
  of the recency window. The orchestrator surfaces **recurring criticals
  first** (highest `seenCount`) in the `PRIOR REVIEW MEMORY` block — a
  long-standing unresolved objection leads, so reviewers escalate it.
- **`recency`** — the pre-Sprint-21 behaviour: drop the oldest entry, no
  summary.

## The injection

Before each reviewer runs, `consensus-orchestrator` resolves that
reviewer's memory for the current primary artifact and prepends a bounded
block to its prompt:

```
PRIOR REVIEW MEMORY (codex on docs/PRD.md):
You have reviewed this artifact before. Previously you raised:
- [round 2 · NEEDS_REVISION] Ambiguous login flow still unresolved
- [round 1 · NEEDS_REVISION] Ambiguous login flow; Missing acceptance criteria

Verify whether these were addressed. Do NOT re-raise resolved items;
escalate (raise as critical) any that recur unaddressed.
---
```

Entries are rendered **most-recent-first** and truncated to
`reviewerMemory.tokenBudget` (default 600 tokens ≈ 2400 chars). All three
reviewers — `codex`, `gemini`, and the `claude-reviewer` subagent — get
their own block.

### Clean first run

On a clean first run there is no store and no entries for the artifact, so
the helper emits **nothing** — the round-1 prompt is byte-identical to
pre-Sprint-20 behaviour. Memory only ever *adds* context; it never changes
the first review.

## Configuration

```jsonc
// vibeflow.config.json
{
  "reviewerMemory": {
    "enabled": true,             // kill switch — false omits the block + stops appends
    "maxEntriesPerArtifact": 5,  // per (reviewer, artifact) detail-entry cap
    "tokenBudget": 600,          // bound on the injected block (chars ≈ tokens × 4)
    "compaction": "theme-aware"  // "theme-aware" (fold dropped into summary) | "recency"
  }
}
```

All fields are optional; partial objects pick up the defaults above
(`ReviewerMemoryConfigSchema`, `mcp-servers/sdlc-engine/src/config.ts`).
Setting `enabled: false` makes the aggregator stop writing entries and the
orchestrator stop injecting the block — a full rollback switch.

## Why JSONL, not Markdown

The store is machine-appended on every round and machine-read on every
prompt build, with a deterministic per-artifact cap. JSONL makes the
append + cap a single `jq` pass and the read a single filter; the
orchestrator renders it into the prose block shown above at injection
time. Humans rarely read the store directly — the
[consensus-learning-report](LEARNING-LOOP.md) is the human-facing view of
the same data.

## See also

- [LEARNING-LOOP.md](LEARNING-LOOP.md) — mines the same consensus history
  for cross-session patterns.
- [CONSENSUS-FLOW.md](CONSENSUS-FLOW.md) — where memory is written
  (aggregator finalize) and injected (orchestrator prompt build).
