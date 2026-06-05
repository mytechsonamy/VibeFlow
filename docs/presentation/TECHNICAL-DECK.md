<!--
VibeFlow — Technical Slide Deck
Format: slide-based Markdown (--- separators). Convert with Marp, Slidev,
reveal.js, or paste each slide into your deck tool.
Audience: architects, staff/principal engineers, technical buyers, CTOs.
~18 slides, ~25 min. Speaker notes under "> Notes:".
-->

# VibeFlow — Technical Architecture

## How an AI‑orchestrated SDLC is actually built — and kept honest

v2.18.0 · Claude Code plugin · 5 MCP servers · 40+ skills · 9 sub‑agents · 2,943 tests

> Notes: This deck is for people who will poke holes. Be concrete, show the mechanisms, and don't oversell — the test count and the file‑backed state are your credibility anchors.

---

# Design principles

- **Plugin‑first.** Everything is a Claude Code native primitive — skills, hooks, sub‑agents, MCP servers. No bespoke runtime.
- **Truth‑driven.** Requirements are the source of truth; testability score < 60 blocks development.
- **Consensus‑based.** Multi‑AI review (Claude + ChatGPT + Gemini) with graceful degradation to whatever CLIs are present.
- **Deterministic core.** No hidden cloud calls in the control flow; state is plain files; Git is the version history.
- **Enum‑safe, schema‑validated.** Zod schemas on every MCP boundary; status values are enums, never string literals.

> Notes: The phrase "graceful degradation" matters — consensus uses whichever of codex/gemini are on PATH; it never hard‑fails because a CLI is missing. Lead with determinism for skeptical architects.

---

# System at a glance

```
┌──────────────────────────────────────────────────────────────┐
│  Claude Code host (the operator's machine / CI)               │
│                                                                │
│  Skills (40+)        Sub‑agents (9)        Hooks (PreToolUse,  │
│  prose + bash        phase specialists     SessionStart, …)    │
│       │                   │                     │              │
│       └──────────┬────────┴──────────┬──────────┘              │
│                  ▼                    ▼                         │
│         MCP servers (5, TypeScript + Zod)                      │
│   sdlc-engine · codebase-intel · design-bridge ·              │
│   dev-ops · observability                                      │
│                  │                                             │
│                  ▼                                             │
│   File‑backed state:  .vibeflow/state/<project>/              │
│     project.json (rollup) + events/ (append‑only) + archive/  │
│   Reports:  .vibeflow/reports/*.md                            │
│   Consensus history:  state/consensus/history.jsonl          │
└──────────────────────────────────────────────────────────────┘
   External CLIs (optional, gated on PATH):  codex · gemini
```

> Notes: Walk top to bottom. The key architectural claim: orchestration logic lives in skills/hooks (prose+bash), heavy/typed logic lives in MCP servers (TS+Zod), and *all durable state is files*. There is no server process and no database.

---

# The four layers

| Layer | Primitive | Responsibility |
|---|---|---|
| Orchestration | **Skills** (prose + bash) | Phase walks, consensus loops, the operator‑facing commands |
| Specialization | **Sub‑agents** | Deep artifact rewrites & reviews in isolated context |
| Enforcement | **Hooks** | Gate writes, drain markers, persist state, inject context |
| Computation | **MCP servers** (TS + Zod) | State transitions, validation, analysis, integrations |

> Notes: This separation is the heart of the design. Skills are easy to read and modify; MCP servers are where you want type safety and tests. Hooks are the deterministic glue that the model can't skip.

---

# State model: files, not a database

```
.vibeflow/state/<project>/
  project.json        # current rollup: phase, satisfied criteria, metrics
  events/             # append-only event log (every transition)
  archive/            # per-phase snapshots
```

- **Single backend.** A v2.0 breaking change retired SQLite/Postgres for a pure filesystem store.
- **Git gives versioning for free** — diff state across time, blame a transition, branch a project.
- **Rebuildable.** `bin/replay-events.sh` reconstructs `project.json` byte‑for‑byte from `events/` + `archive/`.
- **Cross‑process safe** — file locking + a 50‑concurrent‑writer regression test in the suite.

> Notes: Architects will ask "why not a DB?" Answer: portability, zero‑ops, free auditability, and Git as the time machine. The event‑sourcing + replay angle is what makes it defensible, not naive.

---

# The 7 phases & their exit criteria

Each phase has **machine‑checked exit criteria**; `/vibeflow:advance` refuses to move on until they are satisfied.

