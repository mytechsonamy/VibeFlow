#!/usr/bin/env bash
# ui-verification-debt.sh (Sprint 54) — READ-ONLY signal: does this repo have a
# web UI that has never been render-verified, or whose verification is stale?
#
# VibeFlow runs the front-end battery per-increment (when the *current* increment
# is UI-facing). But a UI built in an earlier cycle — or before the visual-testing
# tooling existed — can ship coverage-tested yet never rendered or compared to the
# design ("dark tunnel"), and then stay buried under later backend cycles. This
# reader surfaces that so phase-runner Step 0 + flow-status can flag it.
#
# Output: one JSON line on stdout — {"status": "no-ui" | "never" | "stale" | "verified", "detail"?: "..."}.
# Surface-only: it changes nothing. Fail-safe: any error ⇒ {"status":"no-ui"} (never noisy on a non-UI repo).

set -uo pipefail

ROOT="${1:-.}"
cd "$ROOT" 2>/dev/null || { printf '{"status":"no-ui"}\n'; exit 0; }

emit() { printf '{"status":"%s"%s}\n' "$1" "${2:+,\"detail\":\"$2\"}"; exit 0; }

# 1) A web UI = a package.json that pulls a web framework, AND a web entry point.
has_web_framework() {
  grep -rlqE '"(vite|next|react-scripts|@remix-run/|astro|@vitejs/)"' \
    package.json apps/*/package.json packages/*/package.json 2>/dev/null
}
has_web_entry() {
  # vite/CRA → index.html ; next → next.config.* ; either anywhere shallow.
  for f in index.html apps/*/index.html */index.html \
           next.config.* apps/*/next.config.*; do
    [ -e "$f" ] && return 0
  done
  return 1
}
has_web_framework && has_web_entry || emit "no-ui"

# 2) Never verified — no conformance report from frontend-render-check.
REPORT=".vibeflow/reports/frontend-conformance.md"
[ -f "$REPORT" ] || emit "never" "web UI present but never render-verified"

# 3) Stale — a UI source file changed after the last verification report.
#    Best-effort: scan the conventional UI source dirs for anything newer.
NEWER=""
for d in src apps/*/src packages/*/src; do
  [ -d "$d" ] || continue
  hit="$(find "$d" -type f \( -name '*.tsx' -o -name '*.jsx' -o -name '*.ts' \
        -o -name '*.js' -o -name '*.vue' -o -name '*.svelte' -o -name '*.css' \
        -o -name '*.scss' -o -name '*.html' \) -newer "$REPORT" 2>/dev/null | head -1)"
  [ -n "$hit" ] && { NEWER="$hit"; break; }
done
[ -n "$NEWER" ] && emit "stale" "UI changed since the last render-verification"

emit "verified"
