# Consensus Flow

VibeFlow's consensus loop is the runtime half of the MyVibe
promise: an artifact produced by any analysis skill is reviewed by
Claude + codex + gemini; the verdicts flow through an arbiter that
turns suggestions into diff-first patches; the operator applies
those patches with a single command. Four layers, each independently
testable, each safe to skip if a reviewer CLI or the config is
missing.

## Four layers

```
┌──────────────────────────────────────────────────────────────────┐
│ L2: Skill prose auto-invokes /vibeflow:consensus-orchestrator    │
│     after writing outputs to .vibeflow/reports/                  │
└───────────────────────────┬──────────────────────────────────────┘
                            │
                            ▼
┌──────────────────────────────────────────────────────────────────┐
│ L1: consensus-orchestrator runs                                  │
│   - claude-reviewer subagent  → SubagentStop → aggregator        │
│   - codex CLI      (90s)     → append_cli_verdict() to jsonl    │
│   - gemini CLI     (90s)     → append_cli_verdict() to jsonl    │
│                                                                  │
│  consensus-aggregator.sh tallies the jsonl, writes verdict.json  │
│  orchestrator drains review-pending.json on success              │
└───────────────────────────┬──────────────────────────────────────┘
                            │
                            ├─ status=APPROVED ─► advance unblocked (L3)
                            │
                            └─ status=NEEDS_REVISION
                                    │
                                    ▼
┌──────────────────────────────────────────────────────────────────┐
│ L4: consensus-arbiter (auto-chained from orchestrator)           │
│  reads  jsonl + verdict.json + currentPhase + domain             │
│  decides APPLY / DEFER / REJECT per suggestion                   │
│  writes .patch files + arbiter-decisions.md                      │
│  (never Writes to source — diff-first)                           │
└───────────────────────────┬──────────────────────────────────────┘
                            │
                            ▼
┌──────────────────────────────────────────────────────────────────┐
│ Operator runs /vibeflow:apply-arbiter-patch                      │
│   diff preview → y/n → git apply → optional --run-tests          │
│   updates arbiter-decisions.md (Applied: true)                   │
└──────────────────────────────────────────────────────────────────┘
```

And independent of the skill chain:

```
┌──────────────────────────────────────────────────────────────────┐
│ L3: Phase gate                                                   │
│  /vibeflow:advance <phase> calls sdlc-engine's validator.        │
│  REQUIREMENTS / DESIGN / ARCHITECTURE / PLANNING / TESTING /     │
│  DEPLOYMENT all carry `consensus.<phase>.approved` in their      │
│  exit criteria. Advance blocks until lastConsensus.phase         │
│  matches the from-phase AND lastConsensus.status === APPROVED.   │
│  force: true bypasses. Legacy `consensus.approved` is aliased    │
│  for ARCHITECTURE until v2.4.0.                                  │
│                                                                  │
│  DEVELOPMENT is the one phase without a scoped consensus         │
│  criterion — the commit-time trigger-ai-review marker already    │
│  covers it, and scoping consensus to DEV too would double-gate.  │
└──────────────────────────────────────────────────────────────────┘
```

## Reviewer schema

All three reviewers emit the same JSON shape. `suggestions[]` is
the primary signal the arbiter reads — freeform prose in the
reviewer output is informational only.

```json
{
  "verdict": "APPROVED" | "NEEDS_REVISION" | "REJECTED",
  "score": 0-100,
  "criticalIssues": [],
  "summary": "...",
  "suggestions": [
    {
      "id": "claude-1",
      "type": "fix" | "enhancement" | "question" | "concern",
      "target": {
        "file": "docs/PRD.md",
        "line_range": [42, 58]
      },
      "rationale": "Missing error-handling flow for rate limiting.",
      "proposed_change": "Add a new section 4.2.1 that specifies ...",
      "priority": "high",
      "phase_relevance": ["REQUIREMENTS"]
    }
  ]
}
```

See `agents/claude-reviewer.md` for the Claude-side contract and
`skills/consensus-orchestrator/SKILL.md` Step 3 for the prompt
block sent to codex + gemini.

## Escape hatch: `VF_SKIP_AUTO_CONSENSUS=1`

Set this env var for a single Claude Code session to turn off Layer
2 (skill auto-invoke) and silence the post-commit marker drain in
Layer 3. **Layer 3 phase-gate ignores it** — `/vibeflow:advance`
still blocks on missing consensus regardless. The var is a
noise-reducer for exploratory work, not a compliance bypass.

`load-sdlc-context.sh` prints a visible advisory line when the var
is active so you don't forget you set it:

```
VibeFlow: auto-consensus disabled via VF_SKIP_AUTO_CONSENSUS=1 for this session.
```

## Troubleshooting

### "codex never showed up in the verdict file"

Before Sprint 15-A, codex and gemini were invoked as raw bash
processes. Their stdout wasn't captured into the session jsonl the
aggregator reads, so the quorum counter waited 600 s for them and
then demoted APPROVED to NEEDS_REVISION. Fixed in 2.3.0 —
orchestrator now appends a verdict line per CLI directly.

If you still see `reviewer=unknown` entries on 2.3.0:

- Check that `codex` / `gemini` are on your PATH: `command -v codex`.
- Check the orchestrator actually entered the CLI block — if
  `VF_SKIP_AUTO_CONSENSUS=1` is set, it may have short-circuited
  before reaching Step 3.
- Stale verdict files from pre-2.3.0 runs don't get retroactively
  fixed; they just sit there for history. Delete
  `.vibeflow/state/consensus/*.verdict.json` to reset.

### "advance is blocked and I don't know why"

Run `/vibeflow:status`. The output names every missing exit
criterion. If you see `consensus.<phase>.approved` in that list,
run `/vibeflow:consensus-orchestrator <path-to-primary-report>` —
a fresh APPROVED verdict satisfies the gate.

If you think consensus already ran: confirm
`.vibeflow/state/consensus/<session>.verdict.json` has
`status: APPROVED` and `phase: <currentPhase>`. The scope check
requires both.

### "I don't want codex/gemini on my laptop but I still want advance to work"

Set `consensus.quorum = 1` in `vibeflow.config.json`. The
aggregator then expects only the Claude reviewer, finalises the
session as soon as claude-reviewer's SubagentStop fires, and the
phase gate passes if that verdict is APPROVED.

### "Patches conflict on apply"

`git apply --check` runs before every patch. If a patch would
conflict with the current tree, the apply aborts with a "run
`/vibeflow:consensus-arbiter <session>` again to regenerate"
hint. Arbiter reads the current file state when synthesising
diffs, so a fresh run rebuilds cleanly.

### "Tests failed after --run-tests"

The apply skill prints a `git checkout HEAD -- <file>` line for
the touched files. No auto-revert — we'd rather leave recovery to
you than compound the damage with a guess.

## Files

| Path | Role |
|---|---|
| `skills/consensus-orchestrator/SKILL.md` | Layer 1 + auto-chain to arbiter |
| `skills/consensus-arbiter/SKILL.md` | Layer 4 decision + diff synthesis |
| `skills/apply-arbiter-patch/SKILL.md` | Operator apply |
| `hooks/scripts/consensus-aggregator.sh` | jsonl tally + verdict.json |
| `hooks/scripts/trigger-ai-review.sh` | Post-commit marker |
| `hooks/scripts/load-sdlc-context.sh` | SessionStart marker drain |
| `mcp-servers/sdlc-engine/src/phases.ts` | Phase-scoped exit criteria |
| `mcp-servers/sdlc-engine/src/validation.ts` | Scope-aware validator |
| `agents/claude-reviewer.md` | Reviewer schema |
