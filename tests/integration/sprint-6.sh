#!/bin/bash
# VibeFlow Sprint 6 integration harness.
#
# Complements run.sh + sprint-2.sh + sprint-3.sh + sprint-4.sh + sprint-5.sh.
# Sprint 6 targets v1.1.0 and picks up items deferred from Sprint 5's
# scope decisions. This harness starts as the single-section skeleton
# that Sprint 6 / S6-01 produces; subsequent tickets (S6-04..) extend
# it with their own sections.
#
# Sections:
#   [S6-A] — Concurrent-advance CAS stress test on real PostgreSQL (S6-01)
#
# Exit 0 on full pass, 1 otherwise. Skip gracefully when docker / pg /
# VF_SKIP_LIVE_POSTGRES conditions match — we do NOT fire loudly in
# dev environments that legitimately cannot run a live Postgres.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

PASS=0
FAIL=0
FAILS=()

pass() { PASS=$((PASS + 1)); echo "  ok   $1"; }
fail() { FAIL=$((FAIL + 1)); FAILS+=("$1"); echo "  FAIL $1"; }

# ---------------------------------------------------------------------------
echo "== [S6-A] Concurrent-advance CAS stress test (Postgres) =="

# S6-01 — Sprint 5 / S5-03 shipped a single-process live-Postgres walk.
# That proved the wire-level protocol (real TCP, real `pg` module, real
# advisory lock + FOR UPDATE row lock + revision CAS) survives a single
# reader/writer. It did NOT prove the CAS correctly serializes CONCURRENT
# writers — the only coverage for that was Sprint 1's `FakePool` unit
# tests, which don't exercise the real Postgres lock hierarchy.
#
# S6-A spins up N=5 engine processes under `bin/with-postgres.sh`, all
# racing to advance the same project REQUIREMENTS → DESIGN. Postgres's
# advisory lock (pg_advisory_xact_lock) plus `SELECT ... FOR UPDATE`
# serializes the writes per project, and the in-mutator revision check
# catches any loss of the lock ordering. The expected outcome:
#
#   - Exactly 1 racer's `sdlc_advance_phase` call returns a non-error
#     response with `currentPhase: "DESIGN"` — that racer won the lock
#     first and committed the advance.
#   - The other N-1 racers acquire the advisory lock AFTER the winner
#     committed, read `currentPhase: DESIGN`, then try to validate a
#     REQUIREMENTS → DESIGN transition against a base that is already
#     DESIGN. The phase validator throws PhaseTransitionError ("invalid
#     transition") which surfaces as `isError: true` in the JSON-RPC
#     envelope.
#   - The final `sdlc_get_state` call in a FRESH engine process sees
#     DESIGN — proving the state persisted correctly across all the
#     concurrent writes + subsequent reads.
#
# Note on wording: the original S6-01 ticket draft expected a
# "revision mismatch" error in the losers' output. In the real Postgres
# code path the advisory lock + row lock serialize the writes BEFORE
# they reach the revision CAS, so the losers fail the phase validator
# (not the CAS) — the outcome is the same (N-1 errors + 1 winner) but
# the error text is "invalid transition" rather than "Optimistic lock
# failed". That's a stronger guarantee than the ticket asked for: the
# store's mutual-exclusion primitive is so tight that the second-line
# CAS never has to fire in practice.
#
# Skip conditions (same pattern as sprint-5.sh [S5-B]):
#   - docker not installed → skip gracefully
#   - VF_SKIP_LIVE_POSTGRES=1 → skip (opt-out for restricted dev envs)
#   - pg package not installed in sdlc-engine node_modules → skip

ENGINE_DIST_S6A="$REPO_ROOT/mcp-servers/sdlc-engine/dist/index.js"
WITH_POSTGRES_S6A="$REPO_ROOT/bin/with-postgres.sh"

if [[ ! -f "$ENGINE_DIST_S6A" ]]; then
  fail "[S6-A] sdlc-engine dist present at $ENGINE_DIST_S6A"
elif [[ "${VF_SKIP_LIVE_POSTGRES:-}" == "1" ]]; then
  pass "[S6-A] concurrent CAS stress skipped via VF_SKIP_LIVE_POSTGRES=1"
elif ! command -v docker >/dev/null 2>&1; then
  pass "[S6-A] concurrent CAS stress skipped — docker binary not installed"
