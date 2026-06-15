#!/usr/bin/env bash
# integration-wiring-check.sh (Sprint 58; stack-agnostic since Sprint 59) —
# READ-ONLY: in a full-stack repo, is the front-end actually wired to a real
# back-end, or do its links have "no behind"? A UI that calls fetch('/api/...')
# over an endpoint that no server implements (or is hard-bound to mock fixtures)
# renders and unit-tests fine while never talking to a real backend — the gap
# that lets a cycle ship "mock front-ends over a *claimed* backend".
#
# Stack-agnostic (Sprint 59): the back-end is detected manifest-first across
# Python (pyproject.toml/requirements.txt/setup.py), Go (go.mod), .NET
# (*.csproj/*.sln), Java (pom.xml/build.gradle), Rust (Cargo.toml) and Node
# (package.json with a server dep / Next API routes / a raw http server), with
# per-language route-handler patterns. The front-end is a client-rendered web UI
# that makes server calls — framework-optional (a plain index.html + fetch counts;
# pure static design mockups, which make no calls, do not). Front-end vs back-end
# source dirs are kept separate so an axios `.get(` in the UI is not mistaken for
# a server route, and each language's route patterns only run over its own dirs.
#
# Output: one JSON line on stdout —
#   {"status": "wired" | "unwired" | "single-tier" | "no-app", "detail"?: "..."}
#     wired       — front-end server calls AND a backend that serves routes.
#     unwired     — front-end server calls but NO backend serving them (dangling
#                   endpoints / mock-only) — the "links have no behind" case.
#     single-tier — only one tier, or two tiers that don't talk → integration N/A
#                   (the carve-out: a front-end-only or back-end-only increment).
#     no-app      — neither tier detected; fail-safe.
# Read-only, surface-only. Fail-safe: any error ⇒ {"status":"no-app"}.

set -uo pipefail

ROOT="${1:-.}"
cd "$ROOT" 2>/dev/null || { printf '{"status":"no-app"}\n'; exit 0; }

emit() { printf '{"status":"%s"%s}\n' "$1" "${2:+,\"detail\":\"$2\"}"; exit 0; }

FE_DEP='"(vite|next|react-scripts|@remix-run/|astro|@vitejs/|vue|svelte)"'
JS_BE_DEP='"(express|fastify|koa|@hapi/|@nestjs/|hono|@trpc/server|apollo-server)"'

# narrowest plausible source dir under a project root (keeps the route scan off
# a sibling front-end and out of vendored trees in the common layouts).
src_dir() {
  local d="$1" s
  for s in "$d/src" "$d/app" "$d/internal" "$d/cmd" "$d/Controllers"; do
    [ -d "$s" ] && { printf '%s' "$s"; return; }
  done
  printf '%s' "$d"
}

# --- 1) back-end project roots (manifest-first, multi-stack) ---
BE_SCAN=(); BE_LANG=(); JS_BE_DIRS=()
add_be() { BE_SCAN+=("$(src_dir "$1")"); BE_LANG+=("$2"); }

for pkg in package.json apps/*/package.json packages/*/package.json services/*/package.json; do
  [ -e "$pkg" ] || continue
  grep -qE "$JS_BE_DEP" "$pkg" 2>/dev/null && { d="$(dirname "$pkg")"; add_be "$d" js; JS_BE_DIRS+=("$(src_dir "$d")"); }
done
for man in pyproject.toml requirements.txt setup.py \
           apps/*/pyproject.toml apps/*/requirements.txt apps/*/setup.py \
           services/*/pyproject.toml services/*/requirements.txt \
           */pyproject.toml */requirements.txt; do
  [ -e "$man" ] && add_be "$(dirname "$man")" py
done
for man in go.mod apps/*/go.mod services/*/go.mod */go.mod; do
  [ -e "$man" ] && add_be "$(dirname "$man")" go
done
for man in *.csproj */*.csproj apps/*/*.csproj services/*/*.csproj *.sln */*.sln; do
  [ -e "$man" ] && add_be "$(dirname "$man")" dotnet
done
for man in pom.xml build.gradle build.gradle.kts \
           apps/*/pom.xml services/*/pom.xml */pom.xml */build.gradle */build.gradle.kts; do
  [ -e "$man" ] && add_be "$(dirname "$man")" java
done
for man in Cargo.toml apps/*/Cargo.toml services/*/Cargo.toml */Cargo.toml; do
  [ -e "$man" ] && add_be "$(dirname "$man")" rust
done

# Next.js API routes are a JS back-end surface even without a server dep.
NEXT_API=0
for d in pages/api app/api src/pages/api src/app/api apps/*/pages/api apps/*/app/api \
         apps/*/src/pages/api apps/*/src/app/api; do
  [ -d "$d" ] && NEXT_API=1
done

