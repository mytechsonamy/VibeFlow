#!/bin/bash
# Sprint 66 integration harness — the visual battery is stack-agnostic. A
# server-rendered web UI (FastAPI/Flask/Django HTMLResponse·templates, Rails,
# Razor, a backend-served static SPA) is no longer invisible to ui-styling-check
# / ui-verification-debt / frontend-render-check (the Clera gap: a FastAPI app
# building HTML in Python read as "no-ui", so the whole visual battery skipped).
#
# Sections:
#   [S66-A] vf_web_ui_kind detector (js / server-rendered / static / none)
#   [S66-B] ui-verification-debt + ui-styling-check detect server-rendered (not no-ui)
#   [S66-C] frontend-render-check skill has the stack-agnostic / server-rendered boot path
#   [S66-D] docs
#   [S66-Z] harness self-audit

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PASS=0
FAIL=0
FAILS=()

pass() { PASS=$((PASS + 1)); echo "  ok   $1"; }
fail() { FAIL=$((FAIL + 1)); FAILS+=("$1"); echo "  FAIL $1"; }
assert_grep() { local l="$1" pat="$2" f="$3"; if grep -qE "$pat" "$f" 2>/dev/null; then pass "$l"; else fail "$l (no '$pat' in $f)"; fi; }
assert_eq() { local l="$1" e="$2" a="$3"; if [[ "$e" == "$a" ]]; then pass "$l"; else fail "$l (expected=$e actual=$a)"; fi; }

LIB="$REPO_ROOT/hooks/scripts/_lib.sh"
kind() { bash -c "source '$LIB'; vf_web_ui_kind '$1'"; }

# ---------------------------------------------------------------------------
echo "== [S66-A] vf_web_ui_kind detector =="

assert_grep "[S66-A] vf_web_ui_kind defined in _lib.sh" "^vf_web_ui_kind\\(\\)" "$LIB"

D="$(mktemp -d)"; echo '{"dependencies":{"next":"14"}}' > "$D/package.json"; touch "$D/index.html"
assert_eq "[S66-A] JS framework → js" "js" "$(kind "$D")"; rm -rf "$D"

D="$(mktemp -d)"; echo "from fastapi.responses import HTMLResponse" > "$D/app.py"
assert_eq "[S66-A] FastAPI HTMLResponse → server-rendered" "server-rendered" "$(kind "$D")"; rm -rf "$D"

D="$(mktemp -d)"; mkdir -p "$D/app/templates"; touch "$D/app/templates/home.html"; echo "x" > "$D/app.py"
assert_eq "[S66-A] templates/*.html → server-rendered" "server-rendered" "$(kind "$D")"; rm -rf "$D"

D="$(mktemp -d)"; mkdir -p "$D/src/api/static"; touch "$D/src/api/static/index.html"
assert_eq "[S66-A] backend-served static/index.html → server-rendered" "server-rendered" "$(kind "$D")"; rm -rf "$D"

D="$(mktemp -d)"; touch "$D/index.html"
assert_eq "[S66-A] plain index.html → static" "static" "$(kind "$D")"; rm -rf "$D"

D="$(mktemp -d)"; echo "import pandas" > "$D/engine.py"
assert_eq "[S66-A] pure backend, no UI → none" "none" "$(kind "$D")"; rm -rf "$D"

D="$(mktemp -d)"; mkdir -p "$D/design/mockups"; touch "$D/design/mockups/screen.html"
assert_eq "[S66-A] design mockups only → none (excluded)" "none" "$(kind "$D")"; rm -rf "$D"

# ---------------------------------------------------------------------------
echo "== [S66-B] readers detect server-rendered (not no-ui) =="

UVD="$REPO_ROOT/hooks/scripts/ui-verification-debt.sh"
USC="$REPO_ROOT/hooks/scripts/ui-styling-check.sh"
assert_grep "[S66-B] ui-verification-debt uses vf_web_ui_kind" "vf_web_ui_kind" "$UVD"
assert_grep "[S66-B] ui-styling-check uses vf_web_ui_kind" "vf_web_ui_kind" "$USC"

# A FastAPI server-rendered app with no conformance report → "never" (not no-ui).
D="$(mktemp -d)"; echo "from fastapi.responses import HTMLResponse" > "$D/app.py"; mkdir -p "$D/.vibeflow/reports"
assert_eq "[S66-B] server-rendered, no report → never" "never" "$(bash "$UVD" "$D" | jq -r '.status')"
# styled server-rendered (class + css) → styled
mkdir -p "$D/static"; printf '<div class="card">x</div>' > "$D/static/index.html"; printf '.card{color:red}' > "$D/static/app.css"
assert_eq "[S66-B] server-rendered with css → styled" "styled" "$(bash "$USC" "$D" | jq -r '.status')"
rm -rf "$D"
# server-rendered class markup but NO css anywhere → skinless
D="$(mktemp -d)"; mkdir -p "$D/app/templates"; printf '<div class="x">y</div>' > "$D/app/templates/home.html"; echo "from flask import render_template" > "$D/app.py"
assert_eq "[S66-B] server-rendered, no css → skinless" "skinless" "$(bash "$USC" "$D" | jq -r '.status')"
rm -rf "$D"
# pure backend → no-ui (no regression)
D="$(mktemp -d)"; echo "import pandas" > "$D/x.py"
assert_eq "[S66-B] pure backend → no-ui" "no-ui" "$(bash "$UVD" "$D" | jq -r '.status')"
rm -rf "$D"

# ---------------------------------------------------------------------------
echo "== [S66-C] frontend-render-check stack-agnostic / server-rendered boot =="

FRC="$REPO_ROOT/skills/frontend-render-check/SKILL.md"
assert_grep "[S66-C] Phase Contract is stack-agnostic" "stack-agnostic" "$FRC"
assert_grep "[S66-C] has a server-rendered boot step (Step 1-SR)" "Step 1-SR" "$FRC"
assert_grep "[S66-C] boots the real server (uvicorn/etc.)" "uvicorn" "$FRC"
assert_grep "[S66-C] no-HTTP-server library is BLOCKED" "no HTTP server entry" "$FRC"
assert_grep "[S66-C] allowed-tools include the server-boot binaries" "^allowed-tools:.*uvicorn" "$FRC"

# ---------------------------------------------------------------------------
echo "== [S66-D] docs =="

assert_grep "[S66-D] FRONTEND-TESTING.md documents server-rendered support" "server-rendered" "$REPO_ROOT/docs/FRONTEND-TESTING.md"

# ---------------------------------------------------------------------------
echo "== [S66-Z] harness self-audit =="

SELF="$REPO_ROOT/tests/integration/sprint-66.sh"
if head -1 "$SELF" | grep -q '^#!/bin/bash'; then pass "[S66-Z] shebang #!/bin/bash"; else fail "[S66-Z] shebang #!/bin/bash"; fi
for sec in S66-A S66-B S66-C S66-D S66-Z; do
  if grep -q "echo \"== \[$sec\]" "$SELF"; then pass "[S66-Z] [$sec] section header present"; else fail "[S66-Z] [$sec] section header present"; fi
done

echo
echo "RESULTS: $PASS passed, $FAIL failed"
if (( FAIL > 0 )); then
  for f in "${FAILS[@]}"; do echo "  - $f"; done
  exit 1
fi
exit 0