elif ! docker info >/dev/null 2>&1; then
  # Skip gracefully when the binary is present but the daemon isn't
  # reachable (common on macOS when Docker Desktop is not running).
  # sprint-5.sh [S5-B] has the same skip-ladder pattern for the same
  # reason.
  pass "[S6-A] concurrent CAS stress skipped — docker daemon not running"
elif [[ ! -d "$REPO_ROOT/mcp-servers/sdlc-engine/node_modules/pg" ]]; then
  pass "[S6-A] concurrent CAS stress skipped — pg optional peer dep not installed"
elif [[ ! -x "$WITH_POSTGRES_S6A" ]]; then
  fail "[S6-A] bin/with-postgres.sh present + executable"
else
  # Build the stress walker script that runs INSIDE the with-postgres
  # wrapper. It does four things:
  #   1. Single engine process seeds the project through a full setup
  #      (satisfy criteria + consensus) so the REQUIREMENTS → DESIGN
  #      gate is met. Without this, the racers would all fail the gate
  #      check before even touching the CAS path — testing nothing.
  #   2. Fires N=5 concurrent engine processes via `&` + `wait`. Each
  #      racer issues ONE sdlc_advance_phase call and quits. Output is
  #      captured to a per-racer log file.
  #   3. Counts winners (non-error + contains "DESIGN") vs errors
  #      (isError:true) and prints summary markers for the outer
  #      harness to grep on.
  #   4. A fresh engine process reads back the final state via
  #      sdlc_get_state — the same pattern as S5-B's phase-2. The
  #      response must contain DESIGN or the whole concurrent run
  #      left the database in an inconsistent shape.
  #
  # Why heredoc-inside-heredoc with "$PROJECT" as a shell variable:
  # the inner JSON-RPC payloads need the project id interpolated but
  # must also be literal JSON strings. Using a $PROJECT shell
  # expansion with an unquoted heredoc terminator (`<<PHASE1`) lets
  # bash substitute while the rest of the line stays literal.
  STRESS_SCRIPT="$(cat <<'STRESS_OUTER'
set -uo pipefail
ENGINE="$1"
PROJECT="s6a-stress"
N=5
TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/vf-s6a-XXXXXX")"
trap 'rm -rf "$TMPDIR"' EXIT

export VIBEFLOW_MODE="team"
export VIBEFLOW_PROJECT="$PROJECT"

# ----- Phase 1: setup (single process, sequential) -----
node "$ENGINE" >/dev/null 2>&1 <<PHASE1
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"s6a-setup","version":"1"}}}
{"jsonrpc":"2.0","method":"notifications/initialized"}
{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"sdlc_satisfy_criterion","arguments":{"projectId":"$PROJECT","criterion":"prd.approved"}}}
{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"sdlc_satisfy_criterion","arguments":{"projectId":"$PROJECT","criterion":"testability.score>=60"}}}
{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"sdlc_record_consensus","arguments":{"projectId":"$PROJECT","phase":"REQUIREMENTS","agreement":0.95,"criticalIssues":0}}}
PHASE1
echo "SETUP_DONE"

# ----- Phase 2: N concurrent racers -----
# Each racer gets its own stdin heredoc so the JSON-RPC lines are
# literal. We pass the file handle directly, spawn with &, and wait
# for all racers to finish. Output goes to per-racer logs which the
# outer bash then inspects.
for i in $(seq 1 "$N"); do
  node "$ENGINE" > "$TMPDIR/racer-$i.log" 2>&1 <<RACER &
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"s6a-racer-$i","version":"1"}}}
{"jsonrpc":"2.0","method":"notifications/initialized"}
{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"sdlc_advance_phase","arguments":{"projectId":"$PROJECT","to":"DESIGN"}}}
RACER
done
wait
echo "RACE_DONE"

# ----- Phase 3: count winners vs losers -----
# The sdlc_advance_phase tool handler catches PhaseTransitionError
# and returns {ok: false, errors, state} as a SUCCESSFUL JSON-RPC
# response — no isError:true on the outer envelope. To distinguish
# winners from losers we look inside the text content of the
# tool_result for the stringified ok marker: winners carry ok:true,
# losers carry ok:false. The envelope escapes the quotes, so the
# real grep target is the literal 8-byte substring using grep -F.
WINNERS=0
ERRORS=0
MISSING=0
for i in $(seq 1 "$N"); do
  LOG="$TMPDIR/racer-$i.log"
  RESP_LINE="$(grep '"id":2' "$LOG" 2>/dev/null | head -1 || true)"
  if [[ -z "$RESP_LINE" ]]; then
    MISSING=$((MISSING + 1))
  elif echo "$RESP_LINE" | grep -q '"isError":true'; then
    ERRORS=$((ERRORS + 1))
  elif echo "$RESP_LINE" | grep -qF '\"ok\": true'; then
    WINNERS=$((WINNERS + 1))
  elif echo "$RESP_LINE" | grep -qF '\"ok\": false'; then
    ERRORS=$((ERRORS + 1))
  else
    MISSING=$((MISSING + 1))
  fi
