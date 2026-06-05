# VibeFlow — Technical Brief

> A leave‑behind companion to the technical deck. Reading time ≈ 12 minutes.
> Audience: architects, staff/principal engineers, technical evaluators.
> Version: v2.18.0.

---

## 1. What VibeFlow is, architecturally

VibeFlow is a **Claude Code plugin** that implements a governed,
seven‑phase software delivery lifecycle. It is built **entirely from
Claude Code native primitives** — skills, sub‑agents, hooks, and MCP
servers — with **no separate server process and no database**. All durable
state is plain files inside the project's repo, which makes Git the system
of record for both code *and* delivery state.

The architecture deliberately separates concerns across four layers:

- **Orchestration — Skills (prose + bash).** Operator‑facing commands and
  the control flow of phase walks and consensus loops. Readable and
  editable without a build step.
- **Specialization — Sub‑agents.** Forked, isolated‑context agents that
  perform deep artifact rewrites or focused reviews.
- **Enforcement — Hooks.** Deterministic glue that runs in the host (not
  the model): gating writes, blocking progress until consensus runs,
  persisting state, restoring context.
- **Computation — MCP servers (TypeScript + Zod).** Typed, tested logic
  for state transitions, validation, analysis, and external integrations.

The guiding split: **prose+bash where humans need to read and change the
flow; typed TypeScript where correctness and tests matter; hooks where the
model must not be allowed to route around a rule.**

---

## 2. State model — file‑backed and event‑sourced

```
.vibeflow/state/<project>/
  project.json   # rollup: current phase, satisfied criteria, metrics
  events/        # append-only log of every transition
  archive/       # per-phase snapshots
.vibeflow/reports/*.md
.vibeflow/state/consensus/history.jsonl
```

Key properties:

- **Single filesystem backend.** A v2.0 breaking change retired the
  earlier SQLite/Postgres backends in favor of files only — for
  portability, zero operations, and free auditability.
- **Event‑sourced and rebuildable.** `bin/replay-events.sh` reconstructs
  `project.json` byte‑for‑byte from the event log plus archives;
  `bin/migrate-state-db-to-fs.sh` covers legacy migration.
- **Concurrency‑safe.** File locking is exercised by regression tests
  including a five‑process cross‑process lock test and a fifty‑concurrent‑
  writer test.
- **Git is the time machine.** Because state is text files, you diff it,
  blame it, branch it, and review it like any other artifact.

---

## 3. The seven phases and their gates

Requirements → Design → Architecture → Planning → Development → Testing →
Deployment. Each phase declares **machine‑checked exit criteria** as
enums; `/vibeflow:advance` evaluates them via the engine and refuses to
advance until they are satisfied. Examples:

| Phase | Representative criteria |
|---|---|
| Requirements | `testability.score ≥ 60`, `prd.approved`, `consensus.requirements.approved` |
| Architecture | `adr.recorded`, `consensus.architecture.approved` |
| Development | `code.reviewed`, `quality.gates.passed` |
| Testing | `coverage.met`, `mutation.score.acceptable` |
| Deployment | `release.decision.go`, `deployment.verified`, `health.checks.passed` |

Many criteria are **auto‑satisfied** by the relevant analyzer skill: the
PRD analyzer satisfies `prd.approved`/`testability.score`, the
coverage analyzer satisfies `coverage.met`, the release‑decision engine
satisfies `release.decision.go` on a GO verdict, and so on. A small set of
human‑judgement criteria (`design.approved`, `accessibility.verified`,
`sprint.planned`) are intentionally kept operator‑driven.

Phase boundaries are also **write‑enforced**: `phase-write-guard.sh`
(a PreToolUse hook) consults `phase-policy.json` and blocks file writes
that violate the current phase's allowed paths, with an explicit escape
hatch for deliberate overrides.

---

## 4. Multi‑AI consensus — how it actually works

Consensus is the mechanism that replaces "one model's opinion" with a
reviewed, auditable verdict. The flow:

1. **Marker.** An analysis skill produces its artifact and writes a
   `consensus-needed` marker naming the **primary artifact** (e.g. the PRD
   itself) plus an `evidence[]` list — not a summary of the artifact, the
   artifact.
2. **Gate.** `consensus-gate.sh` (PreToolUse) blocks subsequent
   `Bash`/`Write`/`Edit` calls until consensus runs. This is what makes
   consensus **non‑optional** even though the model is otherwise free to
   choose its actions.
