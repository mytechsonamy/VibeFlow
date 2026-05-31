#!/bin/bash
# VibeFlow Consensus Aggregator Hook (SubagentStop / *).
#
# Runs whenever a subagent finishes. We record the verdict in
# .vibeflow/state/consensus/<session>.jsonl — one line per reviewer — and,
# once the expected reviewer count is reached, compute an aggregate
# status + agreement ratio and write verdict.json.
#
# Expected reviewer count is driven by CLI availability, not by a
# solo/team mode switch (Sprint 14-A). claude-reviewer always
# participates; codex and gemini are added when their CLIs are on PATH.
# Sprint 14-B lets operators override the count via
# `consensus.quorum` in vibeflow.config.json when the detected set
# doesn't match the intended reviewer roster.
#
# The aggregator is intentionally a narrow parser: it scans the subagent's
# output text for "APPROVED", "NEEDS_REVISION", "REJECTED" keywords and a
# "critical issues: N" pattern. Richer structured verdicts come from the
# consensus-orchestrator skill's markdown output.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_lib.sh
source "$SCRIPT_DIR/_lib.sh"

INPUT="$(cat)"
if ! vf_have_jq; then
  echo '{"continue": true}'
  exit 0
fi

# Malformed/empty stdin → fail-safe allow and exit. Never abort the
# calling tool call just because the SubagentStop payload couldn't be
# parsed.
if [[ -z "$INPUT" ]] || ! printf %s "$INPUT" | jq empty >/dev/null 2>&1; then
  echo '{"continue": true}'
  exit 0
fi

STATE_DIR="$(vf_state_dir)"
CONS_DIR="$STATE_DIR/consensus"
mkdir -p "$CONS_DIR"

SESSION_ID="$(printf %s "$INPUT" | jq -r '.session_id // "default"')"
SUBAGENT="$(printf %s "$INPUT" | jq -r '.subagent_type // .tool_name // ""')"
# Claude Code stopped-subagent payloads vary; try the common shapes.
OUTPUT="$(printf %s "$INPUT" | jq -r '.tool_response.content[0].text // .result // .output // ""')"

# Sprint 14-B: only record verdicts from reviewer-class subagents.
# Before this guard, the aggregator fired on every SubagentStop (Explore,
# test-analyst, codebase-explorer, …) and labelled every unparseable
# output as `reviewer=unknown` / `verdict=UNKNOWN`, polluting the verdict
# log and forcing premature REJECTED finalization. We now skip silently
# when the stopping subagent isn't one we expect to produce a review.
case "$SUBAGENT" in
  claude-reviewer|reviewer|*-reviewer|consensus-*)
    : # known reviewer-class agent; fall through
    ;;
  *)
    # Not a reviewer subagent (or name missing entirely). Don't log.
    echo '{"continue": true}'
    exit 0
    ;;
esac

# Verdict extraction. Order matters — REJECTED outranks NEEDS_REVISION,
# which outranks APPROVED. Prefer the structured JSON `verdict` field
# from claude-reviewer's output schema; fall back to plain-text keyword
# matching for subagents that emit free-form prose. If neither yields a
# recognisable verdict, skip the entry entirely rather than logging a
# synthetic UNKNOWN — a missing reviewer must not short-circuit the
# aggregate.
VERDICT=""
# `-Rs` reads arbitrary text as a raw string; `try (fromjson ...) catch
# empty` tolerates non-JSON output (e.g. reviewers that emit prose).
STRUCTURED="$(echo "$OUTPUT" | jq -Rsr 'try (fromjson | .verdict) catch empty' 2>/dev/null || true)"
case "$STRUCTURED" in
  APPROVED|NEEDS_REVISION|REJECTED) VERDICT="$STRUCTURED" ;;
esac
if [[ -z "$VERDICT" ]]; then
  if [[ "$OUTPUT" =~ REJECTED ]]; then
    VERDICT="REJECTED"
  elif [[ "$OUTPUT" =~ NEEDS_REVISION|NEEDS[[:space:]]REVISION ]]; then
    VERDICT="NEEDS_REVISION"
  elif [[ "$OUTPUT" =~ APPROVED ]]; then
    VERDICT="APPROVED"
  fi
fi
if [[ -z "$VERDICT" ]]; then
  # Reviewer-class subagent stopped with no parseable verdict. Silently
  # skip — a subsequent reviewer or a timeout will still finalise the
  # session.
  echo '{"continue": true}'
  exit 0
fi

