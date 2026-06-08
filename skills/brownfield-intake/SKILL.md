---
name: brownfield-intake
description: The brownfield on-ramp. After onboard on an existing codebase, this fingerprints the repo (languages, frameworks, structure, hotspots, tech debt via codebase-intel) so you don't have to explain the architecture, then ASKS how you want to define the work — describe it in plain language, point to an existing requirements/spec doc, answer a few guided questions, or pull a GitHub/GitLab issue — and synthesizes a code-anchored, increment-scoped requirements doc that feeds prd-quality-analyzer and the rest of the SDLC. Use right after onboard on a project that already has code.
disable-model-invocation: false
allowed-tools: Read Write Bash(mkdir *) Bash(jq *) Bash(ls *) Bash(git *) Bash(gh *) Bash(glab *) mcp__codebase-intel__ci_analyze_structure mcp__codebase-intel__ci_dependency_graph mcp__codebase-intel__ci_find_hotspots mcp__codebase-intel__ci_tech_debt_scan mcp__sdlc-engine__sdlc_get_state mcp__sdlc-engine__sdlc_start_cycle
---

# Brownfield Intake

VibeFlow's SDLC starts at REQUIREMENTS, which assumes a requirements doc to
score. On a **greenfield** project you write a PRD. On a **brownfield** project
you already have code, and you're almost never rebuilding the whole product —
you're doing an **increment** (a feature, refactor, bug-fix, migration). This
skill is the on-ramp: it makes VibeFlow *understand the existing code first*,
then guides you to define the increment, and produces the scoped requirements
artifact the rest of the SDLC runs against.

## Phase Contract

Runs in **REQUIREMENTS** only (it produces the requirements artifact). If
`currentPhase` is not REQUIREMENTS, emit a one-line note and stop. Writes are
confined to `docs/**`, `.vibeflow/**`, and `vibeflow.config.json`.

## Step 1: Understand the codebase (so you don't have to explain it)

Reuse `onboard`'s `.vibeflow/reports/codebase-fingerprint.md` if present;
otherwise build one. Use the **codebase-intel MCP** (read-only) against the
project root:

- `mcp__codebase-intel__ci_analyze_structure` — languages, frameworks, test
  runners, build tools, module/package layout.
- `mcp__codebase-intel__ci_dependency_graph` `{ root: ".", detectCycles: true }`
  — the import graph + cycles (so the increment respects real boundaries).
- `mcp__codebase-intel__ci_find_hotspots` — churn × complexity hotspots.
- `mcp__codebase-intel__ci_tech_debt_scan` — debt markers near the work.

Write/refresh `.vibeflow/reports/codebase-fingerprint.md` (stack summary,
module map, hotspots, debt). This is the **context** every later step anchors
to. If codebase-intel isn't loaded, fall back to `git ls-files` + reading
manifests (package.json / pyproject.toml / *.csproj / go.mod) and say so.

## Step 2: ASK how to define the increment (4 ways)

Don't assume — present the intake choice and wait:

```
Define the work for <project> (brownfield — <primary-language>, <framework>):

  1. Describe it      — Tell me in plain language what you want to build / change /
                        fix. I turn it into a scoped, code-anchored requirements doc.
  2. Point to a doc   — You already have a requirements / spec / ticket file. Give the
                        path; I use it and enrich it with the codebase context.
  3. Guided Q&A       — I ask a few targeted questions (goal, change type, which area
                        of the code, acceptance criteria) and synthesize the doc.
  4. From an issue    — Pull a GitHub/GitLab issue (gh / glab) by number or URL, or
                        paste the ticket text; I scope it against the code.

Pick 1 / 2 / 3 / 4:
```

Gather the raw intent per the choice:

- **1 · Describe** — take the operator's free-text description.
- **2 · Doc** — read the given path (`docs/…`, a ticket export, etc.). Treat it
  as the source of truth; you'll validate + enrich, not rewrite its intent.
- **3 · Guided Q&A** — ask, one at a time: (a) the **goal** / problem; (b) the
  **change type** — feature / refactor / bug-fix / migration / performance /
  security; (c) **which area** of the code (module/path — cross-check the
  fingerprint); (d) **acceptance criteria** / done-definition; (e) any
  **constraints** (compat, deadline, must-not-touch).