3. **Fan‑out.** The orchestrator forks the available reviewers —
   `claude-reviewer` plus the `codex` and `gemini` CLIs **if present on
   PATH** (graceful degradation; it never hard‑fails on a missing CLI) —
   and feeds each the primary artifact. Large primaries are **semantically
   excerpted** (sections scored by evidence‑finding density, reviewer‑
   memory hits, and keyword overlap, always keeping the first section,
   falling back to positional head/tail).
4. **Aggregate.** Verdicts are combined into an agreement score; critical
   findings are **deduplicated** by `{file, line_range}` and by Jaccard
   similarity of titles so three reviewers flagging one line counts once.

**Outcome thresholds:** `APPROVED` (≥ 90% agreement, 0 critical),
`NEEDS_REVISION` (50–89%), `REJECTED` (< 50% or ≥ 2 critical).

**Convergence.** When not approved, a **phase specialist** rewrites the
artifact as a single diff‑first patch and the next round runs
automatically (orchestrator → specialist → `apply-arbiter-patch` →
re‑run). A `maxIterations` ceiling and a convergence‑stall guard bound the
loop. If rounds are exhausted without approval, the status becomes
`HUMAN_APPROVAL_REQUIRED` — an explicit pass‑with‑audit that escalates to
a person rather than passing silently.

Every verdict and arbiter decision is appended to
`consensus/history.jsonl` (idempotent by `{sessionId, round}`), which is
both the audit trail and the input to the learning loop (§7).

---

## 5. Diff‑first specialists and reversible application

The six phase specialists (PRD rewriter, design‑spec refiner, ADR author,
test‑strategy refiner, coverage‑gap filler, runbook editor) **never write
to source files directly.** They emit a unified diff under
`.vibeflow/state/patches/…`. The `apply-arbiter-patch` skill applies it
with a **preview and explicit confirmation**, and supports `--dry-run` and
`--run-tests`. The result: every AI‑authored change to your tree is
reviewable and reversible before it lands.

---

## 6. The five MCP servers

| Server | Responsibility | Tests |
|---|---|---|
| `sdlc-engine` | phase state machine, consensus recording, exit criteria, all config schemas | 199 |
| `codebase-intel` | structure analysis, dependency graph, hotspots, tech‑debt scan | 48 |
| `design-bridge` | Figma fetch, design‑token extraction, style generation, impl comparison | 57 |
| `dev-ops` | GitHub + GitLab (SaaS and self‑hosted) clients, pipelines, deploy/rollback | 72 |
| `observability` | metric collection, flaky‑test tracking, perf trend, health dashboard | 76 |

Every server is TypeScript with **Zod‑validated tool inputs** and an
enforced **80/80/80/80 coverage threshold**. Status values are always
enums (e.g. `ConsensusStatus.REJECTED`), never string literals — a
convention the tests pin.

---

## 7. The autonomous learning loop (L3)

This is the part most tools do not attempt: VibeFlow learns from its own
review history and can act on what it learns, **within hard safety
bounds**.

1. **Observe.** `consensus-aggregator.sh` appends durable verdict and
   arbiter‑decision rows to `history.jsonl`.
2. **Mine.** `learning-loop-engine` (consensus‑history mode) detects
   slow‑converging phases, reviewer skew, recurring suggestion themes,
   convergence stalls, primary‑artifact churn, ineffective arbiter
   decisions, and ineffective auto‑tunes.
3. **Act.** `learning-apply` turns findings into action across three lanes:
   - **config‑tune** — a diff‑first patch to `vibeflow.config.json`,
     applied only after the schema re‑validation gate;
   - **template‑route** — fork the appropriate phase specialist on a
     recurring theme;
   - **escalate** — hand off to `decision-recommender`.
4. **Measure & undo.** A bounded **auto‑apply** can land an allow‑listed
   tune, arming a **watch**; if the next round's agreement regresses past
   `regressionDelta`, the aggregator **auto‑reverts** the snapshot and
   arms a cooldown.
5. **Remember.** A key that reverts too often is **self‑demoted** to
   propose‑only; an `auto-tune-ineffective` detector recommends removing it
   from the allow‑list.

### Safety rails (why this is acceptable)

- Auto‑apply is **off by default** and only touches an **allow‑listed** set
  of config keys — never source, never templates.
- Each tune is re‑validated against `EngineConfigSchema`, clamped by
  `maxRelativeStep`, and floored by `minObservations`.
- Changes are **snapshotted**, **auto‑reverting**, **self‑demoting**, and
  **transactional** (multi‑key runs revert/hold as one atomic set).
- Templates stay confirm‑only by design, because large rewrites are not
  mechanically revertible the way a numeric config delta is.

