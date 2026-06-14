#!/usr/bin/env bash
# integration-wiring-check.sh (Sprint 58) — READ-ONLY: in a full-stack repo, is
# the front-end actually wired to a real back-end, or do its links have "no
# behind"? A UI that calls fetch('/api/...') over an endpoint that no server
# implements (or is hard-bound to mock fixtures with no real client path)
# renders and unit-tests fine while never talking to a real backend — the gap
# that lets a cycle ship "mock front-ends over a *claimed* backend".
#
# This is the integration counterpart to ui-styling-check.sh's "skinless" smell.
# It answers only the cheap, static question "is there a server serving routes
# behind the UI's calls?"; the per-endpoint runtime proof (boot the backend +
# seed test data + hit each endpoint + 404 detection) is the integration-verifier
# skill in TESTING. Heuristic by design — front-end and back-end source dirs are
# separated by their nearest package.json so an axios `.get(` in the UI is not
# mistaken for a server route. A standalone front-end that talks to a genuinely
# external API will read as "unwired"; that is the intended bias (surface it,
# don't silently pass) and the operator can skip the gate for a single-tier increment.
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
BE_DEP='"(express|fastify|koa|@hapi/|@nestjs/|hono|@trpc/server|apollo-server)"'

# 1) Split source dirs into front-end vs back-end by their nearest package.json,
#    so an axios `.get(` in the UI isn't read as a server route, and vice versa.
FRONTEND_DIRS=()
BACKEND_DIRS=()
for pkg in package.json apps/*/package.json packages/*/package.json services/*/package.json; do
  [ -e "$pkg" ] || continue
  dir="$(dirname "$pkg")"
  scan="$dir/src"; [ -d "$scan" ] || scan="$dir"
  grep -qE "$FE_DEP" "$pkg" 2>/dev/null && FRONTEND_DIRS+=("$scan")
  grep -qE "$BE_DEP" "$pkg" 2>/dev/null && BACKEND_DIRS+=("$scan")
done

# Next.js API routes are a back-end surface even without a server framework dep.
NEXT_API=0
for d in pages/api app/api src/pages/api src/app/api apps/*/pages/api apps/*/app/api \
         apps/*/src/pages/api apps/*/src/app/api; do
  [ -d "$d" ] && NEXT_API=1
done

# 2) A front-end needs a web entry too (not just a dep) — mirrors ui-styling-check.
has_frontend=0
if [ "${#FRONTEND_DIRS[@]}" -gt 0 ]; then
  for f in index.html apps/*/index.html */index.html next.config.* apps/*/next.config.*; do
    [ -e "$f" ] && has_frontend=1
  done
fi

# A raw server (no framework dep) still counts as a back-end.
RAW_SERVER=0
if [ "${#BACKEND_DIRS[@]}" -eq 0 ]; then
  for d in src apps/*/src services/*/src server/src api/src; do
    [ -d "$d" ] || continue
    grep -rlqE 'http\.createServer|https\.createServer|Bun\.serve|Deno\.serve|new Hono\(|express\(\)|fastify\(' \
      "$d" 2>/dev/null && { BACKEND_DIRS+=("$d"); RAW_SERVER=1; }
  done
fi

has_backend=0
{ [ "${#BACKEND_DIRS[@]}" -gt 0 ] || [ "$NEXT_API" = 1 ]; } && has_backend=1

# 3) Does the front-end make server calls?
fe_calls=0
if [ "${#FRONTEND_DIRS[@]}" -gt 0 ]; then
  grep -rlqE "fetch\(|axios|useSWR|useQuery|useMutation|['\"]/api/|apiClient|import\.meta\.env\.VITE_API|NEXT_PUBLIC_API" \
    "${FRONTEND_DIRS[@]}" 2>/dev/null && fe_calls=1
fi

# 4) Does the back-end actually serve routes? (scoped to back-end dirs only)
be_routes=0
[ "$NEXT_API" = 1 ] && be_routes=1
if [ "$be_routes" = 0 ] && [ "${#BACKEND_DIRS[@]}" -gt 0 ]; then
  grep -rlqE '\.(get|post|put|patch|delete)\(|\.route\(|@(Get|Post|Put|Patch|Delete)\(|createServer|addRoute|app\.use\(' \
    "${BACKEND_DIRS[@]}" 2>/dev/null && be_routes=1
fi

# --- classify ---
[ "$has_frontend" = 0 ] && [ "$has_backend" = 0 ] && emit "no-app"
[ "$has_frontend" = 0 ] && emit "single-tier" "back-end-only increment — no UI to integrate"
[ "$fe_calls" = 0 ] && emit "single-tier" "front-end makes no server calls — nothing to integrate"
[ "$has_backend" = 1 ] && [ "$be_routes" = 1 ] && emit "wired"
emit "unwired" "the UI calls a server API but no backend serving those routes was found — its links have no backend behind them"
