---
name: bible-intake
description: Product Bible ingestion (Sprint 69) — review the input documents you bring INTO a project (a vision doc, Gartner/analyst summaries, competitor decks, an existing PRD/spec/SRS, persona research, an API style guide, …) and file them into the bible. It discovers candidate inputs, classifies each into the bible taxonomy (business/product/engineering doc-type), files it under docs/product-bible/<category>/ (or references it in place if it's a doc VibeFlow already produces — never duplicated), and SEEDS the living docs from the corpus: extracts a Glossary (domain terms), a Domain Model seed (entities + relationships), and Personas where the material supports it. Writes .vibeflow/reports/bible-intake.md. Use once near the start (after onboard / alongside REQUIREMENTS), and again whenever a batch of new input docs arrives. Read-mostly except the bible files it writes (operator-confirmed).
disable-model-invocation: false
allowed-tools: Read Write AskUserQuestion Grep Glob Bash(bash *bible-status.sh*) Bash(jq *) Bash(mkdir *) Bash(ls *) Bash(find *) Bash(cp *)
---

# Bible Intake — ingest the input documents

A project rarely starts from nothing: you bring in a vision, analyst summaries
(Gartner), competitor decks, an existing PRD or spec, persona research, an API
style guide. These should be **reviewed and filed into the Product Bible** — and
mined to seed the living docs (glossary, domain model, personas) — not left as
loose files nobody reads again. That's this skill.

## Step 1 — Know what the bible already has

```bash
bash "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/bible-status.sh"
```

This tells you which canonical docs are present/owed (see `/vibeflow:product-bible`
+ `docs/PRODUCT-BIBLE.md`). Intake fills the **owed** ones from your inputs.

## Step 2 — Gather the input documents (operator choice)

**Operator choice (mobile-friendly — see `docs/OPERATOR-CHOICES.md`).** Present
this with `AskUserQuestion`:
- **Scan the repo (Recommended)** — find candidate docs not yet in the bible
  (`docs/**/*.md`, `*.md` at root, a `research/` or `inputs/` dir), excluding
  what's already filed (`docs/product-bible/**`) and VibeFlow's own outputs.
- **Point to a file or folder** — the operator gives a path (a doc, or a dir of
  inputs).
- **Paste / describe** — the operator pastes the content or describes it.

Only text/markdown is read directly; for a PDF/DOCX, ask the operator to export
it to text/markdown first (note it in the report — don't pretend to read binary).

## Step 3 — Classify each input into the taxonomy

For each input, map it to a bible doc-type from `bible-manifest.json`
(business: vision / competitive-intelligence / gartner-summaries /
competitor-analysis / ai-strategy / roadmap / sales-arguments / rfp-templates /
demo-scenarios / pilot-guides; product: personas / glossary / ux-principles /
prd / srs; engineering: domain-model / api-standards / rule-dsl / …). Show the
proposed classification and let the operator correct it (an input may map to
more than one, or to none — say so rather than force a fit).

## Step 4 — File it into the bible

- **bible-native target** (`source: bible`) → write/merge into the canonical path
  `docs/product-bible/<category>/<doc>.md`. If the doc already exists, **merge**
  (append a clearly-headed section with a provenance line `> _Ingested from
  <input> on <date>._`), never clobber. Multiple inputs of one type (e.g. three
  competitor decks) fold into one canonical doc as sections.
- **vibeflow-produced target** (`source: vibeflow`, e.g. an existing PRD) → do
  **not** copy it into the bible; leave it where VibeFlow expects it (so the
  phase skills + bible-status reference the single source) and note the link.
- Preserve the original input untouched; the bible doc is a filed/curated copy.

## Step 5 — Seed the living docs from the corpus

The highest-value intake output: mine the ingested material to seed the **living**
docs so later phases grow them instead of starting blank.

- **Glossary** — extract domain terms + one-line definitions into
  `docs/product-bible/product/glossary.md` (merge; mark `> _Living document._`).
- **Domain Model** — extract the core entities + their relationships +
  invariants into `docs/product-bible/engineering/domain-model.md` (a seed, not a
  final model — ARCHITECTURE refines it).
- **Personas** — if the inputs contain user/role research, seed
  `docs/product-bible/product/personas.md`.

Extract only what the source supports; mark anything inferred as `(inferred)` so
it's reviewable. Never invent terms/entities not grounded in an input.

## Step 6 — Report

Write `.vibeflow/reports/bible-intake.md`: each input → classification → where it
was filed (or referenced); the terms/entities/personas seeded; and what's **still
owed** (bible docs with no input yet). Each finding `{ finding, why, impact,
confidence }`. Then re-run `bible-status.sh` so the operator sees the bible grow.

> ▶ Next: /vibeflow:product-bible   (see the updated bible; scaffold any remaining gaps)

## Read-mostly

`bible-intake` writes only bible files under `docs/product-bible/` + its report;
it never edits source code, config, or a `source: vibeflow` doc (it references
those). Merges never clobber — they append headed, provenance-tagged sections.

## See also
- `docs/PRODUCT-BIBLE.md` — the corpus + living-vs-static.
- `/vibeflow:product-bible` — status + scaffold.
- `hooks/scripts/bible-manifest.json` — the taxonomy.
