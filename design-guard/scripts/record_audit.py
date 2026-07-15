#!/usr/bin/env python3
"""
design-guard :: record_audit (VibeFlow bridge)

Records a design-auditor verdict into VibeFlow's consensus/history stream so
UI-quality outcomes show up in /vibeflow:flow-status alongside the SDLC state.

    record_audit.py <SHIPPABLE|FIXES_REQUIRED> \
        [--blockers N] [--majors N] [--minors N] [--scope TEXT]

It is a deliberate NO-OP (silent, exit 0) unless the project is ALSO a
VibeFlow project — i.e. `<project>/.vibeflow/state/consensus/` exists. That
keeps design-guard fully standalone: the bridge only fires where VibeFlow is
present, and neither plugin hard-depends on the other (VibeFlow's flow-status
simply reads the row if it's there, and collapses the line when it isn't).

The appended line matches the append-only history.jsonl shape used by the
consensus aggregator (a typed event row):

    {"recordedAt": "<utc>", "type": "design-guard-audit",
     "verdict": "SHIPPABLE"|"FIXES_REQUIRED",
     "blockers": N, "majors": N, "minors": N,
     "scope": "<text>", "source": "design-auditor"}
"""
import argparse
import datetime
import json
import os
import sys


def normalize_verdict(raw: str) -> str:
    v = (raw or "").strip().upper().replace(" ", "_").replace("-", "_")
    if v in ("SHIPPABLE", "SHIP"):
        return "SHIPPABLE"
    if v in ("FIXES_REQUIRED", "FIXESREQUIRED", "FIX_REQUIRED", "BLOCKED"):
        return "FIXES_REQUIRED"
    return ""


def main() -> None:
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument("verdict", help="SHIPPABLE or FIXES_REQUIRED (space form accepted)")
    ap.add_argument("--blockers", type=int, default=0)
    ap.add_argument("--majors", type=int, default=0)
    ap.add_argument("--minors", type=int, default=0)
    ap.add_argument("--scope", default="")
    args = ap.parse_args()

    verdict = normalize_verdict(args.verdict)
    if not verdict:
        print(
            "record_audit: verdict must be SHIPPABLE or FIXES_REQUIRED "
            f"(got {args.verdict!r})",
            file=sys.stderr,
        )
        sys.exit(1)

    project = os.environ.get("CLAUDE_PROJECT_DIR", os.getcwd())
    cons_dir = os.path.join(project, ".vibeflow", "state", "consensus")
    # No-op unless this is also a VibeFlow project — keeps design-guard
    # standalone-safe and side-effect-free elsewhere.
    if not os.path.isdir(cons_dir):
        sys.exit(0)

    row = {
        "recordedAt": datetime.datetime.now(datetime.timezone.utc)
        .strftime("%Y-%m-%dT%H:%M:%SZ"),
        "type": "design-guard-audit",
        "verdict": verdict,
        "blockers": max(0, args.blockers),
        "majors": max(0, args.majors),
        "minors": max(0, args.minors),
        "scope": args.scope,
        "source": "design-auditor",
    }
    line = json.dumps(row, ensure_ascii=False) + "\n"
    history = os.path.join(cons_dir, "history.jsonl")
    try:
        with open(history, "a", encoding="utf-8") as fh:
            fh.write(line)
    except OSError as exc:
        print(f"record_audit: could not write {history}: {exc}", file=sys.stderr)
        sys.exit(1)

    print(f"record_audit: recorded {verdict} → {history}")


if __name__ == "__main__":
    main()
