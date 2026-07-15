#!/usr/bin/env python3
"""
design-guard :: ui_lint (PostToolUse, matcher: Write|Edit)

Generic, config-driven UI lint. All project-specific knowledge lives in the
PROJECT, not in this plugin:

    <project>/.design-guard/rules.json    banned-term / pattern rules
    <project>/.design-guard/glossary.md   canonical terminology (agent reads it)

If the project has no .design-guard/rules.json, this hook is a no-op, so the
plugin is safe to enable globally. Findings are fed back to the model via
additionalContext (PostToolUse cannot undo the write; the goal is immediate
correction). Any UI-file touch also drops a .ui-dirty flag consumed by the
Stop gate.

rules.json schema:
{
  "ui_extensions": [".html", ".tsx", ...],       // optional, defaults below
  "ui_path_hints": ["templates/", "ui/", ...],   // optional, defaults below
  "rules": [
    { "pattern": "<regex>", "message": "<why + canonical fix>",
      "flags": "i" }                             // flags optional: i = ignorecase
  ]
}
"""
import json
import os
import re
import sys

DEFAULT_EXT = (".html", ".htm", ".jinja", ".jinja2", ".j2", ".tsx", ".jsx",
               ".vue", ".svelte", ".css", ".scss", ".cshtml", ".razor")
DEFAULT_HINTS = ("templates/", "components/", "pages/", "views/", "static/",
                 "i18n/", "locales/", "frontend/", "ui/", "wwwroot/")


def project_dir() -> str:
    return os.environ.get("CLAUDE_PROJECT_DIR", os.getcwd())


def load_config():
    path = os.path.join(project_dir(), ".design-guard", "rules.json")
    try:
        with open(path, encoding="utf-8") as fh:
            return json.load(fh)
    except (OSError, json.JSONDecodeError):
        return None


def main() -> None:
    try:
        payload = json.load(sys.stdin)
    except Exception:
        sys.exit(0)

    cfg = load_config()
    if cfg is None:
        sys.exit(0)  # project not initialized -> plugin stays silent

    tool_input = payload.get("tool_input") or {}
    file_path = tool_input.get("file_path") or ""
    if not file_path:
        sys.exit(0)

    exts = tuple(cfg.get("ui_extensions") or DEFAULT_EXT)
    hints = tuple(cfg.get("ui_path_hints") or DEFAULT_HINTS)
    p = file_path.replace("\\", "/").lower()
    if not (p.endswith(exts) or any(h in p for h in hints)):
        sys.exit(0)

    # mark session as UI-dirty for the Stop gate
    dg_dir = os.path.join(project_dir(), ".design-guard")
    os.makedirs(dg_dir, exist_ok=True)
    open(os.path.join(dg_dir, ".ui-dirty"), "a").close()

    compiled = []
    for rule in cfg.get("rules", []):
        try:
            flags = re.IGNORECASE if "i" in rule.get("flags", "") else 0
            compiled.append((re.compile(rule["pattern"], flags),
                             rule.get("message", rule["pattern"])))
        except (re.error, KeyError):
            continue  # bad rule never breaks the build

    if not compiled:
        sys.exit(0)

    try:
        with open(file_path, encoding="utf-8", errors="ignore") as fh:
            lines = fh.readlines()
    except OSError:
        sys.exit(0)

    findings = []
    for lineno, line in enumerate(lines, 1):
        for rx, msg in compiled:
            if rx.search(line):
                findings.append(
                    f"{os.path.basename(file_path)}:{lineno} — {msg}")

    if findings:
        ctx = (
            "DESIGN-GUARD LINT — the file just written violates the project's "
            "terminology/localization rules. Fix before continuing:\n- "
            + "\n- ".join(findings[:20])
            + "\nCanonical source: .design-guard/glossary.md"
        )
        print(json.dumps({
            "hookSpecificOutput": {
                "hookEventName": "PostToolUse",
                "additionalContext": ctx,
            }
        }))
    sys.exit(0)


if __name__ == "__main__":
    main()
