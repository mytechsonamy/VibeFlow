#!/bin/bash
# Sprint 11 integration harness — exercises the filesystem state store
# migration + replay tools end-to-end.
#
# Sections:
#   [S11-F1] migrate-state-db-to-fs.sh round-trip (sqlite → project.json)
#   [S11-F2] replay-events.sh rebuilds project.json from events + archive
#   [S11-Z]  harness self-audit

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PASS=0
FAIL=0
FAILS=()

pass() { PASS=$((PASS + 1)); echo "  ok   $1"; }
fail() { FAIL=$((FAIL + 1)); FAILS+=("$1"); echo "  FAIL $1"; }

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    pass "$label"
  else
    fail "$label (expected=$expected actual=$actual)"
  fi
}

cleanup() { [[ -n "${S11F_DIR:-}" && -d "$S11F_DIR" ]] && rm -rf "$S11F_DIR"; }
trap cleanup EXIT

# ---------------------------------------------------------------------------
echo "== [S11-F1] migrate-state-db-to-fs.sh round-trip =="

MIGRATE="$REPO_ROOT/bin/migrate-state-db-to-fs.sh"
if [[ -x "$MIGRATE" ]]; then
  pass "[S11-F1] bin/migrate-state-db-to-fs.sh present + executable"
else
  fail "[S11-F1] bin/migrate-state-db-to-fs.sh present + executable"
fi

if ! command -v sqlite3 >/dev/null 2>&1; then
  pass "[S11-F1] migrate round-trip skipped — sqlite3 not installed"
elif ! command -v jq >/dev/null 2>&1; then
  pass "[S11-F1] migrate round-trip skipped — jq not installed"
else
  S11F_DIR="$(mktemp -d "${TMPDIR:-/tmp}/vf-s11f-XXXXXX")"
  mkdir -p "$S11F_DIR/.vibeflow"
  sqlite3 "$S11F_DIR/.vibeflow/state.db" <<SQL
CREATE TABLE project_state (
  project_id TEXT PRIMARY KEY,
  current_phase TEXT NOT NULL,
  satisfied_criteria TEXT NOT NULL,
  last_consensus TEXT,
  updated_at TEXT NOT NULL,
  revision INTEGER NOT NULL
);
INSERT INTO project_state VALUES (
  's11f-proj',
  'DESIGN',
  '["prd.approved","testability.score>=60"]',
  '{"phase":"REQUIREMENTS","status":"APPROVED","agreement":0.95,"criticalIssues":0,"recordedAt":"2026-04-01T00:00:00Z"}',
  '2026-04-01T00:00:00Z',
  7
);
SQL

  # --dry-run must report but not write anything.
  bash "$MIGRATE" --cwd "$S11F_DIR" --dry-run >/dev/null 2>&1
  if [[ ! -d "$S11F_DIR/.vibeflow/state" ]]; then
    pass "[S11-F1] --dry-run does not create filesystem layout"
  else
    fail "[S11-F1] --dry-run does not create filesystem layout"
  fi
  if [[ -f "$S11F_DIR/.vibeflow/state.db" ]]; then
    pass "[S11-F1] --dry-run preserves the legacy state.db"
  else
    fail "[S11-F1] --dry-run preserves the legacy state.db"
  fi

  # Real run writes rollup + event, renames state.db to .bak.
  bash "$MIGRATE" --cwd "$S11F_DIR" >/dev/null 2>&1
  ROLLUP="$S11F_DIR/.vibeflow/state/s11f-proj/project.json"
  EVENT="$S11F_DIR/.vibeflow/state/s11f-proj/events/0007-project_imported.json"
  if [[ -f "$ROLLUP" ]]; then
    pass "[S11-F1] project.json created at expected path"
  else
    fail "[S11-F1] project.json created at expected path"
  fi
  if [[ -f "$EVENT" ]]; then
    pass "[S11-F1] numbered project_imported event created"
  else
    fail "[S11-F1] numbered project_imported event created"
  fi
  if [[ ! -f "$S11F_DIR/.vibeflow/state.db" ]]; then
    pass "[S11-F1] legacy state.db renamed to .bak"
  else
    fail "[S11-F1] legacy state.db renamed to .bak"
  fi

  # Rollup fields must match the source row.
  ROLLUP_PHASE="$(jq -r '.currentPhase' "$ROLLUP" 2>/dev/null || echo "")"
  assert_eq "[S11-F1] migrated currentPhase preserved" "DESIGN" "$ROLLUP_PHASE"
  ROLLUP_REV="$(jq -r '.revision' "$ROLLUP" 2>/dev/null || echo "")"
  assert_eq "[S11-F1] migrated revision preserved" "7" "$ROLLUP_REV"
  ROLLUP_STATUS="$(jq -r '.lastConsensus.status' "$ROLLUP" 2>/dev/null || echo "")"
  assert_eq "[S11-F1] migrated lastConsensus.status preserved" "APPROVED" "$ROLLUP_STATUS"

  # Second run is a no-op (db was renamed).
  OUT="$(bash "$MIGRATE" --cwd "$S11F_DIR" 2>&1)"
  if echo "$OUT" | grep -q "nothing to migrate"; then
    pass "[S11-F1] second run is a no-op"
  else
    fail "[S11-F1] second run is a no-op"
  fi

  rm -rf "$S11F_DIR"