# Critical-issue parse: Sprint 17-B accepts the new array shape
# (`criticalIssues: [{id, target, title, rationale}]`) alongside the
# legacy integer count. The full array is passed through to the jsonl
# line so the aggregation pass can dedup by {file, line_range} and
# Jaccard title similarity. When the array shape is absent we fall back
# to the integer count or the free-text "critical issues: N" pattern
# (pre-2.5.0 reviewers).
CRITICAL=0
CRITICAL_ARRAY="[]"
CRITICAL_TYPE="$(echo "$OUTPUT" | jq -Rsr 'try (fromjson | .criticalIssues | type) catch empty' 2>/dev/null || true)"
case "$CRITICAL_TYPE" in
  array)
    CRITICAL_ARRAY="$(echo "$OUTPUT" | jq -Rsr 'try (fromjson | .criticalIssues | tojson) catch "[]"' 2>/dev/null || echo "[]")"
    CRITICAL="$(echo "$OUTPUT" | jq -Rsr 'try (fromjson | .criticalIssues | length) catch 0' 2>/dev/null || echo 0)"
    ;;
  number)
    CRITICAL="$(echo "$OUTPUT" | jq -Rsr 'try (fromjson | .criticalIssues) catch 0' 2>/dev/null || echo 0)"
    ;;
esac
if ! [[ "$CRITICAL" =~ ^[0-9]+$ ]]; then
  CRITICAL=0
fi
if [[ "$CRITICAL" -eq 0 ]] && [[ "$CRITICAL_ARRAY" == "[]" ]]; then
  if [[ "$OUTPUT" =~ critical[[:space:]]+issues[[:space:]]*:[[:space:]]*([0-9]+) ]]; then
    CRITICAL="${BASH_REMATCH[1]}"
  fi
fi

TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
REVIEW_LOG="$CONS_DIR/$SESSION_ID.jsonl"

# Sprint 17-A: round-aware. Orchestrator writes the current round number
# to `<sid>.current-round.txt` before each negotiation round. Default 1
# when the marker is missing — single-round sessions keep working.
CURRENT_ROUND=1
ROUND_MARKER="$CONS_DIR/$SESSION_ID.current-round.txt"
if [[ -f "$ROUND_MARKER" ]]; then
  MARKER_VAL="$(head -n 1 "$ROUND_MARKER" 2>/dev/null | tr -d '[:space:]')"
  if [[ "$MARKER_VAL" =~ ^[0-9]+$ ]] && (( MARKER_VAL >= 1 )); then
    CURRENT_ROUND="$MARKER_VAL"
  fi
fi

jq -n -c \
  --arg ts "$TS" \
  --arg reviewer "$SUBAGENT" \
  --arg verdict "$VERDICT" \
  --argjson critical "$CRITICAL" \
  --argjson criticalItems "$CRITICAL_ARRAY" \
  --argjson round "$CURRENT_ROUND" \
  '{recordedAt:$ts, reviewer:$reviewer, verdict:$verdict, criticalIssues:$critical, criticalItems:$criticalItems, round:$round}' \
  >> "$REVIEW_LOG"

# Expected reviewer count is driven by which CLIs are on PATH + any
# explicit override in vibeflow.config.json's `consensus.quorum`.
# Default roster: claude-reviewer (always), codex (if CLI), gemini
# (if CLI). Operators who know their reviewers are stalled or missing
# can force a lower quorum via the config override.
EXPECTED_DETECTED=1
if command -v codex >/dev/null 2>&1; then
  EXPECTED_DETECTED=$((EXPECTED_DETECTED + 1))
fi
if command -v gemini >/dev/null 2>&1; then
  EXPECTED_DETECTED=$((EXPECTED_DETECTED + 1))
fi
EXPECTED_OVERRIDE="$(vf_config_get ".consensus.quorum" 2>/dev/null || echo "")"
if [[ -n "$EXPECTED_OVERRIDE" ]] && [[ "$EXPECTED_OVERRIDE" =~ ^[0-9]+$ ]]; then
  EXPECTED="$EXPECTED_OVERRIDE"
else
  EXPECTED="$EXPECTED_DETECTED"
fi

COUNT="$(jq -s --argjson round "$CURRENT_ROUND" 'map(select((.round // 1) == $round)) | length' < "$REVIEW_LOG" 2>/dev/null || wc -l < "$REVIEW_LOG" | tr -d ' ')"

