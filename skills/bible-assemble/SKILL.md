---
name: bible-assemble
description: Assembles the Product Bible into one coherent, navigable, shareable export at project end (Sprint 71) — the final "we shipped, here's the whole book" deliverable. Reads bible-status, builds a curated index (docs/product-bible/README.md) with a per-category table of contents linking every canonical doc (bible-native in place + VibeFlow-produced docs referenced where they live — never duplicated), assembles a single concatenated export (docs/product-bible/product-bible-export.md), runs a light cross-consistency curation pass (gaps, stale living docs, glossary↔domain-model↔PRD coherence), and writes .vibeflow/reports/bible-assembly.md with the completeness rollup + what's still owed. Read-mostly — writes only the bible index + export + report. Use at end of a cycle / project, or any time you want the current full bible.
disable-model-invocation: false
allowed-tools: Read Write Grep Glob Bash(bash *bible-status.sh*) Bash(jq *) Bash(mkdir *) Bash(ls *) Bash(cat *)
---

# Bible Assemble — the final, curated Product Bible

Parts B (intake) and C (living-doc growth) fill and grow the bible. This is the
**assembly**: turn the corpus into one coherent, navigable book you can hand to a
new hire, a partner, or a sales team — and surface what's still missing or stale.

## Step 1 — Read the corpus state

```bash
bash "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/bible-status.sh"
```

Gives present/missing per doc + per category. Assembly indexes what's present and
flags what's owed.

## Step 2 — Build the index (`docs/product-bible/README.md`)

Write a curated index with a **per-category table of contents** (business/GTM →
product → engineering), and for each doc a row: title · lifecycle (living/static)
· status (✓ present / ✗ owed) · a one-line summary · a **link to the canonical
file**. Link `source: bible` docs at their `docs/product-bible/...` path and
`source: vibeflow` docs **where they actually live** (`docs/architecture.md`,
`docs/adr/`, `design/design-spec.md`, `.vibeflow/reports/...`) — the index points
at the single source, it never copies. Lead with a completeness line
(`Bible: 21/25 present — business 6/10, product 5/6, engineering 10/9`).

## Step 3 — Assemble the single-file export (`docs/product-bible/product-bible-export.md`)

Concatenate the present docs into one navigable document, in category/phase order,
each under a clear heading with its provenance (path + lifecycle). For a large
`source: vibeflow` doc, include a linked summary + the link rather than inlining
the whole thing (keep the export readable; note it's an excerpt). This is the
"one file to read/share" artifact; the canonical sources stay authoritative.

## Step 4 — Curation pass (light cross-consistency)

Flag — don't auto-fix — coherence gaps across the corpus:
- **Owed docs** — present in the taxonomy but missing (esp. living docs that
  should exist by this phase).
- **Stale living docs** — a living doc not grown in the phases its `growsIn`
  covers (cross-check against `.vibeflow/reports/bible-update.md`).
- **Cross-doc coherence** — a Glossary term with no home in the Domain Model; a
  Persona never referenced by a PRD; an ADR decision not reflected in API
  Standards. Surface as findings `{ finding, why, impact, confidence }`; the
  operator (or bible-update) resolves them.

## Step 5 — Report

Write `.vibeflow/reports/bible-assembly.md`: the completeness rollup, the curation
findings, and the two written artifacts (index + export). End with a breadcrumb:
fill the owed docs via `/vibeflow:bible-intake` (inputs) or by running the phase
that produces them, then re-assemble.

> ▶ Next: /vibeflow:product-bible   (scaffold/seed any owed docs, then re-run /vibeflow:bible-assemble)

## Read-mostly

`bible-assemble` writes only `docs/product-bible/README.md`,
`docs/product-bible/product-bible-export.md`, and its report. It never edits a
source doc (bible-native or vibeflow) — assembly is a *view* over the corpus, and
curation only *flags*.

## See also
- `docs/PRODUCT-BIBLE.md` — the corpus model.
- `/vibeflow:bible-intake` (ingest) · `/vibeflow:bible-update` (grow) ·
  `/vibeflow:product-bible` (status + scaffold).