### Cross‑project learning — privacy by construction

Opt‑in (`globalLearning.enabled`, default off). When enabled, only
`{ key, outcome, phase, projectHash }` is mirrored to
`~/.vibeflow/global-learning.jsonl`, where `projectHash` is a one‑way
SHA‑256. **No source, content, file names, or themes ever leave the
project.** The `cross-project-signal` detector aggregates hold‑rates across
≥ 3 distinct projects and only *recommends*; it never auto‑allow‑lists or
auto‑applies.

---

## 8. Reviewer memory and excerption

To stop reviewers re‑litigating settled points, VibeFlow keeps a
cross‑session **reviewer memory** (`reviewer-memory/<reviewer>.jsonl`,
capped per reviewer+artifact). Each reviewer's prompt is prefixed with a
`PRIOR REVIEW MEMORY` block. Past the cap, entries fold into a per‑artifact
recurrence summary (theme‑aware compaction with `seenCount` via Jaccard
match), and the orchestrator surfaces recurring criticals first. Combined
with semantic excerption of large primaries, this keeps each review round
focused and within a token budget.

---

## 9. Observability

`loop-audit.sh` is a read‑only, fully‑guarded reader that consolidates the
scattered loop telemetry — auto‑apply outcomes, per‑key revert rates,
cooldown markers, the armed watch, learning findings, recent decisions,
phase‑runner progress, and the cross‑project signal — into one JSON
document. It feeds two surfaces:

- `/vibeflow:flow-status` — a quick inline "Autonomous Loop" glance.
- `/vibeflow:loop-status` — the full dashboard, which also writes a
  durable `.vibeflow/reports/loop-status.md`. It flags keys at
  `revertRate ≥ 0.5` as removal candidates and surfaces the cross‑project
  signal as a recommendation only.

Every absent input degrades to nulls/zeros, so a fresh project never
errors and `/vibeflow:flow-status` is unaffected by the extra fields.

---

## 10. Quality engineering

VibeFlow is validated by **2,943 automated tests across 30 layers**, kept
green on every release:

- **Unit (vitest):** the five MCP servers (199 + 48 + 57 + 72 + 76), each
  at the 80% coverage threshold.
- **Hook tests (bash):** 185 assertions over every hook and the shared
  `_lib.sh`, bash 3.2‑compatible.
- **Integration (bash/node):** a platform baseline (399) plus a per‑sprint
  regression harness for each of the 30 sprints.
- **Hard‑path coverage:** cross‑process file‑lock and 50‑concurrent‑writer
  races; config‑schema default/partial‑merge/range‑rejection round‑trips;
  offline/network‑failure/large‑input/output‑budget sentinels.

---

## 11. Extensibility & operations

- **Skills and sub‑agents are Markdown** — add a `SKILL.md` (with `name` +
  `description` frontmatter) or an `agents/<name>.md`; no build step.
- **Hooks** are bash sourcing `_lib.sh`, wired in `hooks.json`.
- **MCP tools** are TypeScript with Zod‑validated input and tests
  (`npm run build`).
- **Config** is a single `vibeflow.config.json`, every section backed by a
  Zod schema with safe defaults, partial‑merge, and range validation.
- **Install** is a Claude Code marketplace/plugin install — minutes, no
  infrastructure. Optional integrations (Figma, GitHub/GitLab) activate
  only when their tokens are present.

---

## 12. Boundaries and deliberate non‑goals

- **No embedding/vector dependency.** Excerption and memory matching use
  lexical scoring (Jaccard + finding density) on purpose; adopting an
  embeddings dependency would trade away the deterministic / no‑external‑
  dependency posture. This is a documented non‑goal, not a backlog item.
- **No redrawing terminal TUI.** Skills are prose+bash; the consolidated
  dashboard plus a written report is the realistic surface.
- **Consensus depends on external CLIs being present** for the non‑Claude
  reviewers; it degrades gracefully to whichever are on PATH rather than
  failing.

---

## Appendix — fast facts

- Version **v2.18.0**, 30 sprints, autonomous‑loop arc feature‑complete.
- **7** SDLC phases · **40+** skills · **9** sub‑agents · **5** MCP servers.
- Consensus reviewers: **Claude + ChatGPT (codex) + Gemini**, PATH‑gated.
- State: **filesystem only**, event‑sourced, Git‑versioned, replayable.
- Tests: **2,943 across 30 layers**.
- Domain release bars: Healthcare ≥ 95 · Financial ≥ 90 · E‑commerce ≥ 85
  · General ≥ 80.