# Timeout: if the oldest review in the log is older than 600 seconds and
# quorum has not been reached, force-finalize the batch with a `timeout:
# true` flag. This keeps the aggregator from stalling forever when one
# of the 3 team reviewers never responds (rate-limited, crashed,
# network dropped, etc.). The aggregator still records the latest
# review before finalizing, so the final verdict reflects what DID
# arrive.
TIMEOUT_SECONDS=600
TIMED_OUT=false
if (( COUNT < EXPECTED )); then
  FIRST_TS="$(head -n 1 "$REVIEW_LOG" | jq -r '.recordedAt // empty' 2>/dev/null || echo "")"
  if [[ -n "$FIRST_TS" ]] && command -v python3 >/dev/null 2>&1; then
    NOW_EPOCH="$(date -u +%s)"
    FIRST_EPOCH="$(python3 -c "import datetime;print(int(datetime.datetime.strptime('$FIRST_TS','%Y-%m-%dT%H:%M:%SZ').replace(tzinfo=datetime.timezone.utc).timestamp()))" 2>/dev/null || echo "")"
    if [[ -n "$FIRST_EPOCH" ]] && (( NOW_EPOCH - FIRST_EPOCH >= TIMEOUT_SECONDS )); then
      TIMED_OUT=true
    fi
  fi
  if [[ "$TIMED_OUT" != "true" ]]; then
    echo '{"continue": true}'
    exit 0
  fi
fi

