---
name: product-bible
description: The Product Bible — the curated, living document corpus a project accumulates across its whole lifecycle (business/GTM → product → engineering): vision, competitive intelligence, personas, glossary, domain model, UX principles, API standards, Rule DSL, AI strategy, ADRs, PRDs/SRSs, test strategy, roadmap, sales arguments, RFP templates, demo scenarios, pilot guides, … This skill shows the bible's current state (which canonical docs exist vs are missing/owed, by category, referencing the VibeFlow outputs you already produce in place — never duplicated), and scaffolds the docs/product-bible/ structure with templated stubs for the missing ones. Read-mostly — its only writes are the bible scaffold under docs/product-bible/ (operator-initiated). Use to see + grow the product bible at any point in the project. (Sprint 68 foundation; intake/ingestion, living-doc growth, and end-of-project assembly land in follow-on sprints.)
disable-model-invocation: false
allowed-tools: Read Write AskUserQuestion Bash(bash *bible-status.sh*) Bash(jq *) Bash(mkdir *) Bash(ls *)
---

# Product Bible

A project isn't just code — by the end you should hold a coherent **product bible**:
the vision, the competitive landscape, the personas, the domain model + glossary,
the UX/API/Rule standards, the AI strategy, the ADRs, the PRDs/SRSs, the test
strategy, the roadmap, and the GTM assets (sales arguments, RFP templates, demo
scenarios, pilot guides). Some are written once; many are **living** — grown each
phase/cycle. This skill is how you **see** that corpus and **scaffold** it.

This is the **foundation** (Sprint 68): the taxonomy + status + structure.
Ingesting the input documents you bring in, growing the living docs across phases,
and assembling the final bible are follow-on sprints — this skill names them as
the next steps.

## Step 1 — Read the current state

```bash
bash "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/bible-status.sh"
```

`bible-status.sh` (read-only) cross-references the taxonomy
(`hooks/scripts/bible-manifest.json`, or a project override at
`docs/product-bible/manifest.json`) against the repo and returns, per doc:
`{key, title, category, phase, lifecycle (living|static), source (bible|vibeflow),
status (present|missing), path}` + per-category totals. Docs VibeFlow already
produces (PRD, ADR, architecture, design-spec, test-strategy, scenario-set, rtm,
release-decision) are **referenced in place** (`source: vibeflow`) — the bible
never duplicates them; it points at the single source.

## Step 2 — Render the bible index

Render a per-category dashboard (business / product / engineering), present-vs-
missing, with each doc's lifecycle + where it lives:

```
Product Bible — <project>     present <P>/<N>

  business      <p>/<n>
    ✓ Vision                  (living)   docs/product-bible/business/vision.md
    ✗ Competitive Intelligence (living)  — owed
    …
  product       <p>/<n>
    ✓ PRD(s)                  (living, via prd-quality-analyzer)  docs/…requirements.md
    ✗ Glossary                (living)   — owed
    …
  engineering   <p>/<n>
    ✓ ADRs                    (living, via architecture-bootstrap) docs/adr/
    ✗ Domain Model            (living)   — owed
    …
```

Mark `source: vibeflow` docs with the skill that produces them so the operator
knows a "missing" one is produced by running that phase (not hand-authored).

## Step 3 — Scaffold the structure (operator choice)

Offer to scaffold `docs/product-bible/` — create the category dirs + a templated
stub for each **missing bible-native** doc (`source: bible`), and a top-level
`docs/product-bible/README.md` index. Do **not** scaffold `source: vibeflow`
docs (those are produced by their phase skills, referenced in place).

**Operator choice (mobile-friendly — see `docs/OPERATOR-CHOICES.md`).** Present
this with the `AskUserQuestion` tool:
- **Scaffold all missing bible-native docs (Recommended)** — create every owed
  `source: bible` stub + the README index.
- **Scaffold one category** — business / product / engineering.
- **Just show status** — write nothing.

Each scaffolded stub is a real template: a title, a one-line purpose, the
expected sections for that doc-type, a `> _Living document — grown each
phase/cycle._` banner for `lifecycle: living`, and a `<!-- TODO -->` so it's
clearly owed. Never overwrite an existing file.

## Step 4 — Breadcrumb the next steps

End by naming what grows the bible from here (the follow-on sprints):
- **Intake** — review the input documents you brought into the project and file
  them into the bible (ingestion). Until that ships, drop them under the matching
  `docs/product-bible/<category>/` path by hand.
- **Living-doc growth** — glossary / domain-model / personas / ADRs / roadmap /
  API-standards / Rule-DSL grow each phase; phase-runner will wire this.
- **Assembly** — a final curated export at project end.

> ▶ Next: /vibeflow:phase-runner   (continue the SDLC; the bible grows as you go)

## Read-mostly

`product-bible` only writes the **scaffold** under `docs/product-bible/`
(operator-initiated, never overwriting) and its own index. It never edits a
`source: vibeflow` doc, source code, or config.

## See also
- `docs/PRODUCT-BIBLE.md` — the concept + the full taxonomy + living vs static.
- `hooks/scripts/bible-manifest.json` — the taxonomy (project-overridable).
