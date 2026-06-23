#!/bin/bash
# VibeFlow consensus-gate (PreToolUse / Bash|Write|Edit).
#
# Deterministic auto-chain enforcement (Sprint 16-A). When an
# analysis skill (Sprint 15-B target set) writes a report to
# `.vibeflow/reports/`, it also writes a marker at
# `.vibeflow/state/consensus-needed.json` that names the required
# follow-up command. This hook refuses any subsequent Bash/Write/Edit
# tool call with a blocking stderr message naming that command,
# until:
#   - the marker is removed (consensus-orchestrator drains it on
#     success, apply-arbiter-patch mirrors the drain defensively),
#   - or the operator sets `VF_SKIP_CONSENSUS_GATE=1` for the call.
#
# The gate is intentionally generous about what passes through
# without a drain:
#   - any Write/Edit whose target is under `.vibeflow/` (framework
#     state must stay writable — the orchestrator and arbiter both
#     need to Write patches, logs, verdict files),
#   - any Bash command that is itself the consensus/arbiter/apply
#     slash-command path, or that removes the marker.
#
# Exit codes: 0 = allow, 2 = block (Claude Code surfaces stderr to
# the model). Empty stdin, missing jq, or missing marker all
# fail-safe to allow — the gate never bricks a session on its own.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_lib.sh
source "$SCRIPT_DIR/_lib.sh"

INPUT="$(cat || true)"

# Fail-safe: no jq = allow. We need JSON parsing to even read the
# tool input, so without it there is nothing we can gate on.
if ! vf_have_jq; then
  echo '{"continue":true}'
  exit 0
fi

# Fail-safe: empty or unparseable stdin = allow.
if [[ -z "$INPUT" ]] || ! printf '%s' "$INPUT" | jq empty >/dev/null 2>&1; then
  echo '{"continue":true}'
  exit 0
fi

# Escape hatch: single-call override.
if [[ "${VF_SKIP_CONSENSUS_GATE:-}" == "1" ]]; then
  echo '{"continue":true}'
  exit 0
fi

MARKER="$(vf_state_dir)/consensus-needed.json"
if [[ ! -f "$MARKER" ]]; then
  echo '{"continue":true}'
  exit 0
fi

FILE="$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // ""')"
CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""')"

# Sprint 50: the escape hatch must also work when VF_SKIP_CONSENSUS_GATE is set
# as a command-prefix env var *alongside another* (e.g.
# `VF_SKIP_CONSENSUS_GATE=1 VF_ALLOW_PHASE_WRITE=1 bash -c …`). Claude Code
# exports a single leading assignment into the hook env (caught at line 48), but
# with two leading assignments that export is unreliable, so the env check
# missed it and the bypass appeared to "only work as the sole leading var".
# Match the assignment only in the *leading* env-var prefix (the run of
# `VAR=val` tokens before the first real command word), so the override is order-
# and count-independent but a mere mention of the var inside a quoted string arg
# does NOT bypass. awk stops at the first non-assignment token.
#
# Sprint 62: also honor the override after a leading `cd <path> &&|;` navigation
# preamble — the very common `cd /repo && VF_SKIP_CONSENSUS_GATE=1 cmd` shape
# (without this the awk stops at `cd` and never sees the override). `cd` is a
# no-op for the gate's purpose (navigation, not forward work), so we strip one or
# more leading `cd … (&&|;)` segments before scanning the env-prefix. ONLY `cd`
# is strippable — real work (`rm … && VF_SKIP=1 …`) can't sneak ahead ungated —
# and a quoted mention after the cd still doesn't bypass (the awk break holds).
GATE_SCAN="$(printf '%s' "$CMD" | sed -E 's/^[[:space:]]*(cd[[:space:]]+[^&;]*(&&|;)[[:space:]]*)+//')"
GATE_LEADING_ENV="$(printf '%s' "$GATE_SCAN" | awk '{for(i=1;i<=NF;i++){if($i ~ /^[A-Za-z_][A-Za-z0-9_]*=/){printf "%s ",$i}else{break}}}')"
if printf '%s' "$GATE_LEADING_ENV" | grep -qE '(^|[[:space:]])VF_SKIP_CONSENSUS_GATE=(1|true)([[:space:]]|$)'; then
  echo '{"continue":true}'
  exit 0
fi

