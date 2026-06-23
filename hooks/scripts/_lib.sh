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

# Sprint 28-A: cross-project meta-learning shared store directory.
# Default `$HOME/.vibeflow`; overridable via VIBEFLOW_GLOBAL_DIR (tests
# point it at a temp dir so they never touch the real home store).
vf_global_dir() {
  echo "${VIBEFLOW_GLOBAL_DIR:-$HOME/.vibeflow}"
}

# Sprint 28-A: one-way, stable hash of the project id — lets the global
# store COUNT distinct projects without IDENTIFYING them (no project name
# leaves the repo). First 12 hex chars of sha256. `shasum` ships on macOS
# + Linux; degrades to a fixed sentinel if absent so callers never break.
vf_project_hash() {
  local pid; pid="$(vf_project_id)"
  if command -v shasum >/dev/null 2>&1; then
    printf '%s' "$pid" | shasum -a 256 | cut -c1-12
  else
    echo "unknownproj0"
  fi
}

# Sprint 60: slugify a git branch name into a projectId-safe token. The
# engine's validateProjectId allows [a-zA-Z0-9_-]{1,64}, so we lowercase,
# replace every other char (incl. `/`) with `-`, collapse runs, trim
# leading/trailing `-`, and clamp to 64. Reads the branch from $1 (or the
# current branch when omitted).
vf_branch_slug() {
  local branch="${1:-}"
  [[ -n "$branch" ]] || return 1
  # lowercase
  branch="$(printf '%s' "$branch" | tr '[:upper:]' '[:lower:]')"
  # non-allowed -> '-', collapse runs of '-', trim edges
  branch="$(printf '%s' "$branch" | sed -e 's/[^a-z0-9_-]/-/g' -e 's/-\{2,\}/-/g' -e 's/^-//' -e 's/-$//')"
  [[ -n "$branch" ]] || return 1
  printf '%s' "${branch:0:64}"
}

# Sprint 60: resolve the work-stream id — the projectId every state read
# and every MCP call should key on. This is the single mechanism behind
# parallel team work: each branch / git worktree gets its own isolated
# `.vibeflow/state/<streamId>/` (the engine already locks + isolates per
# projectId).
#
# Resolution:
#   1. streams.enabled != true            -> bare project id (legacy path,
#                                            bit-for-bit unchanged).
#   2. VIBEFLOW_STREAM set                -> "<project>__<slug(env)>" override.
#   3. streams.idStrategy == "fixed"      -> bare project id.
#   4. not a git repo / detached HEAD /
#      default branch (main|master) /
#      slug == project                    -> bare project id (the initial
#                                            stream keeps the legacy dir).
#   5. otherwise                          -> "<project>__<branch-slug>".
# Always prints SOMETHING when a project id exists; returns 1 only when the
# project id itself can't be resolved.
vf_stream_id() {
  local project enabled strategy branch slug
  project="$(vf_project_id)"
  [[ -n "$project" ]] || return 1

  enabled="$(vf_config_get '.streams.enabled' 2>/dev/null || echo "")"
  if [[ "$enabled" != "true" ]]; then
    printf '%s' "$project"
    return 0
  fi

  # explicit override wins (still namespaced under the project)
  if [[ -n "${VIBEFLOW_STREAM:-}" ]]; then
    slug="$(vf_branch_slug "$VIBEFLOW_STREAM" 2>/dev/null || echo "")"
    if [[ -n "$slug" && "$slug" != "$project" ]]; then
      local id="${project}__${slug}"; printf '%s' "${id:0:64}"
    else
      printf '%s' "$project"
    fi
    return 0
  fi

  strategy="$(vf_config_get '.streams.idStrategy' 2>/dev/null || echo "branch")"
  if [[ "$strategy" == "fixed" ]]; then
    printf '%s' "$project"
    return 0
  fi

  # branch strategy: derive from the current git branch
  if ! command -v git >/dev/null 2>&1; then
    printf '%s' "$project"; return 0
  fi
  branch="$(git -C "$(vf_cwd)" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")"
  # detached HEAD reports "HEAD"; treat as no-branch
  if [[ -z "$branch" || "$branch" == "HEAD" ]]; then
    printf '%s' "$project"; return 0
  fi
  case "$branch" in
    main|master) printf '%s' "$project"; return 0 ;;
  esac
  slug="$(vf_branch_slug "$branch" 2>/dev/null || echo "")"
  if [[ -z "$slug" || "$slug" == "$project" ]]; then
    printf '%s' "$project"
  else
    local id="${project}__${slug}"; printf '%s' "${id:0:64}"
  fi
}

