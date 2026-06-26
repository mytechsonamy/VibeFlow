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
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_lib.sh
source "$SCRIPT_DIR/_lib.sh"
# _lib.sh enables `set -e`; this reader uses non-zero grep/find as conditionals
# (and bare command substitutions), so restore errexit-off (keep -u + pipefail).
set +e

ROOT="${1:-.}"
cd "$ROOT" 2>/dev/null || { printf '{"status":"no-ui"}\n'; exit 0; }

emit() { printf '{"status":"%s"%s}\n' "$1" "${2:+,\"detail\":\"$2\"}"; exit 0; }

# 1) Is there a web UI to render-verify? Sprint 66: stack-agnostic — JS SPA,
#    server-rendered (FastAPI/Flask/Django/Rails/Razor templates or a backend-
#    served static UI), or a plain static site all count. Only a repo with no web
#    UI at all is "no-ui". (Was JS-framework-only, which read Clera's FastAPI
#    HTML-response SPA as no-ui and silently skipped the whole visual battery.)
UI_KIND="$(vf_web_ui_kind . 2>/dev/null || echo none)"
[ "$UI_KIND" = "none" ] && emit "no-ui"

# 2) Never verified — no conformance report from frontend-render-check.
REPORT=".vibeflow/reports/frontend-conformance.md"
[ -f "$REPORT" ] || emit "never" "web UI present but never render-verified"

# 3) Stale — a UI source file changed after the last verification report.
#    Sprint 66: also scan server-rendered UI sources (the route handlers that
#    emit HTML + templates + served static) so a template/HTMLResponse edit marks
#    the conformance report stale, not just JS/TS edits.
NEWER=""
for d in src apps/*/src packages/*/src app templates static src/*/static src/*/templates; do
  [ -d "$d" ] || continue
  hit="$(find "$d" -type f \( -name '*.tsx' -o -name '*.jsx' -o -name '*.ts' \
        -o -name '*.js' -o -name '*.vue' -o -name '*.svelte' -o -name '*.css' \
        -o -name '*.scss' -o -name '*.html' -o -name '*.j2' -o -name '*.jinja' \
        -o -name '*.jinja2' -o -name '*.cshtml' -o -name '*.razor' -o -name '*.erb' \
        -o -name '*.py' \) -newer "$REPORT" 2>/dev/null \
        | grep -vE 'node_modules|/\.venv/|site-packages|/design/|mockups' | head -1)"
  [ -n "$hit" ] && { NEWER="$hit"; break; }
done
[ -n "$NEWER" ] && emit "stale" "UI changed since the last render-verification"

emit "verified"
