#!/bin/bash
# Sprint 55 integration harness — ui-styling-check: catch a "skinless" UI (its
# structure built, its design never implemented — className everywhere, zero
# stylesheet/tokens) in DEVELOPMENT, not only at the TESTING render-check.
#
# Sections:
#   [S55-A] ui-styling-check.sh detector (+ runtime probes)
#   [S55-B] phase-runner DEVELOPMENT + frontend-render-check wiring
#   [S55-Z] harness self-audit

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PASS=0
FAIL=0
FAILS=()

pass() { PASS=$((PASS + 1)); echo "  ok   $1"; }
fail() { FAIL=$((FAIL + 1)); FAILS+=("$1"); echo "  FAIL $1"; }
assert_file() { local l="$1" p="$2"; if [[ -f "$p" ]]; then pass "$l"; else fail "$l (missing: $p)"; fi; }
assert_grep() { local l="$1" pat="$2" f="$3"; if grep -qE "$pat" "$f" 2>/dev/null; then pass "$l"; else fail "$l (no '$pat' in $f)"; fi; }

GATE="$REPO_ROOT/hooks/scripts/ui-styling-check.sh"
RUNNER="$REPO_ROOT/skills/phase-runner/SKILL.md"
FRC="$REPO_ROOT/skills/frontend-render-check/SKILL.md"

# ---------------------------------------------------------------------------
echo "== [S55-A] ui-styling-check.sh detector =="

assert_file "[S55-A] hooks/scripts/ui-styling-check.sh exists" "$GATE"
assert_grep "[S55-A] documented READ-ONLY / surface-only" "READ-ONLY|surface-only" "$GATE"
assert_grep "[S55-A] explains skinless = design specified but never implemented" \
  "design was never implemented|never implemented|bare default HTML" "$GATE"
if bash -n "$GATE" 2>/dev/null; then pass "[S55-A] detector is valid bash"; else fail "[S55-A] detector is valid bash"; fi

st() { bash "$GATE" "$1" 2>/dev/null | sed -n 's/.*"status":"\([a-z-]*\)".*/\1/p'; }

mkui() {  # $1=dir ; creates a vite UI with the given App.tsx body ($2)
  mkdir -p "$1/apps/web/src"
  echo '{"dependencies":{"vite":"5"}}' > "$1/apps/web/package.json"
  touch "$1/apps/web/index.html"
  printf '%s' "$2" > "$1/apps/web/src/App.tsx"
}

# no-ui
T="$(mktemp -d)"; [[ "$(st "$T")" == "no-ui" ]] && pass "[S55-A] empty repo → no-ui" || fail "[S55-A] empty repo → no-ui"; rm -rf "$T"

# skinless — the ANTOS case: className everywhere, no CSS
T="$(mktemp -d)"; mkui "$T" 'export const X = () => <div className="card"><span className="amount">1</span></div>;'
[[ "$(st "$T")" == "skinless" ]] && pass "[S55-A] className + zero CSS → skinless (the ANTOS case)" || fail "[S55-A] skinless (got '$(st "$T")')"; rm -rf "$T"

# styled — a stylesheet import
T="$(mktemp -d)"; mkui "$T" "import './styles.css';\nexport const X = () => <div className=\"card\"/>;"; touch "$T/apps/web/src/styles.css"
[[ "$(st "$T")" == "styled" ]] && pass "[S55-A] stylesheet import → styled" || fail "[S55-A] stylesheet import → styled (got '$(st "$T")')"; rm -rf "$T"

# styled — Tailwind config (the ls-vs-glob trap)
T="$(mktemp -d)"; mkui "$T" 'export const X = () => <div className="p-4"/>;'; touch "$T/tailwind.config.js"
[[ "$(st "$T")" == "styled" ]] && pass "[S55-A] Tailwind config → styled" || fail "[S55-A] Tailwind config → styled (got '$(st "$T")')"; rm -rf "$T"

# styled — design tokens / CSS custom prop consumed
T="$(mktemp -d)"; mkui "$T" 'export const X = () => <div style={{color:"var(--brand)"}} className="card"/>;'
[[ "$(st "$T")" == "styled" ]] && pass "[S55-A] CSS custom prop / token → styled" || fail "[S55-A] token → styled (got '$(st "$T")')"; rm -rf "$T"

# no-ui — backend only (not noisy)
T="$(mktemp -d)"; mkdir -p "$T/apps/api/src"; echo '{"dependencies":{"fastify":"4"}}' > "$T/apps/api/package.json"; echo x > "$T/apps/api/src/x.ts"
[[ "$(st "$T")" == "no-ui" ]] && pass "[S55-A] backend-only → no-ui (quiet)" || fail "[S55-A] backend-only → no-ui"; rm -rf "$T"

# ---------------------------------------------------------------------------
echo "== [S55-B] phase-runner + frontend-render-check wiring =="

assert_grep "[S55-B] phase-runner DEVELOPMENT runs ui-styling-check" "ui-styling-check.sh" "$RUNNER"
assert_grep "[S55-B] phase-runner explains absence is invisible to quality-gates/code.reviewed" \
  "absence.*is invisible|invisible to .quality-gates|reads clean in a diff" "$RUNNER"
assert_grep "[S55-B] phase-runner surfaces skinless prominently (not a nit)" \
  "skinless.*surface .\*\*prominently|never implemented.*Implement the styling|real DEVELOPMENT gap, not a" "$RUNNER"
assert_grep "[S55-B] phase-runner notes TESTING render-check is the hard gate" \
  "render-check is the hard gate|catches the same gap" "$RUNNER"
assert_grep "[S55-B] phase-runner allowed-tools include ui-styling-check" "ui-styling-check.sh" "$RUNNER"
assert_grep "[S55-B] frontend-render-check runs the static skinless pre-check" "ui-styling-check.sh" "$FRC"
assert_grep "[S55-B] frontend-render-check BLOCKs a skinless UI without a browser" \
  "skinless.*BLOCKED|immediate .BLOCKED.|nameable without a browser" "$FRC"

# ---------------------------------------------------------------------------
echo "== [S55-Z] harness self-audit =="
SELF="$REPO_ROOT/tests/integration/sprint-55.sh"
assert_grep "[S55-Z] sprint-55.sh runs under set -uo pipefail" '^set -uo pipefail$' "$SELF"
assert_grep "[S55-Z] covers [S55-A]" '\[S55-A\]' "$SELF"
assert_grep "[S55-Z] covers [S55-B]" '\[S55-B\]' "$SELF"

# ---------------------------------------------------------------------------
echo ""
echo "RESULTS: $PASS passed, $FAIL failed"
if (( FAIL > 0 )); then
  printf '  - %s\n' "${FAILS[@]}"
  exit 1
fi
exit 0