# Sprint 11-C: filesystem backend per-project directory.
# <cwd>/.vibeflow/state/<streamId>/project.json is the rollup target.
# Sprint 60: keyed on vf_stream_id (== vf_project_id when streams are off)
# so every existing state read becomes work-stream-aware for free.
# Prints nothing (returns 1) if the id can't be resolved yet.
vf_state_project_dir() {
  local project
  project="$(vf_stream_id 2>/dev/null)" || project="$(vf_project_id)"
  [[ -n "$project" ]] || return 1
  echo "$(vf_cwd)/.vibeflow/state/$project"
}

# Sprint 60: path to the skill-managed lifecycle.json. With streams OFF
# (default) this is the legacy single location `.vibeflow/state/lifecycle.json`
# — bit-for-bit unchanged. With streams ON it is co-located with the
# work-stream's project.json at `.vibeflow/state/<streamId>/lifecycle.json`
# so each branch/worktree tracks its own cycle independently. Always prints
# a path (never fails); skills read/write this with the Read/Write tools.
vf_lifecycle_path() {
  local enabled sid base
  enabled="$(vf_config_get '.streams.enabled' 2>/dev/null || echo "")"
  if [[ "$enabled" == "true" ]]; then
    sid="$(vf_stream_id 2>/dev/null || echo "")"
    base="$(vf_project_id 2>/dev/null || echo "")"
    # Only a NON-initial stream (sid != bare project id) gets its own
    # subdir. The initial/main stream (sid collapses to the bare project id)
    # keeps the legacy `.vibeflow/state/lifecycle.json`, so turning streams on
    # never moves an existing project's lifecycle.
    if [[ -n "$sid" && "$sid" != "$base" ]]; then
      echo "$(vf_cwd)/.vibeflow/state/$sid/lifecycle.json"
      return 0
    fi
  fi
  echo "$(vf_cwd)/.vibeflow/state/lifecycle.json"
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

# Sprint 14-C removed vf_mode(). The solo/team distinction no longer
# exists — state is filesystem-backed (Sprint 11) and consensus is
# gated by CLI availability (Sprint 14-A), not by a mode switch.
# Callers that need quorum information read
# `.consensus.quorum` from vibeflow.config.json directly.

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

# Sprint 13: phase-write-guard helpers.

# Path to the hook-consumed phase policy file.
vf_policy_path() {
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  echo "$script_dir/phase-policy.json"
}

# Strip the project cwd prefix from an absolute path, returning a
# repo-relative path with no leading slash. Paths already relative (no
# leading slash) pass through unchanged.
vf_relpath() {
  local abs="$1"
  local cwd
  cwd="$(vf_cwd)"
  # Normalize trailing slash on cwd.
  cwd="${cwd%/}"
  case "$abs" in
    "$cwd/"*) echo "${abs#"$cwd"/}" ;;
    "$cwd")   echo "." ;;
    /*)       echo "$abs" ;;  # absolute but outside cwd — caller decides
    *)        echo "$abs" ;;  # already relative
  esac
}

# Produce an allow/warn/block decision for (phase, relative-path)
# against the phase policy JSON. Prints one of those three words on
# stdout. Returns 0 on success; returns 1 only when python3 itself is
# missing (in which case the caller should fail-safe to allow).
vf_phase_decision() {
  local phase="$1" rel="$2" policy="${3:-$(vf_policy_path)}"
  command -v python3 >/dev/null 2>&1 || return 1
  python3 - "$phase" "$rel" "$policy" <<'PY'
import json, re, sys

phase, rel, policy_path = sys.argv[1], sys.argv[2], sys.argv[3]

try:
    with open(policy_path) as f:
        policy = json.load(f)
except (OSError, ValueError):
    print("allow")
    sys.exit(0)

phase_block = policy.get("phases", {}).get(phase, {})
allow_globs = phase_block.get("allow", [])
warn_globs  = phase_block.get("warn", [])

SS, TS, DS = "\x00SS\x00", "\x00TS\x00", "\x00DS\x00"
META = r".+()[]{}^$|\\"


def glob_to_regex(g):
    out = ""
    for ch in g:
        if ch in META:
            out += "\\" + ch
        else:
            out += ch
    out = out.replace("**/", SS).replace("/**", TS).replace("**", DS)
    out = out.replace("*", "[^/]*").replace("?", "[^/]")
    out = out.replace(SS, "(?:.*/)?").replace(TS, "(?:/.*)?").replace(DS, ".*")
    return "^" + out + "$"


def matches_any(globs, path):
    return any(re.match(glob_to_regex(g), path) for g in globs)


if matches_any(allow_globs, rel):
    print("allow")
elif matches_any(warn_globs, rel):
    print("warn")
else:
    print("block")
PY
}
