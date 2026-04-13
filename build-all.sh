#!/bin/bash
# VibeFlow build-all.
#
# Rebuilds the dist/ directory for every MCP server. Used by maintainers
# before committing dist artifacts (which ship with the plugin tarball
# so end users don't need to run a build step on `claude plugin install`).
#
# Usage:
#   ./build-all.sh                 # build all 5 MCP servers
#   ./build-all.sh --check         # check (no install/build), assert dist files exist + parse
#
# Exits 0 on full success, 1 otherwise.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MCPS=(sdlc-engine codebase-intel design-bridge dev-ops observability)

MODE="build"
if [[ "${1:-}" == "--check" ]]; then
  MODE="check"
fi

PASS=0
FAIL=0
FAILS=()

pass() { PASS=$((PASS + 1)); echo "  ok   $1"; }
fail() { FAIL=$((FAIL + 1)); FAILS+=("$1"); echo "  FAIL $1"; }

build_one() {
  local mcp="$1"
  local dir="$REPO_ROOT/mcp-servers/$mcp"
  if [[ ! -d "$dir" ]]; then
    fail "$mcp: directory missing"
    return
  fi
  pushd "$dir" >/dev/null

  if [[ "$MODE" == "build" ]]; then
    if [[ ! -d node_modules ]]; then
      echo "  $mcp: installing dependencies..."
      if npm install >/dev/null 2>&1; then
        pass "$mcp: npm install"
      else
        fail "$mcp: npm install"
        popd >/dev/null
        return
      fi
    else
      pass "$mcp: node_modules already present"
    fi

    echo "  $mcp: building..."
    if npm run build >/dev/null 2>&1; then
      pass "$mcp: npm run build"
    else
      fail "$mcp: npm run build"
      popd >/dev/null
      return
    fi
  fi

  if [[ ! -f dist/index.js ]]; then
    fail "$mcp: dist/index.js missing"
    popd >/dev/null
    return
  fi
  pass "$mcp: dist/index.js exists"

  if node --check dist/index.js 2>/dev/null; then
    pass "$mcp: dist/index.js parses as valid JS"
  else
    fail "$mcp: dist/index.js parses as valid JS"
  fi

  popd >/dev/null
}

echo "== build-all (mode: $MODE) =="
for mcp in "${MCPS[@]}"; do
  echo "-- $mcp --"
  build_one "$mcp"
done

echo
echo "RESULTS: $PASS passed, $FAIL failed"
if (( FAIL > 0 )); then
  echo "Failures:"
  for f in "${FAILS[@]}"; do echo "  - $f"; done
  exit 1
fi
exit 0
