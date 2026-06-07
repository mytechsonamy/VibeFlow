---
name: design-bootstrap
description: The DESIGN-phase guide. Produces the design artifacts (design spec, design tokens, wireframes) that DESIGN consensus reviews. It classifies whether the increment is UI-facing, then ASKS the operator which design source — Claude-native (zero-setup attractive accessible UI spec + tokens + wireframes), an existing Figma file (via the design-bridge MCP), designing from scratch in Figma (official Figma MCP), BOTH side-by-side for comparison (design-comparison.md → pick one), or a technical design (low/no-UI backend/infra increments). Writes everything under design/ and arms the consensus marker. Use at the start of DESIGN.
disable-model-invocation: false
allowed-tools: Read Write Bash(mkdir *) Bash(jq *) Bash(ls *) Bash(cp *) mcp__design-bridge__db_fetch_design mcp__design-bridge__db_extract_tokens mcp__design-bridge__db_generate_styles mcp__design-bridge__db_compare_impl mcp__claude_ai_Figma__use_figma mcp__claude_ai_Figma__get_design_context mcp__claude_ai_Figma__get_screenshot
---

# Design Bootstrap

The DESIGN phase is the one phase VibeFlow doesn't auto-analyze: a design has
to be *authored*, then reviewed. This skill is the author-side guide. It turns
the approved PRD into the design artifacts that DESIGN consensus
(`consensus.design.approved`) and the exit criteria (`design.approved`,
`accessibility.verified`) are checked against — and it lets the operator pick
**how** the design gets made.

## Phase Contract

Runs in **DESIGN** only. Before anything else, read
`vibeflow.config.json`'s `currentPhase`. If it is not DESIGN, emit:

> design-bootstrap is for the DESIGN phase only; current is `<phase>`.
> Advance to DESIGN first (`/vibeflow:advance`).

…and stop. Writes are confined to `design/**`, `.vibeflow/**`, and
`vibeflow.config.json` (the DESIGN phase-write policy).

## Step 1: Resolve context

Read:
- `vibeflow.config.json` → `domain`, `platform`, `project`, optional
  `design.sourceDir` (default `design/`), optional `design.figmaFileUrl`.
- The approved PRD (from REQUIREMENTS — the `lastConsensus` primary, or
  `docs/<prd>`). The design must serve the PRD's screens / flows / entities.
- Existing `design/**` (re-runs build on top of prior work, never clobber
  silently).

Detect what's available, to tailor the offer:
- **design-bridge MCP** (VibeFlow's own Figma bridge): available iff the
  `mcp__design-bridge__db_*` tools resolve **and** `FIGMA_TOKEN` is set
  (plugin `userConfig.figma_token`). A `db_*` call that returns the
  "FIGMA_TOKEN is required" error means the token isn't configured yet.
- **Official Figma MCP** (`mcp__claude_ai_Figma__*` / the `/figma-*` skills):
  available iff those tools resolve in this session (richer Dev-Mode +
  design-from-scratch via `use_figma`).

### Step 1b: Is this increment UI-facing? (Sprint 35)

VibeFlow's DESIGN phase is the **UI/UX** phase (Figma, wireframes, tokens,
accessibility); **technical** design (data model, services, infra) is
ARCHITECTURE's job. But a DESIGN phase entered for a **backend / infra / ops
increment** (e.g. "Postgres + RLS + WORM + K8s hardening") has little or no UI
to design — there, a UI-first menu is the wrong tool. So classify the increment
before offering the menu (a heuristic — you still **ask**, never auto-decide):

- **UI signals** (→ UI-facing): `platform` ∈ {web, ios, android, all}; PRD
  mentions screens / pages / ekran / sayfa / arayüz / dashboard / user
  journeys / wireframes / components / forms.
- **Backend signals** (→ low/no UI): PRD/increment dominated by API / service /
  pipeline / infra / altyapı / Postgres / K8s / RLS / WORM / ops / migration /
  secrets, with no screen inventory.

If backend signals dominate, **lead the menu with a flag**: "this increment
looks backend/infra-heavy — option 5 (technical design) likely fits; the UI
options (1–4) may not apply, and heavy architecture work belongs in the
ARCHITECTURE phase." If UI signals dominate, recommend 1–4 normally.

## Step 2: ASK the operator which design source (always)