# JS raw server with no server dep (http.createServer) — keep S58 parity.
if [ "${#JS_BE_DIRS[@]}" -eq 0 ]; then
  for d in src apps/*/src services/*/src server/src api/src; do
    [ -d "$d" ] || continue
    grep -rlqE 'http\.createServer|https\.createServer|Bun\.serve|Deno\.serve|new Hono\(|express\(\)|fastify\(' \
      "$d" 2>/dev/null && { BE_SCAN+=("$d"); BE_LANG+=(js); JS_BE_DIRS+=("$d"); }
  done
fi

has_backend=0
{ [ "${#BE_SCAN[@]}" -gt 0 ] || [ "$NEXT_API" = 1 ]; } && has_backend=1

# --- 2) does the back-end actually serve routes? (per-language, scoped to BE dirs) ---
be_routes=0
[ "$NEXT_API" = 1 ] && be_routes=1
i=0
while [ "$i" -lt "${#BE_SCAN[@]}" ]; do
  d="${BE_SCAN[$i]}"; lang="${BE_LANG[$i]}"; i=$((i + 1))
  [ "$be_routes" = 1 ] && break
  case "$lang" in
    js)     pat='\.(get|post|put|patch|delete)\(|\.route\(|@(Get|Post|Put|Patch|Delete)\(|createServer|addRoute|app\.use\(' ;;
    py)     pat='@(app|router|blueprint)\.(get|post|put|patch|delete|api_route|route)\(|APIRouter\(|add_api_route|include_router\(|@app\.route\(|urlpatterns' ;;
    go)     pat='http\.HandleFunc|http\.Handle\(|ListenAndServe|\.(GET|POST|PUT|PATCH|DELETE)\(|mux\.Handle' ;;
    dotnet) pat='\.Map(Get|Post|Put|Patch|Delete)\(|MapControllers|\[Http(Get|Post|Put|Patch|Delete)\]|\[Route\(|ControllerBase' ;;
    java)   pat='@(Get|Post|Put|Patch|Delete)Mapping|@RequestMapping|@RestController' ;;
    rust)   pat='HttpServer::new|web::(get|post|resource|scope)|axum::Router|Router::new|\.route\(' ;;
    *)      pat='createServer' ;;
  esac
  grep -rlqE "$pat" "$d" 2>/dev/null && be_routes=1
done

# --- 3) front-end: a client-rendered web UI (framework or framework-less) ---
FE_DIRS=()
for pkg in package.json apps/*/package.json packages/*/package.json; do
  [ -e "$pkg" ] || continue
  grep -qE "$FE_DEP" "$pkg" 2>/dev/null && FE_DIRS+=("$(src_dir "$(dirname "$pkg")")")
done

# framework-less: an index.html outside design mockups / vendored / artifact trees.
FE_HTML_DIRS=()
while IFS= read -r h; do
  case "$h" in *node_modules*|*/.git/*|*/.venv/*|*/venv/*|*/.vibeflow/*|*/dist/*|*/build/*|*/coverage/*|*/htmlcov/*|*/design/*|*design/*|*mockups*) continue ;; esac
  FE_HTML_DIRS+=("$(dirname "$h")")
done < <(find . -maxdepth 4 -name '*.html' \
           -not -path '*/node_modules/*' -not -path '*/.git/*' -not -path '*/.venv/*' \
           -not -path '*/venv/*' -not -path '*/.vibeflow/*' -not -path '*/dist/*' \
           -not -path '*/build/*' -not -path '*/coverage/*' -not -path '*/htmlcov/*' 2>/dev/null)

has_web_entry=0
for f in next.config.* apps/*/next.config.*; do [ -e "$f" ] && has_web_entry=1; done
[ "${#FE_HTML_DIRS[@]}" -gt 0 ] && has_web_entry=1

has_frontend=0
{ { [ "${#FE_DIRS[@]}" -gt 0 ] && [ "$has_web_entry" = 1 ]; } || [ "${#FE_HTML_DIRS[@]}" -gt 0 ]; } && has_frontend=1

# --- 4) does the front-end make server calls? (scoped to FE areas) ---
fe_calls=0
SCANSET=()
for d in "${FE_DIRS[@]:-}" "${FE_HTML_DIRS[@]:-}"; do [ -n "$d" ] && [ -e "$d" ] && SCANSET+=("$d"); done
if [ "${#SCANSET[@]}" -gt 0 ]; then
  grep -rlqE "fetch\(|axios|useSWR|useQuery|useMutation|['\"]/api/|apiClient|import\.meta\.env\.VITE_API|NEXT_PUBLIC_API|XMLHttpRequest" \
    "${SCANSET[@]}" 2>/dev/null && fe_calls=1
fi

# --- classify ---
[ "$has_frontend" = 0 ] && [ "$has_backend" = 0 ] && emit "no-app"
[ "$has_frontend" = 0 ] && emit "single-tier" "back-end-only increment — no UI to integrate"
[ "$fe_calls" = 0 ] && emit "single-tier" "front-end makes no server calls — nothing to integrate"
[ "$has_backend" = 1 ] && [ "$be_routes" = 1 ] && emit "wired"
emit "unwired" "the UI calls a server API but no backend serving those routes was found — its links have no backend behind them"