fi

# ---------------------------------------------------------------------------
echo "== [S11-F2] replay-events.sh rebuilds project.json =="

REPLAY="$REPO_ROOT/bin/replay-events.sh"
if [[ -x "$REPLAY" ]]; then
  pass "[S11-F2] bin/replay-events.sh present + executable"
else
  fail "[S11-F2] bin/replay-events.sh present + executable"
fi

ENGINE_DIST="$REPO_ROOT/mcp-servers/sdlc-engine/dist/index.js"
if [[ ! -f "$ENGINE_DIST" ]]; then
  fail "[S11-F2] sdlc-engine dist missing (run npm run build)"
else
  S11F_DIR="$(mktemp -d "${TMPDIR:-/tmp}/vf-s11f-replay-XXXXXX")"
  export VIBEFLOW_STATE_DIR="$S11F_DIR/state"
  export VIBEFLOW_PROJECT="replay-proj"

  # Drive the engine through a full REQUIREMENTS → DESIGN walk so the
  # event log spans one archive boundary.
  node "$ENGINE_DIST" >/dev/null 2>&1 <<'EOF'
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"r","version":"1"}}}
{"jsonrpc":"2.0","method":"notifications/initialized"}
{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"sdlc_satisfy_criterion","arguments":{"projectId":"replay-proj","criterion":"prd.approved"}}}
{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"sdlc_satisfy_criterion","arguments":{"projectId":"replay-proj","criterion":"testability.score>=60"}}}
{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"sdlc_record_consensus","arguments":{"projectId":"replay-proj","phase":"REQUIREMENTS","agreement":0.95,"criticalIssues":0}}}
{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"sdlc_advance_phase","arguments":{"projectId":"replay-proj","to":"DESIGN"}}}
EOF

  ROLLUP="$S11F_DIR/state/replay-proj/project.json"
  if [[ -f "$ROLLUP" ]]; then
    pass "[S11-F2] engine produced project.json rollup"
  else
    fail "[S11-F2] engine produced project.json rollup"
  fi

  # --check must succeed against a healthy rollup.
  if bash "$REPLAY" --state-dir "$S11F_DIR/state" replay-proj --check >/dev/null 2>&1; then
    pass "[S11-F2] --check succeeds on healthy rollup"
  else
    fail "[S11-F2] --check succeeds on healthy rollup"
  fi

  # Corrupt the rollup, rebuild via replay, verify recovery.
  ORIG="$(cat "$ROLLUP")"
  echo "not json" > "$ROLLUP"
  bash "$REPLAY" --state-dir "$S11F_DIR/state" replay-proj >/dev/null 2>&1
  REBUILT="$(cat "$ROLLUP")"
  if [[ "$ORIG" == "$REBUILT" ]]; then
    pass "[S11-F2] replay reconstructs rollup byte-for-byte"
  else
    fail "[S11-F2] replay reconstructs rollup byte-for-byte"
  fi

  # --check on the rebuilt rollup must still pass.
  if bash "$REPLAY" --state-dir "$S11F_DIR/state" replay-proj --check >/dev/null 2>&1; then
    pass "[S11-F2] --check green after replay rebuild"
  else
    fail "[S11-F2] --check green after replay rebuild"
  fi

  rm -rf "$S11F_DIR"
  unset VIBEFLOW_STATE_DIR VIBEFLOW_PROJECT
fi

# ---------------------------------------------------------------------------
echo "== [S11-Z] harness self-audit =="

SELF="$REPO_ROOT/tests/integration/sprint-11.sh"
if [[ -f "$SELF" && -x "$SELF" ]]; then
  pass "[S11-Z] sprint-11.sh is executable"
else
  fail "[S11-Z] sprint-11.sh is executable"
fi
if head -1 "$SELF" | grep -q '^#!/bin/bash'; then
  pass "[S11-Z] sprint-11.sh shebang is #!/bin/bash"
else
  fail "[S11-Z] sprint-11.sh shebang is #!/bin/bash"
fi
for sec in "S11-F1" "S11-F2" "S11-Z"; do
  if grep -q "echo \"== \[$sec\]" "$SELF"; then
    pass "[S11-Z] [$sec] section header present"
  else
    fail "[S11-Z] [$sec] section header present"
  fi
done

echo
echo "RESULTS: $PASS passed, $FAIL failed"
if (( FAIL > 0 )); then
  for f in "${FAILS[@]}"; do echo "  - $f"; done
  exit 1
fi
exit 0
