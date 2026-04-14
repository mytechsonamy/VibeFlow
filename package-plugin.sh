#!/bin/bash
# VibeFlow plugin packager.
#
# Produces vibeflow-plugin-<version>.tar.gz, ready for
# `claude plugin install ./vibeflow-plugin-<version>.tar.gz`.
#
# Usage:
#   ./package-plugin.sh                # build + tarball + verify
#   ./package-plugin.sh --skip-build   # just tarball + verify (assumes dists are fresh)
#   ./package-plugin.sh --dry-run      # list files that would be tarred, no archive written
#
# Exits 0 on full success, 1 otherwise.
#
# Whitelist discipline: this script enumerates EXPLICITLY which paths
# go into the tarball. A blacklist (`tar -X exclude.txt`) would let new
# accidentally-tracked files leak into the archive — the whitelist is
# how we keep control of what ships.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_ROOT"

SKIP_BUILD=false
DRY_RUN=false
for arg in "$@"; do
  case "$arg" in
    --skip-build) SKIP_BUILD=true ;;
    --dry-run)    DRY_RUN=true ;;
    *) echo "unknown flag: $arg" >&2; exit 1 ;;
  esac
done

VERSION="$(jq -r '.version' .claude-plugin/plugin.json)"
if [[ -z "$VERSION" || "$VERSION" == "null" ]]; then
  echo "package-plugin: cannot read version from .claude-plugin/plugin.json" >&2
  exit 1
fi

ARCHIVE="vibeflow-plugin-${VERSION}.tar.gz"

PASS=0
FAIL=0
FAILS=()

pass() { PASS=$((PASS + 1)); echo "  ok   $1"; }
fail() { FAIL=$((FAIL + 1)); FAILS+=("$1"); echo "  FAIL $1"; }

# -----------------------------------------------------------------------------
echo "== [1] preflight =="

if [[ "$SKIP_BUILD" == "false" ]]; then
  echo "  rebuilding all MCP server dists..."
  if ./build-all.sh >/dev/null 2>&1; then
    pass "build-all.sh succeeded"
  else
    fail "build-all.sh failed — re-run with --skip-build to debug"
    echo "RESULTS: $PASS passed, $FAIL failed"
    exit 1
  fi
else
  pass "skipping build (--skip-build)"
fi

# Sanity: every dist/index.js must exist + parse before we package.
for mcp in sdlc-engine codebase-intel design-bridge dev-ops observability; do
  if [[ ! -f "mcp-servers/$mcp/dist/index.js" ]]; then
    fail "$mcp: dist/index.js missing"
    continue
  fi
  if node --check "mcp-servers/$mcp/dist/index.js" >/dev/null 2>&1; then
    pass "$mcp: dist/index.js parses"
  else
    fail "$mcp: dist/index.js does not parse"
  fi
done

if (( FAIL > 0 )); then
  echo "RESULTS: $PASS passed, $FAIL failed"
  exit 1
fi

# -----------------------------------------------------------------------------
echo "== [2] file whitelist =="

# Files that must be in the tarball. Each entry is either a glob or a
# concrete path. Globs are expanded by `find` so we can include subtree
# contents while excluding the per-subtree noise (node_modules, src,
# tests).
WHITELIST=(
  ".claude-plugin/plugin.json"
  ".mcp.json"
  "hooks/hooks.json"
  "hooks/scripts"
  "agents"
  "skills"
  "examples/demo-app/README.md"
  "examples/demo-app/vibeflow.config.json"
  "examples/demo-app/package.json"
  "examples/demo-app/tsconfig.json"
  "examples/demo-app/vitest.config.ts"
  "examples/demo-app/.gitignore"
  "examples/demo-app/docs"
  "examples/demo-app/src"
  "examples/demo-app/tests"
  "examples/demo-app/.vibeflow/reports"
  "examples/nextjs-demo/README.md"
  "examples/nextjs-demo/vibeflow.config.json"
  "examples/nextjs-demo/package.json"
  "examples/nextjs-demo/tsconfig.json"
  "examples/nextjs-demo/vitest.config.ts"
  "examples/nextjs-demo/next.config.mjs"
  "examples/nextjs-demo/.gitignore"
  "examples/nextjs-demo/docs"
  "examples/nextjs-demo/app"
  "examples/nextjs-demo/lib"
  "examples/nextjs-demo/actions"
  "examples/nextjs-demo/tests"
  "examples/nextjs-demo/.vibeflow/reports"
  "docs/GETTING-STARTED.md"
  "docs/CONFIGURATION.md"
  "docs/SKILLS-REFERENCE.md"
  "docs/PIPELINES.md"
  "docs/HOOKS.md"
  "docs/MCP-SERVERS.md"
  "docs/TROUBLESHOOTING.md"
  "docs/TEAM-MODE.md"
)

# MCP servers: ship dist/ + package.json + tsconfig.json. Source files,
# tests, vitest.config.ts, and node_modules are excluded.
for mcp in sdlc-engine codebase-intel design-bridge dev-ops observability; do
  WHITELIST+=("mcp-servers/$mcp/package.json")
  WHITELIST+=("mcp-servers/$mcp/tsconfig.json")
  WHITELIST+=("mcp-servers/$mcp/dist")
