#!/bin/bash
# VibeFlow hook shared helpers.
# Sourced by every hook script; never executed directly.
#
# Every helper is defensive: if something is missing (config, db, jq, sqlite3),
# it prints nothing and returns non-zero so the caller can fall back. Hooks
# must never crash the surrounding tool call because of absent state.

set -euo pipefail

# Resolve the user-project cwd. Claude Code invokes hooks with cwd set to the
# user's working directory, but VIBEFLOW_CWD can override for tests.
vf_cwd() {
  echo "${VIBEFLOW_CWD:-$PWD}"
}

vf_config_path() {
  echo "$(vf_cwd)/vibeflow.config.json"
}

vf_state_db() {
  echo "$(vf_cwd)/.vibeflow/state.db"
}

vf_state_dir() {
  local d
  d="$(vf_cwd)/.vibeflow/state"
  mkdir -p "$d"
  echo "$d"
}

# Sprint 11-C: filesystem backend per-project directory.
# <cwd>/.vibeflow/state/<projectId>/project.json is the rollup target.
# Prints nothing (returns 1) if the project id can't be resolved yet.
vf_state_project_dir() {
  local project
  project="$(vf_project_id)"
  [[ -n "$project" ]] || return 1
  echo "$(vf_cwd)/.vibeflow/state/$project"
}

# Path to the filesystem-backend rollup file. Returns 1 if the file
# doesn't exist — callers fall back to the sqlite path for
# backend-agnostic behaviour during the Sprint 11 transition.
vf_project_json() {
  local pdir f
  pdir="$(vf_state_project_dir 2>/dev/null)" || return 1
  f="$pdir/project.json"
  [[ -f "$f" ]] || return 1
  echo "$f"
}

vf_traces_dir() {
  local d
  d="$(vf_cwd)/.vibeflow/traces"
  mkdir -p "$d"
  echo "$d"
}

vf_have_jq() {
  command -v jq >/dev/null 2>&1
}

vf_have_sqlite3() {
  command -v sqlite3 >/dev/null 2>&1
}

# Read a field from vibeflow.config.json. Prints empty and returns 1 when
# either the file or jq is missing.
vf_config_get() {
  local field="$1"
  local cfg
  cfg="$(vf_config_path)"
  [[ -f "$cfg" ]] || return 1
  vf_have_jq || return 1
  jq -r "${field} // empty" "$cfg"
}

vf_project_id() {
  vf_config_get ".project" || echo ""
}

vf_mode() {
  local m
  m="$(vf_config_get ".mode" || echo "")"
  echo "${m:-solo}"
}

# Read the authoritative current phase.
#
# Backend precedence (Sprint 11-C):
#   1. Filesystem rollup at .vibeflow/state/<project>/project.json
#   2. Legacy SQLite db at .vibeflow/state.db (kept until Sprint 11-E)
#   3. currentPhase field in vibeflow.config.json
#   4. "REQUIREMENTS" fallback
vf_current_phase() {
  local project db pjson phase
  project="$(vf_project_id)"

  # 1. filesystem rollup
  pjson="$(vf_project_json 2>/dev/null)" || pjson=""
  if [[ -n "$pjson" ]] && vf_have_jq; then
    phase="$(jq -r '.currentPhase // empty' "$pjson" 2>/dev/null || true)"
    if [[ -n "$phase" ]]; then
      echo "$phase"
      return 0
    fi
  fi

  # 2. legacy sqlite
  db="$(vf_state_db)"
  if [[ -n "$project" && -f "$db" ]] && vf_have_sqlite3; then
    phase="$(sqlite3 "$db" \
      "SELECT current_phase FROM project_state WHERE project_id = '$(vf_sql_escape "$project")';" 2>/dev/null || true)"
    if [[ -n "$phase" ]]; then
      echo "$phase"
      return 0
    fi
  fi

  # 3 + 4
  vf_config_get ".currentPhase" || echo "REQUIREMENTS"
}

# Read the last consensus status. Prefers project.json, falls back to state.db.
vf_last_consensus_status() {
  local project db pjson row

  pjson="$(vf_project_json 2>/dev/null)" || pjson=""
  if [[ -n "$pjson" ]] && vf_have_jq; then
    row="$(jq -r '.lastConsensus.status // empty' "$pjson" 2>/dev/null || true)"
    if [[ -n "$row" ]]; then
      echo "$row"
      return 0
    fi
  fi

  project="$(vf_project_id)"
  db="$(vf_state_db)"
  [[ -n "$project" && -f "$db" ]] || return 1
  vf_have_sqlite3 || return 1
  vf_have_jq || return 1
  row="$(sqlite3 "$db" \
    "SELECT last_consensus FROM project_state WHERE project_id = '$(vf_sql_escape "$project")';" 2>/dev/null || true)"
  [[ -n "$row" ]] || return 1
  echo "$row" | jq -r '.status // empty'
}

# Read satisfied criteria (JSON array). Prefers project.json, falls back to state.db.
vf_satisfied_criteria() {
  local project db pjson row

  pjson="$(vf_project_json 2>/dev/null)" || pjson=""
  if [[ -n "$pjson" ]] && vf_have_jq; then
    row="$(jq -c '.satisfiedCriteria // []' "$pjson" 2>/dev/null || true)"
    if [[ -n "$row" ]]; then
      echo "$row"
      return 0
    fi
  fi

  project="$(vf_project_id)"
  db="$(vf_state_db)"
  if [[ -z "$project" || ! -f "$db" ]] || ! vf_have_sqlite3; then
    echo "[]"
    return 0
  fi
  row="$(sqlite3 "$db" \
    "SELECT satisfied_criteria FROM project_state WHERE project_id = '$(vf_sql_escape "$project")';" 2>/dev/null || true)"
  echo "${row:-[]}"
}

# Escape a single-quote for inline SQL (we don't accept external input here;
# project ids come from our own config — but defensive anyway).
vf_sql_escape() {
  echo "${1//\'/\'\'}"
}

# Phase ordering kept in sync with mcp-servers/sdlc-engine/src/phases.ts.
# Development-gating hooks care about the index, not the identity.
VF_PHASE_ORDER=(REQUIREMENTS DESIGN ARCHITECTURE PLANNING DEVELOPMENT TESTING DEPLOYMENT)

vf_phase_index() {
  local target="$1" i=0
  for p in "${VF_PHASE_ORDER[@]}"; do
    if [[ "$p" == "$target" ]]; then
      echo "$i"
      return 0
    fi
    i=$((i + 1))
  done
  return 1
}
