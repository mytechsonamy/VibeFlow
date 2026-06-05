# Onboarding a new project — the first-run sequence

> New in v2.19.0. The bootstrap skill was renamed `init` → **`onboard`** so
> it no longer collides with Claude Code's built-in `/init`. And every
> phase-flow skill now ends with a `▶ Next:` breadcrumb so you always know
> the one command to run next.

## The happy path (REQUIREMENTS → DESIGN)

You have a product/requirements doc and want VibeFlow to drive the SDLC.
Run these in order — each command prints the next one as its last line.

```
1. /vibeflow:onboard
      → creates vibeflow.config.json + .vibeflow/ state
      → ▶ Next: /vibeflow:prd-quality-analyzer docs/<your-prd>.md

2. /vibeflow:prd-quality-analyzer docs/<your-prd>.md
      → scores testability (blocks dev if < 60), writes the reports,
        arms the consensus marker
      → ▶ Next: /vibeflow:phase-runner

3. /vibeflow:phase-runner
      → runs the phase analyzers, then drives a REAL cross-AI consensus
        verdict headlessly (codex + gemini), and on APPROVED records the
        verdict + auto-advances to DESIGN.
```

That's it for a clean run: three commands and you're in DESIGN.

## When consensus does NOT approve

`phase-runner` is honest about where a human is genuinely needed. The
deep-rewrite chain (specialist → arbiter → apply) edits your PRD/ADR and
is operator-confirmed **by design** — it is never auto-run. So on a
`NEEDS_REVISION` / `REJECTED` verdict, phase-runner stops and prints:

```
▶ Next: /vibeflow:consensus-specialist <session-id>   (deep rewrite)
    then  /vibeflow:apply-arbiter-patch <session-id> --yes
    then  /vibeflow:phase-runner
```

Run those, review the diff-first patch, and re-run `phase-runner`. It
re-runs consensus on the revised artifact and advances once it converges.

## `onboard` vs `init`

- `/vibeflow:onboard` — VibeFlow's project bootstrap (this).
- `/init` — Claude Code's built-in "generate a CLAUDE.md" command. Unrelated.

Before v2.19.0 VibeFlow's bootstrap was also called `init`, and typing
"init" in the picker was ambiguous. The rename removes that collision. If
muscle memory has you reaching for `/vibeflow:init`, it no longer exists —
use `/vibeflow:onboard`.

## The `▶ Next:` convention

Every skill that's part of the phase flow ends with a single
copy-pasteable line:

```
▶ Next: /vibeflow:<command> [args]
```

It's always the **last line** of the skill's output. When in doubt about
what to run next, scroll to the bottom — the breadcrumb is there. For the
full autonomous-loop picture across phases, see `/vibeflow:loop-status`
and [LOOP-STATUS.md](LOOP-STATUS.md).

## How phase-runner runs consensus without you (headless)

The five consensus skills (`consensus-orchestrator`, `-specialist`,
`-arbiter`, `apply-arbiter-patch`, `advance`) are
`disable-model-invocation: true` — only the operator can launch them, so a
forked agent can't fabricate a verdict. That guardrail is good, but it
used to mean `phase-runner` couldn't drive consensus at all (it deadlocked
against its own `consensus-gate`).

Since v2.19.0, `phase-runner` calls `hooks/scripts/consensus-run.sh`
directly as plain Bash. That script runs the external reviewer CLIs
(codex, gemini) and finalises a real `verdict.json` — no dependency on the
un-forkable skills. When you invoke `/vibeflow:phase-runner` you ARE the
human in the loop authorising the walk, so this preserves the guardrail's
intent. For the full 3-AI interactive review with iterative negotiation
(adds `claude-reviewer`), run `/vibeflow:consensus-orchestrator` by hand —
see [CONSENSUS-FLOW.md](CONSENSUS-FLOW.md).

> If neither `codex` nor `gemini` is on your PATH, headless consensus
> can't run a panel (claude-reviewer is model-only). phase-runner will
> tell you to run `/vibeflow:consensus-orchestrator` instead.
