# Sprint 16 — Deterministic Auto-Consensus Chain ✅ COMPLETE

Shipped: v2.4.0 on 2026-04-20
Branch: `feature/sprint16-consensus-gate` (merged)
Baseline change: hooks 75 → 86 (+11 from `[S16-A]` gate); new
`sprint-16.sh` at 77 assertions; total baseline 1881 → 1969.

## Context

Sprint 15's auto-consensus chain relied on natural-language prose
to make analysis skills invoke the orchestrator. That works in a
main-agent context but fails in forked-subagent contexts: forked
subagents can't invoke slash commands. The result — reports
landed in `.vibeflow/reports/` but the orchestrator never ran,
`/vibeflow:advance` blocked silently at the phase-gate, and the
operator had to reverse-engineer which step failed.

Sprint 16 replaces the trust-based dispatch with a deterministic
marker + PreToolUse hook pattern. Analysis skills write a
`consensus-needed.json` marker file; a new `consensus-gate.sh`
hook reads it on every `Bash|Write|Edit` tool call and refuses
the call with a stderr message naming the required command.
Orchestrator, arbiter, and apply-arbiter-patch all drain the
marker on success.

## Tickets shipped

- [x] S16-A — new `hooks/scripts/consensus-gate.sh` PreToolUse
  hook; wired into `hooks/hooks.json` on `Bash|Write|Edit`
  matcher. Fail-safes: missing jq, empty stdin, missing marker,
  `VF_SKIP_CONSENSUS_GATE=1`. Pass-through allows for writes
  under `.vibeflow/**`, `vibeflow:consensus-*` /
  `vibeflow:apply-arbiter-*` commands, and `rm`-ing the marker.
  +11 hook test assertions (commit `84057e0`)
- [x] S16-B — orchestrator + arbiter + apply-arbiter-patch drain
  `consensus-needed.json` on any terminal verdict (APPROVED /
  NEEDS_REVISION / REJECTED). Orchestrator handles all three
  statuses; arbiter + apply unconditionally drain at end of
  successful run so direct operator invocation on a stored
  session doesn't leave a stale marker (commit `6cf1246`)
- [x] S16-C — 6 analysis skills' Final Step block rewritten:
  each now Writes `consensus-needed.json` with
  `{artifact, requiredCommand, createdAt, createdBy}` as their
  mandatory final action. `release-decision-engine` gains
  `Write` in `allowed-tools` (missing since v1.0). Prose-invoke
  fallback kept as best-effort for main-agent path (commit
  `3b3ec82`)
- [x] S16-D — `tests/integration/sprint-16.sh` (77 assertions)
  + `docs/CONSENSUS-FLOW.md` gains "Layer 2 in detail" section
  documenting the marker mechanism + hook pass-through rules +
  drain points + bypass (commit `9b6475a`)
- [x] S16-E — v2.4.0 release: plugin + marketplace 2.3.0 →
  2.4.0, CHANGELOG, release-notes, tarball, tag, push. Forward-
  compatibility fix in `sprint-15.sh` so its `[S15-I]` plugin-
  version sentinel checks `>= 2.3.0` rather than `== 2.3.0`,
  preventing future releases from regressing it (commit
  `e5d53e0`)

## Outcome

- The auto-consensus chain is deterministic. Once an analysis
  skill writes a marker, the next tool call is hard-blocked
  until consensus runs. No silent drops.
- `consensus-gate.sh` gives operators a clear escape hatch:
  `VF_SKIP_CONSENSUS_GATE=1 <command>` for a single-call bypass,
  plus the whitelist of consensus-related commands that pass
  through automatically.
- Layer 2 ("skill prose auto-invoke") of the
  `docs/CONSENSUS-FLOW.md` diagram is rewritten around the
  marker mechanism. The old prose-invoke approach is documented
  as the fallback for the main-agent case.

## See also

- release-notes/2.4.0.md
- CHANGELOG.md `[2.4.0]` entry
- Git tag `v2.4.0`
