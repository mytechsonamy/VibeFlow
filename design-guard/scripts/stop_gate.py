#!/usr/bin/env python3
"""
design-guard :: stop_gate (Stop)

If UI files were touched this session (.design-guard/.ui-dirty exists),
refuse to let the turn end until the design-auditor agent has reviewed the
changes (exit 2 -> stderr is fed to the model as the reason).

Loop protection: when stop_hook_active is set (we already forced one review
round), clear the flag and allow stopping. No-op in uninitialized projects.
"""
import json
import os
import sys


def main() -> None:
    try:
        payload = json.load(sys.stdin)
    except Exception:
        sys.exit(0)

    project = os.environ.get("CLAUDE_PROJECT_DIR", os.getcwd())
    dg = os.path.join(project, ".design-guard")
    flag = os.path.join(dg, ".ui-dirty")

    if not os.path.exists(os.path.join(dg, "rules.json")):
        sys.exit(0)  # project not initialized
    if not os.path.exists(flag):
        sys.exit(0)  # no UI changes this session

    if payload.get("stop_hook_active"):
        try:
            os.remove(flag)
        except OSError:
            pass
        sys.exit(0)

    print(
        "UI files changed this session. Before finishing, run the "
        "design-auditor agent on the changed files, fix all BLOCKER "
        "findings, and report a short audit summary. Canonical terminology: "
        ".design-guard/glossary.md",
        file=sys.stderr,
    )
    sys.exit(2)


if __name__ == "__main__":
    main()