# Quorum reached OR timeout fired — compute aggregate. Agreement = (#
# APPROVED) / total. Status uses CLAUDE.md thresholds: >=0.9 + 0
# critical → APPROVED, <0.5 or >=2 critical → REJECTED, else
# NEEDS_REVISION. When timed out, the `timeout: true` flag is added and
# the status is demoted from APPROVED to NEEDS_REVISION (a partial
# quorum cannot ship a clean APPROVED verdict — the missing reviewer
# could have objected).
# Sprint 17-A: per-round aggregation (filter by CURRENT_ROUND).
# Sprint 17-B: critical-issue dedup across reviewers. When a reviewer
# emits structured `criticalItems[]`, we dedup across reviewers by
# `{file, line_range}` equality OR by Jaccard(title words) >= 0.6 —
# three reviewers flagging the same underlying issue now count as 1,
# not 3. When reviewers emit only legacy integer counts, we fall back
# to summing (no dedup possible) and add the note to verdict.json.
#
# `total`, `approved`, `criticalTotal`, `agreement`, `status` stay
# top-level so existing consumers (tests, arbiter, phase-gate) keep
# working. `rounds[]` accumulates per-round snapshots.
AGG="$(jq -s --argjson round "$CURRENT_ROUND" '
  def jaccard_title(a; b):
    (a | ascii_downcase | gsub("[^a-z0-9 ]"; " ") | split(" ") | map(select(length > 2)) | unique) as $aw
    | (b | ascii_downcase | gsub("[^a-z0-9 ]"; " ") | split(" ") | map(select(length > 2)) | unique) as $bw
    | if ($aw | length) == 0 or ($bw | length) == 0 then 0
      else
        ([$aw[], $bw[]] | unique | length) as $union
        | (($aw + $bw) | unique | length) as $u
        | ($aw | map(select(. as $x | $bw | index($x))) | length) as $i
        | (if $u > 0 then ($i / $u) else 0 end)
      end;
    # Collect all structured critical items across reviewers (for
    # this round) and dedup.
    def dedup_critical(items):
      reduce items[] as $e ([];
        . as $acc
        | if any($acc[]; (.target.file // null) == ($e.target.file // null)
                         and (.target.line_range // null) == ($e.target.line_range // null))
          then $acc
          else
            if any($acc[]; jaccard_title(.title // ""; $e.title // "") >= 0.6)
            then $acc
            else $acc + [$e]
            end
          end);

  map(select((.round // 1) == $round)) as $rows
  | ($rows | map(.criticalItems // []) | flatten) as $allCritical
  | ($allCritical | length) as $rawCount
  | dedup_critical($allCritical) as $deduped
  | ($deduped | length) as $dedupCount
  # Legacy fallback: if NO reviewer supplied structured items, use
  # the integer sum.
  | (if ($rawCount == 0) then ($rows | map(.criticalIssues // 0) | add // 0) else $dedupCount end) as $effectiveCritical
  | {
      total: ($rows | length),
      approved: ($rows | map(select(.verdict == "APPROVED")) | length),
      needsRevision: ($rows | map(select(.verdict == "NEEDS_REVISION")) | length),
      rejected: ($rows | map(select(.verdict == "REJECTED")) | length),
      unknown: ($rows | map(select(.verdict == "UNKNOWN")) | length),
      criticalTotal: $effectiveCritical,
      criticalRawCount: $rawCount,
      criticalDeduped: $deduped
    }
  | . + { agreement: (if .total > 0 then (.approved / .total) else 0 end) }
  | . + {
      # Sprint 19-C: reviewer sentiment is authoritative. The pre-19
      # `criticalTotal >= 2 → REJECTED` path fired even when ZERO
      # reviewers actually voted REJECTED (FlowBridge_TR case:
      # 2× NEEDS_REVISION + 1× APPROVED, criticalTotal=2, rejected=0
      # → used to go REJECTED, now correctly NEEDS_REVISION).
      #
      # New rule:
      #   1) strict reject majority            → REJECTED
      #   2) ≥1 reject vote AND ≥2 critical    → REJECTED (escalation)
      #   3) agreement ≥ 0.9 AND zero critical → APPROVED
      #   4) otherwise                         → NEEDS_REVISION
      #
      # The critical count becomes a modifier that requires actual
      # reviewer rejection to escalate; no reject votes ⇒ iteration
      # can continue through the arbiter/specialist path.
      status: (
        if (.rejected * 2) > .total then "REJECTED"
        elif .rejected >= 1 and .criticalTotal >= 2 then "REJECTED"
        elif .agreement >= 0.9 and .criticalTotal == 0 then "APPROVED"
        else "NEEDS_REVISION"
        end
      )
    }
' < "$REVIEW_LOG")"

VERDICT_FILE="$CONS_DIR/$SESSION_ID.verdict.json"

# Read existing rounds[] so we preserve history across negotiation rounds.
EXISTING_ROUNDS="[]"
if [[ -f "$VERDICT_FILE" ]]; then
  EXISTING_ROUNDS="$(jq -c '.rounds // []' "$VERDICT_FILE" 2>/dev/null || echo "[]")"
fi

# Compose verdict.json: top-level = current round's numbers (back-compat);
# add `round` + `finalRound` + `rounds[]` (each entry is a minimal
# per-round snapshot so the orchestrator can see agreement curve).
echo "$AGG" \
  | jq --arg ts "$TS" \
       --arg session "$SESSION_ID" \
       --argjson expected "$EXPECTED" \
       --argjson count "$COUNT" \
       --argjson timed_out "$TIMED_OUT" \
       --argjson round "$CURRENT_ROUND" \
       --argjson existingRounds "$EXISTING_ROUNDS" \
       '. + {
          round: $round,
          finalRound: $round,
          finalizedAt: $ts,
          sessionId: $session,
          expectedReviewers: $expected,
          receivedReviewers: $count,
          timeout: $timed_out,
          status: (if $timed_out and .status == "APPROVED" then "NEEDS_REVISION" else .status end)
        }
        | . as $current
        | . + {
            rounds: ($existingRounds + [{
              round: $round,
              agreement: $current.agreement,
              criticalTotal: $current.criticalTotal,
              status: $current.status,
              timeout: $timed_out,
              finalizedAt: $ts
            }])
          }' > "$VERDICT_FILE"

# Sprint 20-A: append one compact row per finalised round to the
# cross-session consensus history roll-up. The slow loop
# (learning-loop-engine `consensus-history` mode, Sprint 20-B/C) and
# the reviewer-memory store (Sprint 20-D) both read this file. The
# per-session jsonl/verdict files are siloed; this is the single
# place every round across every session/phase accumulates.
#
# Idempotent: keyed by {sessionId, round}. Re-finalising the same
# round (e.g. a re-run) REPLACES the prior row rather than appending
# a duplicate, so the history stays one-row-per-round.
#
# primaryArtifact + phase are resolved from a sidecar the orchestrator
# writes (`<sid>.primary.txt`) and the live project phase; both degrade
# to "unknown" so a legacy single-file invocation still produces a row.
HISTORY_FILE="$CONS_DIR/history.jsonl"
PRIMARY_MARKER="$CONS_DIR/$SESSION_ID.primary.txt"
HIST_PRIMARY="unknown"
if [[ -f "$PRIMARY_MARKER" ]]; then
  HIST_PRIMARY="$(head -n 1 "$PRIMARY_MARKER" 2>/dev/null | tr -d '\n' || echo "unknown")"
  [[ -n "$HIST_PRIMARY" ]] || HIST_PRIMARY="unknown"
fi
HIST_PHASE="$(vf_current_phase 2>/dev/null || echo "unknown")"
[[ -n "$HIST_PHASE" ]] || HIST_PHASE="unknown"

# Per-reviewer breakdown + suggestion themes for THIS round, read from
# the round log before it is archived below.
HIST_REVIEWERS="$(jq -s -c --argjson round "$CURRENT_ROUND" \
  'map(select((.round // 1) == $round) | {name: .reviewer, verdict: .verdict, critical: (.criticalIssues // 0)})' \
  < "$REVIEW_LOG" 2>/dev/null || echo "[]")"
[[ -n "$HIST_REVIEWERS" ]] || HIST_REVIEWERS="[]"
HIST_THEMES="$(jq -s -c --argjson round "$CURRENT_ROUND" \
  '[map(select((.round // 1) == $round) | (.suggestions // [])[] | (.type // empty)) | .[]] | unique' \
  < "$REVIEW_LOG" 2>/dev/null || echo "[]")"
[[ -n "$HIST_THEMES" ]] || HIST_THEMES="[]"

# Build the row from the authoritative finalised verdict.json (captures
# the timeout demotion + final status), grafting on resolved context.
HIST_ROW="$(jq -c \
  --arg sid "$SESSION_ID" \
  --arg phase "$HIST_PHASE" \
  --arg primary "$HIST_PRIMARY" \
  --argjson reviewers "$HIST_REVIEWERS" \
  --argjson themes "$HIST_THEMES" \
  '{
     type: "verdict",
     sessionId: $sid,
     phase: $phase,
     primaryArtifact: $primary,
     round: (.round // 1),
     status: .status,
     agreement: .agreement,
     counts: {
       approved: (.approved // 0),
       needsRevision: (.needsRevision // 0),
       rejected: (.rejected // 0),
       critical: (.criticalTotal // 0)
     },
     reviewers: $reviewers,
     suggestionThemes: $themes,
     timeout: (.timeout // false),
     recordedAt: (.finalizedAt // "")
   }' "$VERDICT_FILE" 2>/dev/null || echo "")"

if [[ -n "$HIST_ROW" ]]; then
  touch "$HISTORY_FILE"
  TMP_HIST="$HISTORY_FILE.tmp.$$"
  # Drop any existing row for this {sessionId, round}, then append.
  jq -c --arg sid "$SESSION_ID" --argjson round "$CURRENT_ROUND" \
    'select((.sessionId != $sid) or ((.round // 1) != $round))' \
    "$HISTORY_FILE" > "$TMP_HIST" 2>/dev/null || : > "$TMP_HIST"
  printf '%s\n' "$HIST_ROW" >> "$TMP_HIST"
  mv "$TMP_HIST" "$HISTORY_FILE"
fi

# Sprint 20-D: cross-session reviewer memory. For every reviewer that
# voted this round, append a bounded entry to its own memory store so
# the orchestrator (Sprint 20-E) can remind that reviewer next round /
# next sprint what it already raised on the same artifact — closing the
# "reviewers have amnesia" gap. Stored as JSONL for deterministic
# capping; capped to `reviewerMemory.maxEntriesPerArtifact` (default 5)
# entries per (reviewer, primaryArtifact). Disable via
# `reviewerMemory.enabled=false`.
RM_ENABLED="$(vf_config_get '.reviewerMemory.enabled' 2>/dev/null || echo "true")"
if [[ "$RM_ENABLED" != "false" ]]; then
  RM_DIR="$CONS_DIR/reviewer-memory"
  RM_CAP="$(vf_config_get '.reviewerMemory.maxEntriesPerArtifact' 2>/dev/null || echo 5)"
  [[ "$RM_CAP" =~ ^[0-9]+$ ]] || RM_CAP=5
  # Sprint 21-B: compaction mode. "theme-aware" (default) folds entries
  # dropped past the cap into a rolling recurrence summary so a
  # long-standing critical keeps its seenCount; "recency" drops silently.
  RM_COMPACTION="$(vf_config_get '.reviewerMemory.compaction' 2>/dev/null || echo "theme-aware")"
  mkdir -p "$RM_DIR"
  RM_REVIEWERS="$(jq -s -r --argjson round "$CURRENT_ROUND" \
    'map(select((.round // 1) == $round) | .reviewer) | unique | .[]' \
    < "$REVIEW_LOG" 2>/dev/null || true)"
  while IFS= read -r rv; do
    [[ -n "$rv" ]] || continue
    # Latest row for this reviewer this round → memory entry with the
    # top-3 critical titles (the signal worth remembering).
    RM_ENTRY="$(jq -s -c --arg rv "$rv" --argjson round "$CURRENT_ROUND" \
      --arg phase "$HIST_PHASE" --arg primary "$HIST_PRIMARY" --arg ts "$TS" \
      'map(select((.round // 1) == $round and .reviewer == $rv)) | last
       | { recordedAt:$ts, phase:$phase, primaryArtifact:$primary,
           round:$round, status:(.verdict // "UNKNOWN"),
           criticals: ((.criticalItems // []) | map(.title // empty) | .[0:3]) }' \
      < "$REVIEW_LOG" 2>/dev/null || echo "")"
    [[ -n "$RM_ENTRY" && "$RM_ENTRY" != "null" ]] || continue
    RM_FILE="$RM_DIR/$rv.jsonl"
    touch "$RM_FILE"
    RM_TMP="$RM_FILE.tmp.$$"
    if [[ "$RM_COMPACTION" == "recency" ]]; then
      # Legacy: keep the last N detail entries per artifact, drop the rest.
      { cat "$RM_FILE"; printf '%s\n' "$RM_ENTRY"; } \
        | jq -s -c --argjson n "$RM_CAP" \
          'group_by(.primaryArtifact) | map(.[-$n:]) | add // [] | .[]' \
        > "$RM_TMP" 2>/dev/null && mv "$RM_TMP" "$RM_FILE" || rm -f "$RM_TMP"
    else
      # theme-aware: keep the last N detail entries PLUS a per-artifact
      # head {type:"summary", recurringCriticals:[{title,seenCount,
      # firstSeen,lastSeen}]} that accumulates the criticals from every
      # entry dropped past the cap. Titles are matched by Jaccard ≥ 0.6
      # (same tokenisation as the verdict-dedup pass above).
      { cat "$RM_FILE"; printf '%s\n' "$RM_ENTRY"; } \
        | jq -s -c --argjson n "$RM_CAP" '
            def norm(t): (t // "") | ascii_downcase | gsub("[^a-z0-9 ]"; " ")
              | split(" ") | map(select(length > 2)) | unique;
            def jac(a; b): (norm(a)) as $x | (norm(b)) as $y
              | if ($x|length)==0 or ($y|length)==0 then 0
                else (($x | map(select(. as $w | $y | index($w))) | length)) as $i
                | (($x + $y) | unique | length) as $u
                | (if $u > 0 then ($i / $u) else 0 end) end;
            def fold($sum; $c; $ts):
              $sum | (.recurringCriticals // []) as $rc
              | if any($rc[]; jac(.title; $c) >= 0.6)
                then .recurringCriticals = ($rc | map(
                       if jac(.title; $c) >= 0.6
                       then .seenCount += 1 | .lastSeen = $ts else . end))
                else .recurringCriticals = ($rc + [{title:$c, seenCount:1,
                       firstSeen:$ts, lastSeen:$ts}]) end;
            group_by(.primaryArtifact) | map(
              (map(select(.type=="summary")) | .[0]) as $sum0
              | (map(select(.type != "summary"))) as $details
              | ($details | .[($n * -1):]) as $kept
              | (if ($details|length) > $n
                 then ($details | .[0:($details|length - $n)]) else [] end) as $dropped
              | (reduce ($dropped[]) as $d
                   (($sum0 // {type:"summary",
                      primaryArtifact: ($details[0].primaryArtifact // "unknown"),
                      recurringCriticals: []});
                    reduce (($d.criticals // [])[]) as $c
                      (.; fold(.; $c; ($d.recordedAt // ""))))) as $sum
              | (if (($sum.recurringCriticals // []) | length) > 0
                 then [$sum] else [] end) + $kept
            ) | add // [] | .[]' \
        > "$RM_TMP" 2>/dev/null && mv "$RM_TMP" "$RM_FILE" || rm -f "$RM_TMP"
    fi
  done <<< "$RM_REVIEWERS"
fi

# Archive current round's log so the next round starts on an empty jsonl.
# Legacy name kept for single-round callers; new name includes round
# number for multi-round sessions so the audit trail is navigable.
if [[ "$CURRENT_ROUND" -eq 1 ]] && [[ ! -f "$ROUND_MARKER" ]]; then
  mv "$REVIEW_LOG" "$CONS_DIR/$SESSION_ID.$(date -u +%s).archived.jsonl"
else
  mv "$REVIEW_LOG" "$CONS_DIR/$SESSION_ID.r${CURRENT_ROUND}.archived.jsonl"
fi

echo '{"continue": true}'
exit 0
