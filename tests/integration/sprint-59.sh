#!/bin/bash
# Sprint 59 integration harness — make the front↔back integration gate
# STACK-AGNOSTIC: the Sprint-58 detector + verifier were JS/TS-only, so a
# Python/FastAPI (or Go/.NET) backend behind a UI read as no-app/single-tier and
# the gate stayed dormant (the live-Clera blind spot). Now the back-end is
# detected manifest-first across Node/Python/Go/.NET/Java with per-language route
# patterns, and the front-end is framework-optional.
#
# Sections:
#   [S59-A] integration-wiring-check.sh stack-agnostic detector (+ runtime probes)
#   [S59-B] integration-verifier skill boots any stack (+ VF_BACKEND_CMD override)
#   [S59-C] phase-runner stack-agnostic note
#   [S59-D] docs (Supported stacks)
#   [S59-Z] harness self-audit

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
DOC="$REPO_ROOT/docs/INTEGRATION-TESTING.md"

# ---------------------------------------------------------------------------
echo "== [S59-A] stack-agnostic detector =="

assert_grep "[S59-A] detector documents stack-agnostic" "Stack-agnostic|stack-agnostic|manifest-first" "$GATE"
assert_grep "[S59-A] detector knows Python manifests" "pyproject.toml|requirements.txt" "$GATE"
assert_grep "[S59-A] detector knows Go/.NET manifests" "go\.mod|csproj" "$GATE"
if bash -n "$GATE" 2>/dev/null; then pass "[S59-A] detector is valid bash"; else fail "[S59-A] detector is valid bash"; fi

st() { bash "$GATE" "$1" 2>/dev/null | sed -n 's/.*"status":"\([a-z-]*\)".*/\1/p'; }
probe() { local label="$1" want="$2" dir="$3"; local got; got="$(st "$dir")"; [[ "$got" == "$want" ]] && pass "$label" || fail "$label (want '$want' got '$got')"; rm -rf "$dir"; }

mkfe() {  # $1=root ; $2=App body — a vite web app under apps/web (the JS UI)
  mkdir -p "$1/apps/web/src"
  echo '{"dependencies":{"vite":"5"}}' > "$1/apps/web/package.json"
  touch "$1/apps/web/index.html"
  printf '%s' "$2" > "$1/apps/web/src/App.tsx"
}

# --- JS regression (Sprint 58 must still hold) ---
T="$(mktemp -d)"; probe "[S59-A] JS empty → no-app" "no-app" "$T"
T="$(mktemp -d)"; mkfe "$T" 'const f=()=>fetch("/api/x");'; mkdir -p "$T/apps/api/src"; echo '{"dependencies":{"express":"4"}}' > "$T/apps/api/package.json"; printf 'app.get("/api/x",h);' > "$T/apps/api/src/r.ts"; probe "[S59-A] JS UI fetch + express routes → wired" "wired" "$T"
T="$(mktemp -d)"; mkfe "$T" 'import axios from "axios"; axios.get("/api/x");'; probe "[S59-A] axios .get in UI is not a server route → unwired" "unwired" "$T"

# --- Python ---
T="$(mktemp -d)"; mkfe "$T" 'const f=()=>fetch("/api/dash");'; mkdir -p "$T/apps/api/src"; echo '[project]' > "$T/apps/api/pyproject.toml"; printf 'from fastapi import APIRouter\nrouter=APIRouter()\n@router.get("/api/dash")\ndef d(): return {}\n' > "$T/apps/api/src/main.py"; probe "[S59-A] Python FastAPI routes + UI fetch → wired" "wired" "$T"
T="$(mktemp -d)"; mkfe "$T" 'const f=()=>fetch("/api/dash");'; mkdir -p "$T/apps/api/src"; echo '[project]' > "$T/apps/api/pyproject.toml"; printf 'def add(a,b): return a+b\n' > "$T/apps/api/src/lib.py"; probe "[S59-A] Python backend, UI fetch, no routes → unwired" "unwired" "$T"
T="$(mktemp -d)"; mkdir -p "$T/src/clera"; echo '[project]' > "$T/pyproject.toml"; printf 'def match(): pass\n' > "$T/src/clera/engine.py"; probe "[S59-A] Python backend-only, no UI → single-tier (the Clera shape)" "single-tier" "$T"

