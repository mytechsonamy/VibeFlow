#!/bin/bash
# Sprint 54 integration harness — ui-verification-debt signal: surfaces a web UI
# that has never been render-verified (no frontend-conformance.md) or whose
# verification is stale, so a UI built in an earlier cycle can't stay buried.
#
# Sections:
#   [S54-A] ui-verification-debt.sh reader (+ runtime probes)
#   [S54-B] phase-runner Step 0 + flow-status surface it
#   [S54-Z] harness self-audit

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PASS=0
FAIL=0
FAILS=()

pass() { PASS=$((PASS + 1)); echo "  ok   $1"; }
fail() { FAIL=$((FAIL + 1)); FAILS+=("$1"); echo "  FAIL $1"; }
assert_file() { local l="$1" p="$2"; if [[ -f "$p" ]]; then pass "$l"; else fail "$l (missing: $p)"; fi; }
assert_grep() { local l="$1" pat="$2" f="$3"; if grep -qE "$pat" "$f" 2>/dev/null; then pass "$l"; else fail "$l (no '$pat' in $f)"; fi; }

GATE="$REPO_ROOT/hooks/scripts/ui-verification-debt.sh"
RUNNER="$REPO_ROOT/skills/phase-runner/SKILL.md"
FS="$REPO_ROOT/skills/flow-status/SKILL.md"

# ---------------------------------------------------------------------------
echo "== [S54-A] ui-verification-debt.sh reader =="

assert_file "[S54-A] hooks/scripts/ui-verification-debt.sh exists" "$GATE"
assert_grep "[S54-A] documented as READ-ONLY / surface-only" "READ-ONLY|Surface-only" "$GATE"
assert_grep "[S54-A] looks for the frontend-conformance.md report" "frontend-conformance.md" "$GATE"
assert_grep "[S54-A] fail-safe to no-ui on a non-UI repo" 'status.:.no-ui' "$GATE"
if bash -n "$GATE" 2>/dev/null; then pass "[S54-A] reader is valid bash"; else fail "[S54-A] reader is valid bash"; fi

st() { bash "$GATE" "$1" 2>/dev/null | sed -n 's/.*"status":"\([a-z-]*\)".*/\1/p'; }

# no-ui — empty dir
T="$(mktemp -d)"; [[ "$(st "$T")" == "no-ui" ]] && pass "[S54-A] empty repo → no-ui" || fail "[S54-A] empty repo → no-ui"; rm -rf "$T"

# never — vite UI + entry, no report
T="$(mktemp -d)"; mkdir -p "$T/apps/web/src"; echo '{"dependencies":{"vite":"5"}}' > "$T/apps/web/package.json"
touch "$T/apps/web/index.html"; echo x > "$T/apps/web/src/App.tsx"
[[ "$(st "$T")" == "never" ]] && pass "[S54-A] web UI, no report → never" || fail "[S54-A] web UI, no report → never (got '$(st "$T")')"

# verified — report newer than src
mkdir -p "$T/.vibeflow/reports"; touch "$T/.vibeflow/reports/frontend-conformance.md"
sleep 1; touch "$T/.vibeflow/reports/frontend-conformance.md"   # ensure report is newest
[[ "$(st "$T")" == "verified" ]] && pass "[S54-A] report newer than UI src → verified" || fail "[S54-A] verified (got '$(st "$T")')"

# stale — src newer than report
sleep 1; touch "$T/apps/web/src/App.tsx"
[[ "$(st "$T")" == "stale" ]] && pass "[S54-A] UI src newer than report → stale" || fail "[S54-A] stale (got '$(st "$T")')"
rm -rf "$T"

# a backend-only repo (no web framework) → no-ui (not noisy)
T="$(mktemp -d)"; mkdir -p "$T/apps/api/src"; echo '{"dependencies":{"fastify":"4"}}' > "$T/apps/api/package.json"; echo x > "$T/apps/api/src/x.ts"
[[ "$(st "$T")" == "no-ui" ]] && pass "[S54-A] backend-only repo → no-ui (quiet)" || fail "[S54-A] backend-only → no-ui (got '$(st "$T")')"; rm -rf "$T"

# ---------------------------------------------------------------------------
echo "== [S54-B] phase-runner + flow-status surface it =="

assert_grep "[S54-B] phase-runner Step 0 calls the reader" "ui-verification-debt.sh" "$RUNNER"
assert_grep "[S54-B] phase-runner surfaces never/stale → frontend-render-check" \
  "never render-verified|render-verification — re-run|/vibeflow:frontend-render-check" "$RUNNER"
assert_grep "[S54-B] phase-runner is surface-only (verified/no-ui → say nothing)" \
  "verified.*no-ui.*say nothing|never blocks, never auto-runs" "$RUNNER"
assert_grep "[S54-B] phase-runner allowed-tools include the reader" "ui-verification-debt.sh" "$RUNNER"
assert_grep "[S54-B] flow-status renders the UI render-verification line" "ui-verification-debt.sh" "$FS"
assert_grep "[S54-B] flow-status only shows it when there's debt" \
  "only when there.s debt|render nothing" "$FS"
assert_grep "[S54-B] flow-status allowed-tools include the reader" "ui-verification-debt.sh" "$FS"

# ---------------------------------------------------------------------------
echo "== [S54-Z] harness self-audit =="
SELF="$REPO_ROOT/tests/integration/sprint-54.sh"
assert_grep "[S54-Z] sprint-54.sh runs under set -uo pipefail" '^set -uo pipefail$' "$SELF"
assert_grep "[S54-Z] covers [S54-A]" '\[S54-A\]' "$SELF"
assert_grep "[S54-Z] covers [S54-B]" '\[S54-B\]' "$SELF"

# ---------------------------------------------------------------------------
echo ""
echo "RESULTS: $PASS passed, $FAIL failed"
if (( FAIL > 0 )); then
  printf '  - %s\n' "${FAILS[@]}"
  exit 1
fi
exit 0