Do **not** assume a default — present the choice every DESIGN run (per the
framework's design decision). Emit this menu, annotated with the Step-1b
classification + per-option availability, and wait for the answer:

```
DESIGN source for <project> (domain=<domain>, platform=<platform>)?
[<Step-1b flag, if backend-heavy>]

  1. Claude-native   — I generate an attractive, accessible UI spec +
                       design tokens + wireframes from the PRD. Zero setup.
  2. Figma (existing)— You have a Figma file already. I pull it via the
                       design-bridge MCP → design tokens + styles + a spec
                       that references your frames. Needs FIGMA_TOKEN + URL.
  3. Figma (scratch) — Design from scratch in Figma using the official Figma
                       MCP (use_figma) against a design system, then sync back.
                       Needs the Figma MCP connected.
  4. Both (compare)  — I produce BOTH a Claude-native design AND a Figma design,
                       lay them side-by-side in design/design-comparison.md, and
                       you pick the one to carry forward (or merge). For when the
                       look matters enough to weigh two directions.
  5. Technical design— This increment has little/no UI (backend/infra/ops). I
                       write design-spec.md as a TECHNICAL design instead of a
                       UI design (or hand the heavy parts to ARCHITECTURE).

Pick 1 / 2 / 3 / 4 / 5:
```

Annotate each option with availability from Step 1 (e.g. "(2 unavailable —
FIGMA_TOKEN not set; I'll walk you through it if you pick it)"; "(4 needs a
Figma path available for its Figma half)"). Whatever the operator picks, the
**output contract is the same** (Step 4): real files under `design/` + the
consensus marker on `design/design-spec.md`.

## Step 3: Route

### 3·A — Claude-native (zero setup)

Generate, from the PRD, a design that is genuinely **user-friendly and
attractive** — this is a product where the UI matters, so do not emit a bland
skeleton. Apply modern, accessible UI craft:

- **`design/design-spec.md`** (the PRIMARY artifact consensus reviews):
  - Screen / page inventory mapped to PRD flows + entities.
  - Per screen: purpose, layout, key components, and **every state**
    (empty / loading / error / success / permission-denied / offline).
  - Primary user journeys as step sequences.
  - Interaction + navigation model (information architecture).
  - Responsive behaviour for `<platform>` (breakpoints / adaptive rules).
  - **Accessibility section** (feeds `accessibility.verified`): WCAG 2.2 AA
    targets — contrast ratios, focus order, semantic landmarks, hit targets,
    motion-reduction, screen-reader labels. Be specific, not aspirational.
  - A **domain-appropriate visual direction**: for `financial`, calm +
    trustworthy + high-legibility (clear hierarchy for numbers, restrained
    accent use, careful red/green for gains/losses with non-colour cues);
    adapt for e-commerce / healthcare / general.
- **`design/design-tokens.json`** — a real token system: a semantic color
  palette (base + semantic roles + **dark mode**), a typographic scale
  (families, sizes, weights, line-heights), spacing scale, radii, shadows,
  and motion durations/easings. Domain-tuned. Valid JSON.
- **`design/wireframes/<screen>.md`** — ASCII/markdown wireframes (or, when
  the operator wants something clickable, a single-file HTML mockup under
  `design/mockups/`) for the top 3–5 screens, showing layout + states.

Keep tokens and wireframes consistent with the spec.

### 3·B — Figma (existing file via design-bridge)

1. **Token check.** If a `db_*` call returns "FIGMA_TOKEN is required",
   stop and walk the operator through it:
   > Create a Figma personal access token
   > (Figma → Settings → Security → Personal access tokens, scope: File
   > content read). Add it to the plugin: set `userConfig.figma_token`
   > (so it maps to `FIGMA_TOKEN`), then restart Claude Code and re-run me.
2. **Resolve the file URL** from `design.figmaFileUrl` (config) or ask the
   operator for the Figma file/frame URL. Persist it to
   `vibeflow.config.json` → `design.figmaFileUrl` for next time.
3. Call:
   - `mcp__design-bridge__db_fetch_design({ url })` → frame inventory.
   - `mcp__design-bridge__db_extract_tokens({ url })` → color/type/spacing
     tokens (with source node IDs as evidence).
   - `mcp__design-bridge__db_generate_styles({ url })` → CSS custom
     properties + a Tailwind snippet.
4. Write `design/design-tokens.json` (from extract), `design/styles.css`
   (from generate), and **`design/design-spec.md`** that references the Figma
   file + the fetched frames as the screen inventory, plus the same
   accessibility section as 3·A (the design still has to pass WCAG).

### 3·C — Figma (from scratch via the official Figma MCP)

Use the **official** Figma MCP, not design-bridge. If it isn't connected,
point the operator at it (`/figma-use` / the Figma MCP setup) and stop.
Otherwise:

1. Load `/figma-use` (mandatory before `use_figma`) and, for a new system,
   `/figma-generate-design` / `/figma-generate-library`.
2. Drive `use_figma` to generate the screens from the PRD against an existing
   design system, attractive + accessible by construction.
3. Pull the result back: `get_design_context` / `get_screenshot` into
   `design/figma/` (screenshots) and distil a **`design/design-spec.md`**
   (frames, components, tokens, a11y) as the reviewable primary.

### 3·D — Both (compare Claude-native vs Figma) — Sprint 35

For when the look matters enough to weigh two directions before committing.

1. **Produce the Claude-native candidate** (run 3·A) into
   `design/candidates/claude-native/` — `design-spec.md` + `design-tokens.json`
   + wireframes.
2. **Produce the Figma candidate** — run 3·B if the operator has an existing
   file (design-bridge → tokens/styles), else 3·C (official MCP, from scratch)
   — into `design/candidates/figma/` (`design-spec.md` + tokens/styles +
   screenshots). If no Figma path is available, say so and fall back to 3·A
   only (can't compare against nothing).
3. **Write `design/design-comparison.md`** — a side-by-side the operator can
   actually decide from:
   - visual direction (mood, hierarchy, domain fit),
   - token systems (palette / type / spacing) — diff the two,
   - layout + information-architecture approach,
   - fidelity + accessibility coverage,
   - effort / maintenance / hand-off trade-offs,
   - **a recommendation** with the reasoning.
   When both candidates have screenshots, `db_compare_impl({leftPath,
   rightPath})` adds a dimension/identity check to the qualitative compare.
4. **Ask the operator to pick** (1 = Claude-native, 2 = Figma, or "merge —
   take tokens from X, layout from Y"). Copy the chosen (or merged) candidate
   to the canonical **`design/design-spec.md`** + `design/design-tokens.json`.
   Note the choice + rationale at the top of `design-comparison.md`.

The chosen spec is what consensus reviews (Step 4 / Final Step unchanged).

### 3·E — Technical design (low/no-UI increment) — Sprint 35

When Step 1b flagged a backend/infra/ops increment and the operator picks 5.
First, a one-line honesty check: **if this is heavy architecture** (new
services, data model, formal tech decisions), say so and recommend doing it in
the **ARCHITECTURE** phase (ADRs) instead — DESIGN is for UI. If the operator
still wants a DESIGN-phase technical note (e.g. a light increment, or they're
treating DESIGN as their technical-design step), write **`design/design-spec.md`**
as a TECHNICAL design:

- components / services + responsibilities, and their boundaries;
- data model + key interfaces / contracts (request/response, events);
- primary sequences / flows (not screens — call paths);
- infra / ops considerations for the increment (deploy, config, migration);
- non-functional: security, performance, observability, failure modes;
- open questions → ARCHITECTURE.

No `design-tokens.json` / wireframes (there's no UI). The same consensus +
operator-confirmed criteria apply — the panel reviews the technical spec.

## Step 4: Output contract (all paths)

Regardless of route, produce:
- `design/design-spec.md` — the **primary** artifact (the thing consensus
  reviews).
- `design/design-tokens.json` — the token system (Claude-native or extracted).
- wireframes/mockups/screenshots as evidence under `design/`.

Then **announce the manual-criterion reminder** from `docs/AUTO-SATISFY.md`:
`design.approved` + `accessibility.verified` are operator-confirmed (the
design needs a human's eye), distinct from the consensus pass.

## Final Step: arm consensus + breadcrumb

Write `.vibeflow/state/consensus-needed.json` (marker schema v2) so the
DESIGN consensus reviews the design spec:

```json
{
  "primaryArtifact": "design/design-spec.md",
  "evidence": ["design/design-tokens.json"],
  "artifact": "design/design-spec.md",
  "requiredCommand": "/vibeflow:phase-runner",
  "createdAt": "<UTC ISO-8601>",
  "createdBy": "design-bootstrap"
}
```

Then close with the breadcrumb as the **literal last line** (the `▶ Next:`
prefix is the project-wide next-step convention):

```
▶ Next: /vibeflow:phase-runner
   (runs cross-AI consensus on design/design-spec.md, then advances on APPROVED)
```

## Output

- `design/design-spec.md` (primary), `design/design-tokens.json`, wireframes
  / mockups / Figma screenshots under `design/`
- `design/styles.css` (Figma-existing path)
- `.vibeflow/state/consensus-needed.json` (arms DESIGN consensus)
- optional `vibeflow.config.json` → `design.figmaFileUrl` (persisted)
