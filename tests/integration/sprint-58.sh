#!/bin/bash
# Sprint 58 integration harness — integration-verifier: a full-stack increment
# must prove the front-end actually talks to a REAL back-end with seeded test
# data (locally, no deploy) before GO — closing the gap where a mock front-end
# over a *claimed* backend slid straight to GO because the only live-backend
# check (uat-executor) needed a deployed staging env most projects never have.
#
# Sections:
#   [S58-A] integration-wiring-check.sh detector (+ runtime probes)
#   [S58-B] integration-verifier skill structure
#   [S58-C] phase-runner TESTING wiring + the three-rung ladder + registry
#   [S58-D] phase-runner DEVELOPMENT early surfacing of an unwired UI
#   [S58-E] docs (INTEGRATION-TESTING.md + FRONTEND-TESTING.md + render-check note)
#   [S58-Z] harness self-audit

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PASS=0
FAIL=0
FAILS=()

pass() { PASS=$((PASS + 1)); echo "  ok   $1"; }
fail() { FAIL=$((FAIL + 1)); FAILS+=("$1"); echo "  FAIL $1"; }
assert_file() { local l="$1" p="$2"; if [[ -f "$p" ]]; then pass "$l"; else fail "$l (missing: $p)"; fi; }
assert_grep() { local l="$1" pat="$2" f="$3"; if grep -qE "$pat" "$f" 2>/dev/null; then pass "$l"; else fail "$l (no '$pat' in $f)"; fi; }

GATE="$REPO_ROOT/hooks/scripts/integration-wiring-check.sh"
SKILL="$REPO_ROOT/skills/integration-verifier/SKILL.md"
RUNNER="$REPO_ROOT/skills/phase-runner/SKILL.md"
FRC="$REPO_ROOT/skills/frontend-render-check/SKILL.md"
REGISTRY="$REPO_ROOT/skills/phase-policy.json"
DOC="$REPO_ROOT/docs/INTEGRATION-TESTING.md"
FEDOC="$REPO_ROOT/docs/FRONTEND-TESTING.md"

# ---------------------------------------------------------------------------
echo "== [S58-A] integration-wiring-check.sh detector =="

assert_file "[S58-A] hooks/scripts/integration-wiring-check.sh exists" "$GATE"
assert_grep "[S58-A] documented READ-ONLY / surface-only" "READ-ONLY|surface-only" "$GATE"
assert_grep "[S58-A] explains links have no backend behind them" \
  "no behind|no backend behind|links have" "$GATE"
if bash -n "$GATE" 2>/dev/null; then pass "[S58-A] detector is valid bash"; else fail "[S58-A] detector is valid bash"; fi

st() { bash "$GATE" "$1" 2>/dev/null | sed -n 's/.*"status":"\([a-z-]*\)".*/\1/p'; }

mkfe() {  # $1=root ; $2=App body — a vite web app under apps/web
  mkdir -p "$1/apps/web/src"
  echo '{"dependencies":{"vite":"5"}}' > "$1/apps/web/package.json"
  touch "$1/apps/web/index.html"
  printf '%s' "$2" > "$1/apps/web/src/App.tsx"
}
mkbe() {  # $1=root ; $2=source body — an express api under apps/api
  mkdir -p "$1/apps/api/src"
  echo '{"dependencies":{"express":"4"}}' > "$1/apps/api/package.json"
  printf '%s' "$2" > "$1/apps/api/src/server.ts"
}
probe() { local label="$1" want="$2" dir="$3"; local got; got="$(st "$dir")"; [[ "$got" == "$want" ]] && pass "$label" || fail "$label (want '$want' got '$got')"; }

# no-app — empty repo
T="$(mktemp -d)"; probe "[S58-A] empty repo → no-app" "no-app" "$T"; rm -rf "$T"

# single-tier — backend only (the carve-out)
T="$(mktemp -d)"; mkbe "$T" 'app.get("/api/x", handler);'; probe "[S58-A] backend-only → single-tier (carve-out)" "single-tier" "$T"; rm -rf "$T"

# single-tier — static front-end (no server calls)
T="$(mktemp -d)"; mkfe "$T" 'export const X = () => <div>hi</div>;'; probe "[S58-A] static front-end → single-tier" "single-tier" "$T"; rm -rf "$T"

# unwired — front-end calls /api but NO backend at all (the ANTOS case)
T="$(mktemp -d)"; mkfe "$T" 'const useDash = () => fetch("/api/dashboard");'
probe "[S58-A] UI fetch + no backend → unwired (the ANTOS case)" "unwired" "$T"; rm -rf "$T"

# unwired — front-end calls + a backend dep present but it serves NO routes
T="$(mktemp -d)"; mkfe "$T" 'const u = () => fetch("/api/x");'; mkbe "$T" 'export const moduleName = "api";'
probe "[S58-A] UI fetch + backend with no routes → unwired" "unwired" "$T"; rm -rf "$T"

# wired — front-end calls + a backend serving routes
T="$(mktemp -d)"; mkfe "$T" 'const u = () => fetch("/api/dashboard");'; mkbe "$T" 'app.get("/api/dashboard", handler);'
probe "[S58-A] UI fetch + backend routes → wired" "wired" "$T"; rm -rf "$T"

# guard — an axios .get( IN the front-end must NOT be read as a server route
T="$(mktemp -d)"; mkfe "$T" 'import axios from "axios"; export const u = () => axios.get("/api/x");'
probe "[S58-A] axios .get in the UI is not a server route → unwired" "unwired" "$T"; rm -rf "$T"

# ---------------------------------------------------------------------------
echo "== [S58-B] integration-verifier skill structure =="