done
echo "WINNERS=$WINNERS"
echo "ERRORS=$ERRORS"
echo "MISSING=$MISSING"
echo "TOTAL=$N"

# ----- Phase 4: final-state read (fresh engine process) -----
node "$ENGINE" > "$TMPDIR/final.log" 2>&1 <<FINAL
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"s6a-final","version":"1"}}}
{"jsonrpc":"2.0","method":"notifications/initialized"}
{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"sdlc_get_state","arguments":{"projectId":"$PROJECT"}}}
FINAL
FINAL_LINE="$(grep '"id":2' "$TMPDIR/final.log" 2>/dev/null | head -1 || true)"
if [[ -z "$FINAL_LINE" ]]; then
  echo "FINAL_MISSING"
elif echo "$FINAL_LINE" | grep -q '"isError":true'; then
  echo "FINAL_ERROR"
  echo "$FINAL_LINE" | head -c 300
elif echo "$FINAL_LINE" | grep -q "DESIGN"; then
  echo "FINAL_DESIGN"
else
  echo "FINAL_UNEXPECTED"
  echo "$FINAL_LINE" | head -c 300
fi
STRESS_OUTER
)"

  OUT="$(bash "$WITH_POSTGRES_S6A" bash -c "$STRESS_SCRIPT" _ "$ENGINE_DIST_S6A" 2>&1 || true)"

  # Setup completed?
  if echo "$OUT" | grep -q "^SETUP_DONE"; then
    pass "[S6-A] phase-1 setup completed against real Postgres"
  else
    fail "[S6-A] phase-1 setup completed against real Postgres"
    echo "    OUT tail:" >&2
    echo "$OUT" | tail -20 >&2
  fi

  # All N racers terminated?
  if echo "$OUT" | grep -q "^RACE_DONE"; then
    pass "[S6-A] phase-2 race — all 5 concurrent engines terminated (no hangs)"
  else
    fail "[S6-A] phase-2 race — all 5 concurrent engines terminated"
  fi

  # Exactly one winner (the advisory lock + validator serializes correctly).
  WINNERS="$(echo "$OUT" | sed -n 's/^WINNERS=\(.*\)$/\1/p' | head -1)"
  ERRORS_COUNT="$(echo "$OUT" | sed -n 's/^ERRORS=\(.*\)$/\1/p' | head -1)"
  TOTAL="$(echo "$OUT" | sed -n 's/^TOTAL=\(.*\)$/\1/p' | head -1)"
  if [[ "${WINNERS:-}" == "1" ]]; then
    pass "[S6-A] exactly one racer won the advance (winners=1)"
  else
    fail "[S6-A] exactly one racer won the advance (winners=${WINNERS:-?})"
    echo "    OUT tail:" >&2
    echo "$OUT" | tail -20 >&2
  fi

  # The remaining N-1 racers all failed (phase validator rejects
  # REQUIREMENTS → DESIGN when base is already DESIGN). This is the
  # strong assertion that catches any regression where the store
  # loses the mutual-exclusion property.
  if [[ "${ERRORS_COUNT:-}" == "4" ]]; then
    pass "[S6-A] remaining N-1 racers were correctly rejected (errors=4)"
  else
    fail "[S6-A] remaining N-1 racers were correctly rejected (errors=${ERRORS_COUNT:-?} total=${TOTAL:-?})"
  fi

  # Final state read from a FRESH process must see DESIGN.
  if echo "$OUT" | grep -q "^FINAL_DESIGN"; then
    pass "[S6-A] fresh-process get_state returns DESIGN (state survives concurrent write)"
  else
    fail "[S6-A] fresh-process get_state returns DESIGN"
    echo "    OUT tail:" >&2
    echo "$OUT" | tail -15 >&2
  fi
fi

echo
echo "RESULTS: $PASS passed, $FAIL failed"
if (( FAIL > 0 )); then
  echo "Failures:"
  for f in "${FAILS[@]}"; do echo "  - $f"; done
  exit 1
fi
exit 0