done

# Build the literal file list by walking each whitelist entry and
# applying a per-entry exclusion. We collect into a temp file because
# `tar` on macOS doesn't take stdin-of-paths the same way as GNU.
TMPLIST="$(mktemp -t vf-pkg-list.XXXXXX)"
trap 'rm -f "$TMPLIST"' EXIT

for entry in "${WHITELIST[@]}"; do
  if [[ ! -e "$entry" ]]; then
    fail "whitelist: $entry does not exist on disk"
    continue
  fi
  if [[ -f "$entry" ]]; then
    echo "$entry" >> "$TMPLIST"
  else
    # Directory — walk it and keep only the meaningful files.
    find "$entry" \
      -type d \( \
        -name node_modules -o \
        -name __pycache__ -o \
        -name .next -o \
        -name .git \
      \) -prune -o \
      -type f \
        ! -name '*.map' \
        ! -name '*.log' \
        ! -name '.DS_Store' \
        ! -name 'state.db' \
        ! -name 'state.db-shm' \
        ! -name 'state.db-wal' \
        -print >> "$TMPLIST"
  fi
done

FILE_COUNT="$(wc -l < "$TMPLIST" | tr -d ' ')"
pass "whitelist resolved $FILE_COUNT files"

# Sanity caps so a typo in the whitelist can't accidentally include
# the whole repo.
if (( FILE_COUNT < 100 )); then
  fail "whitelist suspiciously small ($FILE_COUNT files) — check the script"
fi
if (( FILE_COUNT > 5000 )); then
  fail "whitelist suspiciously large ($FILE_COUNT files) — likely captured node_modules"
fi
pass "whitelist size in expected range (100..5000)"

# -----------------------------------------------------------------------------
echo "== [3] forbidden-path scan =="

# These patterns must NEVER appear in the tarball list. If they do,
# either the whitelist or a glob escaped what it should have.
FORBIDDEN=(
  "node_modules/"
  "/.git/"
  "/.vibeflow/state.db"
  "/.vibeflow/artifacts/"
  "/.vibeflow/traces/"
  "/.vibeflow/state/"
  "/.DS_Store"
  "/.claude/"
  "/CLAUDE.md"
  "/ROADMAP.md"
  "/docs/SPRINT-"
  "/tests/integration/"
  "/hooks/tests/"
  "mcp-servers/sdlc-engine/src/"
  "mcp-servers/sdlc-engine/tests/"
)
for pat in "${FORBIDDEN[@]}"; do
  if grep -F "$pat" "$TMPLIST" >/dev/null 2>&1; then
    fail "forbidden path leaked into tarball: $pat"
  else
    pass "no $pat in tarball"
  fi
done

if (( FAIL > 0 )); then
  echo "RESULTS: $PASS passed, $FAIL failed"
  exit 1
fi

# -----------------------------------------------------------------------------
if [[ "$DRY_RUN" == "true" ]]; then
  echo "== dry run — would tar these files: =="
  cat "$TMPLIST"
  echo
  echo "RESULTS: $PASS passed, $FAIL failed (dry run)"
  exit 0
fi

echo "== [4] writing $ARCHIVE =="
# `tar -cz -T list` reads the file list from a paths-file. Same on
# macOS BSD tar and GNU tar (the -T flag is portable).
if tar -cz -T "$TMPLIST" -f "$ARCHIVE" 2>/dev/null; then
  ARCHIVE_SIZE="$(du -h "$ARCHIVE" | awk '{print $1}')"
  pass "archive written ($ARCHIVE_SIZE)"
else
  fail "tar invocation failed"
fi

# -----------------------------------------------------------------------------
echo "== [5] post-archive verification =="

# The archive must contain the manifest at the expected path.
if tar -tzf "$ARCHIVE" 2>/dev/null | grep -q "^.claude-plugin/plugin.json$"; then
  pass "archive contains .claude-plugin/plugin.json"
else
  fail "archive contains .claude-plugin/plugin.json"
fi

# Each MCP server dist/index.js must be in the archive.
for mcp in sdlc-engine codebase-intel design-bridge dev-ops observability; do
  if tar -tzf "$ARCHIVE" 2>/dev/null | grep -q "^mcp-servers/$mcp/dist/index.js$"; then
    pass "archive contains $mcp/dist/index.js"
  else
    fail "archive contains $mcp/dist/index.js"
  fi
done

# No node_modules in the archive.
if tar -tzf "$ARCHIVE" 2>/dev/null | grep -q "/node_modules/"; then
  fail "archive contains node_modules — packaging leak"
else
  pass "archive contains no node_modules"
fi

# No .DS_Store in the archive.
if tar -tzf "$ARCHIVE" 2>/dev/null | grep -q "\\.DS_Store$"; then
  fail "archive contains .DS_Store"
else
  pass "archive contains no .DS_Store"
fi

echo
echo "RESULTS: $PASS passed, $FAIL failed"
echo "Archive: $REPO_ROOT/$ARCHIVE"
if (( FAIL > 0 )); then
  echo "Failures:"
  for f in "${FAILS[@]}"; do echo "  - $f"; done
  exit 1
fi
exit 0