# --- Go ---
T="$(mktemp -d)"; mkfe "$T" 'const f=()=>fetch("/api/x");'; mkdir -p "$T/apps/api"; echo 'module x' > "$T/apps/api/go.mod"; printf 'package main\nfunc main(){ http.HandleFunc("/api/x", h); http.ListenAndServe(":8080", nil) }\n' > "$T/apps/api/main.go"; probe "[S59-A] Go http routes + UI fetch → wired" "wired" "$T"

# --- .NET ---
T="$(mktemp -d)"; mkfe "$T" 'const f=()=>fetch("/api/x");'; mkdir -p "$T/apps/api"; echo '<Project/>' > "$T/apps/api/Api.csproj"; printf 'var app=WebApplication.Create();\napp.MapGet("/api/x", () => "ok");\n' > "$T/apps/api/Program.cs"; probe "[S59-A] .NET MapGet + UI fetch → wired" "wired" "$T"

# --- framework-less front-end ---
T="$(mktemp -d)"; mkdir -p "$T/app"; echo '[project]' > "$T/pyproject.toml"; printf 'from fastapi import FastAPI\napp=FastAPI()\n@app.get("/api/x")\ndef x(): return {}\n' > "$T/app/main.py"; printf '<html><script>fetch("/api/x")</script></html>' > "$T/index.html"; probe "[S59-A] framework-less index.html + fetch + Python routes → wired" "wired" "$T"

# ---------------------------------------------------------------------------
echo "== [S59-B] integration-verifier boots any stack =="

assert_grep "[S59-B] skill description says stack-agnostic" "[Ss]tack-agnostic" "$SKILL"
assert_grep "[S59-B] Step 1 detects the stack manifest-first" "manifest-first" "$SKILL"
assert_grep "[S59-B] Python boot (uvicorn) named" "uvicorn" "$SKILL"
assert_grep "[S59-B] Go boot (go run) named" "go run" "$SKILL"
assert_grep "[S59-B] .NET boot (dotnet run) named" "dotnet run" "$SKILL"
assert_grep "[S59-B] VF_BACKEND_CMD override documented" "VF_BACKEND_CMD" "$SKILL"
assert_grep "[S59-B] no-HTTP-server library (Clera shape) → BLOCKED" "no HTTP server at all|library .the Clera shape" "$SKILL"
assert_grep "[S59-B] allowed-tools include python + uvicorn + go + dotnet" "Bash\(python \*\).*Bash\(uvicorn \*\)" "$SKILL"

# ---------------------------------------------------------------------------
echo "== [S59-C] phase-runner stack-agnostic note =="

assert_grep "[S59-C] phase-runner notes the detector is stack-agnostic" "stack-agnostic.*Sprint 59|recognises Node, Python, Go" "$RUNNER"
assert_grep "[S59-C] names a non-JS backend example" "Python/FastAPI|Python.FastAPI or Go" "$RUNNER"

# ---------------------------------------------------------------------------
echo "== [S59-D] docs — supported stacks =="

assert_grep "[S59-D] doc has a Supported stacks section" "Supported stacks" "$DOC"
assert_grep "[S59-D] doc lists Python/Go/.NET rows" "pyproject.toml" "$DOC"
assert_grep "[S59-D] doc documents VF_BACKEND_CMD override" "VF_BACKEND_CMD" "$DOC"
assert_grep "[S59-D] doc names the Clera-style Python case" "Clera" "$DOC"
assert_grep "[S59-D] doc notes server-rendered apps have no decoupled wire" "server-rendered" "$DOC"

# ---------------------------------------------------------------------------
echo "== [S59-Z] harness self-audit =="
SELF="$REPO_ROOT/tests/integration/sprint-59.sh"
assert_grep "[S59-Z] sprint-59.sh runs under set -uo pipefail" '^set -uo pipefail$' "$SELF"
assert_grep "[S59-Z] covers [S59-A]" '\[S59-A\]' "$SELF"
assert_grep "[S59-Z] covers [S59-B]" '\[S59-B\]' "$SELF"
assert_grep "[S59-Z] covers [S59-C]" '\[S59-C\]' "$SELF"
assert_grep "[S59-Z] covers [S59-D]" '\[S59-D\]' "$SELF"

# ---------------------------------------------------------------------------
echo ""
echo "RESULTS: $PASS passed, $FAIL failed"
if (( FAIL > 0 )); then
  printf '  - %s\n' "${FAILS[@]}"
  exit 1
fi
exit 0