- **4 · Issue** — if `gh`/`glab` is on PATH and the operator gives a number/URL,
  pull it (`gh issue view <n> --json title,body,labels` / `glab issue view`).
  Otherwise accept pasted ticket text. Treat title+body as the intent.

## Step 3: Synthesize the increment requirements (code-anchored)

Write **`docs/<increment-slug>-requirements.md`** — a *scoped* requirements doc,
not a whole-product PRD. From the Step-2 intent + the Step-1 fingerprint:

- **Goal / problem statement** — what the increment achieves and why.
- **Scope** — explicitly **in** and **out**; this is an increment, name its edges.
- **Code anchor** — which modules / files / components it touches (from the
  dependency graph), the integration points, the existing patterns/conventions
  to follow, and any **hotspots / tech-debt** it lands near (from Step 1).
- **Change-type classification** — UI / backend / infra / mixed. This routes the
  later phases: a backend increment makes DESIGN light (design-bootstrap option
  5 "technical / no-UI") and the architecture mostly fixed by existing code
  (architecture-bootstrap "stack-agnostic / incremental"); a UI increment makes
  DESIGN central. **State the classification + the phase implications** so the
  operator knows the road ahead.
- **Functional requirements + acceptance criteria** — testable, numbered.
- **Non-functional / compatibility constraints** — must not break existing
  behaviour; perf / security / migration safety as relevant.
- **Risks** — concentrated on the hotspots + debt the increment touches.

Keep the intent faithful to the operator's input (especially for paths 2 & 4 —
enrich, don't redirect). Persist the increment slug to
`vibeflow.config.json` → `requirements.activeIncrement` for traceability.

**Open the increment's lifecycle cycle (Sprint 42).** Read
`.vibeflow/state/lifecycle.json`. If `currentCycle` is `completed` (or this is a
brand-new increment after a shipped cycle), open a **new** cycle — push the old
one into `history[]` and set:

```json
{ "currentCycle": {
    "id": "cycle-<N>", "kind": "increment", "title": "<increment-slug>",
    "phase": "REQUIREMENTS", "branch": "<current branch — ideally increment/<slug>>",
    "prUrl": null, "status": "in-progress", "startedAt": "<UTC ISO-8601>" } }
```

If `currentCycle` is the still-open `initial` cycle (cycle-1 brownfield start),
just record the increment title on it — don't open a second cycle. Each cycle =
one branch / PR; if the operator isn't on a dedicated branch yet, breadcrumb
`git checkout -b increment/<slug>` in Step 4.

**Reset the SDLC engine for the new cycle (Sprint 48).** The engine
(`sdlc-engine` MCP) models one linear pass and stays pinned at the *previous*
cycle's terminal phase (DEPLOYMENT) — so without a reset, `phase-runner` for the
new cycle would mismatch (engine=DEPLOYMENT vs config=REQUIREMENTS) and refuse.
When you open a **new increment cycle** (not the still-open initial one), call
`mcp__sdlc-engine__sdlc_start_cycle` `{ projectId, note: "<increment-slug>" }` —
it resets `currentPhase` to REQUIREMENTS, clears criteria + consensus, and bumps
the engine's cycle counter, so `phase-runner` walks the new cycle cleanly. (Check
`mcp__sdlc-engine__sdlc_get_state` first; if the engine is already at
REQUIREMENTS — e.g. a brand-new project — skip the reset.)

## Step 4: Hand off to the SDLC

The increment requirements doc is now the REQUIREMENTS primary. Close with the
breadcrumb as the **literal last line**:

```
▶ Next: /vibeflow:prd-quality-analyzer docs/<increment-slug>-requirements.md
   (scores testability ≥60, then /vibeflow:phase-runner walks the SDLC scoped to this increment)
```

Note any phase the classification will lighten/skip, so the walk isn't a
surprise (e.g. "backend increment → DESIGN will be a technical-design note, not
UI").

## Output

- `docs/<increment-slug>-requirements.md` (the scoped, code-anchored primary)
- `.vibeflow/reports/codebase-fingerprint.md` (built/refreshed)
- `vibeflow.config.json` → `requirements.activeIncrement` (the slug)