assert_file "[S58-B] skills/integration-verifier/SKILL.md exists" "$SKILL"
assert_grep "[S58-B] has name frontmatter" "^name: integration-verifier$" "$SKILL"
assert_grep "[S58-B] model-invocable (phase-runner can fork it)" "^disable-model-invocation: false$" "$SKILL"
assert_grep "[S58-B] TESTING Phase Contract, full-stack only" "Runs in \*\*TESTING\*\*, \*\*full-stack" "$SKILL"
assert_grep "[S58-B] gates on integration-wiring-check (single-tier/no-app skip)" \
  "integration-wiring-check.sh" "$SKILL"
assert_grep "[S58-B] skips single-tier increments (the carve-out)" "single-tier.*skip|skipping integration" "$SKILL"
assert_grep "[S58-B] boots the real back-end LOCALLY (no staging)" "no staging|locally|no deploy" "$SKILL"
assert_grep "[S58-B] no HTTP server is itself a BLOCKED finding" "no HTTP server" "$SKILL"
assert_grep "[S58-B] seeds deterministic test data via test-data-manager" "test-data-manager" "$SKILL"
assert_grep "[S58-B] drives the SCN-UI-*-DATA data-binding scenarios" "SCN-UI-<screen>-DATA|SCN-UI-.*-DATA" "$SKILL"
assert_grep "[S58-B] checks endpoints for a 404 / missing route" "404" "$SKILL"
assert_grep "[S58-B] arm-on-pass: marker only when VERDICT == PASS" "only if .VERDICT == .PASS.|only on PASS" "$SKILL"

# ---------------------------------------------------------------------------
echo "== [S58-C] phase-runner TESTING wiring + ladder + registry =="

assert_grep "[S58-C] phase-runner TESTING runs integration-verifier" "integration-verifier" "$RUNNER"
assert_grep "[S58-C] gated on wired/unwired, single-tier/no-app skip" \
  "wired./unwired|single-tier. / .no-app. .* skip|single-tier\` / \`no-app" "$RUNNER"
assert_grep "[S58-C] reframes the three integration rungs" \
  "three integration rungs|renders on \*\*mocks\*\*.*talks right|integration rungs, in order" "$RUNNER"
assert_grep "[S58-C] names the missing-middle-rung problem" \
  "middle rung is what was missing|staging env most projects never|slipped straight to GO" "$RUNNER"
assert_grep "[S58-C] uat-executor reframed as the deployed walk" "deployed.*walk|deployed staging" "$RUNNER"
assert_grep "[S58-C] allowed-tools include integration-wiring-check" "integration-wiring-check.sh" "$RUNNER"
if command -v jq >/dev/null 2>&1; then
  if jq -e '.skills["integration-verifier"].phases | index("TESTING") != null' "$REGISTRY" >/dev/null 2>&1; then
    pass "[S58-C] phase-policy registry registers integration-verifier for TESTING"
  else
    fail "[S58-C] phase-policy registry registers integration-verifier for TESTING"
  fi
  jq -e . "$REGISTRY" >/dev/null 2>&1 && pass "[S58-C] skills/phase-policy.json is valid JSON" || fail "[S58-C] skills/phase-policy.json is valid JSON"
fi

# ---------------------------------------------------------------------------
echo "== [S58-D] phase-runner DEVELOPMENT early surfacing =="

assert_grep "[S58-D] DEVELOPMENT runs integration-wiring-check too" \
  "catch an .*unwired.* UI here too" "$RUNNER"
assert_grep "[S58-D] surfaces an unwired UI prominently" "no backend behind them" "$RUNNER"
assert_grep "[S58-D] DEVELOPMENT surfaces, TESTING gates (hard gate is integration-verifier)" \
  "integration-verifier. is the hard gate" "$RUNNER"

# ---------------------------------------------------------------------------
echo "== [S58-E] docs =="

assert_file "[S58-E] docs/INTEGRATION-TESTING.md exists" "$DOC"
assert_grep "[S58-E] doc states a claimed backend is not a verified backend" \
  "claimed.*not a .*verified|claimed backend is not a" "$DOC"
assert_grep "[S58-E] doc lays out the three rungs" "frontend-render-check|integration-verifier|uat-executor" "$DOC"
assert_grep "[S58-E] doc documents the full-stack-vs-single-tier carve-out" "single-tier|carve-out" "$DOC"
assert_grep "[S58-E] doc names the no-deploy property" "no deploy|no-deploy|locally" "$DOC"
assert_grep "[S58-E] FRONTEND-TESTING.md refreshed to three rungs" \
  "Three integration rungs|integration-verifier" "$FEDOC"
assert_grep "[S58-E] frontend-render-check note points at integration-verifier" "integration-verifier" "$FRC"

# ---------------------------------------------------------------------------
echo "== [S58-Z] harness self-audit =="
SELF="$REPO_ROOT/tests/integration/sprint-58.sh"
assert_grep "[S58-Z] sprint-58.sh runs under set -uo pipefail" '^set -uo pipefail$' "$SELF"
assert_grep "[S58-Z] covers [S58-A]" '\[S58-A\]' "$SELF"
assert_grep "[S58-Z] covers [S58-B]" '\[S58-B\]' "$SELF"
assert_grep "[S58-Z] covers [S58-C]" '\[S58-C\]' "$SELF"
assert_grep "[S58-Z] covers [S58-D]" '\[S58-D\]' "$SELF"
assert_grep "[S58-Z] covers [S58-E]" '\[S58-E\]' "$SELF"

# ---------------------------------------------------------------------------
echo ""
echo "RESULTS: $PASS passed, $FAIL failed"
if (( FAIL > 0 )); then
  printf '  - %s\n' "${FAILS[@]}"
  exit 1
fi
exit 0
