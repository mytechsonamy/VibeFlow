# VibeFlow

> **Governed, multi-AI software delivery for Claude Code.**
> Requirements to release as a single, auditable, self-improving loop.

![version](https://img.shields.io/badge/version-v2.39.0-blue)
![tests](https://img.shields.io/badge/tests-3%2C000%2B%20across%2032%20layers-brightgreen)
![state](https://img.shields.io/badge/state-filesystem%20%C2%B7%20event--sourced-informational)
![runtime](https://img.shields.io/badge/runtime-Claude%20Code%20plugin-8A2BE2)
![license](https://img.shields.io/badge/license-Apache--2.0-lightgrey)

---

Most AI coding tools stop at *generate code*. VibeFlow governs the **whole**
delivery lifecycle — requirements through deployment — as one orchestrated,
auditable loop, and adds the three things teams actually need before they
trust AI in delivery:

- **Truth-validated requirements** — every requirement is scored for
  testability; specs that can't be tested *block* the build at the source,
  where defects are cheapest to kill.
- **Multi-AI consensus review** — critical artifacts (the PRD, the
  architecture, the release decision) are cross-checked by **Claude +
  ChatGPT + Gemini** until they reach a quorum, or the system escalates to a
  human. No silent passes.
- **Risk-proportional quality gates** — the release bar is tuned to the
  domain's risk (healthcare ≥ 95, financial ≥ 90, e-commerce ≥ 85, general
  ≥ 80), so a marketing site and a payments core aren't held to the same
  standard.

It runs **entirely on your own machine** as a Claude Code plugin. All durable
state is plain files in your Git repo — no server, no database, no telemetry.
And it **learns from its own history to improve over time**, with strict
safety rails that auto-revert any change that makes outcomes worse.

> This repository is the reference implementation — a working, hardened
> demonstration of what a governed AI-orchestrated SDLC looks like when it is
> engineered rather than improvised.

---

## Why it exists

The bottleneck in software has moved from *writing* code to *trusting* it.
AI can produce a great deal of plausible code, quickly — and that is exactly
the danger. An ambiguous PRD yields confident code that solves the wrong
problem; a single model is confidently wrong with no second opinion and no
record of *why* a decision was made; quality scrutiny bolted on at the end
surfaces problems when they are most expensive to fix.

VibeFlow is an opinion about how to close that gap: **deterministic where it
must be, intelligent where it helps** — and the architecture keeps the two
in their lanes.

## The four principles

1. **Truth-driven** — requirements are the source of truth; untestable
   requirements gate development.
2. **Consensus-based** — multiple AIs review critical work and must converge;
   disagreement escalates to a person, never passes silently.
3. **Quality-gated** — automated, risk-proportional gates at every phase
   boundary; nothing advances on a hunch.
4. **Self-improving — safely** — the system mines its own review history and
   auto-tunes within strict, allow-listed bounds, reverting anything that
   regresses.

## The seven governed phases

Each phase boundary is a **gate** with machine-checked exit criteria;
`/vibeflow:advance` refuses to move on until they are satisfied.

| Phase | What VibeFlow guarantees |
|---|---|
| 1 · Requirements | Testability scored; ambiguity flagged; `score < 60` blocks the build |
| 2 · Design | Wireframes, design tokens, accessibility checks |
| 3 · Architecture | Decision records (ADRs), 3-AI vote |
| 4 · Planning | Epic breakdown, dependency graph, test strategy |
| 5 · Development | Quality gates on every commit |
| 6 · Testing | Coverage, mutation testing, chaos injection |
| 7 · Deployment | GO / CONDITIONAL / BLOCKED release decision + rollback |

## Architecture at a glance

VibeFlow is built **entirely from Claude Code native primitives** — skills,
sub-agents, hooks, and MCP servers — with no separate server process and no
database. Four layers, each with a deliberate job:

| Layer | Primitive | Responsibility |
|---|---|---|
| Orchestration | **Skills** (prose + bash) | Phase walks, consensus loops, operator commands |
| Specialization | **Sub-agents** | Deep artifact rewrites & reviews in isolated context |
| Enforcement | **Hooks** | Gate writes, run consensus, persist & restore state |
| Computation | **MCP servers** (TypeScript + Zod) | State transitions, validation, analysis, integrations |

All durable state lives in your repo:

```
.vibeflow/state/<project>/
  project.json   # rollup: current phase, satisfied criteria, metrics
  events/        # append-only log of every transition
  archive/       # per-phase snapshots
.vibeflow/state/consensus/history.jsonl
```

Because state is text, **Git is the time machine** — you diff it, blame it,
branch it, and review it like any other artifact. `bin/replay-events.sh`
reconstructs `project.json` byte-for-byte from the event log.

### The five MCP servers

| Server | Surface | Tests |
|---|---|---|
| `sdlc-engine` | phase state machine, consensus recording, exit criteria, config schemas | 199 |
| `codebase-intel` | structure analysis, dependency graph, hotspots, tech-debt scan | 48 |
| `design-bridge` | Figma fetch, design-token extraction, style generation, impl comparison | 57 |
| `dev-ops` | GitHub + GitLab clients, pipelines, deploy/rollback | 72 |
| `observability` | metric collection, flaky-test tracking, perf trend, health dashboard | 76 |

Every server is TypeScript with Zod-validated inputs and an enforced
80/80/80/80 coverage threshold.

## How consensus works

1. An analysis skill produces an artifact and writes a **consensus-needed
   marker** naming the primary artifact (the PRD itself, not a summary).
2. A PreToolUse hook (`consensus-gate.sh`) blocks further tool calls until
   consensus runs — the loop **cannot be skipped**.
3. The orchestrator forks the available reviewers (claude-reviewer + the
   `codex` and `gemini` CLIs *if present on PATH* — graceful degradation),
   feeds each the primary artifact, and collects verdicts.
4. Verdicts are aggregated into an agreement score; critical findings are
   deduplicated so three reviewers flagging one line counts once.

**Thresholds:** `APPROVED` (≥ 90% agreement, 0 critical) ·
`NEEDS_REVISION` (50–89%) · `REJECTED` (< 50% or ≥ 2 critical).
When not approved, a phase specialist rewrites the artifact as a diff-first
patch and the next round runs automatically. Out of rounds without approval
⇒ `HUMAN_APPROVAL_REQUIRED` — an explicit pass-with-audit, never a silent
pass. Every verdict is appended to `consensus/history.jsonl`.

## The autonomous learning loop

VibeFlow observes its own consensus history, mines it for recurring problems
and slow-converging phases, and can act on what it learns — **within hard
safety bounds**:

- **Off by default.** Auto-apply is opt-in and only touches an
  **allow-listed** set of config keys — never source, never templates.
- **Re-validated & clamped.** Every tune passes the Zod config schema and a
  `maxRelativeStep` clamp before it lands.
- **Snapshotted & watched.** A tune arms a watch; if the next round's
  agreement regresses, it **auto-reverts** and arms a cooldown.
- **Self-demoting.** A key that reverts too often drops back to propose-only.
- **Transactional.** Multi-key runs revert or hold as one atomic set.

Optional cross-project learning shares only `{ key, outcome, phase,
projectHash }` — `projectHash` is a one-way SHA-256. **No source, content,
file names, or themes ever leave the project.**

## Quality engineering

**2,943 automated tests across 30 layers**, kept green on every release:
unit (vitest, five servers) + hook tests (bash) + integration harnesses +
per-sprint regression suites, plus cross-process file-lock and
50-concurrent-writer races, config-schema round-trips, and
offline/network-failure/large-input sentinels.

## Getting started

VibeFlow installs as a **Claude Code plugin** — minutes, no infrastructure.
The MCP servers ship pre-bundled, so there's nothing to build.

**Install (inside a Claude Code session):**

```
/plugin marketplace add github:mytechsonamy/VibeFlow
/plugin install vibeflow@vibeflow
```

> Using the interactive `/plugin` menu instead? In the **Add Marketplace**
> field enter `mytechsonamy/VibeFlow` (bare `owner/repo` — **no `github:`
> prefix**, the menu rejects it); the `github:` form is only for the slash
> command above.

Then **restart Claude Code** and verify with `/vibeflow:flow-status` (it
should report "project not initialized"). Start your first project with:

```
/vibeflow:onboard
```

**Prerequisites:** Claude Code, Node 18+, Git, and **`jq`** (the hooks need
it). For multi-AI consensus install at least one of the **`codex`** / **`gemini`**
CLIs (authenticated). Optional: a Figma token (DESIGN) and a GitHub/GitLab
token (DEPLOYMENT) — these integrations activate only when present.

Full walkthrough: [`docs/GETTING-STARTED.md`](docs/GETTING-STARTED.md).
Developing the plugin itself? Clone it and run with
`claude --plugin-dir ./` (see GETTING-STARTED, Option B).

> A runnable demo lives in [`examples/demo-app`](examples/demo-app).

## Documentation

- **Presentation kit** — executive & technical decks + briefs:
  [`docs/presentation/`](docs/presentation/)
- **Consensus flow** — [`docs/CONSENSUS-FLOW.md`](docs/CONSENSUS-FLOW.md)
- **Learning loop** — [`docs/LEARNING-LOOP.md`](docs/LEARNING-LOOP.md)
- **Auto-apply & safety rails** — [`docs/AUTO-APPLY.md`](docs/AUTO-APPLY.md)
- **Cross-project learning** — [`docs/CROSS-PROJECT-LEARNING.md`](docs/CROSS-PROJECT-LEARNING.md)
- **Roadmap** — [`ROADMAP.md`](ROADMAP.md)

## Status & scope

- **v2.26.0** — 38 engineering sprints; the autonomous-learning arc is
  feature-complete, plus guided DESIGN + ARCHITECTURE phases (Figma /
  Claude-native design, ADR authoring) and a hardened consensus pipeline.
- This is a **governance layer and a reference architecture**, not a SaaS
  product. It is a plugin: your machines, your files, your Git.
- It depends on the Claude Code runtime and, for non-Claude reviewers, on
  external CLIs — by design.

## License

Released under the **Apache License 2.0**. See [`LICENSE`](LICENSE).

## Author

Built by **Mustafa Yıldırım** — a technology leader with 25+ years in core
banking, payment infrastructure, and regulated fintech, exploring how
AI-orchestrated delivery can be made *governable* for high-stakes domains.

*If VibeFlow is useful to you, a ⭐ helps others find it.*
