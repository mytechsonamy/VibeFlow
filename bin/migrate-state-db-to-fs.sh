#!/bin/bash
# migrate-state-db-to-fs.sh — one-shot migration for v1.x → v2.0 upgraders.
#
# Reads the legacy .vibeflow/state.db (SQLite, solo mode) and produces
# the v2 layout:
#   .vibeflow/state/<projectId>/project.json  (rollup, schemaVersion=1)
#   .vibeflow/state/<projectId>/events/
#     0001-project_imported.json (+.md)       (seq = existing revision)
# When the write completes, state.db is renamed to
#   .vibeflow/state.db.migrated-<YYYYMMDD-HHMMSS>.bak
# so a second run is a no-op.
#
# Usage:
#   bin/migrate-state-db-to-fs.sh [--cwd DIR] [--dry-run]
#
# Requires: sqlite3, jq. Exits non-zero if either is missing so the
# user doesn't silently end up with a half-migrated project.

set -euo pipefail

DRY_RUN=0
CWD="$PWD"

while (( "$#" )); do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --cwd) CWD="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,18p' "$0"
      exit 0
      ;;
    *)
      echo "unknown arg: $1" >&2
      exit 2
      ;;
  esac
done

die() { echo "migrate: $*" >&2; exit 1; }

command -v sqlite3 >/dev/null || die "sqlite3 not found on PATH"
command -v jq      >/dev/null || die "jq not found on PATH"

DB="$CWD/.vibeflow/state.db"
STATE_DIR="$CWD/.vibeflow/state"

if [[ ! -f "$DB" ]]; then
  echo "migrate: no legacy state.db at $DB — nothing to migrate."
  exit 0
fi

ROW_COUNT="$(sqlite3 "$DB" \
  "SELECT COUNT(*) FROM project_state;" 2>/dev/null || echo 0)"
if [[ "$ROW_COUNT" -eq 0 ]]; then
  echo "migrate: state.db exists but project_state table is empty."
  exit 0
fi

echo "migrate: found $ROW_COUNT project(s) in $DB"
if (( DRY_RUN )); then
  echo "migrate: DRY RUN — no files will be written"
fi

ISO_NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Iterate rows. We use a sentinel separator to avoid pipe-in-subshell
# confusion when the criteria/consensus fields contain tabs/newlines.
SEP="$(printf '\x1f')"   # ASCII unit separator — safe inside JSON blobs

sqlite3 -separator "$SEP" "$DB" "\
SELECT project_id, current_phase, satisfied_criteria, \
  COALESCE(last_consensus, ''), updated_at, revision \
FROM project_state;" | while IFS="$SEP" read -r PID PHASE CRIT LAST_CON UPD REV; do
  if [[ -z "$PID" ]]; then
    continue
  fi

  # Build the rollup JSON. satisfied_criteria + last_consensus are
  # already JSON strings in the legacy schema (SqliteStateStore wrote
  # them with JSON.stringify).
  if [[ -z "$LAST_CON" ]]; then
    LAST_CON="null"
  fi
  ROLLUP="$(jq -n \
    --arg pid "$PID" \
    --arg phase "$PHASE" \
    --argjson crit "$CRIT" \
    --argjson cons "$LAST_CON" \
    --arg upd "$UPD" \
    --argjson rev "$REV" \
    '{projectId:$pid, currentPhase:$phase, satisfiedCriteria:$crit, lastConsensus:$cons, updatedAt:$upd, revision:$rev, schemaVersion:1}')"

  # Build the single project_imported event. seq == existing revision
  # so a downstream event 0<rev+1> lands naturally after the next write.
  PADDED="$(printf '%04d' "$REV")"
  EVENT_JSON="$(jq -n \
    --arg pid "$PID" \
    --arg ts "$ISO_NOW" \
    --argjson seq "$REV" \
    --arg source ".vibeflow/state.db" \
    --arg note "Imported from legacy SQLite rollup — per-event history is not reconstructible from the rollup-only source." \
    '{seq:$seq, revision:$seq, type:"project_imported", projectId:$pid, recordedAt:$ts, actor:"migrate-state-db-to-fs.sh", payload:{source:$source, importedAt:$ts, note:$note}, prevRevision:0, schemaVersion:1}')"

  EVENT_MD=$'---\n'
  EVENT_MD+="seq: $REV"$'\n'
  EVENT_MD+="revision: $REV"$'\n'
  EVENT_MD+="type: project_imported"$'\n'
  EVENT_MD+="projectId: \"$PID\""$'\n'
  EVENT_MD+="recordedAt: \"$ISO_NOW\""$'\n'
  EVENT_MD+="actor: \"migrate-state-db-to-fs.sh\""$'\n'
  EVENT_MD+="prevRevision: 0"$'\n'
  EVENT_MD+="schemaVersion: 1"$'\n'
  EVENT_MD+="payload: $(echo "$EVENT_JSON" | jq -c '.payload')"$'\n'
  EVENT_MD+="---"$'\n\n'
  EVENT_MD+="# Project imported from .vibeflow/state.db"$'\n\n'
  EVENT_MD+="Imported at $ISO_NOW.

Per-event history is not reconstructible from the rollup-only source."

  PROJ_DIR="$STATE_DIR/$PID"
  EVENTS_DIR="$PROJ_DIR/events"
  ROLLUP_PATH="$PROJ_DIR/project.json"
  EVENT_JSON_PATH="$EVENTS_DIR/${PADDED}-project_imported.json"
  EVENT_MD_PATH="$EVENTS_DIR/${PADDED}-project_imported.md"

  echo "migrate: $PID  phase=$PHASE rev=$REV"
  echo "         → $ROLLUP_PATH"
  echo "         → $EVENT_JSON_PATH"
  if (( DRY_RUN )); then
    continue
  fi

  mkdir -p "$EVENTS_DIR"
  echo "$ROLLUP" > "$ROLLUP_PATH"
  echo "$EVENT_JSON" > "$EVENT_JSON_PATH"
  printf '%s' "$EVENT_MD" > "$EVENT_MD_PATH"
done

if (( DRY_RUN )); then
  echo "migrate: dry-run complete — no files were written."
  exit 0
fi

# Rename the legacy db so re-runs see "nothing to migrate".
STAMP="$(date -u +%Y%m%d-%H%M%S)"
BAK="$DB.migrated-$STAMP.bak"
mv "$DB" "$BAK"
# Keep the WAL / SHM sidecars out of the way too.
for sidecar in "$DB-wal" "$DB-shm"; do
  [[ -f "$sidecar" ]] && mv "$sidecar" "$sidecar.migrated-$STAMP.bak" || true
done
echo "migrate: renamed legacy db → $BAK"
echo "migrate: done."
