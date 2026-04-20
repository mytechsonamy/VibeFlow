#!/bin/bash
# replay-events.sh — rebuild .vibeflow/state/<project>/project.json from
# the event log. Rescue tool for crash-corrupted rollups; also useful
# when verifying that the event log alone captures the full state.
#
# Usage:
#   bin/replay-events.sh [--cwd DIR] <projectId> [--check]
#
# Default: overwrites project.json with the replay result.
# With --check: compares against the on-disk rollup and exits non-zero
# on mismatch (stdout shows the diff).

set -euo pipefail

CWD="$PWD"
PROJECT=""
CHECK_ONLY=0
STATE_DIR_OVERRIDE=""

while (( "$#" )); do
  case "$1" in
    --cwd) CWD="$2"; shift 2 ;;
    --state-dir) STATE_DIR_OVERRIDE="$2"; shift 2 ;;
    --check) CHECK_ONLY=1; shift ;;
    -h|--help)
      sed -n '2,13p' "$0"
      exit 0
      ;;
    -*)
      echo "unknown flag: $1" >&2
      exit 2
      ;;
    *)
      if [[ -z "$PROJECT" ]]; then
        PROJECT="$1"
      else
        echo "unexpected positional arg: $1" >&2
        exit 2
      fi
      shift
      ;;
  esac
done

if [[ -z "$PROJECT" ]]; then
  echo "replay-events: missing <projectId>" >&2
  exit 2
fi

command -v node >/dev/null || { echo "replay-events: node not on PATH" >&2; exit 1; }

if [[ -n "$STATE_DIR_OVERRIDE" ]]; then
  STATE_DIR="$STATE_DIR_OVERRIDE"
elif [[ -n "${VIBEFLOW_STATE_DIR:-}" ]]; then
  STATE_DIR="$VIBEFLOW_STATE_DIR"
else
  STATE_DIR="$CWD/.vibeflow/state"
fi
PROJ_DIR="$STATE_DIR/$PROJECT"
if [[ ! -d "$PROJ_DIR" ]]; then
  echo "replay-events: no project dir at $PROJ_DIR" >&2
  exit 1
fi

# Find the sdlc-engine dist next to this repo root. The script sits in
# bin/ of the VibeFlow repo, so the dist is two levels up.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENGINE_DIST="$REPO_ROOT/mcp-servers/sdlc-engine/dist/state/filesystem.js"
if [[ ! -f "$ENGINE_DIST" ]]; then
  echo "replay-events: sdlc-engine dist missing at $ENGINE_DIST (run npm run build)" >&2
  exit 1
fi

REPLAY_OUT="$(
node --input-type=module -e "
import { FilesystemStateStore } from '$ENGINE_DIST';
const store = new FilesystemStateStore('$STATE_DIR');
await store.init();
const state = await store.rebuildRollup('$PROJECT');
if (state === null) {
  process.stderr.write('replay-events: no events for $PROJECT\n');
  process.exit(1);
}
const rollup = { ...state, schemaVersion: 1 };
process.stdout.write(JSON.stringify(rollup, null, 2) + '\n');
await store.close();
"
)"

ROLLUP_PATH="$PROJ_DIR/project.json"

if (( CHECK_ONLY )); then
  if [[ ! -f "$ROLLUP_PATH" ]]; then
    echo "replay-events: project.json missing — cannot --check" >&2
    exit 1
  fi
  if diff -u <(cat "$ROLLUP_PATH") <(printf '%s\n' "$REPLAY_OUT"); then
    echo "replay-events: project.json matches replay ✓"
    exit 0
  else
    echo "replay-events: MISMATCH between project.json and replay" >&2
    exit 1
  fi
fi

printf '%s\n' "$REPLAY_OUT" > "$ROLLUP_PATH"
echo "replay-events: rebuilt $ROLLUP_PATH from events + archive."