# Allow: Write/Edit targeting framework state (.vibeflow/**).
# The orchestrator, arbiter, and apply skills all need to write
# jsonl/verdict/patch/decision files while the marker is still in
# place. Phase-write-guard (Sprint 13) already honours this invariant
# for the same reason.
if [[ -n "$FILE" ]]; then
  REL="$(vf_relpath "$FILE")"
  case "$REL" in
    .vibeflow/*|*/.vibeflow/*)
      echo '{"continue":true}'
      exit 0
      ;;
  esac
fi

# Allow: Bash command that is itself part of the consensus chain.
# Slash commands dispatch via Bash in Claude Code, so matching
# `vibeflow:consensus-` / `vibeflow:apply-arbiter-patch` captures
# the whole chain. Also allow the explicit marker rm for scripts
# that drain manually.
if [[ -n "$CMD" ]]; then
  case "$CMD" in
    *vibeflow:consensus-orchestrator*) echo '{"continue":true}'; exit 0 ;;
    *vibeflow:consensus-arbiter*)      echo '{"continue":true}'; exit 0 ;;
    *vibeflow:apply-arbiter-patch*)    echo '{"continue":true}'; exit 0 ;;
    # Sprint 31-C: the headless consensus runner IS the drain action — it
    # runs the reviewer CLIs, writes verdict.json, and removes the marker.
    # phase-runner calls it as plain Bash, so it must pass the gate (the
    # very marker it's about to drain would otherwise block it).
    *consensus-run.sh*)                echo '{"continue":true}'; exit 0 ;;
    *rm*.vibeflow/state/consensus-needed.json*) echo '{"continue":true}'; exit 0 ;;
    *rm*consensus-needed.json*)                 echo '{"continue":true}'; exit 0 ;;
    # Sprint 56: VibeFlow's own READ-ONLY readers + `git status` only inspect
    # state — they don't "move past" the consensus requirement, so gating them is
    # pure friction (phase-runner Step 0 / flow-status call them while a marker is
    # armed, right before draining via consensus-run.sh). Allow them through.
    *ui-verification-debt.sh*) echo '{"continue":true}'; exit 0 ;;
    *ui-styling-check.sh*)     echo '{"continue":true}'; exit 0 ;;
    *loop-audit.sh*)           echo '{"continue":true}'; exit 0 ;;
    # Sprint 60: read-only work-stream readers (phase-runner/onboard/streams
    # resolve the stream id + lifecycle path with these; inspect-only).
    *stream-id.sh*)            echo '{"continue":true}'; exit 0 ;;
    *streams-audit.sh*)        echo '{"continue":true}'; exit 0 ;;
    # read-only git inspection (phase-runner Step 0 surfaces in-flight work +
    # resolves the DEVELOPMENT diff base with these; both only read).
    *"git status"*)    echo '{"continue":true}'; exit 0 ;;
    *"git rev-parse"*) echo '{"continue":true}'; exit 0 ;;
  esac
fi

# Block: emit the operator-visible instruction the marker names.
# Sprint 20-F: prefer the marker-schema-v2 `primaryArtifact` (the doc
# under review — PRD/ADR/…) over the legacy `artifact` (which points
# at the analyzer's evidence report). Falls back to `artifact` for
# pre-v2.7.0 markers so the message never goes blank.
PRIMARY="$(jq -r '.primaryArtifact // .artifact // "unknown"' "$MARKER" 2>/dev/null || echo "unknown")"
EVIDENCE="$(jq -r 'if (.evidence // []) | length > 0 then (.evidence | join(", ")) else "—" end' "$MARKER" 2>/dev/null || echo "—")"
REQUIRED_CMD="$(jq -r '.requiredCommand // "/vibeflow:consensus-orchestrator"' "$MARKER" 2>/dev/null || echo "/vibeflow:consensus-orchestrator")"
CREATED_AT="$(jq -r '.createdAt // "?"' "$MARKER" 2>/dev/null || echo "?")"

cat >&2 <<MSG
VibeFlow consensus-gate: a pending cross-AI consensus review is
blocking this tool call. An analysis skill wrote a report that
must pass through consensus-orchestrator before any further work.

Primary artifact: $PRIMARY
Evidence:         $EVIDENCE
Created at:       $CREATED_AT

RUN THIS NEXT:
  $REQUIRED_CMD

Bypass for one call (discouraged — the phase-gate will still block
/vibeflow:advance even if you bypass here):
  VF_SKIP_CONSENSUS_GATE=1 <your-command>
MSG
exit 2