| Phase | Representative gate criteria |
|---|---|
| Requirements | `prd.approved`, `testability.score ≥ 60`, `consensus.requirements.approved` |
| Design | `design.approved`, `accessibility.verified` |
| Architecture | `adr.recorded`, `consensus.architecture.approved` |
| Planning | `test-strategy.approved`, `sprint.planned` |
| Development | `code.reviewed`, `quality.gates.passed` |
| Testing | `coverage.met`, `mutation.score.acceptable` |
| Deployment | `release.decision.go`, `deployment.verified`, `health.checks.passed` |

> Notes: The point is that "advance" is not a vibe — it's an enum‑checked predicate evaluated by the engine. Many criteria are *auto‑satisfied* by the relevant analyzer skill (next slides).

---

# Multi‑AI consensus — the mechanism

1. An analysis skill produces an artifact and writes a **consensus‑needed marker** (`primaryArtifact` + `evidence[]`).
2. A **PreToolUse hook** (`consensus-gate.sh`) blocks further tool calls until consensus runs — the loop can't be skipped.
3. The **orchestrator** forks reviewers (claude‑reviewer + codex + gemini, whichever are present), feeds each the *primary artifact* (semantically excerpted if large), and collects verdicts.
4. The **aggregator** computes agreement, dedups critical findings (by `{file,line_range}` and Jaccard title similarity), and emits a status enum.

> Notes: The non‑obvious engineering here: (a) the gate hook makes consensus *non‑optional* despite the model being free‑willed; (b) reviewers see the actual PRD/ADR, not a summary of it; (c) findings are deduped so three reviewers flagging the same line counts once.

---

# Consensus outcomes & convergence

- **Thresholds:** `APPROVED` ≥ 90% agreement + 0 critical · `NEEDS_REVISION` 50–89% · `REJECTED` < 50% or ≥ 2 critical.
- **Iterative negotiation:** if not approved, a phase **specialist** rewrites the artifact as one diff‑first patch → next round runs automatically.
- **Convergence guardrails:** `maxIterations` ceiling + a convergence‑stall guard prevent infinite loops.
- **Explicit escalation:** out of rounds without approval ⇒ `HUMAN_APPROVAL_REQUIRED` (pass‑with‑audit), never a silent pass.

> Notes: Emphasize the auto‑chain: aggregator → specialist patch → apply → next round. It's a real loop with a defined fixpoint and a defined escape hatch. The `agreement<0.5⇒REJECTED` false‑positive bug was fixed in S19 — mention if asked about rigor.

---

# Diff‑first specialists & safe application

- Six phase specialists (PRD, design, ADR, test‑strategy, coverage, runbook) **never write to source directly**.
- They emit a **unified diff patch** under `.vibeflow/state/patches/…`.
- `apply-arbiter-patch` applies it with **preview + explicit confirmation**, optional `--run-tests`, `--dry-run`.
- This keeps every AI‑authored change **reviewable and reversible** before it touches your tree.

> Notes: This is the "we don't let the AI scribble on your repo" slide. Diff‑first + explicit apply is what makes the autonomous parts palatable to a senior engineer.

---

# The 5 MCP servers

| Server | Surface | Tests |
|---|---|---|
| **sdlc-engine** | phase state machine, consensus recording, criteria, config schemas | 199 |
| **codebase-intel** | structure, dependency graph, hotspots, tech‑debt scan | 48 |
| **design-bridge** | Figma fetch, token extraction, style gen, impl compare | 57 |
| **dev-ops** | GitHub + GitLab clients, pipelines, deploy/rollback | 72 |
| **observability** | metric collect, flaky tracking, perf trend, health dashboard | 76 |

All TypeScript, all Zod‑validated inputs, all with 80/80/80/80 coverage thresholds.

> Notes: The engine is the brain (199 tests for a reason); the other four are typed integration surfaces. Mention the coverage thresholds — they're enforced, not aspirational.

---

# Phase enforcement via hooks

- `phase-write-guard.sh` (PreToolUse) consults `phase-policy.json` and **blocks writes that violate the current phase's boundaries** (with an explicit escape hatch).
- `consensus-gate.sh` blocks progress until the required consensus runs.
- `save-plan-doc.sh` persists every approved plan to `docs/SPRINT‑NN.md`.
- `load-sdlc-context.sh` (SessionStart) restores phase, domain, and pending‑review state on every session.
- All hooks source a shared `_lib.sh`; bash 3.2‑compatible (macOS default shell).

> Notes: Hooks are the deterministic enforcement the model literally cannot route around — they run in the host, not the model. This is how "the AI should run consensus" becomes "the AI cannot proceed without it."

---

# The autonomous learning loop (L3)

