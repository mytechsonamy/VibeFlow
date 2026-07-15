---
name: design-guard-init
description: >
  Bootstrap design-guard for a project. Use when the user asks to "initialize
  design-guard", "set up the design guard", "generate the glossary", or when
  the design-auditor agent reports that .design-guard/ files are missing.
  Reads the project's own documentation (product docs, PRDs, README, i18n
  resources, UI code) and generates the three project files that drive the
  whole system: profile.md, glossary.md, and rules.json.
---

# design-guard init — bootstrap procedure

Goal: create `<project>/.design-guard/` with three files. Templates live in
`${CLAUDE_PLUGIN_ROOT}/templates/` — copy their structure, fill with THIS
project's content.

## Step 1 — Discover the product

Read, in priority order (skip what doesn't exist):
- `docs/` product bible, PRDs, SRS, vision docs
- `README.md`, marketing/pitch material
- i18n resource files (`i18n/`, `locales/`, `*.resx`, `*.json` bundles)
- main navigation / layout components (nav labels reveal the domain language)

Extract: product category, target buyer/user, shipped locales, core value
proposition, and the trust story (what failure would embarrass this product
most — that calibrates audit severity).

## Step 2 — Write `.design-guard/profile.md`

Use `templates/profile.template.md`. One page max. This is what the
design-auditor reads to calibrate severity.

## Step 3 — Write `.design-guard/glossary.md`

Use `templates/glossary.template.md`. Mine terminology from the docs and the
EXISTING UI (Grep for badge labels, nav items, status enums, report line
items). For every concept record: key, canonical term per locale, and
**banned variants actually found in the codebase** — those become lint rules.
Where the docs and the UI disagree, the docs win; flag the UI occurrences.
Include: status taxonomy, core domain concepts, user-visible report/line
labels, number+date format rules per locale, and the single standardized
footer/trust line.

## Step 4 — Write `.design-guard/rules.json`

Only deterministic, regex-catchable violations (banned variants, internal
jargon leaks, mixed-language markers, format-hint contradictions). Schema
and a worked example: `templates/rules.example.json`. Keep messages
actionable: "banned variant X → canonical Y". Set `ui_extensions` /
`ui_path_hints` to match this project's stack. Validate the JSON parses.

## Step 5 — Wire up and verify

- Add `.design-guard/.ui-dirty` to `.gitignore`.
- Commit `.design-guard/` (profile, glossary, rules are team assets).
- Sanity test: temporarily write a banned term into a scratch UI file and
  confirm the PostToolUse lint reports it; then remove the scratch file.
- Tell the user how to trigger a full baseline audit with the
  design-auditor agent.

## Maintenance rule (tell the user)

New term needed → add to glossary.md FIRST, then use it in code. If it has
banned variants, add a rule to rules.json in the same change.
