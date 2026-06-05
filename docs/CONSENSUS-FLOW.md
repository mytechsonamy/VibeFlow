# Consensus Flow

VibeFlow's consensus loop is the runtime half of the MyVibe
promise: a **primary artifact** (the PRD, the ADR, the test
strategy — the thing the team is actually building) is reviewed by
Claude + codex + gemini; the verdicts flow through an arbiter that
turns suggestions into diff-first patches; the operator applies
those patches with a single command. Four layers, each independently
testable, each safe to skip if a reviewer CLI or the config is
missing.

## Four layers

```
┌──────────────────────────────────────────────────────────────────┐
│ L2: Skill writes .vibeflow/state/consensus-needed.json marker    │
│     (Sprint 16-A). consensus-gate PreToolUse hook blocks every   │
│     Bash|Write|Edit call until the operator runs the required    │
│     /vibeflow:consensus-orchestrator command. Orchestrator and   │
│     arbiter/apply skills drain the marker on success (16-B).     │
│     The old skill-prose invoke is a best-effort fallback for     │
│     the main-agent case — forked subagents cannot invoke slash   │
│     commands, so the marker is what actually closes the gap.     │
└───────────────────────────┬──────────────────────────────────────┘
                            │
                            ▼
┌──────────────────────────────────────────────────────────────────┐
│ L1: consensus-orchestrator runs (Sprint 19-B: reviews primary,   │
│     not report — analyzer reports become evidence context)       │
│   - claude-reviewer subagent  → SubagentStop → aggregator        │
│   - codex CLI      (90s)     → append_cli_verdict() to jsonl    │
│   - gemini CLI     (90s)     → append_cli_verdict() to jsonl    │
│                                                                  │
│  consensus-aggregator.sh tallies the jsonl, writes verdict.json  │
│  orchestrator drains review-pending.json AND                     │
│  consensus-needed.json on APPROVED/NEEDS_REVISION/REJECTED       │
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

## Layer 2 in detail: the consensus-needed marker (Sprint 16-A)

Before Sprint 16, "Layer 2" was purely prose — each analysis skill
ended with `/vibeflow:consensus-orchestrator <path>` and trusted
Claude to invoke it. That worked in direct main-agent invocations
but failed in any forked subagent, since forked subagents have no
slash-command dispatch. The result: reports landed in
`.vibeflow/reports/`, `/vibeflow:advance` blocked, the operator had
no idea why.

Sprint 16-A replaced the trust with a filesystem marker.

**How it works:**

1. Every L1 analysis skill's **Final Step** now writes
   `.vibeflow/state/consensus-needed.json` with:
   ```json
   {
     "artifact": ".vibeflow/reports/<primary-report>.md",
     "requiredCommand": "/vibeflow:consensus-orchestrator <path>",
     "createdAt": "<ISO-8601 UTC>",
     "createdBy": "<skill-name>"
   }
   ```
2. `hooks/scripts/consensus-gate.sh` (`PreToolUse` on
   `Bash|Write|Edit`) reads the marker on every tool call. If it
   exists, the hook blocks the call with a stderr message naming
   `requiredCommand`. Claude Code surfaces that message to the
   model — the next response runs the orchestrator.
3. Pass-throughs (the hook does NOT block):
   - Writes targeting `.vibeflow/**` (framework state must stay
     writable during the arbiter/apply flow)
   - Bash commands containing `vibeflow:consensus-*` or
     `vibeflow:apply-arbiter-patch`
   - Bash commands removing the marker
4. Drains (who deletes `consensus-needed.json`):
   - `consensus-orchestrator` on APPROVED / NEEDS_REVISION / REJECTED
   - `consensus-arbiter` at end of successful run
   - `apply-arbiter-patch` as final step
5. Bypass (per-call only): `VF_SKIP_CONSENSUS_GATE=1 <your-command>`.
   The phase-gate in Layer 3 still ignores this; it is a
   noise-reducer for explicit operator overrides.

**Why the marker instead of a slash-command invoke:** Claude Code
has no programmatic `SlashCommand` tool. A skill cannot instruct
Claude to run `/foo` in a way that actually fires; it can only
print text. Prose works as a hint but is defeated by context
compaction, forking, or a busy main agent. A file on disk survives
all three.

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

Run `/vibeflow:flow-status`. The output names every missing exit
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

### "consensus-gate is blocking every command and I can't get out"

Run the `requiredCommand` named in the block message — that's the
fast path. If you need to bypass for a single call (e.g. you're
manually inspecting state), prefix with `VF_SKIP_CONSENSUS_GATE=1`.
To drain the marker without running consensus:

```
rm -f .vibeflow/state/consensus-needed.json
```

The hook whitelists `rm *consensus-needed.json*` so this always
passes through. Note that the phase-gate (Layer 3) will still
refuse `/vibeflow:advance` — the marker drain doesn't create a
consensus record.

## Files

| Path | Role |
|---|---|
| `skills/consensus-orchestrator/SKILL.md` | Layer 1 + auto-chain to arbiter; Sprint 19-B resolves marker v2 → primary + evidence |
| `docs/PRIMARY-ARTIFACT.md` | Sprint 19-A marker v2 schema + per-phase primary table |
| `skills/phase-runner/SKILL.md` | End-to-end phase orchestrator (analyzer → headless consensus via `consensus-run.sh` → record + advance on APPROVED; honest operator breadcrumb to specialist/apply on NEEDS_REVISION). Sprint 19-F, headless in Sprint 31-C |
| `skills/consensus-arbiter/SKILL.md` | Layer 4 decision + diff synthesis |
| `skills/apply-arbiter-patch/SKILL.md` | Operator apply |
| `hooks/scripts/consensus-aggregator.sh` | jsonl tally + verdict.json (SubagentStop path + Sprint 31 `--finalize` mode) |
| `hooks/scripts/consensus-run.sh` | Sprint 31 headless runner — codex/gemini + `--finalize` → verdict.json; what `phase-runner` calls |
| `hooks/scripts/consensus-gate.sh` | Layer 2 PreToolUse block until marker drains (Sprint 16-A; allowlists `consensus-run.sh`) |
| `hooks/scripts/trigger-ai-review.sh` | Post-commit marker |
| `hooks/scripts/load-sdlc-context.sh` | SessionStart marker drain |
| `mcp-servers/sdlc-engine/src/phases.ts` | Phase-scoped exit criteria |
| `mcp-servers/sdlc-engine/src/validation.ts` | Scope-aware validator |
| `agents/claude-reviewer.md` | Reviewer schema |

## Layer 3 in detail — the slow loop (Sprint 20)

Two side-effects of the flow above feed the L3 Truth-Evolution layer:

1. **Consensus history roll-up.** When `consensus-aggregator.sh`
   finalises a round's `verdict.json`, it also appends one compact
   row to the cross-session `.vibeflow/state/consensus/history.jsonl`
   (`apply-arbiter-patch` appends an `arbiter-decision` row per run).
   `learning-loop-engine --mode consensus-history` mines this for
   slow-converging phases, recurring reviewer themes, convergence
   stalls, and the arbiter-decision effectiveness trace —
   see [LEARNING-LOOP.md](LEARNING-LOOP.md).
2. **Reviewer memory.** The same finalize step appends a bounded entry
   to `.vibeflow/state/consensus/reviewer-memory/<reviewer>.jsonl`, and
   `consensus-orchestrator` prepends a `PRIOR REVIEW MEMORY` block to
   each reviewer's next prompt for the same artifact —
   see [REVIEWER-MEMORY.md](REVIEWER-MEMORY.md).

Both degrade cleanly: absent history/memory ⇒ no rows, no block, and
the round behaves exactly as it did pre-Sprint-20.

## Sprint 21 signal-quality refinements

Three refinements sharpen the loop's inputs/outputs without changing its
mechanics:

- **Semantic excerption** — when a primary exceeds
  `consensus.excerptTokenBudget`, the reviewer prompt now carries
  **section-scored** excerpts (evidence density + reviewer-memory hits +
  keyword overlap) instead of positional head/tail. See
  [EXCERPTION.md](EXCERPTION.md).
- **Theme-aware memory compaction** — reviewer-memory entries dropped
  past the cap fold into a recurrence summary (`seenCount`) so a
  long-standing objection keeps its signal. See
  [REVIEWER-MEMORY.md](REVIEWER-MEMORY.md).
- **Progress ledger** — `phase-runner` writes
  `.vibeflow/state/phase-runner-progress.json`, rendered by
  `/vibeflow:flow-status`. See [PROGRESS-LEDGER.md](PROGRESS-LEDGER.md).

## Closing the action gap (Sprint 22)

The slow loop now *acts*, not just observes: `learning-apply` turns
`consensus-learning-report.md` recommendations into diff-first,
operator-confirmed `vibeflow.config.json` patches (config-tune) and
phase-specialist dispatch recommendations (template-route) — never
writing config or source directly. See [ACTION-GAP.md](ACTION-GAP.md).

## Interactive vs headless consensus (Sprint 31)

There are now two ways to reach a verdict, sharing one aggregator:

- **Interactive — `/vibeflow:consensus-orchestrator`.** The full path: it
  forks the `claude-reviewer` subagent (a third reviewer), whose
  SubagentStop fires `consensus-aggregator.sh`, and runs the iterative
  negotiation rounds (Step 5). `disable-model-invocation: true` — only the
  operator launches it. Use when you want the deepest 3-AI review.
- **Headless — `hooks/scripts/consensus-run.sh`.** What `phase-runner`
  calls as plain Bash. It runs the external reviewer CLIs on PATH (codex,
  gemini) and finalises the **same** `verdict.json` via
  `consensus-aggregator.sh --finalize` — an additive mode that computes the
  verdict from the reviewer lines already on disk, skipping the SubagentStop
  stdin ingest and the 600s quorum wait (the panel is exactly the CLIs that
  ran). No `claude-reviewer` (model-only) and no iteration; a real
  codex+gemini panel. It drains `consensus-needed.json` so the gate
  unblocks.

This is why `phase-runner` no longer deadlocks: the consensus skills are
all `disable-model-invocation: true` (un-forkable by the model), so before
Sprint 31 phase-runner could never drive consensus and got stuck behind its
own `consensus-gate`. Calling `consensus-run.sh` directly sidesteps the
un-forkable skills while preserving the Sprint 16 guardrail — `phase-runner`
is operator-invoked, so a human authorised the walk; the runner executes
real reviewer CLIs (no fabricated verdicts). On a non-APPROVED verdict,
phase-runner stops and hands the operator the specialist → arbiter → apply
chain, which rewrites the primary artifact and stays operator-confirmed by
design. See [ONBOARDING.md](ONBOARDING.md).

Both paths feed the identical history.jsonl / reviewer-memory / auto-revert
machinery (Layer 3), so headless verdicts participate in the slow loop just
like interactive ones.