```
consensus history.jsonl
        │  mine
        ▼
learning-loop-engine ── findings ──► learning-apply
 (slow‑converging phases,            ├─ config‑tune  (bounded, allow‑listed)
  reviewer skew, recurring           ├─ template‑route (fork a specialist)
  themes, ineffective tunes)         └─ escalate
        ▲                                   │ applies a tune
        │ feeds back                        ▼
        └──────── auto‑revert watch ◄── consensus‑aggregator
                  (next round worse? restore snapshot + cooldown)
```

> Notes: This is the differentiator slide for a technical audience. The loop is: observe → recommend → (optionally) act within bounds → measure the next round → undo if it regressed → remember the regression. Walk the arrows; this is real control theory, not a buzzword.

---

# Safety rails on autonomy

- **Off by default.** Auto‑apply is opt‑in and only touches an **allow‑listed** set of config keys — never source, never templates.
- **Re‑validated.** Every tune passes the Zod `EngineConfigSchema` gate + a `maxRelativeStep` clamp before it lands.
- **Snapshotted + watched.** A tune snapshots config and arms a watch; if the next round's agreement drops past `regressionDelta`, it **auto‑reverts** and arms a cooldown.
- **Self‑demoting.** A key that reverts too often (≥ `demoteAfterReverts`) is dropped back to propose‑only.
- **Transactional.** Multi‑key runs revert/hold as one atomic set.

> Notes: This is where you defuse the "autonomous AI editing config" fear. Every adjective here — bounded, allow‑listed, re‑validated, snapshotted, auto‑reverting, self‑demoting, transactional — is a deliberate guardrail. None of it is hand‑wavy.

---

# Cross‑project learning — privacy by construction

- Opt‑in (`globalLearning.enabled`, default **off**).
- Mirrors only `{ key, outcome, phase, projectHash }` to `~/.vibeflow/global-learning.jsonl`.
- `projectHash` is a **one‑way SHA‑256** — no code, no content, no file names, no themes ever leave the project.
- A `cross-project-signal` detector aggregates hold‑rates across ≥ 3 distinct projects and **recommends** — it never auto‑allow‑lists or auto‑applies.

> Notes: Privacy isn't a policy here, it's the data model — the only fields that exist are non‑sensitive. Make the point that even with the feature on, an attacker reading the global file learns nothing about your code.

---

# Observability of the loop

- `loop-audit.sh` — a read‑only, fully‑guarded reader that consolidates every loop surface into one JSON document.
- Feeds two surfaces: `/vibeflow:status` (quick inline glance) and `/vibeflow:loop-status` (full dashboard + durable `.vibeflow/reports/loop-status.md`).
- Surfaces per‑key revert rates (flags `revertRate ≥ 0.5` removal candidates), cooldowns, armed watches, phase‑runner progress, and the cross‑project signal.

> Notes: You can't run an autonomous loop you can't see. This is the pane of glass — and it's read‑only, so observing never mutates. Every absent file degrades to nulls, so a fresh project never errors.

---

# Quality engineering

- **2,943 automated tests across 30 layers**, green on every release.
- Unit (vitest, 5 servers) + hook tests (bash) + integration (bash/node) + per‑sprint regression harnesses.
- Cross‑process/file‑race regression tests (5‑process lock, 50‑concurrent‑writer).
- Schema round‑trips, config default/partial‑merge/range‑rejection tests for every config schema.
- Offline / network‑failure / large‑input / output‑budget sentinels.

> Notes: This slide answers "is it tested?" with a number and a taxonomy. The race and config‑schema tests show the team tests the *hard* things, not just the happy path.

---

# Extending VibeFlow

- **New skill:** `skills/<name>/SKILL.md` (YAML frontmatter: `name` + `description`) — prose + bash, no build step.
- **New sub‑agent:** `agents/<name>.md`.
- **New hook:** `hooks/scripts/<name>.sh` sourcing `_lib.sh`; wire in `hooks.json`.
- **New MCP tool:** add to `mcp-servers/<server>/src`, Zod‑validate input, add tests, `npm run build`.
- **Phase policy:** register write boundaries in `skills/phase-policy.json`.

> Notes: The extension story matters to a technical buyer who wants to adapt it. The headline: skills/agents are just Markdown — most customization needs no compilation and no platform knowledge.

---

# Summary

- A **full‑SDLC governance layer** built entirely from Claude Code primitives.
- **Multi‑AI consensus** with iterative convergence, dedup, and explicit human escalation.
- **File‑backed, event‑sourced, Git‑versioned** state — zero‑ops, fully auditable.
- A **bounded, self‑reverting autonomous loop** with privacy‑safe cross‑project learning.
- **~3,000 tests / 30 layers** — engineered, not improvised.

**Deterministic where it must be, intelligent where it helps.**

> Notes: Land on the closing line. The whole pitch in one sentence: determinism for trust, intelligence for leverage — and the architecture keeps them in their lanes.
