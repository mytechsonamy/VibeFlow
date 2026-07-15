# design-guard

**AI-governed UI quality gate for Claude Code.** Three enforcement layers,
one project-owned knowledge base:

| Layer | Mechanism | Guarantees |
|---|---|---|
| Prevent | `ui-quality-rules` skill | Claude writes UI against the project glossary from the start |
| Catch | `PostToolUse` lint hook | Deterministic regex scan of every edited UI file; violations injected back as context — the model can forget, the hook can't |
| Gate | `Stop` hook + `design-auditor` agent | Work cannot be declared done until an audit pass runs and BLOCKER findings are fixed |

All domain knowledge lives in the **project**, not the plugin:

```
<your-project>/.design-guard/
├── profile.md      # what the product is, who buys it, trust story
├── glossary.md     # canonical terminology (single source of truth)
├── rules.json      # deterministic lint rules (regex + message)
└── .ui-dirty       # runtime flag (gitignore this)
```

The plugin is inert in projects without `.design-guard/rules.json`, so it is
safe to enable globally.

## Plugin layout

```
design-guard/
├── .claude-plugin/plugin.json
├── agents/design-auditor.md          # generic auditor, reads project files
├── skills/
│   ├── design-guard-init/SKILL.md    # bootstrap: mines project docs → generates .design-guard/
│   └── ui-quality-rules/SKILL.md     # writing rules, glossary-driven
├── hooks/hooks.json                  # PostToolUse lint + Stop gate
├── scripts/{ui_lint.py, stop_gate.py}
└── templates/                        # profile / glossary / rules templates
```

## Install & try

```bash
# local development / trial
claude --plugin-dir /path/to/design-guard
```

Or add to a marketplace / VibeFlow's plugin set and enable per project.
Requires `python3` on PATH.

## First use in a project

```
Initialize design-guard for this project.
```

The `design-guard-init` skill reads the project's docs, PRDs, i18n
resources, and existing UI, then generates `profile.md`, `glossary.md`, and
`rules.json`. Review the generated glossary — it encodes your product
language, treat it like an ADR. Then run a baseline:

```
Run the design-auditor agent on all user-facing pages and write the
findings to docs/audit/ui-audit-baseline.md. Report only, don't fix.
```

## Maintenance contract

New term → glossary first, code second. Banned variant discovered →
rules.json in the same change. The glossary is a reviewed, versioned team
asset; the lint rules are derived from it.

## VibeFlow integration notes

- design-guard is a **risk-proportional quality gate**: the Stop hook plays
  the same role as VibeFlow's phase-boundary consensus, scoped to UI work.
- The `design-auditor` verdict line (SHIPPABLE / FIXES REQUIRED) is
  machine-greppable — it can feed VibeFlow's consensus/history stream so
  UI-quality outcomes appear in per-project observability alongside
  reviewer/challenger verdicts.
- `design-guard-init` is the pattern worth generalizing: *project docs →
  generated governance config*. The same bootstrap shape applies to other
  gates (API naming, log hygiene, accessibility).

## License

Apache-2.0.
