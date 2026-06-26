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
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_lib.sh
source "$SCRIPT_DIR/_lib.sh"
# _lib.sh enables `set -e`; this reader uses non-zero grep/find as conditionals,
# so restore errexit-off (keep -u + pipefail).
set +e

ROOT="${1:-.}"
cd "$ROOT" 2>/dev/null || { printf '{"status":"no-ui"}\n'; exit 0; }

emit() { printf '{"status":"%s"%s}\n' "$1" "${2:+,\"detail\":\"$2\"}"; exit 0; }

# 1) Is there a web UI at all? Sprint 66: stack-agnostic (JS SPA / server-rendered
#    / static), not JS-framework-only.
UI_KIND="$(vf_web_ui_kind . 2>/dev/null || echo none)"
[ "$UI_KIND" = "none" ] && emit "no-ui"

# 1b) Server-rendered / static UI (FastAPI/Flask/Django/Rails/Razor templates or a
#     served static SPA): the "skinless" smell is class= markup with no stylesheet/
#     style/token anywhere. Scan the HTML/template/static + HTML-emitting sources.
if [ "$UI_KIND" != "js" ]; then
  SR_FILES="$(find . -maxdepth 6 \
      \( -path '*/templates/*' -o -path '*/static/*' -o -name '*.html' -o -name '*.j2' \
         -o -name '*.jinja' -o -name '*.jinja2' -o -name '*.cshtml' -o -name '*.razor' -o -name '*.erb' \) \
      -type f 2>/dev/null | grep -vE 'node_modules|/\.git/|/\.venv/|site-packages|/\.vibeflow/|/design/|mockups|/docs/' | head -200)"
  [ -n "$SR_FILES" ] || emit "styled"   # HTML emitted purely in code → don't guess skinless
  # uses class= markup?
  echo "$SR_FILES" | tr '\n' '\0' | xargs -0 grep -lqE 'class=' 2>/dev/null || emit "styled"
  sr_styled=0
  # a stylesheet served / linked, a <style> block, inline style=, tailwind cdn, or CSS custom props
  find . -maxdepth 6 -path '*/static/*' -name '*.css' 2>/dev/null | grep -qvE 'site-packages|node_modules' && sr_styled=1
  echo "$SR_FILES" | tr '\n' '\0' | xargs -0 grep -lqE "<link[^>]+stylesheet|href=['\"][^'\"]+\.css|<style|style=|tailwind|var\(--|class=['\"][^'\"]*\b(bg-|text-|flex|grid|p-[0-9]|m-[0-9])" 2>/dev/null && sr_styled=1
  # HTML built in code (e.g. FastAPI HTMLResponse) with an embedded <style>/stylesheet
  grep -rlqE "<style|stylesheet|\.css" --include='*.py' . 2>/dev/null | grep -vqE 'site-packages|/\.venv/' && sr_styled=1
  [ "$sr_styled" = 1 ] && emit "styled"
  emit "skinless" "server-rendered UI uses class= markup but no stylesheet/style/tokens are applied — design specified but never implemented"
fi

# --- JS SPA path (unchanged) ---
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
