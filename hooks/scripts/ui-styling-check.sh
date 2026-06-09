#!/usr/bin/env bash
# ui-styling-check.sh (Sprint 55) — READ-ONLY: is the web UI "skinless"? Its
# components reference styling (className / class) but NO styling layer is
# actually applied — no stylesheet imported, no Tailwind, no CSS-in-JS, design
# tokens never consumed. That's a UI whose *structure* was built but whose
# *design was never implemented*: it renders as bare default HTML. This is a
# static, cheap signal meant to fire in DEVELOPMENT (when the UI is written),
# not only at the TESTING render-check.
#
# Output: one JSON line — {"status": "no-ui" | "styled" | "skinless", "detail"?: "..."}.
# Read-only, surface-only. Fail-safe: any error / no UI ⇒ {"status":"no-ui"}.

set -uo pipefail

ROOT="${1:-.}"
cd "$ROOT" 2>/dev/null || { printf '{"status":"no-ui"}\n'; exit 0; }

emit() { printf '{"status":"%s"%s}\n' "$1" "${2:+,\"detail\":\"$2\"}"; exit 0; }

# 1) A web UI = a web-framework dependency + a web entry (same gate as ui-verification-debt).
grep -rlqE '"(vite|next|react-scripts|@remix-run/|astro|@vitejs/)"' \
  package.json apps/*/package.json packages/*/package.json 2>/dev/null || emit "no-ui"
web_entry=0
for f in index.html apps/*/index.html */index.html next.config.* apps/*/next.config.*; do
  [ -e "$f" ] && web_entry=1
done
[ "$web_entry" = 1 ] || emit "no-ui"

# 2) The UI source dirs.
SRCDIRS=()
for d in src apps/*/src; do [ -d "$d" ] && SRCDIRS+=("$d"); done
[ "${#SRCDIRS[@]}" -gt 0 ] || emit "no-ui"

# 3) Does the UI even use styling hooks (className / class:)? If it styles purely
#    inline (style={{…}}), that's not our "skinless" smell — leave it alone.
grep -rlqE 'className[=:]|class:|class=' "${SRCDIRS[@]}" 2>/dev/null || emit "styled"

# 4) Is a real styling layer present AND applied? Any ONE of these ⇒ styled.
styled=0
# (a) a stylesheet imported from code
grep -rqE "import[^;]*['\"][^'\"]+\.(css|scss|sass|less)['\"]" "${SRCDIRS[@]}" 2>/dev/null && styled=1
# (b) Tailwind configured (loop, not `ls`, so a non-matching glob doesn't lie)
for f in tailwind.config.* apps/*/tailwind.config.* postcss.config.*; do
  [ -e "$f" ] && styled=1
done
# (c) CSS-in-JS (styled-components / emotion / vanilla-extract)
grep -rqE "from ['\"]@?(styled-components|emotion|@emotion|@vanilla-extract)" "${SRCDIRS[@]}" 2>/dev/null && styled=1
# (d) a stylesheet linked in the HTML entry
grep -rqE "<link[^>]+stylesheet|href=['\"][^'\"]+\.css" index.html apps/*/index.html 2>/dev/null && styled=1
# (e) design tokens consumed in code (CSS custom props / a tokens import)
grep -rqE "design-tokens|var\(--|tokens['\"]?\s*[:=]|theme\(" "${SRCDIRS[@]}" 2>/dev/null && styled=1

[ "$styled" = 1 ] && emit "styled"
emit "skinless" "UI components use className but no stylesheet/tokens are applied — the design was specified but never implemented"
