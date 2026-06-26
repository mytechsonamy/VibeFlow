---
name: bible-update
description: Grows the Product Bible's LIVING documents at a phase boundary (Sprint 70) so they accrete instead of going stale. For the current SDLC phase, it reads that phase's artifacts (the PRD/design-spec/architecture/test-strategy + the increment diff) and appends what's new into each living bible-native doc the manifest says grows in this phase — new terms into the Glossary, new entities/relationships/invariants into the Domain Model, new roles into Personas, new conventions into API Standards / Rule DSL / UX Principles, milestones into the Roadmap. Merges never clobber (headed, provenance-tagged, deduped) and never invent — only what the phase artifacts support. phase-runner runs it automatically at each phase; you can also run it directly. Writes only living docs under docs/product-bible/ + .vibeflow/reports/bible-update.md.
disable-model-invocation: false
allowed-tools: Read Write Grep Glob Bash(bash *bible-status.sh*) Bash(jq *) Bash(mkdir *) Bash(ls *) Bash(git diff*) Bash(git rev-parse*) mcp__sdlc-engine__sdlc_get_state
---

# Bible Update — grow the living docs each phase

The Product Bible's value is that its **living** docs (glossary, domain model,
personas, API standards, Rule DSL, UX principles, roadmap, vision, …) keep
growing as the product is built — not a one-time intake that goes stale. This
skill is the per-phase growth step: at a phase boundary it folds what that phase
produced into the relevant living docs.

## Step 1 — Resolve the phase + which living docs grow now

```bash
PHASE="$(jq -r '.currentPhase // "REQUIREMENTS"' .vibeflow/state/*/project.json 2>/dev/null | head -1)"   # or sdlc_get_state
jq -r --arg p "$PHASE" '
  .docs | to_entries[]
  | select(.value.source=="bible" and .value.lifecycle=="living")
  | select((.value.growsIn // []) | index($p))
  | "\(.key)\t\(.value.path)"' "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/bible-manifest.json"
```

That lists the living bible-native docs whose `growsIn` includes the current
phase (e.g. ARCHITECTURE → domain-model, api-standards, rule-dsl, ai-strategy,
vision, srs, glossary). `source: vibeflow` living docs (architecture, ADRs,
test-strategy, …) already grow via their own phase skills — bible-update does
**not** touch them.

## Step 2 — Read this phase's artifacts (the growth source)

Gather what the current phase produced — the phase primary + its reports:

- REQUIREMENTS → the PRD/requirements doc(s) + `prd-quality-report.md`.
- DESIGN → `design/design-spec.md` + tokens.
- ARCHITECTURE → `docs/architecture.md` + `docs/adr/*` + `architecture-report.md`.
- PLANNING → `scenario-set.md` + `test-strategy.md` + `rtm.md`.
- DEVELOPMENT → the increment diff (`git diff <base>..HEAD`) + new source modules.
- TESTING/DEPLOYMENT → test reports + release-decision.

These are the **evidence**. Only grow a living doc from what they actually contain.

## Step 3 — Fold the new material into each living doc (merge, never clobber)

For each living doc from Step 1, append what's new:

- **Glossary** — new domain terms + one-line definitions appearing this phase.
- **Domain Model** — new entities, relationships, invariants (ARCHITECTURE
  refines the intake seed; DEVELOPMENT records what the code actually models).
- **Personas** — new/changed roles or user goals surfaced in REQUIREMENTS/DESIGN.
- **API Standards / Rule DSL** — new conventions/operators established in
  ARCHITECTURE/DEVELOPMENT.
- **UX Principles** — principles affirmed in DESIGN.
- **Roadmap** — milestones/decisions from PLANNING/DEPLOYMENT.

Rules:
- **Merge, never clobber.** Append under a dated, headed section with a
  provenance line `> _Grown in <PHASE> (cycle N) from <artifact> on <date>._`.
- **Dedupe.** If a term/entity already exists, refine it in place (note the
  change) rather than adding a duplicate.
- **Never invent.** Only what the phase artifacts support; mark inferred items
  `(inferred)`. If a doc has nothing new this phase, leave it untouched and say so.
- Create the doc from a stub if it doesn't exist yet (same template as
  `/vibeflow:product-bible` scaffold), then fill it.

## Step 4 — Report

Write `.vibeflow/reports/bible-update.md`: per living doc, what was added/refined
(or "no change this phase"), with the source artifact. Then re-run
`bible-status.sh` so newly-created living docs flip to present.

## Phase-runner integration

phase-runner runs `bible-update` automatically near the end of each phase (after
the analyzers/consensus, before/at advance) — **surface-only**, never a gate:
growing docs must not block the SDLC. Run it directly any time you want the bible
to catch up.

## Read-mostly

`bible-update` writes only living docs under `docs/product-bible/` + its report.
It never edits source code, config, a `source: vibeflow` doc, or a `static` doc.

## See also
- `docs/PRODUCT-BIBLE.md` — living vs static + the growth model.
- `/vibeflow:bible-intake` — the initial seed; `/vibeflow:product-bible` — status.
