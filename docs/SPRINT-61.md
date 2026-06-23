# Sprint 61 — Operator decision points become tappable choices

## Context

When VibeFlow pauses for an **operator decision**, the skills today print a prose
menu / `[y/N]` prompt and expect the user to **read the findings and type** an
answer. On a phone (Claude Code remote/web) that is slow and error-prone: you
scroll a wall of analysis, then type a free-form reply.

The improvement: at every operator-blocking decision point, **extract the
decision into tappable options** using the built-in **`AskUserQuestion`** tool —
2–4 choices, each with a one-line condensed rationale (so the "why" is in the
option, not buried in the report). `AskUserQuestion` always offers **"Other"**
for a typed/manual answer, so the structured form **loses nothing** vs free-text
— it's strictly better for remote/mobile. This is therefore **default behaviour,
no config flag**.

Investigation facts:
- No skill uses `AskUserQuestion` today (`grep` → none); decision points are all
  prose menus (`brownfield-intake` Step 2 "4 ways", `design-bootstrap` Step 2 "5
  sources", `onboard` Step 1 domain/platform/risk, `apply-arbiter-patch`
  `[y/N]`, etc.).
- `AskUserQuestion` is a built-in interaction tool; to use it inside a skill it
  must be in that skill's `allowed-tools` frontmatter (skills are tool-gated).

## Approach

A single reusable **convention** applied to each operator-blocking decision
point, plus a reference doc. No engine/hook change.

### 1. The convention (one doc, reused wording)

New `docs/OPERATOR-CHOICES.md` defines the pattern every skill points to:

> **Operator choice (mobile-friendly).** When you need an operator decision,
> present it with the **`AskUserQuestion`** tool: extract 2–4 options, each a
> short label + a **one-line condensed rationale** (put the "why" — the relevant
> finding — in the description so the operator doesn't scroll the full report).
> The built-in **"Other"** always lets them type a manual answer, so this never
> removes free-form input. Recommended option first, labelled "(Recommended)".
> Free-form-only inputs (e.g. a project name, a file path, an issue URL) stay a
> normal typed prompt — don't force them into options.

### 2. Apply it at each operator-blocking decision point

For each skill below: add `AskUserQuestion` to `allowed-tools`, and at the
decision point add a short **"Operator choice"** instruction naming the options
to surface (keeping the existing prose menu as the fallback rendering). Pattern,
applied to representative files:

- **`skills/onboard/SKILL.md`** Step 1 — `domain` (financial/e-commerce/
  healthcare/general), `platform` (web/ios/android/all), `riskTolerance`
  (low/medium/high) as one multi-question `AskUserQuestion` call; **project
  name** + **tech stack** stay typed (tech stack: auto-detect then confirm
  via a yes/adjust choice).
- **`skills/brownfield-intake/SKILL.md`** Step 2 — intake path (Describe / Point
  to a doc / Guided Q&A / From an issue).
- **`skills/design-bootstrap/SKILL.md`** Step 2 — design source (Claude-native /
  Figma existing / Figma scratch / Both-compare / Technical) + the 3·D pick
  (Claude / Figma / merge).
- **`skills/architecture-bootstrap/SKILL.md`** — tech baseline (Propose defaults
  / Specify the stack / Stack-agnostic).
- **`skills/apply-arbiter-patch/SKILL.md`** Step 3 — replace `[y/N]` with Apply /
  Dry-run / Skip (the diff summary stays the context above the choice).
- **`skills/phase-runner/SKILL.md`** — the NEEDS_REVISION/REJECTED follow-up
  breadcrumb becomes a choice (Run specialist / Run arbiter / Apply patch /
  Stop) so the next step is one tap on mobile.
- **`skills/integrate/SKILL.md`** (Sprint 60) — Step 5 ship/fix (Drive to
  DEPLOYMENT / Fix on feature stream / Stop).
- **`skills/release-decision-engine/SKILL.md`** — next action on
  GO/CONDITIONAL/BLOCKED.
- **`skills/learning-apply/SKILL.md`** — which lane / which recommendation to
  apply (when not `--yes`).

Each option's `description` carries the condensed finding (e.g. for apply: "3
files, +42/−10, touches PRD §4" not just "apply"). Recommended option first.

### 3. Docs + registry

- `docs/OPERATOR-CHOICES.md` (new) — the convention + a "why mobile" note +
  the "Other = still type" guarantee.
- `CLAUDE.md` — one line under conventions pointing at it.
- No `skills/phase-policy.json` change (no new skill).

## Out of scope / deliberate limits
- **No config flag.** "Other" preserves typing, so default-on is pure upside.
- **No engine/hook/MCP change** — pure skill-prose + frontmatter + docs.
- Free-form inputs (names, paths, URLs, prose descriptions) stay typed prompts;
  only genuinely enumerable decisions become options.
- Analysis skills that just *report* (no operator branch) are untouched.

## Critical files
- New: `docs/OPERATOR-CHOICES.md`, `tests/integration/sprint-61.sh`
- Edited (frontmatter `allowed-tools` += `AskUserQuestion` + a decision-point
  "Operator choice" block): the ~9 skills listed above.
- `CLAUDE.md` (one pointer line).

## Verification
- `tests/integration/sprint-61.sh` (new): for each target skill assert (a)
  `AskUserQuestion` is in `allowed-tools`, (b) an "Operator choice" instruction
  is present at the decision point, (c) the existing prose menu still exists as
  fallback; assert `docs/OPERATOR-CHOICES.md` exists + is referenced; harness
  self-audit [S61-Z].
- Full regression stays green (no logic touched): `bash hooks/tests/run.sh`,
  `bash tests/integration/run.sh`, `cd mcp-servers/sdlc-engine && npm test`,
  and the prior `bash tests/integration/sprint-60.sh`. (Pre-existing failures —
  sprint-8 [S8-C], sprint-11 [S11-F2], sprint-20/24 catalog-count, sprint-47
  [S47-B] — are unrelated and already present on a clean tree.)
- Manual mobile check: run `/vibeflow:brownfield-intake` and confirm the intake
  path renders as tappable options with an "Other" escape.
