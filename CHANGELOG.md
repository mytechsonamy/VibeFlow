# Changelog

All notable changes to VibeFlow are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [2.20.2] — 2026-06-06

### Fixed
- **Reviewer rationale silently dropped when codex/gemini wrap their verdict
  JSON in prose or a ```` ```json ```` fence** (the FlowBridge / AntOS
  "codex gives NEEDS_REVISION with no rationale → specialist→apply runs
  blind → consensus never converges" trap). `append_cli_verdict` parsed the
  verdict by running `fromjson` over the CLI's **whole** stdout, so any
  surrounding prose/markdown made the parse fail — collapsing a structured
  dissent (with `criticalIssues` + `suggestions`) into a bare keyword-grep
  `NEEDS_REVISION` with empty rationale. New `vf_extract_json` helper unwraps
  the JSON first (whole output → strip code fences → first-`{`…last-`}` span),
  so the reviewer's actual findings + suggestions now flow into the jsonl →
  reviewer-memory → the specialist that has to act on them. Fixed in
  `consensus-run.sh` (headless) and the `consensus-orchestrator` prose
  (interactive 3-AI). Pinned by `tests/integration/sprint-31.sh [S31-C]`
  (static + a runtime probe feeding fenced+prose codex output → asserts
  `suggestions`/`criticalItems` are captured). Pure-prose replies still fall
  back to keyword-grep classification; pure-JSON replies are unchanged.

---

## [2.20.1] — 2026-06-06

### Fixed
- **`apply-arbiter-patch` had no rollback safety net off git.** Its entire
  revert story was `git checkout HEAD -- <file>`, which only works when the
  project is a git repo *and* the target file is committed. Projects in
  REQUIREMENTS are often just a PRD with no repo yet, so applying a
  specialist patch rewrote the artifact in place with no way back. The skill
  now **snapshots every target file to `.vibeflow/state/arbiter-backups/<session>/`
  before the first `git apply`** (new Step 3.5) and prints the
  git-independent restore command (`cp -R .vibeflow/state/arbiter-backups/<session>/. .`).
  The snapshot is the primary rollback path; `git checkout` stays as the
  secondary path for committed git repos. Pinned by
  `tests/integration/sprint-15.sh [S15-G]`.

---

## [2.20.0] — 2026-06-06

Built-in command-collision audit + the second (and last) rename it found.

### Changed
- **BREAKING (command rename): `/vibeflow:status` → `/vibeflow:flow-status`.**
  A full audit of all 41 VibeFlow skills against Claude Code's built-in
  slash commands found exactly one remaining exact collision after the
  v2.19.0 `init`→`onboard` rename: `status` shadowed the built-in `/status`
  (usage/quota), so typing `/status` surfaced VibeFlow's skill. Renamed, no
  shim. `loop-status` was reviewed and kept (distinct name; `/loop` matches
  the built-in exactly, only a fuzzy-search edge surfaces it).

### Fixed
- **Stale `/vibeflow:review` Key Command** in CLAUDE.md — no such skill
  exists; replaced with `/vibeflow:consensus-orchestrator` (the real
  multi-AI review trigger).

### Audit result
- 41 skills × Claude Code built-ins → after this rename, **zero exact
  collisions remain**. The audit is captured in `docs/COMMAND-COLLISIONS.md`.

---

## [2.19.0] — 2026-06-06

Sprint 31 — onboarding clarity + a `phase-runner` that really runs.
Triggered by a real first-run session that hit two papercuts and the
contradiction beneath them.

### Changed
- **BREAKING (command rename): `/vibeflow:init` → `/vibeflow:onboard`.**
  VibeFlow's bootstrap skill collided with Claude Code's built-in `/init`.
  Renamed, no deprecation shim (a shim would re-create the collision).
  Update muscle memory / scripts. Behaviour otherwise identical.
- **`phase-runner` drives consensus headlessly instead of deadlocking.**
  It no longer claims to fork the `disable-model-invocation` consensus
  chain (which is impossible). It now calls the new
  `hooks/scripts/consensus-run.sh` as plain Bash → a real `verdict.json`
  → records consensus + auto-advances on APPROVED, or stops with an honest
  operator breadcrumb on NEEDS_REVISION/REJECTED.

### Added
- **`hooks/scripts/consensus-run.sh`** — headless equivalent of the
  orchestrator's codex/gemini pipeline; finalises a real verdict via the
  new `consensus-aggregator.sh --finalize` mode (no 600s quorum stall),
  drains `consensus-needed.json`.
- **`consensus-aggregator.sh --finalize <session> <round>`** — additive
  mode that computes `verdict.json` from existing reviewer lines without
  the SubagentStop stdin ingest or quorum wait. The normal SubagentStop
  path is byte-identical.
- **`▶ Next:` breadcrumb convention** on `onboard`, `prd-quality-analyzer`,
  and `phase-runner` — the next command is always the last output line.
- **`consensus-gate.sh`** allowlists `consensus-run.sh` (it is the drain).
- New `docs/ONBOARDING.md`; `docs/PHASE-BOUNDARIES.md` + the
  consensus-orchestrator skill note the interactive-vs-headless split.

### Fixed
- **`vf_run_timeout` pure-bash watchdog 90s hang** (latent since Sprint
  26-F; hit on macOS, which ships no `timeout`/`gtimeout`). The backgrounded
  watchdog subshell inherited the `CMD="$( … | vf_run_timeout … )"` capture
  pipe, so `$( … )` blocked for the full timeout **after** the reviewer CLI
  had already returned — every headless consensus run looked hung for
  ~90s/CLI. The watchdog now redirects its fds to `/dev/null` (drops the
  pipe), `disown`s itself (no "Terminated" job notice), and reaps its
  `sleep` child. Fixed in both `consensus-run.sh` and the
  `consensus-orchestrator` prose.
- **`set -e` leak aborting consensus-run on the first reviewer error.**
  `_lib.sh` declares `set -euo pipefail`, so sourcing it turned errexit ON
  inside `consensus-run.sh`; a single reviewer CLI exiting non-zero (e.g. a
  bad model id) aborted the whole run at `OUT="$(codex …)"` — before the rc
  was read — so the error handling never fired and no verdict was produced.
  consensus-run now `set +e`s after sourcing.
- **Stale, account-incompatible default models.** The hardcoded defaults
  `gpt-4o` / `gemini-2.0-flash` silently failed on accounts/CLIs that don't
  accept them (codex runs on the operator's ChatGPT login). Now: when
  `models.openai` / `models.gemini` is `"default"` / empty / unset,
  consensus-run **omits** `-m` / `--model` and lets each CLI use its own
  configured model. `onboard`'s template ships `"default"`. Pin a concrete
  id only to override. A reviewer CLI that errors is now **warned loudly**
  (naming the model + the config key) and **skipped** — no longer recorded
  as a phantom `REJECTED` vote that poisons the panel; if every CLI errors,
  consensus-run exits 3 with the fix instructions instead of a silent bad
  verdict. consensus-run also surfaces the aggregator's stderr if no
  `verdict.json` is produced.

### Unchanged
- The interactive `/vibeflow:consensus-orchestrator` (full 3-AI panel +
  iteration) and the SubagentStop aggregator path are untouched; all
  existing consensus suites stay green.

---

## [2.18.0] — 2026-06-05

Sprint 30 (backlog B4) — the **loop-status dashboard**, and the capstone
of the autonomous-loop arc. Sprints 20–29 built a deep loop whose state
was scattered across half a dozen files; v2.18.0 gives it one pane of
glass.

- **Reader extension (S30-A).** `hooks/scripts/loop-audit.sh` gains two
  sections: `phaseRunner` (from the Sprint-21 progress ledger) and
  `crossProject` (from the Sprint-28 global store, only when
  `globalLearning.enabled`). Both `null` when absent — `/vibeflow:status`'
  Autonomous Loop section is byte-for-byte unchanged.
- **New skill (S30-B).** `/vibeflow:loop-status` — a read-only dashboard
  that consolidates phase-runner progress + auto-apply tally/revert-rates
  + cooldowns + armed watch + learning findings + the cross-project
  signal into one view, flags `revertRate ≥ 0.5` removal candidates,
  surfaces cross-project as a recommendation only, collapses to one idle
  line when nothing has looped, and writes a durable
  `.vibeflow/reports/loop-status.md` audit. Registered in
  `phase-policy.json` (ALL, read-only).
- **Docs (S30-C).** New `docs/LOOP-STATUS.md`; `docs/LOOP-AUDIT.md`
  refreshed (the reader now feeds two surfaces).

Skill + hook only (no engine change). Tests: new `sprint-30.sh` (58),
`hooks/tests/run.sh` 174 → 185 (+11). Total baseline 2874 → 2943 across
30 test layers. **Backlog B4 done — B1/B2/B4/B5 all shipped; the
autonomous-loop arc is feature-complete. B3 (embedding excerption)
remains a deliberate non-goal.**

---

## [2.17.0] — 2026-06-05

Sprint 29 (backlog B5) — phase-runner TESTING auto-run. TESTING was the
one phase that wasn't a one-command walk, because `coverage-analyzer`
parses an existing coverage JSON rather than producing it.

- **Generate step (S29-A).** `phase-runner` Step 2a (TESTING only) runs
  the project's coverage command before forking the analyzers — resolved
  from `tech.coverageCommand` or defaulted by `tech.testRunner` (vitest →
  `npx vitest run --coverage`, jest, pytest, dotnet). Recorded as
  `generate:coverage` in the progress ledger; `allowed-tools` gains the
  runner binaries.
- **Safe by default (S29-B).** Best-effort (a missing/failing command
  logs + continues so coverage-analyzer surfaces the gap); `--no-generate`
  / `VF_SKIP_GENERATE=1` opt-out; runs **only** in TESTING (other phase
  walks unchanged).

Skill-only sprint (no engine change). Docs: `docs/TESTING-READINESS.md`
refresh. Tests: new `sprint-29.sh` (34). Total baseline 2840 → 2874.
**Backlog B5 done.**

- `.claude-plugin/plugin.json`: 2.16.0 → 2.17.0

---

## [2.16.0] — 2026-06-05

Sprint 28 (backlog B2) — cross-project meta-learning, opt-in /
privacy-safe / read-only.

- **Config + helpers (S28-A).** New `GlobalLearningConfigSchema`
  `{ enabled: false }` (default off); `_lib.sh` `vf_global_dir()`
  (`$HOME/.vibeflow`, overridable via `VIBEFLOW_GLOBAL_DIR`) +
  `vf_project_hash()` (one-way sha256, first 12 chars).
- **Global-store writes (S28-B).** When `globalLearning.enabled`,
  `consensus-aggregator.sh` (reverted/held) and `learning-apply`
  (applied) mirror **only** `{key, outcome, phase, projectHash}` to
  `global-learning.jsonl` — never code/content/file names/themes. Off ⇒
  nothing leaves the project.
- **Detector (S28-C).** `learning-loop-engine` consensus-history mode
  gains `cross-project-signal` (`LEARNING-CROSS-PROJECT-SIGNAL`): per-key
  hold-rate across ≥ 3 distinct projects → a **read-only** recommendation
  (≥ 0.7 allowlist / ≤ 0.3 avoid); never auto-allowlists.
  `patternCatalogVersion` → 4.

Docs: `docs/CROSS-PROJECT-LEARNING.md` + META-LEARNING refresh. Tests:
sdlc-engine 196→199, hooks 167→174, new `sprint-28.sh` (44). Total
baseline 2786 → 2840. **Backlog B2 done.**

- `.claude-plugin/plugin.json`: 2.15.0 → 2.16.0
- `@vibeflow/sdlc-engine`: 1.13.0 → 1.14.0

---

## [2.15.0] — 2026-06-05

Sprint 27 (backlog B1) — template-route autonomy, propose-only. The
learning loop's template lane was manual; v2.15.0 auto-forks the
specialist on a recurring-theme finding.

- **Config (S27-A).** `LearningApplyConfigSchema` += `autoForkSpecialist`
  (default **false**) — nested in `learningApply`, no extra wiring.
- **Auto-fork lane (S27-B).** `learning-apply` Step 4: with
  `autoForkSpecialist` on, a `recurring-suggestion-theme` finding writes a
  learning-fork brief to `.vibeflow/state/patches/learning-fork-<ts>/`,
  forks the matching phase specialist, and records the diff-first patch —
  **never applying it** (operator confirms via apply-arbiter-patch). Off
  ⇒ recommend-only (Sprint 22-C) unchanged.
- **Specialist bridge (S27-C).** The six phase-specialist agents accept a
  learning-fork brief (a `recurring-suggestion-theme` finding) as an
  equivalent trigger to a consensus session; new
  `agents/_shared/learning-fork-brief.md` documents the format. Diff-first
  / never-write-source unchanged.

Docs: `docs/TEMPLATE-AUTONOMY.md` + ACTION-GAP / LEARNING-APPLY refreshes.
Tests: sdlc-engine 194→196, new `sprint-27.sh` (44). Total baseline
2740 → 2786. **Backlog B1 done.**

- `.claude-plugin/plugin.json`: 2.14.0 → 2.15.0
- `@vibeflow/sdlc-engine`: 1.12.0 → 1.13.0

---

## [2.14.0] — 2026-06-05

Sprint 26 — TESTING→DEPLOYMENT consumer hardening. A real consumer's
(FlowBridge) phase walk surfaced two boundary gaps + two consensus-CLI
bugs.

- **release.decision.go wiring (S26-A).** `release-decision-engine`
  auto-satisfies `release.decision.go` on a GO verdict only — the release
  decision now flows into project state / `/vibeflow:status` / loop-audit.
- **Opt-in entry-gate (S26-B).** New `GatesConfigSchema`
  `{ enforceEntryCriteria: false }`. When on, the validator also enforces
  the target phase's `entryCriteria` (e.g. no DEPLOYMENT without a
  recorded GO). Default off ⇒ unchanged behaviour. Threaded
  config → engine → tools → validator.
- **Portable timeout (S26-F).** macOS ships no `timeout`/`gtimeout`, so
  the orchestrator's `timeout 90 codex …` failed (rc 127) → every CLI
  recorded as cli_error on macOS. New `vf_run_timeout` helper: timeout →
  gtimeout → pure-bash watchdog (returns 124, preserves the piped prompt
  so the child doesn't get stdin from /dev/null).
- **codex stdin footgun (S26-G).** The documented `codex exec "$(cat …)"`
  argument form leaves stdin open and hangs; fixed to the pipe form
  (stdin EOF) with a warning.
- **Pipeline contract (S26-C/D).** Harness + phases unit tests pin the
  TESTING/DEPLOYMENT criteria + analyzer artifact/auto-satisfy/map; new
  `docs/TESTING-READINESS.md` (incl. "empty artifacts/ in DEVELOPMENT is
  normal").

Bug tracker: #14 (macOS no-timeout) + #15 (codex stdin hang) — both
FIXED. Tests: sdlc-engine 185→194, new `sprint-26.sh` (54). Total
baseline 2677 → 2740.

- `.claude-plugin/plugin.json`: 2.13.0 → 2.14.0
- `@vibeflow/sdlc-engine`: 1.11.0 → 1.12.0

---

## [2.13.0] — 2026-06-05

Sprint 25 — autonomous-loop observability. The deep autonomy of Sprints
20–24 was opaque (telemetry spread across six files); v2.13.0 adds one
pane of glass.

- **Audit reader (S25-A).** New read-only `hooks/scripts/loop-audit.sh`
  consolidates `history.jsonl` auto-apply outcomes, `cooldown-*` markers,
  `auto-apply/watch.json`, the learning report, and the decisions log
  into one JSON summary (per-key counts + revert rate, cooled-down keys,
  armed watch, finding count, recent decisions). Fully guarded — empty
  project ⇒ all-zero JSON.
- **Status section (S25-B).** `/vibeflow:status` gains an **Autonomous
  Loop** section that runs the reader and renders it, flagging keys at
  `revertRate ≥ 0.5`; collapses to one idle line when there's no
  activity.
- **Config (S25-C).** New `LoopAuditConfigSchema` `{ window: 20 }` bounds
  the per-key tally to recent history rows.

Docs: `docs/LOOP-AUDIT.md` + `AUTO-APPLY.md` / `META-LEARNING.md`
refreshes. Tests: sdlc-engine 182→185, hooks 155→167, new `sprint-25.sh`
(42). Total baseline 2620 → 2677.

- `.claude-plugin/plugin.json`: 2.12.0 → 2.13.0
- `@vibeflow/sdlc-engine`: 1.10.0 → 1.11.0

---

## [2.12.0] — 2026-06-05

Sprint 24 — self-correcting auto-apply. Sprint 23 made config auto-apply
autonomous; v2.12.0 makes it learn from its own outcomes + adds
transactional revert.

- **Telemetry (S24-A).** `learning-apply` appends an `auto-apply` row to
  `history.jsonl` on auto-apply; `consensus-aggregator.sh` appends an
  `auto-apply-held` row on the HELD branch (it already wrote
  `auto-revert`). Every auto-tune outcome is now a queryable per-key row.
- **Detector (S24-B).** `learning-loop-engine` consensus-history mode
  gains `auto-tune-ineffective` (`LEARNING-AUTO-TUNE-INEFFECTIVE`): a key
  reverted in ≥ 3 attempts at revert-rate ≥ 0.5 → recommend removing it
  from `autoApply.keys`. `patternCatalogVersion` → 3.
- **Self-demote (S24-C).** `learning-apply` counts a key's `auto-revert`
  rows; ≥ `autoApply.demoteAfterReverts` (default 3) demotes it to
  propose-only for the run even while allowlisted (`Applied: demoted`).
- **Transactional revert (S24-D).** `autoApply.transactional` (default
  true): a run's auto-applies share one snapshot + one `watch.json`
  `keys[]`; the aggregator restores atomically and cools down every key.
  Reads `keys // [key]` for Sprint-23 back-compat.

Docs: `docs/META-LEARNING.md` + `AUTO-APPLY.md` / `LEARNING-LOOP.md`
refreshes. Tests: sdlc-engine 179→182, hooks 149→155, new `sprint-24.sh`
(41). Total baseline 2570 → 2620.

- `.claude-plugin/plugin.json`: 2.11.0 → 2.12.0
- `@vibeflow/sdlc-engine`: 1.9.0 → 1.10.0

---

## [2.11.0] — 2026-06-04

Sprint 23 — bounded auto-apply with auto-revert. Sprint 22's
`learning-apply` was propose-only; v2.11.0 lets the slow loop auto-apply
config tunes the operator trusts, within strict guardrails.

- **autoApply config (S23-A).** New `AutoApplyConfigSchema` nested in
  `LearningApplyConfigSchema` — `{enabled:false, keys:[],
  revertOnRegression:true, regressionDelta:0.05}`. **Off by default** —
  existing installs are unchanged.
- **Auto-apply path (S23-B).** `learning-apply` Step 7: a config-tune
  finding whose key is in `autoApply.keys` and clears every Sprint 22
  gate snapshots `vibeflow.config.json`, `git apply`s without a prompt
  (`Applied: auto`), and arms `.vibeflow/state/auto-apply/watch.json`.
  Non-allowlisted keys stay operator-confirmed; a cooled-down key is
  skipped.
- **Auto-revert (S23-C).** `consensus-aggregator.sh` evaluates the watch
  after finalising a round: if the same `{phase, primaryArtifact}`
  round's agreement dropped by more than `regressionDelta` below the
  baseline, it restores the snapshot, appends an `auto-revert` row to
  `history.jsonl`, logs to `.vibeflow/reports/auto-apply-reverts.md`, and
  arms a cooldown. Agreement held ⇒ "AUTO-APPLY HELD". No watch ⇒ no-op.

Docs: `docs/AUTO-APPLY.md` + `LEARNING-APPLY.md` / `ACTION-GAP.md`
refreshes. Tests: sdlc-engine 176→179, hooks 139→149, new `sprint-23.sh`
(43). Total baseline 2514 → 2570.

- `.claude-plugin/plugin.json`: 2.10.0 → 2.11.0
- `@vibeflow/sdlc-engine`: 1.8.0 → 1.9.0

---

## [2.10.0] — 2026-06-02

Sprint 22 — close the action gap. The L3 slow loop observed (Sprint 20)
and framed (Sprint 20-G) but never acted; v2.10.0 adds the acting stage.

- **`learning-apply` skill (S22-A/B/C).** New
  `/vibeflow:learning-apply [--dry-run] [--yes]` reads
  `consensus-learning-report.md` and classifies each finding into three
  lanes: **config-tune** (diff-first patch to `vibeflow.config.json`
  under `.vibeflow/state/patches/learning-<ts>/`), **template-route**
  (recurring-theme → a `/vibeflow:consensus-specialist` dispatch
  recommendation via the phase→specialist map; does not auto-fork), and
  **escalate** (→ `decision-recommender`). **Propose-only** — never
  writes config or source directly; config patches apply only with
  `--yes` after an `EngineConfigSchema` re-validation gate + a
  `maxRelativeStep` bounds clamp + a `minObservations` evidence floor.
- **Config (S22-D).** New `LearningApplyConfigSchema`
  (`{enabled, maxRelativeStep: 0.5, minObservations: 3}`), composed into
  `EngineConfigSchema` with the standard partial-merge; `learning-apply`
  registered in `skills/phase-policy.json`.

Docs: `docs/ACTION-GAP.md`, `docs/LEARNING-APPLY.md`,
`skills/learning-apply/references/lanes.md`, plus `LEARNING-LOOP.md` /
`CONSENSUS-FLOW.md` refreshes. Tests: sdlc-engine 173→176, new
`sprint-22.sh` (56). Total baseline 2455 → 2514.

- `.claude-plugin/plugin.json`: 2.9.0 → 2.10.0
- `@vibeflow/sdlc-engine`: 1.7.0 → 1.8.0

---

## [2.9.0] — 2026-05-31

Sprint 21 — signal-quality refinement. Sharpens three coarse
inputs/outputs of the consensus loop with no new mechanics:

- **Semantic excerption (S21-A).** `consensus-orchestrator` excerpts
  oversized primaries by **section score** (evidence-finding density +
  reviewer-memory hits + keyword overlap) instead of positional
  head/tail. `consensus.excerptStrategy` (`semantic` default |
  `headtail`) + `consensus.excerptTokenBudget` (30000). Falls back to
  head/tail when a doc has no section structure. New
  `skills/consensus-orchestrator/references/excerption.md`.
- **Theme-aware memory compaction (S21-B).** Reviewer-memory entries
  dropped past the cap fold into a per-artifact recurrence summary with
  a `seenCount` (Jaccard title match) instead of silent recency drop;
  `consensus-orchestrator` surfaces recurring criticals first.
  `reviewerMemory.compaction` (`theme-aware` default | `recency`).
- **Progress ledger (S21-C/D).** `phase-runner` writes
  `.vibeflow/state/phase-runner-progress.json` at each step boundary;
  `/vibeflow:status` renders a Phase-Runner Progress section with a
  stale-guard.
- **Config (S21-E).** `ConsensusConfigSchema` += `excerptTokenBudget` +
  `excerptStrategy`; `ReviewerMemoryConfigSchema` += `compaction`.

Docs: `docs/EXCERPTION.md`, `docs/PROGRESS-LEDGER.md`, plus
`REVIEWER-MEMORY.md` / `CONSENSUS-FLOW.md` refreshes. Tests: sdlc-engine
168→173, hooks 133→139, new `sprint-21.sh` (65). Total baseline 2379 →
2455.

- `.claude-plugin/plugin.json`: 2.8.0 → 2.9.0
- `@vibeflow/sdlc-engine`: 1.6.0 → 1.7.0

---

## [2.8.0] — 2026-05-31

Sprint 20 — close the L3 learning loop. The fast loop (per-run
consensus) was complete in v2.7.0; v2.8.0 builds the slow loop that
looks across time. Three groups plus two polish items:

- **Durable consensus history (S20-A).** `consensus-aggregator.sh`
  appends one `verdict` row per finalised round to a cross-session
  `.vibeflow/state/consensus/history.jsonl` (idempotent by
  `{sessionId, round}`); `apply-arbiter-patch` appends an
  `arbiter-decision` row; `consensus-orchestrator` writes a
  `<sid>.primary.txt` sidecar so the aggregator can resolve the
  reviewed artifact.
- **Learning-loop consensus-history mode (S20-B/C).**
  `learning-loop-engine` gains a fourth mode that mines the roll-up for
  slow-converging phases, reviewer skew, recurring suggestion themes,
  convergence stalls, primary-artifact churn, and the arbiter-decision
  effectiveness trace (applied-theme → next-round agreement delta).
  Writes `.vibeflow/reports/consensus-learning-report.md`.
- **Cross-session reviewer memory (S20-D/E).** The finalize step
  appends a bounded (top-3 criticals, capped per reviewer+artifact)
  entry to `reviewer-memory/<reviewer>.jsonl`; the orchestrator
  prepends a `PRIOR REVIEW MEMORY` block to each reviewer's next prompt.
  Omitted on clean first runs.
- **S20-F** — `consensus-gate.sh` names the primary artifact
  (`.primaryArtifact // .artifact`) in its block message.
- **S20-G** — `decision-recommender` consumes
  `consensus-learning-report.md`; `consensus.*` recommendations
  auto-detect as `gate-adjustment` decisions.
- **Config (S20-H).** New `LearningLoopConfigSchema` +
  `ReviewerMemoryConfigSchema` (both fully defaulted, partial-merge);
  `reviewerMemory.enabled: false` is a full rollback switch.

Docs: `docs/LEARNING-LOOP.md`, `docs/REVIEWER-MEMORY.md`, plus
`CONSENSUS-FLOW.md` / `CONSENSUS-ITERATION.md` refreshes. Tests:
sdlc-engine 160→168, hooks 117→133, new `sprint-20.sh` (85). Total
baseline 2270 → 2379.

- `.claude-plugin/plugin.json`: 2.7.0 → 2.8.0
- `@vibeflow/sdlc-engine`: 1.5.0 → 1.6.0

---

## [2.7.0] — 2026-04-23

Sprint 19 — refocus consensus on primary artifacts + end-to-end
phase automation. Addresses three architectural gaps the
FlowBridge_TR walkthrough exposed: (1) consensus reviewed the
analyzer's **report** instead of the PRD itself, so reviewer
feedback targeted report quality rather than the PRD's
readiness; (2) the aggregator's mechanical `criticalTotal >= 2
→ REJECTED` rule fired on zero-reject verdicts, breaking
iteration; (3) there was no single command to walk a phase
through analyzer → consensus → specialist → apply → advance.

### Added
- **Marker schema v2** (Sprint 19-A) — every analysis skill's
  Final Step marker now carries `primaryArtifact` (the PRD,
  ADR, test strategy — the thing being reviewed) and
  `evidence[]` (analyzer reports as context). Legacy
  `artifact` + `requiredCommand` fields retained so
  `consensus-gate.sh` works unchanged. 8 analyzer skills
  updated: prd-quality-analyzer, architecture-validator,
  test-strategy-planner, traceability-engine,
  coverage-analyzer, mutation-test-runner,
  release-decision-engine, deploy-verifier. `quality-gates`
  stays marker-less (it satisfies its criterion directly,
  no consensus round).
- **`docs/PRIMARY-ARTIFACT.md`** — full marker v2 schema +
  per-phase primary map + evidence distillation rules +
  back-compat notes.
- **Orchestrator primary-artifact resolution** (Sprint 19-B)
  — `consensus-orchestrator` Step 2b reads the incoming
  marker, resolves `primaryArtifact` + `evidence[]`, builds
  reviewer prompts with `PRIMARY ARTIFACT UNDER REVIEW` +
  `SUPPORTING EVIDENCE` blocks. Evidence distilled to ≤500
  tokens/source; primary excerpted (head+tail+findings-
  anchored) when >30k tokens. Legacy single-file invocation
  still works for pre-v2.7.0 callers.
- **`skills/phase-runner/SKILL.md`** (Sprint 19-F) — new
  one-command phase orchestrator. Runs the current phase's
  registered analyzer(s), invokes consensus-orchestrator on
  the primary, auto-chains arbiter/specialist → apply on
  NEEDS_REVISION, calls `mcp__sdlc-engine__sdlc_advance_phase`
  MCP tool directly on APPROVED. Bounded by
  `phaseRunner.autoAdvance` + `phaseRunner.maxConvergenceAttempts`.
  `--pause-between-steps`, `--no-auto-advance`, `--no-auto-chain`
  flags.
- **`PhaseRunnerConfigSchema`** in sdlc-engine config
  (`autoAdvance: true`, `maxConvergenceAttempts: 3`; ranges
  validated; silent fallback on malformed values). +3 unit
  tests.
- **`apply-arbiter-patch` Step 9 auto-chain** (Sprint 19-E)
  — after successful apply + passing tests, writes a fresh
  `consensus-needed.json` marker pointing at the same
  primaryArtifact for iteration N+1. Reads `verdict.json.round`
  (Sprint 17-A field; no new state file) to compute next
  round. Guardrails: `--no-chain` flag, `VF_SKIP_AUTO_CHAIN=1`,
  convergence-stall guard (agreement delta ≤0.05 over 2
  rounds), `consensus.maxIterations` ceiling.
- **`tests/integration/sprint-19.sh`** — 87 assertions across
  `[S19-A]`..`[S19-Z]`, including a runtime regression for
  the S19-C rule change (2 NEEDS_REVISION + 1 APPROVED +
  critical=2 + rejected=0 → NEEDS_REVISION, not REJECTED).
- `release-notes/2.7.0.md`.

### Changed
- **Aggregator status rule** (Sprint 19-C) — the
  `criticalTotal >= 2 → REJECTED` path now requires
  `rejected >= 1` as a co-condition. Zero-reject verdicts
  with high critical counts land as NEEDS_REVISION so
  iteration continues. Pre-19 rule wrongly promoted 2
  NEEDS_REVISION + 1 APPROVED to REJECTED despite no
  reviewer actually voting reject.
- **Specialist guardrail** (Sprint 19-D) — `consensus-specialist`
  Step 1 gains a 4-case decision matrix: APPROVED stops,
  genuine REJECTED (rejected≥1) stops with operator triage,
  NEEDS_REVISION / HUMAN_APPROVAL_REQUIRED dispatch. The
  "soft REJECTED" case the S19-C refactor eliminates gets a
  defensive "treat as NEEDS_REVISION" branch for pre-2.7.0
  verdict files.
- `skills/phase-policy.json` registers `phase-runner` (phases:
  ALL).
- `docs/CONSENSUS-FLOW.md` diagram + file table updated for
  primary-artifact refocus.
- `docs/CONSENSUS-ITERATION.md` gains "Auto-chain on apply"
  section with convergence-stall + max-iterations guards.
- `docs/AUTO-SATISFY.md` header note points at phase-runner
  as the one-command alternative.

### Version bumps
- `.claude-plugin/plugin.json`: 2.6.1 → 2.7.0
- `.claude-plugin/marketplace.json`: 2.6.1 → 2.7.0
- `mcp-servers/sdlc-engine/package.json`: 1.4.0 → 1.5.0
  (new PhaseRunnerConfigSchema export)
- `tests/integration/sprint-4.sh` `EXPECTED_PLUGIN_VERSION`:
  2.6.1 → 2.7.0
- Test layers: 18 → 19 (new `sprint-19.sh` at 87 assertions)
- sdlc-engine unit: 157 → 160 (+3 PhaseRunner schema tests)
- Total baseline: 2180 → 2270 (+90)

---

## [2.6.1] — 2026-04-22

Process-gap patch. CLAUDE.md's "Sprint Tracking" policy asked
for every sprint to land a `docs/SPRINT-N.md` file; in practice
the last one committed was `SPRINT-13.md` and Sprints 14-18
shipped with plans only in the ephemeral
`~/.claude/plans/<slug>.md` scratch location. This patch closes
the gap two ways: a new hook that auto-writes plan docs into
the repo on every `ExitPlanMode`, and five backfilled
`SPRINT-14.md`..`SPRINT-18.md` docs reconstructed from
release-notes, CHANGELOG entries, and git log.

### Added
- **`hooks/scripts/save-plan-doc.sh`** (new) — PostToolUse hook
  registered on `ExitPlanMode` matcher. Reads stdin's `cwd`
  (Claude Code fills this with the project root), finds the
  most-recently-modified markdown in `~/.claude/plans/`, parses
  the plan title for `/^#\s*Sprint\s+(\d+)/`, and copies the
  plan to `<cwd>/docs/SPRINT-<N>.md`. Non-sprint plans (no
  match) fall back to `<cwd>/docs/plans/<slug>-<YYYYMMDD>.md`.
  Fail-safes: missing jq / empty stdin / non-VibeFlow project
  (guard via `vibeflow.config.json` presence check) all exit 0
  silently. Bypass: `VF_SKIP_PLAN_SAVE=1`. Never blocks
  ExitPlanMode.
- **`docs/SPRINT-14.md`..`docs/SPRINT-18.md`** (5 new) —
  backfilled from release-notes + CHANGELOG + git log. Each
  one cites the shipping tag, branch, and commit SHAs for every
  ticket. Sprint 17 rolls up v2.5.1..v2.5.4 patches as
  "Known follow-ups" so the doc captures the full Sprint-17
  arc.
- **`docs/plans/`** directory with `.gitkeep` so the fallback
  path exists even before the first non-sprint plan lands.
- **ROADMAP.md "Completed Sprints Appendix"** — short index
  linking sprints 8-18 with ship dates and themes. The
  narrative per-sprint rows above stop at Sprint 7; this
  appendix covers 8-18 without rewriting the whole section.
- **`[S19-PLAN]`** section in `hooks/tests/run.sh` — 7
  assertions covering sprint-numbered title write, non-sprint
  fallback, missing-config guard, `VF_SKIP_PLAN_SAVE=1`
  bypass, hooks.json wiring. Hooks baseline: 110 → 117.
- `CLAUDE.md` Sprint Tracking section notes the new hook + the
  backfill.
- `release-notes/2.6.1.md`.

### Version bumps
- `.claude-plugin/plugin.json`: 2.6.0 → 2.6.1
- `.claude-plugin/marketplace.json`: 2.6.0 → 2.6.1
- `tests/integration/sprint-4.sh` `EXPECTED_PLUGIN_VERSION`:
  2.6.0 → 2.6.1
- `@vibeflow/sdlc-engine`: 1.4.0 (unchanged — no engine code)
- Hooks baseline: 110 → 117 (+7)
- Total baseline: ~2173 → ~2180

---

## [2.6.0] — 2026-04-21

Sprint 18 — full auto-satisfy rollout. Every automatable SDLC
exit criterion is now satisfied by the skill that produces its
authoritative evidence; only the three criteria that require
real human judgment (`design.approved`, `accessibility.verified`,
`sprint.planned`) stay operator-driven, and those are enumerated
+ justified in a new `docs/AUTO-SATISFY.md`. Each phase
transition becomes a single-command advance sequence.

### Added
- **`skills/quality-gates/SKILL.md`** (new, DEVELOPMENT phase).
  Runs lint + typecheck + unit tests from
  `vibeflow.config.json.tech.*` (or inferred defaults per
  language — JS/TS, Python, .NET, Go, Rust). Writes a
  per-run report under `.vibeflow/reports/quality-gates-*.md`
  and auto-satisfies `quality.gates.passed` when every command
  exits 0.
- **`skills/deploy-verifier/SKILL.md`** (new, DEPLOYMENT phase).
  Cross-checks CI pipeline status (via `dev-ops` MCP),
  endpoint smoke tests (curl), and observability health
  dashboard (via `observability` MCP). Auto-satisfies
  `deployment.verified` + `health.checks.passed` when the
  overall verdict is PASS. Writes the consensus-needed marker
  for the third DEPLOYMENT criterion
  (`consensus.deployment.approved`) so multi-AI review still
  runs. No auto-rollback — prints the `docs/runbooks/` hint
  and leaves recovery to the operator.
- **Auto-satisfy extensions** on existing analyzers:
  - `architecture-validator` → `adr.recorded` when verdict ≠ BLOCKED
  - `test-strategy-planner` → `test-strategy.approved` (unconditional)
  - `coverage-analyzer` → `coverage.met` when verdict == PASS
  - `mutation-test-runner` → `mutation.score.acceptable` when
    verdict == PASS (also gains its first Final Step section
    with auto-consensus marker write)
- **`consensus-orchestrator` Step 3c.0b** — DEVELOPMENT-phase
  extension. On APPROVED or HUMAN_APPROVAL_REQUIRED + phase ==
  DEVELOPMENT, also auto-satisfies `code.reviewed`. DEVELOPMENT
  doesn't carry a scoped consensus criterion (Sprint 15-C), so
  the orchestrator's DEVELOPMENT verdict is the authoritative
  code-review signal.
- **`docs/AUTO-SATISFY.md`** — per-criterion matrix covering
  all 19 exit criteria across 7 phases. Marks each as AUTO or
  MANUAL, documents gate conditions, explains why manual
  criteria stay manual, and includes a troubleshooting section
  for "criterion stuck unsatisfied" scenarios.
- **`tests/integration/sprint-18.sh`** — 67 assertions across
  `[S18-A]`..`[S18-Z]`.

### Changed
- `skills/phase-policy.json` registers `quality-gates`
  (DEVELOPMENT) + `deploy-verifier` (DEPLOYMENT) alongside
  the existing skill entries.

### Version bumps
- `.claude-plugin/plugin.json`: 2.5.4 → 2.6.0
- `.claude-plugin/marketplace.json`: 2.5.4 → 2.6.0
- `@vibeflow/sdlc-engine`: 1.4.0 (unchanged — no engine code
  changes this sprint)
- `tests/integration/sprint-4.sh` `EXPECTED_PLUGIN_VERSION`:
  2.5.4 → 2.6.0
- Integration layers: 17 → 18 (new `sprint-18.sh` at 67
  assertions)
- Total baseline: 2106 → 2173 (+67)

---

## [2.5.4] — 2026-04-21

Close the last manual step. After a successful PRD analysis +
consensus run, state registration into `project.json` now happens
automatically — operators no longer need to call
`sdlc_record_consensus` or `sdlc_satisfy_criterion` by hand before
`/vibeflow:advance` works.

### Changed
- **`skills/consensus-orchestrator/SKILL.md`** — new Step 3c.0
  calls `mcp__sdlc-engine__sdlc_record_consensus` on every
  terminal verdict (APPROVED / NEEDS_REVISION / REJECTED /
  HUMAN_APPROVAL_REQUIRED), reading `status`, `agreement`, and
  `criticalTotal` from `verdict.json`. The validator's scope
  check for `consensus.<phase>.approved` needs this to unblock
  `/vibeflow:advance`. Without the auto-record, the chain up to
  advance failed silently at the phase gate with "consensus not
  recorded for this phase" — exactly what FlowBridge_TR hit.
- **`skills/prd-quality-analyzer/SKILL.md`** — new auto-satisfy
  step calls `mcp__sdlc-engine__sdlc_satisfy_criterion` for
  `prd.approved` unconditionally + for `testability.score>=60`
  when the measured score is ≥ 60. Completes the REQUIREMENTS
  phase's exit-criterion registration automatically.

Both skills fail gracefully: if the MCP tool isn't reachable
(sdlc-engine server unavailable), they emit a visible manual-
command hint and continue — the verdict.json + report remain the
source of truth on disk.

### Added
- **`tests/integration/sprint-17.sh [S17.2]`** section — 7 new
  regression assertions pinning the orchestrator auto-record +
  prd-quality-analyzer auto-satisfy prose.

### Version bumps
- `.claude-plugin/plugin.json`: 2.5.3 → 2.5.4
- `.claude-plugin/marketplace.json`: 2.5.3 → 2.5.4
- `tests/integration/sprint-4.sh` `EXPECTED_PLUGIN_VERSION`:
  2.5.3 → 2.5.4
- sprint-17.sh baseline: 98 → 106 (+8)

---

## [2.5.3] — 2026-04-21

**Critical fix.** `.mcp.json` used bare `./mcp-servers/…/dist/bundle.js`
paths, which resolved against the consumer project's cwd instead
of the plugin install directory when the plugin was installed in
another project. The symptom: MCP tools (including
`sdlc_advance_phase`) failed to surface, `/vibeflow:advance` and
every other MCP-backed skill couldn't call their tools, and
operators saw the plugin as loaded-but-inert in consumer repos.

Paths now use `${CLAUDE_PLUGIN_ROOT}/mcp-servers/…/dist/bundle.js`
which Claude Code resolves to the plugin's own install location
regardless of cwd — matching the pattern `hooks.json` already uses.

### Fixed
- **`.mcp.json` paths now use `${CLAUDE_PLUGIN_ROOT}/`**. All five
  MCP servers (sdlc-engine, codebase-intel, design-bridge,
  dev-ops, observability) updated. This was a v2.0.0-2.5.2 bug
  that only surfaced when the plugin was installed in a
  consumer project (within the VibeFlow repo itself, `.`
  coincidentally resolved correctly so local tests passed).

### Added
- **Regression guard** in `tests/integration/run.sh`: asserts
  every `.mcp.json` server uses the `${CLAUDE_PLUGIN_ROOT}/`
  prefix, fails the test if any regress back to bare `./`.
- **Test harness MCP path resolver** (`tests/integration/run.sh`)
  now handles both `${CLAUDE_PLUGIN_ROOT}` and legacy `./`
  prefixes when resolving dist-file-exists assertions.

### Version bumps
- `.claude-plugin/plugin.json`: 2.5.2 → 2.5.3
- `.claude-plugin/marketplace.json`: 2.5.2 → 2.5.3
- `tests/integration/sprint-4.sh` `EXPECTED_PLUGIN_VERSION`:
  2.5.2 → 2.5.3
- Integration run.sh: 398 → 399 assertions (+1 regression guard)

---

## [2.5.2] — 2026-04-21

Skill polish. `/vibeflow:advance` now defaults `TARGET_PHASE` to
the next phase in the canonical SDLC order when the argument is
omitted. Typing `/vibeflow:advance` is enough to move forward
one phase; explicit target is only needed when skipping phases
or re-entering a non-sequential one.

### Changed
- **`skills/advance/SKILL.md`** — `TARGET_PHASE` is now
  optional. When absent, the skill reads
  `vibeflow.config.json.currentPhase` (or falls back to
  `sdlc_get_state`) and picks the next phase in
  `REQUIREMENTS → DESIGN → ARCHITECTURE → PLANNING →
  DEVELOPMENT → TESTING → DEPLOYMENT`. If currentPhase is
  DEPLOYMENT, the skill stops with a "nothing to advance"
  message instead of erroring.

### Version bumps
- `.claude-plugin/plugin.json`: 2.5.1 → 2.5.2
- `.claude-plugin/marketplace.json`: 2.5.1 → 2.5.2
- `tests/integration/sprint-4.sh` `EXPECTED_PLUGIN_VERSION`:
  2.5.1 → 2.5.2

---

## [2.5.1] — 2026-04-21

Post-Sprint-17 polish. Ships the missing `/vibeflow:advance` slash
command that was documented in CLAUDE.md but never implemented —
operators had to assemble `sdlc_advance_phase` MCP tool arguments
by hand. Now you run `/vibeflow:advance DESIGN` (or any target
phase) and the skill handles projectId lookup, humanOverrideNote
parsing for HUMAN_APPROVAL_REQUIRED advances, and exit-criterion
failure remediation hints.

### Added
- **`skills/advance/SKILL.md`** — thin wrapper around
  `mcp__sdlc-engine__sdlc_advance_phase`. Reads projectId from
  `vibeflow.config.json`, uppercases the target phase argument,
  extracts optional `humanOverrideNote="..."` from $ARGUMENTS,
  invokes the MCP tool, and surfaces success/failure with
  remediation hints that point at the relevant skill
  (consensus-orchestrator / consensus-arbiter /
  consensus-specialist / analyzer skills) based on which
  exit criterion failed.
- `skills/phase-policy.json` registers `advance` (phases: ALL).

### Fixed
- **Documentation drift.** `/vibeflow:advance` appeared in
  CLAUDE.md's "Key Commands" list since v1.0 but wasn't
  implemented as a skill; operators were told to run it but
  Claude Code had nothing to dispatch. This release closes
  the gap.

### Version bumps
- `.claude-plugin/plugin.json`: 2.5.0 → 2.5.1
- `.claude-plugin/marketplace.json`: 2.5.0 → 2.5.1
- `tests/integration/sprint-4.sh` `EXPECTED_PLUGIN_VERSION`:
  2.5.0 → 2.5.1

---

## [2.5.0] — 2026-04-20

Sprint 17 — iterative consensus negotiation loop + phase
specialists. Reviewers now talk across multiple rounds
(default 5), critical findings are deduped cross-reviewer, and
six new phase-specialist subagents deeply rewrite artifacts
based on reviewer feedback as diff-first patches. A new
`HUMAN_APPROVAL_REQUIRED` status covers the case where rounds
exhaust without reaching the approval threshold — advance
passes with an audit event recording the operator's explicit
justification.

### Added
- **Iterative consensus rounds.** `hooks/scripts/consensus-aggregator.sh`
  is now round-aware: orchestrator writes
  `.vibeflow/state/consensus/<sid>.current-round.txt` before each
  negotiation round; aggregator tags each jsonl line with
  `round: N` and filters aggregation by current round.
  `verdict.json` accumulates a `rounds[]` array alongside the
  usual top-level fields so pre-2.5.0 consumers keep working.
  Orchestrator Step 5 documents the loop + round-N prompt
  template (prior-round verdicts + top-3 critical findings
  embedded, ≤500 tok per reviewer).
- **Three new config keys.** `consensus.maxIterations`
  (default 5, range [1, 20]), `consensus.approvalThreshold`
  (default 0.9, range [0, 1]), `consensus.iteration.enabled`
  (default true — rollback switch).
  `mcp-servers/sdlc-engine/src/config.ts` gains
  `ConsensusConfigSchema` with typed defaults and silent-fallback
  parsing for malformed values.
- **Critical finding dedup.** Reviewer `criticalIssues` is now an
  array of `{id, target:{file, line_range}, title, rationale}`.
  Aggregator dedups cross-reviewer by `{file, line_range}`
  equality OR Jaccard(title words) ≥ 0.6. Three reviewers
  flagging the same issue now count as 1, not 3. Legacy integer
  shape still accepted. `criticalRawCount` + `criticalDeduped[]`
  preserved in verdict.json for audit.
- **`HUMAN_APPROVAL_REQUIRED` consensus status.** New enum value
  in `mcp-servers/sdlc-engine/src/consensus.ts`. Emitted by the
  orchestrator loop when `maxIterations` rounds pass without
  reaching `approvalThreshold` agreement but the run is not a
  hard reject. Validator accepts it as equivalent to APPROVED
  (pass-with-audit). `sdlc_advance_phase` MCP tool gains an
  optional `humanOverrideNote: string` field; the engine threads
  it through to the `phase_advanced` event payload for audit.
  `load-sdlc-context.sh` surfaces a visible advisory on
  subsequent SessionStart calls.
- **Six phase-specialist subagents (Sprint 17-D).** One per SDLC
  phase, each produces one diff-first patch that rewrites the
  phase's artifact based on reviewer feedback:
  - `prd-rewriter` (REQUIREMENTS)
  - `design-spec-refiner` (DESIGN)
  - `adr-author` (ARCHITECTURE)
  - `test-strategy-refiner` (PLANNING)
  - `coverage-gap-filler` (TESTING)
  - `runbook-editor` (DEPLOYMENT)
  Each agent runs `context: fork` + `model: opus` + `effort:
  high`. All share the same diff-first contract: never writes
  to source directly, emits exactly one
  `.vibeflow/state/patches/<sid>/specialist-NN-<phase>.patch`
  and a decision report at
  `.vibeflow/reports/specialist-decisions-<phase>.md`.
- **`consensus-specialist` dispatcher skill (Sprint 17-E).**
  New skill at `skills/consensus-specialist/SKILL.md`. Reads
  `vibeflow.config.json.currentPhase`, forks the matching
  specialist, and routes its patch into the session's
  `manifest.json` with `type: "specialist"`.
  `apply-arbiter-patch` processes it in order alongside
  arbiter patches.
- **`tests/integration/sprint-17.sh`** — 98 assertions across
  `[S17-A]`..`[S17-Z]`.
- **`docs/CONSENSUS-ITERATION.md`** — loop shape + config
  surface + `rounds[]` schema + `HUMAN_APPROVAL_REQUIRED` flow
  + escape hatches + troubleshooting.
- **`docs/SPECIALISTS.md`** — 6-agent table + dispatcher
  walkthrough + per-agent decision-heuristic highlights +
  rollback + "adding a new specialist" recipe.
- `release-notes/2.5.0.md`.

### Fixed
- **`agreement < 0.5 → REJECTED` rule retired.** Pre-2.5.0 the
  aggregator demoted NEEDS_REVISION to REJECTED whenever fewer
  than half of reviewers voted APPROVED, which conflated "none
  approved yet" with "majority rejected". Three reviewers
  unanimously voting NEEDS_REVISION (approved=0, agreement=0)
  used to fall through to REJECTED, skipping the arbiter entirely.
  New rule requires an explicit majority of REJECTED verdicts
  (`rejected * 2 > total`) to demote.
- **`release-decision-engine`'s `allowed-tools` already had
  `Write`** (fixed in 2.4.0) — unchanged here, documented in
  docs/SPECIALISTS.md's rollback section.

### Version bumps
- `.claude-plugin/plugin.json`: 2.4.0 → 2.5.0
- `.claude-plugin/marketplace.json`: 2.4.0 → 2.5.0
- `mcp-servers/sdlc-engine/package.json`: 1.3.0 → 1.4.0
- `tests/integration/sprint-4.sh` `EXPECTED_PLUGIN_VERSION`:
  2.4.0 → 2.5.0
- Hooks baseline: 86 → 110 (+24)
- Unit (sdlc-engine) baseline: 142 → 157 (+15)
- Integration layers: 16 → 17 (new `sprint-17.sh` at 98
  assertions)
- Total baseline: ~1969 → ~2106 (+137)

---

## [2.4.0] — 2026-04-20

Sprint 16 — deterministic auto-consensus chain. Analysis skills
enforce consensus via a filesystem marker + PreToolUse hook rather
than trusting the skill to invoke a slash command. Closes the
last gap in the MyVibe closed loop: forked subagents, context
compaction, and busy main agents can no longer silently skip the
review step.

### Added
- **`hooks/scripts/consensus-gate.sh`** — new PreToolUse hook
  registered on `Bash|Write|Edit`. Reads
  `.vibeflow/state/consensus-needed.json`; if the marker exists,
  exits 2 with a stderr message naming the `requiredCommand` the
  operator must run. Fail-safe on missing jq, empty stdin, or
  missing marker. Pass-through for writes under `.vibeflow/**`,
  Bash commands containing `vibeflow:consensus-*` /
  `vibeflow:apply-arbiter-*`, and `rm`-ing the marker. Per-call
  bypass: `VF_SKIP_CONSENSUS_GATE=1`.
- **Marker-writing step on 6 analysis skills.**
  `prd-quality-analyzer`, `architecture-validator`,
  `test-strategy-planner`, `traceability-engine`,
  `coverage-analyzer`, and `release-decision-engine` now Write
  `consensus-needed.json` with
  `{artifact, requiredCommand, createdAt, createdBy}` as their
  mandatory final step. Replaces the prose-only invoke from 2.3.0.
- **Marker drain on `consensus-orchestrator` + `consensus-arbiter`
  + `apply-arbiter-patch`.** All three skills remove
  `consensus-needed.json` on successful completion, so the chain
  is self-clearing regardless of entry point. Orchestrator
  drains on every terminal verdict status
  (APPROVED/NEEDS_REVISION/REJECTED); arbiter and apply drain
  unconditionally at end-of-run to handle direct operator
  invocation.
- **`tests/integration/sprint-16.sh`** — 77 assertions pinning
  the hook, the marker-drain in each downstream skill, the
  marker-write on each L1 skill, the hooks.json wiring, and
  CONSENSUS-FLOW.md coverage.
- **`docs/CONSENSUS-FLOW.md` "Layer 2 in detail"** — documents
  the marker mechanism, the hook's pass-through rules, the drain
  points, and the per-call bypass. Layer 2's diagram section
  rewritten to reflect the deterministic chain.
- `release-notes/2.4.0.md`.

### Fixed
- **Skills never actually triggered consensus.** In 2.3.0, the
  "Final Step: Auto-Consensus" block relied on Claude to invoke
  the orchestrator as a slash command after writing the report.
  In practice the invocation was defeated by forked subagents
  (no slash-command dispatch), compaction of the skill's final
  instruction, or the main agent simply moving on. The result:
  reports landed in `.vibeflow/reports/`, no consensus record
  appeared, `/vibeflow:advance` blocked with no operator-visible
  cause. The marker + hook chain makes this path deterministic.
- **`release-decision-engine` lacked `Write` in `allowed-tools`.**
  Predates the auto-consensus requirement — with `Read Grep Glob`
  only, the skill physically could not drop its report file.
  `Write` is now listed alongside the other three.

### Version bumps
- `.claude-plugin/plugin.json`: 2.3.0 → 2.4.0
- `.claude-plugin/marketplace.json`: 2.3.0 → 2.4.0
- `mcp-servers/sdlc-engine/package.json`: 1.3.0 (unchanged — no
  engine-level changes)
- `tests/integration/sprint-4.sh` `EXPECTED_PLUGIN_VERSION`:
  2.3.0 → 2.4.0
- Hooks baseline: 75 → 86 (+11 [S16-A])
- Integration layers: 15 → 16 (new `sprint-16.sh` at 77 assertions)

---

## [2.3.0] — 2026-04-20

MyVibe closed-loop — consensus now actually runs end-to-end: codex
and gemini's verdicts reach the aggregator, analysis skills
auto-invoke consensus, phase-advance gates on per-phase verdicts,
and a new arbiter turns reviewer suggestions into diff-first
patches the operator applies with one command.

### Fixed
- **codex/gemini verdicts never reached the aggregator.** The
  consensus-orchestrator skill ran the two CLIs as raw bash
  subprocesses, which don't emit Claude Code `SubagentStop`
  events. The aggregator expected 3 reviewers (all CLIs on PATH)
  but only saw one (claude-reviewer's SubagentStop) and fell
  through to its 600s global timeout, demoting APPROVED verdicts
  to NEEDS_REVISION. Orchestrator now appends one JSONL line per
  CLI directly into `.vibeflow/state/consensus/<session>.jsonl`
  in the exact schema `consensus-aggregator.sh:110-116` writes.
  Per-CLI 90s timeout prevents the 600s global fallback.

### Added
- **Auto-invoke prose on 6 analysis skills** — `prd-quality-analyzer`,
  `architecture-validator`, `test-strategy-planner`,
  `traceability-engine`, `coverage-analyzer`, and
  `release-decision-engine` now end with a mandatory "Final Step:
  Auto-Consensus" section that invokes
  `/vibeflow:consensus-orchestrator` on the primary report.
  `VF_SKIP_AUTO_CONSENSUS=1` is the single documented skip
  condition.
- **Phase-scoped consensus exit criteria.** Every phase except
  DEVELOPMENT now carries `consensus.<phase>.approved` as an
  exit criterion. The validator scope-checks `lastConsensusPhase`
  — stale REQUIREMENTS consensus no longer carries through to
  DESIGN advance. DEVELOPMENT intentionally omits the gate
  because the commit-time `trigger-ai-review.sh` marker already
  covers it.
- **`consensus-arbiter` skill (new).** Reads the session jsonl +
  verdict + currentPhase + domain, decides per-suggestion
  APPLY / DEFER / REJECT against a 10-rule matrix, emits
  `git apply`-compatible patches under
  `.vibeflow/state/patches/<session>/` and an audit trail at
  `.vibeflow/reports/arbiter-decisions.md`. Never touches source
  files — diff-first contract.
- **`apply-arbiter-patch` skill (new).** Shows a git-style diff
  preview, asks for confirmation (or accepts `--yes`), applies
  via `git apply`. Flags: `--dry-run`, `--run-tests` (runs the
  project's test command post-apply, prints `git checkout HEAD`
  rollback hint on failure). Every applied patch flips
  `Applied: false` → `Applied: true` in arbiter-decisions.md.
- **Marker drain on SessionStart.** `load-sdlc-context.sh` reads
  `review-pending.json` (written by `trigger-ai-review.sh` after
  large commits), emits a strong "ACTION REQUIRED: run
  /vibeflow:consensus-orchestrator" line when the marker is
  fresh (< 24h). Closes the post-commit half of the MyVibe
  promise.
- **Reviewer suggestion schema.** `agents/claude-reviewer.md`
  pins the `suggestions[]` entry shape — `id`, `type`,
  `target.file`, `target.line_range`, `rationale`,
  `proposed_change`, `priority`, `phase_relevance`. All three
  reviewers emit the same shape so the arbiter can deduplicate
  across models.
- **`VF_SKIP_AUTO_CONSENSUS=1`** escape hatch. Disables Layer 2
  (skill auto-invoke) for one session; Layer 3 phase-gate
  ignores it (always enforced). `load-sdlc-context.sh` surfaces
  a visible advisory when the var is set.
- **`consensus.quorum`** config override (already shipped in
  2.2.0, now documented end-to-end). Operators can pin the
  expected reviewer count when a CLI is offline.
- **`tests/integration/sprint-15.sh`** — 82 assertions pinning
  every Sprint 15 behaviour change.
- **`docs/CONSENSUS-FLOW.md`** + **`docs/ARBITER.md`** — user-
  facing references for the 4-layer flow and the arbiter
  decision matrix.
- **`skills/phase-policy.json`** — new entries for
  `consensus-arbiter` (ALL) and `apply-arbiter-patch`
  (DEVELOPMENT, TESTING).

### Changed
- `mcp-servers/sdlc-engine/src/phases.ts` — exit criteria
  extended (see Added). The old global `consensus.approved`
  criterion on ARCHITECTURE is renamed to
  `consensus.architecture.approved`. Legacy alias in the
  validator accepts the old name for one release; drop in
  v2.4.0.
- `mcp-servers/sdlc-engine/src/validation.ts` —
  `PhaseTransitionRequest` gains `lastConsensusPhase`. Scope-
  aware walk: `CONSENSUS_CRITERION_PATTERN` matches require
  both phase and verdict to align; everything else falls back
  to the existing satisfied-set check. DEVELOPMENT keeps the
  Sprint 14 "any lastConsensus must be APPROVED" legacy check.
- Plugin version: `2.2.0 → 2.3.0`.
- `@vibeflow/sdlc-engine`: `1.2.0 → 1.3.0`.
- `CLAUDE.md` baseline: 14 → 15 test layers, 1793 → 1881.

### Upgrade

```bash
claude plugin marketplace update vibeflow
claude plugin install vibeflow@vibeflow
```

Behavioural changes to expect:
- Skills that write `.vibeflow/reports/*.md` now chain into
  consensus-orchestrator by default. To suppress for a single
  session: `VF_SKIP_AUTO_CONSENSUS=1`.
- `/vibeflow:advance` now requires a fresh per-phase APPROVED
  consensus for REQUIREMENTS / DESIGN / ARCHITECTURE / PLANNING
  / TESTING / DEPLOYMENT. Run
  `/vibeflow:consensus-orchestrator` if blocked.
- ARCHITECTURE projects mid-flight with the old
  `consensus.approved` criterion in their satisfiedCriteria
  still advance (alias accepted through v2.3.x).

---

## [2.2.0] — 2026-04-20

Consensus flow unified; `mode` concept retired; skill output contract
fixed. Closes three field-reported bugs from v2.1.0 testing.

### Changed
- **Consensus is CLI-availability-gated, not mode-gated.** `codex` and
  `gemini` CLI reviewers participate whenever their CLIs are on PATH —
  both use the operator's own authenticated session, so there is no
  API billing reason to hide them behind a solo/team switch.
  `hooks/scripts/consensus-aggregator.sh` now derives the expected
  reviewer count from `command -v codex` + `command -v gemini`, with
  an optional `consensus.quorum` integer override in
  `vibeflow.config.json` for CI or offline-CLI scenarios.
- `hooks/scripts/trigger-ai-review.sh` no longer short-circuits in
  "solo mode" — the hook now writes the review-pending marker
  whenever the diff crosses the 50-line threshold, and downstream
  decides who reviews.
- `skills/consensus-orchestrator/SKILL.md` Step 3 section renamed
  from "Team Mode Only, Graceful Degradation" to "CLI-availability
  only", with an explicit note that both CLIs use operator-owned
  sessions → no API billing → no mode gate.

### Fixed
- `reviewer=unknown` / `verdict=UNKNOWN` consensus entries. The
  aggregator was firing on every `SubagentStop` payload (Explore,
  test-analyst, codebase-explorer, …) and logging any subagent with
  unparseable output as an UNKNOWN verdict, prematurely finalising
  the session as REJECTED. The aggregator now filters by subagent
  name (allow-list: `claude-reviewer`, `*-reviewer`, `consensus-*`)
  and skips entries with no recognisable verdict instead of logging
  synthetic UNKNOWN rows.
- `prd-quality-analyzer`, `architecture-validator`,
  `test-strategy-planner`, and `traceability-engine` produced
  reports in chat only — their `allowed-tools` was `Read Grep Glob`,
  so Claude couldn't Write to `.vibeflow/reports/`. All four now
  carry `Write` in allowed-tools and name their `.vibeflow/reports/`
  target paths explicitly in the "Output Files" section, with a
  "never print to chat only" directive.
- Malformed `SubagentStop` payloads (e.g. JSON strings with embedded
  `\n` escapes that got interpreted as newlines mid-pipe) no longer
  abort the aggregator with `exit 5`. Fail-safe path: parse-failure
  → `{"continue":true}` + exit 0.

### Removed
- `vf_mode()` helper deleted from `hooks/scripts/_lib.sh`. Every
  hook (load-sdlc-context, compact-recovery, trigger-ai-review,
  consensus-aggregator) dropped its `MODE=...` read. Status line
  output no longer includes `mode=...`. The legacy `"mode": "solo"`
  / `"team"` field in synthesised test fixtures and checked-in
  `vibeflow.config.json` files is gone.
- `docs/HOOKS.md` "Solo mode" subsection on trigger-ai-review
  merged into the rate-limit section; Quorum subsection on
  consensus-aggregator rewritten around CLI detection +
  `consensus.quorum` override.
- `docs/CONFIGURATION.md` sample config no longer carries `mode`;
  fields table drops `mode` + `db_connection` (both retired long
  ago but the doc was stale); `userConfig` table cleaned up.

### Added
- `consensus.quorum` integer field in `vibeflow.config.json` —
  overrides the CLI-detected default.
- `tests/integration/sprint-14.sh` — 36 assertions pinning every
  Sprint 14 behaviour change (CLI detection, non-reviewer filter,
  mode-absence, skill output contract).
- Sprint 14-D regression sentinel in `tests/integration/sprint-4.sh`:
  any skill with an `## Output Files` section must carry `Write`
  in its allowed-tools.

### Upgrade

```bash
claude plugin marketplace update vibeflow
claude plugin install vibeflow@vibeflow
```

Behavioural difference: reviewers that previously only ran in "team
mode" now run unconditionally if their CLI is on PATH. If you have
`codex` or `gemini` installed but don't want them to participate,
set `"consensus": { "quorum": 1 }` in `vibeflow.config.json`.

No data migration needed. `mode` in your existing config file is
harmlessly ignored.

### Versioning
- Plugin: `2.1.0 → 2.2.0`
- `@vibeflow/sdlc-engine`: `1.1.0 → 1.2.0`

### Tests
1793 passing checks across 14 layers (`hooks` 75 + `run.sh` 398 +
`sprint-*` 1220 + MCP units 389 + sprint-8's pre-existing 29/33).
sprint-8's 4 `[S8-C]` prerelease runtime failures remain pre-existing
and out of scope.

---

## [2.1.0] — 2026-04-20

Generic phase enforcement. Write/Edit tool calls are now gated per
phase by a new `phase-write-guard` hook, closing the gap that let
`/vibeflow:init` scaffold source code during REQUIREMENTS.

### Added
- `hooks/scripts/phase-write-guard.sh` — PreToolUse hook on
  `Write|Edit`. Reads `hooks/scripts/phase-policy.json`, matches the
  target file against the current phase's allow/warn/deny globs, and
  exits 2 on deny. Fail-safe allow when the policy file or `python3`
  is missing. Per-call bypass: `VF_ALLOW_PHASE_WRITE=1`.
- `hooks/scripts/phase-policy.json` — path policy for all seven
  phases. `.vibeflow/**` + `vibeflow.config.json` are always allowed
  so the framework never self-blocks. TESTING `warn`s on non-test
  `src/` writes; DEPLOYMENT `warn`s on `src/`.
- `skills/phase-policy.json` — advisory skill→phases registry for
  all 31 skills. Sprint 13 uses it only for documentation + the
  skill self-check template; Sprint 14 can layer invocation-level
  gating on top.
- `docs/PHASE-BOUNDARIES.md` — user-facing reference (allow/warn/
  deny table per phase, escape hatch docs, troubleshooting).
- `tests/integration/sprint-13.sh` — 55 assertions pinning the
  policy structure, the hook wire-up, the init skill regression,
  the four Phase Contracts, and the retrospective sprint docs.
- Phase Contract sections on five high-risk skills: `init`,
  `component-test-writer`, `release-decision-engine`,
  `test-strategy-planner`, `coverage-analyzer`. Each reads
  `currentPhase` and refuses to run outside its allowed phase(s).
- Retrospective docs: `docs/SPRINT-11.md`, `docs/SPRINT-12.md`,
  `docs/SPRINT-13.md`.
- `_lib.sh` helpers: `vf_policy_path`, `vf_relpath`,
  `vf_phase_decision`.

### Changed
- `hooks/hooks.json` gains a third PreToolUse entry for the new
  guard (`matcher: "Write|Edit"`).
- `skills/init/SKILL.md` rewritten: Step 4 no longer invokes
  `codebase-explorer`, no longer scaffolds tests or modifies `src/`;
  the Sprint 11-E `mode` legacy prompt removed (config template
  trimmed to match).
- `hooks/tests/run.sh` `[S13-A]` section: +15 assertions covering
  every allow/warn/deny branch of the guard and both escape hatches.
- `docs/GETTING-STARTED.md` unchanged in this sprint — already
  points at the GitHub-source marketplace flow from Sprint 12.
- Plugin version `2.0.2 → 2.1.0`. sdlc-engine `1.0.1 → 1.1.0`.
- `CLAUDE.md` baseline updated to 1753 across 13 test layers.

### Upgrade

```bash
claude plugin marketplace update vibeflow
claude plugin install vibeflow@vibeflow
```

Behaviour change: existing sessions that tried to write source code
in REQUIREMENTS/DESIGN/ARCHITECTURE/PLANNING will now see the
`phase-write-guard` block message. Either advance the phase with
`/vibeflow:advance` or use `VF_ALLOW_PHASE_WRITE=1 <tool>` for
one-shot overrides. See `docs/PHASE-BOUNDARIES.md` for the full
allow/warn/deny table.

---

## [2.0.2] — 2026-04-20

Schema fix — `.claude-plugin/plugin.json`'s `repository` and `bugs`
fields are now strings (previously `{ type, url }` objects). Claude
Code's plugin loader validates these fields as strings per the
[plugin reference](https://code.claude.com/docs/en/plugins-reference.md)
and rejects the object form with: *"repository: Invalid input:
expected string, received object"*.

Also corrected the homepage / repository URLs to point at the actual
GitHub repo `mytechsonamy/VibeFlow` (an earlier copy referenced the
wrong `mustiyildirim/vibeflow` slug).

`tests/integration/sprint-4.sh` updated in lockstep — it now asserts
string-type repository/bugs and matches the correct URL prefix. No
runtime behaviour change; upgrade is required only to get `claude
plugin install vibeflow@vibeflow` past the manifest validator.

---

## [2.0.1] — 2026-04-20

Packaging fix — makes `claude plugin install` complete in seconds
instead of hanging on a ~500 MB directory copy. No behavioural change
from 2.0.0; if your install of 2.0.0 succeeded, upgrading is optional.

### Changed
- Every MCP server now ships a self-contained `dist/bundle.js`
  (~620-690 KB) produced by `esbuild --bundle --platform=node
  --format=esm`. The bundle inlines every npm dep so the plugin
  runtime no longer needs `node_modules` on disk.
- `.mcp.json` routes all five MCP servers through `dist/bundle.js`.
- Total plugin runtime footprint: ~3.2 MB of JS plus skills/hooks/
  config. Previously claude plugin install was copying 500 MB of
  `node_modules` from the source directory because the marketplace
  `source: directory` type is a naive recursive copy.

### Fixed
- Install-hang that affected anyone doing `claude plugin marketplace
  add <local-path>` against a VibeFlow clone with populated
  `node_modules`. Install now either:
  (a) uses `claude plugin marketplace add github:<org>/VibeFlow`,
      which does a git clone (gitignored `node_modules` never leaves
      the dev machine), or
  (b) uses the local-path marketplace against a fresh clone that
      hasn't run `npm install` yet — bundles still boot standalone.

### Added
- `esbuild` to each MCP server's `devDependencies`.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>

---

## [2.0.0] — 2026-04-20

**Breaking change — state store is filesystem-only.**

Sprint 11 retired the SQLite (solo) and PostgreSQL (team) backends in
favour of a single file-backed store. Every state mutation now lands in
`.vibeflow/state/<project>/project.json` alongside an append-only event
log under `events/` and archived per-phase bundles under `archive/`.
Git versions the whole thing for free and `cat` is enough to read it.

### Removed
- `mcp-servers/sdlc-engine/src/state/sqlite.ts` + `postgres.ts` —
  replaced by `filesystem.ts`.
- `bin/with-postgres.sh`, `bin/with-postgres-matrix.sh`,
  `.github/workflows/pg-matrix.yml`, `docs/TEAM-MODE.md` — all
  Postgres-specific infrastructure.
- `mode` + `db_connection` from `.claude-plugin/plugin.json` userConfig.
- `VIBEFLOW_MODE` env from `.mcp.json` and the legacy
  `ModeSchema` / `stateStore.{sqlitePath,postgresUrl}` fields from
  `src/config.ts`.
- `better-sqlite3` (dependency) and `pg` (peer dependency) from
  `mcp-servers/sdlc-engine/package.json`.
- Integration blocks `sprint-5.sh [S5-B]`, `sprint-6.sh [S6-A]`,
  `sprint-7.sh [S7-E]`, `sprint-10.sh [S10-A]` — the behaviours they
  guarded are now covered by filesystem parity suites.

### Added
- `src/state/filesystem.ts` — `FilesystemStateStore` implements the
  unchanged `StateStore` interface. Cross-process safety via
  `proper-lockfile`; in-process safety via the existing
  `KeyedAsyncLock`. Atomic `writeFile + fsync + rename` per payload.
- `src/state/events.ts` — `StateEvent` discriminated union plus
  `deriveEvent`, `renderEventMd`, `parseEventMd`, `serializeEventJson`,
  `parseEventJson`. Every transact emits one numbered JSON+MD pair.
- Archive mechanism — on phase advance, the completed phase's events
  migrate from `events/` to `archive/NN-<PHASE>/` inside the same
  transact lock window. `read()` never touches archive.
- `VIBEFLOW_STATE_DIR` env (falls back to `.vibeflow/state`).
  `VIBEFLOW_STATE_FSYNC=off` disables fsync for CI.
- Backend-agnostic hook helpers in `hooks/scripts/_lib.sh`:
  `vf_current_phase` / `vf_last_consensus_status` /
  `vf_satisfied_criteria` read `project.json` first.

### Changed
- Plugin version: `1.5.2 → 2.0.0`.
- Engine version: `0.1.0 → 1.0.0`.

### Migration
Existing `.vibeflow/state.db` users can either start fresh
(recommended if the project history isn't load-bearing) or run the
one-shot `bin/migrate-state-db-to-fs.sh` (shipped in a follow-up
minor) to import the existing rollup into a `project.json` seed.

---

## [1.5.2] — 2026-04-19

<!-- Notes pre-filled from --notes-file. -->

### Fixed
- **Release workflow CI gauntlet — two-step recovery over v1.5.0.**
  - v1.5.1 fixed `tests/integration/sprint-4.sh [S4-C]`: the
    test-count regex was hardcoded to `Tests  [0-9]+ passed` (double
    space) and missed vitest's single-space variant on the GitHub
    Actions runner, producing "could not parse test count" for all 5
    MCP servers and failing the v1.4.0 + v1.5.0 release jobs. The new
    pipeline strips ANSI escapes, isolates the "Tests" summary line,
    and extracts `<N> passed` tolerantly.
  - v1.5.2 fixes `.github/workflows/release.yml`: sprint-8.sh `[S8-C]`
    runtime probes re-invoke release.sh in --dry-run mode, which
    trips release.sh step [0] ("working tree cleanliness") whenever
    build-all.sh rebuilt `dist/` with a tsc version that produces
    bytes different from the committed dist output. That's a
    maintainer-local sanity check; in CI the release workflow is
    already the real end-to-end release.sh run, so the [S8-C]
    structural sentinels (11 assertions) are what matter here.
    `VF_SKIP_S8C_RUNTIME=1` is now set on the sprint-8.sh invocation.
    The workflow also explicitly runs `sprint-9.sh` + `sprint-10.sh`
    which were omitted from the preflight gauntlet since Sprint 9
    (their runtime probes are tempdir-scoped + don't re-invoke
    release.sh, so no skip envs needed).

With both fixes the release.yml workflow now completes end-to-end —
the tarball + sha256 get rebuilt in the clean runner, published to
GitHub Releases, and the `gh release view v1.5.2` invariant holds.

### Added

None.

### Changed

None.

### Note on v1.5.1

v1.5.1 was cut locally and pushed as an annotated tag, but the
release-workflow gauntlet failed at sprint-8.sh [S8-C] after sprint-4.sh
[S4-C] was fixed (the gauntlet had been masking the [S8-C] failure
since the two-step recovery). No GitHub Release artifact was ever
published for v1.5.1. If you see the orphan tag in
`git tag -l "v1.5.*"`, you can delete it locally + remotely:

```
git tag -d v1.5.1
git push origin :refs/tags/v1.5.1
```

v1.5.2 is the first public post-v1.5.0 release.

### Breaking changes

None.

### Migration

N/A.

## [1.5.1] — 2026-04-19

<!-- Notes pre-filled from --notes-file. -->

### Fixed
- **Release workflow test-count regex (v1.5.1).** `tests/integration/sprint-4.sh
  [S4-C]` was failing on all 5 MCP servers in the GitHub Actions release
  workflow with "could not parse test count". Root cause: a hardcoded
  `Tests  [0-9]+ passed` pattern (double space) didn't match vitest's
  single-space variant in the GHA runner. The v1.4.0 + v1.5.0 release
  jobs both tripped on this and the public release pages had to be
  stitched together manually. The regex now strips ANSI escapes, isolates
  the "Tests" summary line, and extracts `<N> passed` tolerantly —
  including from vitest's partial-pass format (`Tests  1 failed | 47
  passed`). With this fix the release.yml workflow completes end-to-end
  and the tarball + sha256 are uploaded automatically.

### Changed

None.

### Added

None.

### Breaking changes

None.

### Migration

N/A.

## [1.5.0] — 2026-04-19

<!-- Notes pre-filled from --notes-file. -->

### Added
- **PgBouncer transaction-mode startup probe (S10-01).**
  `PostgresStateStore.init()` now opens a single client and runs two
  explicit transactions on it, comparing the backend pid via
  `pg_backend_pid()`. If the pid changes between the two transactions
  the pool is in transaction mode and `pg_advisory_xact_lock` cannot
  serialize writes — the probe throws with a clear pointer to
  `docs/TEAM-MODE.md` and the two fix paths (switch the pool to
  session mode OR connect to the direct Postgres endpoint).
  Opt-out via `VF_SKIP_POOLER_CHECK=1` for operators who run
  transaction mode deliberately and accept the advisory-lock caveat.
- **Scheduled pg-matrix weekly CI workflow (S10-03).** New
  `.github/workflows/pg-matrix.yml` runs `sprint-7.sh` with
  `VF_RUN_PG_MATRIX=1` every Monday 03:00 UTC against `main`. Manual
  re-runs via `workflow_dispatch`. Failures open a tracking issue
  (labels: `ci-failure`, `pg-matrix`) instead of emailing.
- **`release.sh --notes-file` pre-fill (S10-04).** Both
  `--notes-file <path>` and `--notes-file=<path>` accepted; the file
  body replaces the empty Added/Fixed/Changed stub block during
  CHANGELOG insertion. Missing or empty path → exit 2 with a clear
  error. New post-release warning fires when the previous CHANGELOG
  entry has empty stub sections (signal that the prior release
  shipped without notes).
- **Sprint 10 integration harness (S10-05).**
  `tests/integration/sprint-10.sh` ships 45 assertions across
  `[S10-A]` / `[S10-C]` / `[S10-D]` / `[S10-Z]`. There is no
  `[S10-B]` — that letter is reserved for a future S10-02 (managed
  cloud Postgres) reopen.

### Fixed
- `tests/integration/sprint-5.sh` release-script preflight loop now
  expects `sprint-9.sh` and `sprint-10.sh` (was: `...sprint-8.sh`).
  Catches a regression where a new sprint harness ships without
  being wired into the release gauntlet.

### Changed
- Test inventory: 15 → **16 layers**; baseline 1638 → **1694**
  passing checks offline (1698 live, 1710 with
  `VF_RUN_PG_MATRIX=1`). `sdlc-engine` vitest grew 105 → 114
  (+9 from S10-01 probe tests). `sprint-5.sh` grew 96 → 98
  (+2 from sprint-9 + sprint-10 in the preflight loop).
- `bin/release.sh` preflight gauntlet wording bumped from "all 15
  pre-flight harnesses passed" to "all 16 pre-flight harnesses
  passed".
- `docs/RELEASING.md` Quickstart gains a `--notes-file` tip block.
- `docs/TEAM-MODE.md` PgBouncer caveat updated to describe the
  live S10-01 probe + the `VF_SKIP_POOLER_CHECK=1` escape hatch.

### Dropped
- **S10-02 (live RDS / Cloud SQL / Azure Database integration test).**
  Dropped after explicit scope review — there is no managed-cloud
  deployment target, no operator volunteering AWS credentials, and
  the vanilla PG13/14/15/16 matrix (S7-02) covers the SQL surface
  we actually use today. This is a *dropped* ticket, not a
  *deferred* one — it does not carry forward to Sprint 11+ as a
  dead item. Reopen with a fresh ticket id if managed-cloud
  testing becomes relevant.

### Breaking changes

None.

### Migration

N/A.

## [1.4.0] — 2026-04-17

Fourth minor release. Sprint 9 picked up three tickets from the
Sprint 8 carry-over backlog (cross-host tarball reproducibility,
SemVer-aware tarball selection, stable-release branch guard) plus
the integration harness + release closure. A narrow scope by
design — S9-02 (pgbouncer probe), S9-03 (cloud postgres), S9-04
(scheduled pg-matrix), and S9-06 (release.sh `--notes-file`) are
explicitly deferred. 39 new integration assertions.

### Added

- **`bin/release.sh` step [1.5] branch guard** — stable releases
  refuse to run unless `HEAD` is on `main` or `release/*`. Error
  message names three recovery paths: (1) PR-and-merge to main,
  (2) re-run with `--prerelease`, (3) `VF_RELEASE_ALLOW_BRANCH=1`
  one-off override. `VF_SKIP_BRANCH_CHECK=1` is an accepted alias.
  Placed after step [1] (version argument) so an invalid version
  still exits with exit 2 regardless of branch state — preserves
  sprint-8.sh [S8-C]'s contract. `--prerelease` is exempt. (S9-05)
- **Branch-aware Next-Steps hint** — when HEAD is on main the
  release script prints `git push origin main`; off main, it
  prints the branch-specific push command plus a reminder to merge
  to main. Printing a main-push hint from a feature branch
  encouraged the stale-main drift S9-05 was cut to address. (S9-05)
- **`package-plugin.sh` GNU-tar probe (`gtar`)** — prefer `gtar`
  on `$PATH` → `tar --version` reports GNU → bsdtar fallback with
  a WARN line that surfaces the `brew install gnu-tar` remediation.
  GNU-tar path reports "cross-host reproducible"; bsdtar path
  reports "host-local reproducible". Completes the S7-05B
  reproducibility story: mac laptop + CI Linux runner now produce
  byte-identical tarballs when gtar is installed on both. (S9-01)
- **`docs/RELEASING.md` Release branch policy + Reproducible
  tarballs H2s** — policy walkthrough for step [1.5], macOS setup
  recipe for `brew install gnu-tar`, and a main-reconciliation
  recipe for the override path. (S9-01 + S9-05)
- **`tests/integration/sprint-9.sh`** — new 15th test layer with
  four sections: SemVer-aware tarball selection [S9-A] (7 static +
  2 runtime), gtar fallback [S9-B] (9 static + 1 runtime), branch
  guard [S9-C] (10 static + 4 runtime), harness self-audit [S9-Z]
  (8 assertions). Runtime opt-outs mirror Sprint 8's pattern:
  `VF_SKIP_S9A_RUNTIME` / `VF_SKIP_S9B_RUNTIME` /
  `VF_SKIP_S9C_RUNTIME`. (S9-08)

### Fixed

- **`tests/integration/sprint-4.sh [S4-H]/[S4-K]` tarball
  selection** — the fresh-install simulation used `ls
  vibeflow-plugin-*.tar.gz | head -1` which sorts alphabetically,
  picking 1.10.0 before 1.9.0 and — the bug that tripped the
  v1.3.0 cut during Sprint 8 / S8-08 — a stale 1.2.0 ahead of a
  freshly-built 1.3.0. Replaced with a jq lookup on plugin.json's
  version + explicit `vibeflow-plugin-${VERSION}.tar.gz` path
  construction. Missing-tarball path now prints a diagnostic
  listing of stray tarballs. (S9-07)
- **`package-plugin.sh` [5] verification survives pipefail +
  SIGPIPE** — per-check `tar -tzf "$ARCHIVE" | grep -q <pattern>`
  lost every match under `set -uo pipefail` on fast tar
  implementations: `grep -q` closed stdin on first match, tar
  exited 141 on SIGPIPE, pipefail propagated the 141, and the
  `if` branch evaluated false even though grep matched. Listing
  is now captured once into `$ARCHIVE_LISTING` and echoed per
  check. Same fix applied to `tests/integration/sprint-4.sh
  [S4-H]`. (S9-01)
- **`tests/integration/sprint-4.sh [S4-G]` userConfig docs check
  compat with GNU grep 3.11+** — swapped `grep -qE "\\\`key\\\`"`
  (which grep 3.11 silently no-matches, unlike earlier versions
  that treated `\`` as literal backtick) for `grep -qF
  "\`key\`"` so the pattern is always a literal match.
  (Sprint 9 polish)
- **`hooks/tests/run.sh` portable mtime read** — replaced
  `stat -f '%m' ... || stat -c '%Y' ...` with an explicit
  probe-once-then-pick pattern. GNU stat re-interprets
  `-f '%m'` as a filesystem-info request, prints fs stats to
  stdout, exits non-zero, and both sides of `||` land in the
  command-substitution capture. (Sprint 9 polish)

### Changed

- **`bin/release.sh` preflight** — runs **15 harnesses** (added
  `tests/integration/sprint-9.sh`). The "all N pre-flight
  harnesses passed" summary count corrected to 15 (was a stale 11
  — Sprint 8 forgot to rebase it when it added sprint-8.sh).
- **Baseline test count** — **1599 → 1638 offline / 1603 → 1642
  live / 1615 → 1654** with `VF_RUN_PG_MATRIX=1`. Sprint 9 adds
  39 assertions (all from the new sprint-9.sh layer); sprint-5's
  local floor also bumped from 94 → 96 to match the observed
  offline count.

### Breaking changes

None. `bin/release.sh <ver>` now refuses stable cuts from non-main
branches by default, but `VF_RELEASE_ALLOW_BRANCH=1` restores the
v1.3 behaviour for one-off situations, and `--prerelease` is
entirely exempt. Maintainers who have been cutting stable releases
from `main` see no change.

### Migration

Stable-release muscle memory stays:

```bash
# From main — same as before
git checkout main && git pull
bash bin/release.sh 1.4.1   # passes branch guard
```

If you cut v1.3.x or earlier from a feature branch, either:

```bash
# Option A: merge to main first (recommended)
gh pr create --base main --head <your-branch>
# ... review + merge ...
git checkout main && git pull && bash bin/release.sh 1.4.1

# Option B: keep the feature-branch habit, flag it explicitly
VF_RELEASE_ALLOW_BRANCH=1 bash bin/release.sh 1.4.1
# Then reconcile main:
git checkout main && git merge --ff-only <your-branch> && git push origin main
```

For cross-host reproducible tarballs, install GNU tar on macOS:

```bash
brew install gnu-tar   # adds gtar to PATH
./package-plugin.sh    # the WARN line should be gone
```

### Distribution

- **Tarball**: `vibeflow-plugin-1.4.0.tar.gz`
- **Sha256 sidecar**: `vibeflow-plugin-1.4.0.tar.gz.sha256`
- **Deterministic**: byte-identical on the same host AND
  cross-host when both sides use GNU tar (S9-01).

### Deferred to Sprint 10+

- **S9-02** PgBouncer transaction-mode startup probe
- **S9-03** Live RDS / Cloud SQL / Azure Database integration test
- **S9-04** Scheduled pg-matrix weekly CI workflow
- **S9-06** `release.sh --notes-file` pre-fill

[1.4.0]: https://github.com/mytechsonamy/vibeflow/releases/tag/v1.4.0

## [1.3.0] — 2026-04-17

Third minor release. Sprint 8 delivered the long-deferred
prerelease / beta-channel workflow (originally scoped for Sprint 6
/ S6-06, twice punted to Sprint 7 / S7-03) plus two release-cycle
hardening items captured during the v1.2.0 cut. 14 new commits,
14 new [S8-C] sentinels, and the first release cut on a branch
other than `main` — exercising the prerelease-aware promotion
path end-to-end.

### Added

- **`bin/release.sh --prerelease`** — opt-in mode that accepts
  SemVer 2.0.0 prerelease identifiers (`1.3.0-rc.1`,
  `1.3.0-beta.2`, `1.3.0-alpha`, `1.3.0-dev`). Strict
  cross-validation refuses `--prerelease` + strict X.Y.Z and
  prerelease X.Y.Z-id without `--prerelease`, each with a
  specific remediation hint. (S8-01)
- **CHANGELOG `## Pre-releases` footer** — prerelease entries
  land under this section at the bottom of `CHANGELOG.md`
  instead of the top. Stable releases continue to become
  "latest"; prereleases never do. (S8-01)
- **Two-mode `insert_changelog_entry`** — second positional arg
  (`is_prerelease`) switches between prepending at the top
  (stable) and inserting under the footer (prerelease). Post-
  insert verify guards both paths. (S8-01)
- **Conditional `gh release create --prerelease` hint** —
  the Next-Steps block surfaces the `--prerelease` flag when the
  release mode is prerelease, plus a warning line about GitHub's
  "latest" semantics and package-manager default filtering.
  Dry-run mode also prints a preview of the hint block. (S8-01)
- **`VF_SKIP_GAUNTLET=1` escape hatch** — env-only (no CLI flag
  so a human can't mis-skip the gauntlet) knob that short-
  circuits `release.sh` step [2] when the S8-C runtime sentinels
  recursively invoke `release.sh` from inside its own preflight.
  Without this, running `release.sh` would infinitely recurse
  through sprint-8.sh. (S8-01)
- **`docs/RELEASING.md` Prereleases H2** — covers when-to-cut,
  command syntax, CHANGELOG convention, rc → stable promotion
  path, tag + tarball naming, GitHub release effect. (S8-01)
- **`tests/integration/sprint-8.sh [S8-C]`** — 13 new sentinels
  (9 static + 4 runtime dry-run probes) covering the full
  prerelease surface. Runtime opt-out via `VF_SKIP_S8C_RUNTIME=1`
  for environments with dirty trees or missing pg peer dep. (S8-01)

### Fixed

- **`tests/integration/sprint-7.sh [S7-C]` multi-tarball
  save/restore** — the determinism runtime sentinel used to save
  only the FIRST pre-existing tarball (`ls … | head -1`) but
  delete ALL of them (`rm -f vibeflow-plugin-*.tar.gz`). When
  the harness ran with multiple version tarballs on disk — exactly
  what happens right after a fresh `release.sh <newer>` produces
  a new tarball alongside a stale older one — the new release
  artifact got clobbered. This bit the v1.2.0 release during
  Sprint 7 / S7-07. Rewritten save + restore loops that iterate
  every match + matching `.sha256` sidecar; `mkdir -p` for the
  save destination. Six new `[S8-A]` regression sentinels
  including a runtime fixture test that seeds two fake tarballs
  and verifies both survive. (S8-02)

### Changed

- **`.github/workflows/release.yml` preflight** — now runs
  `sprint-6.sh` + `sprint-7.sh` + `sprint-8.sh` alongside the
  existing `sprint-5.sh` step. CI release runs exercise the full
  14-layer gauntlet. `sprint-6.sh [S6-A]` concurrent-CAS walk
  and `[S6-B]` next-build gate both skip in CI (no docker-in-
  docker, no Next installed on fresh runners) via the existing
  opt-out env vars. (S8-03)
- **Baseline test count** — **1585 → 1599 offline / 1589 → 1603
  live / 1601 → 1615** with `VF_RUN_PG_MATRIX=1`. New `sprint-
  8.sh` layer contributes **33 assertions** (6 [S8-A] + 6 [S8-B] +
  13 [S8-C] + 8 [S8-Z]).

### Breaking changes

None. `bin/release.sh <ver>` continues to reject prerelease
identifiers without `--prerelease` — a v1.2 consumer that doesn't
use prereleases sees no behavioural change.

### Migration

N/A. Existing stable-release muscle memory is untouched:

```bash
bash bin/release.sh 1.4.0   # same as before — stable release
```

For prereleases, opt in explicitly:

```bash
bash bin/release.sh 1.4.0-rc.1 --prerelease
```

## [1.2.0] — 2026-04-16

Second minor release. Sprint 7 delivered v1.1's deferrals
(self-hosted GitLab, Postgres version matrix) + captured two
release-workflow lessons from the v1.1.0 cut (the "pg missing
mid-release" incident + the sha256 sidecar drift). All shipped
tickets tighten release discipline and expand the supported
infrastructure surface.

**No breaking changes.** Drop-in replacement for v1.1.0.

### Added

- **Self-hosted GitLab support — `createGitlabClient` plumbed
  end-to-end.** Sprint 5 / S5-02 shipped the client with a
  configurable `baseUrl` option, but the plugin manifest had no
  `gitlab_base_url` key, `.mcp.json` did not expose it as an env
  var, `dev-ops/src/tools.ts` never consumed it from env, and the
  19 vitest cases all hit gitlab.com. A self-hosted-GitLab user had
  to hand-edit `client.ts` to make it work. S7-01 closes every link
  of the chain: new `gitlab_base_url` + `gitlab_token` userConfig
  keys, `.mcp.json` plumbs both, `tools.ts` reads
  `process.env.GITLAB_BASE_URL` as the baseUrl fallback,
  `client.ts` coerces empty-string `baseUrl` to the default,
  9 new vitest cases + 1 tools-layer case, `docs/CONFIGURATION.md`
  gains four new rows with worked examples (SaaS, custom port,
  sub-path install, local dev). (S7-01)
- **Postgres version matrix — PG13 / PG14 / PG15 / PG16.** Sprint
  5 / S5-03 pinned the first live-Postgres test to
  `postgres:14-alpine`; Sprint 6 / S6-01 kept the pin. S7-02 ships
  `bin/with-postgres-matrix.sh` which loops `VF_PG_IMAGES` (default:
  PG13 through PG16 Alpine) and invokes the existing
  `bin/with-postgres.sh` wrapper per image. `sprint-5.sh [S5-B]`
  and `sprint-6.sh [S6-A]` taught to reuse an outer `DATABASE_URL`
  so nested wrapper calls don't collide on port 55432. Opt-in
  runtime sentinel via `VF_RUN_PG_MATRIX=1` in `sprint-7.sh [S7-E]`
  runs the full matrix end-to-end. Live-verified: all 4 PG versions
  pass the full sprint-5 walk. `docs/TEAM-MODE.md` gains a
  "Supported Postgres versions" section + a "Managed-cloud Postgres
  (AWS RDS, GCP Cloud SQL, Azure)" section covering
  `sslmode=require`, the PgBouncer transaction-mode advisory-lock
  gotcha, and IAM-auth scope. (S7-02)
- **`bin/release.sh` step [0.5] — pg peer-dep sanity check.** The
  v1.1.0 release failed mid-flight at step [5] because `pg` had
  been uninstalled during S6-01 testing and `tsc` couldn't find
  the module. plugin.json had already been bumped, leaving the
  tree in a half-released state. The new step [0.5] probes both
  `mcp-servers/sdlc-engine/node_modules/pg` AND
  `node_modules/@types/pg` before any tree mutation and surfaces
  the fix command in the error output. (S7-04)
- **`docs/RELEASING.md` Troubleshooting expanded from 6 to 9
  entries.** Three new entries capture the v1.1.0 release lessons:
  "pg peer dep is not installed", "release.sh fails MID-FLIGHT",
  and "sha256 sidecar doesn't match the uploaded tarball" (with
  the `gh release upload --clobber` recovery). (S7-05)
- **Reproducible `package-plugin.sh` tarballs.** The v1.1.0 sha256
  drift incident had a root cause: `tar -cz` bakes timestamps into
  the gzip header, and `find`'s filesystem-order output produced
  different tar orderings across runs. S7-05B rewrites step [4] to
  stage files into a tempdir, normalize mtimes to epoch 0 via
  `touch -t 197001010000.00`, sort the file list, detect BSD-vs-GNU
  tar for ownership flags, and pipe uncompressed tar through
  `gzip -n`. Two consecutive runs now produce byte-identical
  archives. `sprint-7.sh [S7-C]` includes a runtime sentinel that
  actually runs packaging twice and asserts sha256 equality.
  (S7-05B)
- **`tests/integration/sprint-7.sh`** — new 51-assertion harness
  covering all five Sprint 7 shipped tickets plus a closing
  [S7-Z] self-audit that mirrors sprint-6.sh's [S6-Z]. (S7-01 /
  S7-02 / S7-04 / S7-05 / S7-05B / S7-06)

### Changed

- **`bin/release.sh` preflight gauntlet** now runs 13 harnesses
  (was 12 in v1.1.0) — sprint-7.sh added alongside the existing
  layers.
- **`tests/integration/sprint-4.sh [S4-F]` userConfig key list**
  extended with `gitlab_token` + `gitlab_base_url` (+12
  assertions).
- **`tests/integration/sprint-4.sh [S4-H]` EXPECTED_PLUGIN_VERSION**
  bumped 1.1.0 → 1.2.0 via the parameterized variable introduced
  in S5-07.
- **`mcp-servers/dev-ops/src/client.ts`** — `createGitlabClient`
  now treats empty-string `baseUrl` the same as unset (userConfig
  values arrive as `""` for unset keys).

### Fixed

- **sha256 sidecar drift during release** — see S7-05B under Added.
  The v1.1.0 release briefly uploaded a sidecar that didn't match
  the tarball; the root cause is fixed in v1.2.0 so future releases
  produce byte-identical tarballs across runs on the same host.
- **Nested `with-postgres.sh` port collision** — sprint-5.sh
  [S5-B] and sprint-6.sh [S6-A] used to always invoke their own
  wrapper. Under the S7-02 matrix runner that caused a port-55432
  collision. Both sections now detect `DATABASE_URL` from an outer
  context and reuse the running container.

### Test baseline growth

| Version | Test layers | Baseline checks | Bonus suites |
|---------|-------------|-----------------|--------------|
| v1.0.0  | 10          | 1255            | demo-app (45) |
| v1.0.1  | 11          | 1445            | demo-app (45) + nextjs-demo (41) |
| v1.1.0  | 12          | 1489            | demo-app (45) + nextjs-demo (66) |
| v1.2.0  | **13**      | **1565**        | demo-app (45) + nextjs-demo (66) |

76-check growth v1.1.0 → v1.2.0 split:
- `sprint-7.sh` (new harness): 51 assertions across
  [S7-A/B/C/D/E/Z]
- `sprint-4.sh`: 355 → 367 (+12 from the two new userConfig keys)
- `sprint-5.sh`: 94 → 97 (+3 from preflight list + counter
  settling)
- `dev-ops` vitest: 62 → 72 (+10 from S7-01 self-hosted GitLab
  coverage)

Opt-in `VF_RUN_PG_MATRIX=1` adds +12 assertions for the 4-image
live matrix run → **1581** total.

### Breaking changes

None.

### Migration

N/A — v1.2.0 is a drop-in replacement for v1.1.0. New optional
env vars default to "do nothing":
- `VF_RUN_PG_MATRIX=1` — opt IN to the 4-image Postgres matrix
- `VF_PG_IMAGES` — override the default matrix image list
- `GITLAB_BASE_URL` — self-hosted GitLab API URL (unset = gitlab.com)
- `GITLAB_TOKEN` — GitLab PAT (unset = fall back to `GITHUB_TOKEN`)

Self-hosted GitLab users can now set `userConfig.gitlab_base_url`
directly in Claude Code plugin settings — no more hand-editing
`client.ts`.

### Distribution

- **Tarball**: `./package-plugin.sh` produces
  `vibeflow-plugin-1.2.0.tar.gz`. **Now byte-reproducible** across
  consecutive runs on the same host thanks to S7-05B.
- **Local install**: `claude --plugin-dir ~/Projects/VibeFlow`
- **Marketplace**: `claude plugin install vibeflow@vibeflow-marketplace`
- **Tag/release push**: user-gated. v1.2.0 uses the annotated
  fall-back (no `user.signingkey` on the release host).

### Documentation

- [Releasing](./docs/RELEASING.md) — now 9 troubleshooting entries
- [Team Mode](./docs/TEAM-MODE.md) — new "Supported Postgres
  versions" + "Managed-cloud Postgres" sections
- [Configuration](./docs/CONFIGURATION.md) — four new rows
  (`gitlab_base_url`, `gitlab_token`, `GITLAB_BASE_URL`,
  `GITLAB_TOKEN`)

[1.2.0]: https://github.com/mytechsonamy/VibeFlow/releases/tag/v1.2.0

## [1.1.0] — 2026-04-16

First minor release after v1.0. Sprint 6 picks up items deferred
from Sprint 5's scope decisions + the one bug surfaced during v1.0.1
(the BSD awk silent CHANGELOG break). No new SDLC skills — Sprint 6
is hardening + v1.1 polish. Real skill work lands in v1.2+.

**No breaking changes.** Drop-in replacement for v1.0.1.

### Added

- **Concurrent-advance CAS stress test on real PostgreSQL** —
  `tests/integration/sprint-6.sh [S6-A]` spins up 5 engine
  processes under `bin/with-postgres.sh` and races them all on the
  same `sdlc_advance_phase` call. Asserts exactly 1 winner + 4
  losers + final state consistency. Sprint 1's 14 `FakePool` unit
  tests covered the CAS logic at the unit layer; Sprint 5's `[S5-B]`
  walked one fresh engine against a real Postgres; neither
  exercised concurrent writers against the real wire protocol.
  `[S6-A]` closes that gap. The advisory lock + `FOR UPDATE` row
  lock serializes the writes so tightly that the revision CAS
  never has to fire — losers hit the phase validator with "Cannot
  transition to the same phase (DESIGN)" instead. (S6-01)
- **Next.js demo `"use client"` component surface** —
  `examples/nextjs-demo/components/rating-picker.tsx` is the first
  client component in the demo, backed by pure helpers in
  `lib/rating.ts` (`computeDisplay`, `clampRating`, `renderStars`,
  `isValidSubmittedRating`). 25 new vitest cases cover every branch
  in the node environment without mounting React. The detail page
  (`app/products/[id]/page.tsx`) imports the picker — this is where
  the RSC/client boundary runs. Total `examples/nextjs-demo` vitest
  count: 41 → 66. (S6-04)
- **Optional `next build` gate in the harness** —
  `sprint-6.sh [S6-B]` auto-runs `npm run build` in the Next.js demo
  when `examples/nextjs-demo/node_modules/next` is present and
  `VF_SKIP_NEXT_BUILD=1` is unset. Produces a real production build
  alongside the vitest suite, catching type/lint regressions the
  pure-logic tests cannot. Skipped gracefully when Next is not
  installed. (S6-04)
- **GPG-signed release tags** — `bin/release.sh [7]` teaches the
  release workflow to sign the tag when a key is configured, with
  a three-step graceful fall-back ladder:
  1. `VF_SKIP_GPG_SIGN=1` → annotated tag (opt-out)
  2. `user.signingkey` unset → annotated tag + configuration hint
  3. `git tag -s` fails at runtime → half-tag cleanup + annotated
     fall-back + `WARN` line surfacing the gpg error
  `TAG_MODE` is recorded and surfaced in the "Release prepared
  locally" hint block. Dry-run prints the probe result without
  creating anything. (S6-05)
- **`docs/RELEASING.md`** — new 210+ line end-to-end release
  walkthrough. Covers `bin/release.sh`'s seven steps, the tag
  signing ladder, one-time GPG key setup, `git tag -v` verification,
  a 5-step Quickstart checklist, a three-scenario Rollback guide,
  and a troubleshooting table with 5 common errors. (S6-05)
- **`tests/integration/sprint-6.sh`** — new 37-assertion harness
  covering S6-01 ([S6-A]), S6-04 ([S6-B]), S6-05 ([S6-C]), and the
  S6-08 self-audit ([S6-Z]). Skip gracefully when docker / pg /
  next are not installed. (S6-01 / S6-04 / S6-05 / S6-08)
- **`sprint-6.sh [S6-Z]` harness self-audit** — 8 sentinels that
  catch regressions a future refactor might silently introduce:
  section header presence, executable bit, release.sh preflight
  reference, shebang, `set -uo pipefail` discipline. (S6-08)

### Fixed

- **`bin/release.sh` CHANGELOG insertion — BSD awk portability.**
  The v1.0.0 implementation passed the new version entry through
  `awk -v entry="$NEW_ENTRY"` which BSD awk on macOS rejected with a
  "newline in string" runtime error on multiline values. awk exited
  non-zero, the `&& mv tmp CHANGELOG.md` short-circuited, and
  `release.sh` reported success even though CHANGELOG.md was never
  updated. First run on the v1.0.1 release session produced a
  commit with ONLY `plugin.json` bumped — a silent broken-release
  path. The insertion step is now a standalone
  `insert_changelog_entry()` helper using portable
  `head`/`tail`/`grep` + post-insertion verification. (v1.0.1
  shipped the initial patch; v1.1.0 / S6-07 adds the runtime-sentinel
  that catches this bug class at build time.)
- **`release.sh --test-changelog-insert <version>`** — new mode
  that runs ONLY the CHANGELOG insertion step against CHANGELOG.md
  in `cwd`, skipping every other release step. Called from
  isolated tempdir fixtures by `sprint-5.sh [S5-C]` with happy-path
  + header-less negative path + source-grep sentinels. Closes the
  runtime-verification gap that let the BSD awk bug slip past
  every static source-grep check. (S6-07)
- **`sprint-5.sh [S5-B]` and `sprint-6.sh [S6-A]` docker-daemon
  skip probe.** The old `command -v docker` check only verified
  the binary, not the daemon. macOS contributors with docker
  installed but Docker Desktop not running would see the walks
  fire and fail instead of skip. Added `docker info >/dev/null`
  to both skip ladders. (S6-01)

### Changed

- **`bin/release.sh` preflight gauntlet** now runs
  `tests/integration/sprint-6.sh` alongside sprint-5 and earlier
  harnesses. 11 total preflight commands.
- **`package-plugin.sh` whitelist** extended with
  `examples/nextjs-demo/components/` so the new client component
  ships in the tarball.
- **`tests/integration/sprint-4.sh [S4-H]` expected plugin version**
  parameterized via `EXPECTED_PLUGIN_VERSION` and bumped to
  `1.1.0`. Future releases bump this single variable.

### Test baseline growth

| Version | Test layers | Baseline checks | Bonus suites |
|---------|-------------|-----------------|--------------|
| v1.0.0  | 10          | 1255            | demo-app (45) |
| v1.0.1  | 11 (+ sprint-5.sh) | 1445 | demo-app (45) + nextjs-demo (41) |
| v1.1.0  | **12** (+ sprint-6.sh) | **1489** | demo-app (45) + nextjs-demo (66) |

44-check growth v1.0.1 → v1.1.0 split:
- `sprint-6.sh` (new harness): 37 assertions — [S6-A] 5 + [S6-B] 16
  + [S6-C] 12 + [S6-Z] 8 (some counted with different prerequisites
  — totals reflect the normal-dev path; live mode with docker + pg
  adds 4 more for [S6-A])
- `sprint-5.sh`: 93 → 94 (+1 for the new sprint-6.sh preflight
  entry in [S5-C])
- `nextjs-demo` vitest: 41 → 66 (+25 rating helpers in tests/rating.test.ts)

### Breaking changes

None.

### Migration

N/A — v1.1.0 is a drop-in replacement for v1.0.1. Existing
`ci_provider: github` and `ci_provider: gitlab` configurations are
unchanged. `VIBEFLOW_POSTGRES_URL` team-mode setups are unchanged.

New optional environment variables (all default to "do nothing"):
- `VF_SKIP_GPG_SIGN=1` — opt out of tag signing in `bin/release.sh`
- `VF_SKIP_NEXT_BUILD=1` — opt out of the optional `next build`
  step in `sprint-6.sh [S6-B]`

### Distribution

- **Tarball**: `./package-plugin.sh` produces
  `vibeflow-plugin-1.1.0.tar.gz` (grown slightly by the new Next.js
  demo client component + `docs/RELEASING.md`).
- **Local install**: `claude --plugin-dir ~/Projects/VibeFlow`
- **Marketplace**: `claude plugin install vibeflow@vibeflow-marketplace`
- **Tag/release push**: user-gated — `bin/release.sh` stops at a
  local commit + local tag; `git push` + `gh release create` require
  explicit authorization. The signing probe is purely opt-in — all
  maintainers can still cut a release without configuring a key.

### Documentation

- [Releasing](./docs/RELEASING.md) — new
- [Getting Started](./docs/GETTING-STARTED.md)
- [Next.js Demo Walkthrough](./examples/nextjs-demo/docs/NEXTJS-DEMO-WALKTHROUGH.md) — updated for `"use client"` boundary + `next build` gate
- [Demo Walkthrough](./examples/demo-app/docs/DEMO-WALKTHROUGH.md) — unchanged

[1.1.0]: https://github.com/mytechsonamy/VibeFlow/releases/tag/v1.1.0

## [1.0.1] — 2026-04-14

Post-v1.0 maintenance release. Closes the forward-looking stubs that
landed in v1.0.0, adds real-world coverage the original release did
not have time for, and ships the marketplace-publish workflow so
future v1.0.x releases are reproducible without hand surgery.

**No breaking changes.** No new SDLC skills — this sprint is
maintenance + missing-piece closure. Skill work returns in v1.1
(Sprint 6+).

### Added

- **GitLab CI provider** — `dev-ops` MCP server now supports
  `ci_provider: gitlab` end-to-end. New `createGitlabClient` in
  `mcp-servers/dev-ops/src/client.ts` (155 LoC) with `PRIVATE-TOKEN`
  auth, status normalization (10+ GitLab states → 3-value
  `queued`/`in_progress`/`completed`), URL-encoded `namespace/name`
  project paths, `artifacts_expire_at` expiry detection, and lazy
  construction parity with the GitHub client. Token resolution order:
  explicit → `GITLAB_TOKEN` → `GITHUB_TOKEN`. The "not yet
  implemented" stub is removed from `tools.ts`. 19 new vitest cases
  in `tests/gitlab-client.test.ts`. (S5-02)
- **Live PostgreSQL team-mode integration test** — new
  `bin/with-postgres.sh` wrapper spins up a throwaway
  `postgres:14-alpine` container, exports `DATABASE_URL` +
  `VIBEFLOW_POSTGRES_URL`, and tears down on exit/error/interrupt.
  Configurable via `VF_PG_*` env vars. `sprint-5.sh [S5-B]` drives
  the engine through a phase-1-writes / phase-2-read-in-fresh-process
  walk against the real `pg` wire protocol — the hand-rolled
  `FakePool` unit tests from Sprint 1 never exercised this path. `pg`
  moved from `optionalDependencies` to regular `dependencies` in
  `sdlc-engine/package.json` (dynamic import path preserved, so
  solo-mode users are not forced to carry it). Gracefully skips when
  docker / pg / `VF_SKIP_LIVE_POSTGRES=1`. (S5-03)
- **`bin/release.sh`** — 7-step release-prep script (working-tree
  cleanliness → strict SemVer validation → preflight gauntlet across
  all 11 layers → `plugin.json` bump → CHANGELOG stub insertion →
  `build-all.sh` + `package-plugin.sh` → sha256 manifest → local
  commit + annotated tag). **Does not push** — tag/release push is
  user-gated (same discipline as v1.0.0 in Sprint 4 / S4-07).
  `--check-clean` exit-code-only mode for CI / harness use.
  `--dry-run` walks the pipeline without writing any files. Strict
  SemVer (rejects `1.0.1-beta` and build-metadata suffixes). (S5-04)
- **`.github/workflows/release.yml`** — tag-push-triggered GitHub
  Actions workflow (`v*.*.*`). Rebuilds dists, runs the full test
  gauntlet with `VF_SKIP_LIVE_POSTGRES=1`, packages the tarball,
  verifies `plugin.json` version matches the tag, generates sha256,
  extracts release notes from CHANGELOG via awk, and uploads via
  `softprops/action-gh-release@v2`. (S5-04)
- **Second demo — `examples/nextjs-demo/`** — parallel to the
  existing TypeScript-only demo. Next.js 14 app-router project with
  two React Server Component pages, one `"use server"` action, and
  14 numbered requirements across `PROD-*` / `REV-*` / `ACT-*` /
  `PAGE-*` families. 41 vitest tests (14 catalog + 18 reviews + 9
  action) covering every branch without booting Next.js. Pre-baked
  VibeFlow artifacts: `prd-quality-report.md` (APPROVED, testability
  86), `scenario-set.md` (14 scenarios), `test-strategy.md`,
  `release-decision.md` (**GO 91/100**). `docs/NEXTJS-DEMO-WALKTHROUGH.md`
  parallels the existing demo's walkthrough. `package-plugin.sh`
  whitelist extended to ship the new demo; `.next/` added to the
  `find -prune` list so a future `next build` does not leak build
  artifacts into the tarball. (S5-05)
- **Bug #13 cross-process reproducer in the platform baseline** —
  `tests/integration/run.sh [4]` now drives two engine invocations
  against the same `state.db`: a writer (REQUIREMENTS → DESIGN) and
  a fresh reader that calls `sdlc_get_state`. Before the Sprint 4
  fix to `engine.getOrInit()` this path crashed with "revision must
  increment by exactly 1". The new reproducer fires exactly the two
  expected failures when the fix is reverted — gold-standard
  verified. (S5-01) The same reproducer is **mirrored in
  `sprint-5.sh [S5-E]`** so contributors who only run the Sprint 5
  harness still catch the regression. (S5-06)

### Changed

- **`mcp-servers/sdlc-engine/package.json`** — `pg` moved from
  `optionalDependencies` to `dependencies` so team-mode users do not
  need to manually install the peer. Solo-mode users are still
  unaffected (`openStore` dynamic-imports pg only when team mode is
  requested).
- **`package-plugin.sh`** — whitelist extended to include
  `examples/nextjs-demo/{app,lib,actions,docs,tests,.vibeflow/reports}`
  plus the standard manifest files. `find -prune` list grew to
  include `.next/` alongside `node_modules`, `__pycache__`, `.git`.
- **`docs/CONFIGURATION.md`** — `ci_provider` row updated to note
  GitLab is now implemented (v1.0.1 / Sprint 5 / S5-02).

### Fixed

- **`bin/release.sh` CHANGELOG insertion — BSD awk portability.**
  The original v1.0.0 implementation passed the new version entry
  through `awk -v entry="$NEW_ENTRY"` which BSD awk on macOS rejects
  with a "newline in string" runtime error whenever the value
  contains embedded newlines. awk then exited non-zero, the
  `&& mv tmp CHANGELOG.md` short-circuited, and release.sh reported
  success even though CHANGELOG.md was never updated — the v1.0.1
  release commit would have landed with a stale changelog. The
  insertion step is rewritten to use `head`/`tail`/`grep` (POSIX,
  no multiline-variable gotchas) with a post-insertion verification
  step that refuses to continue if the new version header is not at
  the top of CHANGELOG.md after the rewrite.

### Test baseline growth

| Version | Test layers | Baseline checks | Bonus suites |
|---------|-------------|-----------------|--------------|
| v1.0.0  | 10          | 1255            | demo-app (45) |
| v1.0.1  | **11** (+ `sprint-5.sh`) | **1445** | demo-app (45) + nextjs-demo (41) |

190-check growth split:
- `sprint-5.sh` (new harness): 87 assertions — [S5-A] GitLab 23 +
  [S5-B] Postgres 4 + [S5-C] release 14 + [S5-D] Next.js 41 +
  [S5-E] Bug #13 mirror 5
- `run.sh`: +4 (Bug #13 cross-process reproducer)
- `dev-ops` vitest: +19 (GitLab client)
- The rest of the delta reflects the test inventory refresh captured
  across the 5 MCP servers between Sprint 4 and Sprint 5.

### Breaking changes

None.

### Migration

N/A — v1.0.1 is a drop-in replacement for v1.0.0. Users of
`ci_provider: github` see no change. Users setting
`ci_provider: gitlab` who previously hit the "not yet implemented"
error can now configure a real GitLab project via the standard
`userConfig` key.

### Distribution

- **Tarball**: `./package-plugin.sh` produces
  `vibeflow-plugin-1.0.1.tar.gz` (grown by the `nextjs-demo` directory).
- **Local install**: `claude --plugin-dir ~/Projects/VibeFlow`
- **Marketplace**: `claude plugin install vibeflow@vibeflow-marketplace`
- **Tag/release push**: user-gated (`bin/release.sh` stops at a
  local commit + local annotated tag; `git push` + `gh release create`
  require explicit authorization).

### Documentation

- [Next.js Demo Walkthrough](./examples/nextjs-demo/docs/NEXTJS-DEMO-WALKTHROUGH.md) — new
- [Getting Started](./docs/GETTING-STARTED.md)
- [Demo Walkthrough](./examples/demo-app/docs/DEMO-WALKTHROUGH.md) — TypeScript-only, unchanged

[1.0.1]: https://github.com/mustiyildirim/vibeflow/releases/tag/v1.0.1

---

## [1.0.0] — 2026-04-13

First public release. Production-ready Claude Code plugin orchestrating
the full SDLC through multi-AI consensus and truth validation.

### Highlights

- **5 MCP servers** with stdio JSON-RPC interfaces, all built and shipped pre-compiled
- **26 skills** across 4 layers (L0 Truth Creation → L3 Truth Evolution)
- **7 hooks** with shared `_lib.sh` defensive helper surface
- **7 canonical pipelines** covering new feature → release decision → production feedback
- **8 user-facing docs** + a working sample project
- **1255 passing checks across 10 test layers** (5 vitest suites, 1 hook test runner, 4 integration harness scripts) — every commit since Sprint 1 has cleared this baseline

### Added — Sprint 1 (Foundations)

- **`sdlc-engine` MCP server** — authoritative SQLite/PostgreSQL state store for SDLC phase tracking, consensus verdicts, and satisfied criteria. 104 vitest cases.
- **7-phase SDLC model** — REQUIREMENTS → DESIGN → ARCHITECTURE → PLANNING → DEVELOPMENT → TESTING → DEPLOYMENT
- **Phase advance gates** with entry criteria + consensus requirements
- **Domain quality thresholds** — financial/healthcare/e-commerce/general with built-in tighten-only override discipline
- **7 hook scripts** — commit-guard, load-sdlc-context, post-edit, trigger-ai-review, test-optimizer, compact-recovery, consensus-aggregator
- **Shared `_lib.sh`** helper surface — defensive `vf_*` helpers used by every hook
- **Bash 3.2 compatibility** — works on default macOS shell without associative arrays
- **Initial integration harness** — 21 plug-in manifest + hooks.json + .mcp.json + sdlc-engine smoke checks

### Added — Sprint 2 (Truth Foundation)

- **`codebase-intel` MCP server** — per-call code analysis (structure, dependency graph, hotspots, tech debt scan). 46 vitest cases.
- **`design-bridge` MCP server** — Figma REST bridge with lazy client construction. 4 tools: fetch / extract tokens / generate styles / compare. 54 vitest cases.
- **L1 Truth Validation skills** (7 skills): architecture-validator, component-test-writer, contract-test-writer, business-rule-validator, test-data-manager, invariant-formalizer, checklist-generator
- **`test-data-manager` deterministic generator contract** — same seed → same output, no `Math.random` / `Date.now`
- **Cross-skill reference coherence** — `business-rule-validator` and `invariant-formalizer` cross-check via `test-data-manager` factories
- **`io-standard.md`** — single-source-of-truth for skill input/output naming
- **Sprint-2 integration harness** — 94 assertions covering L1 skill inventory + io-standard output coherence + cross-skill references + gate contract declarations + design-bridge round-trip
- **Bug #3 fixed** — sdlc-engine race condition under concurrent SQLite writers
- **Bug #4 fixed** — phase-index off-by-one in commit-guard
- **Bug #7 fixed** — design-bridge FIGMA_TOKEN now flows from `userConfig` instead of being hardcoded; integration harness has a regression sentinel

### Added — Sprint 3 (Execution + Decision)

- **`dev-ops` MCP server** — GitHub Actions bridge for CI orchestration. 5 tools: trigger / status / artifacts / deploy / rollback. Lazy GitHub client. 41 vitest cases.
- **`observability` MCP server** — vitest/jest/playwright reporter parser, flakiness scoring, perf trends, health dashboard. 76 vitest cases.
- **L2 Truth Execution skills** (12 skills): e2e-test-writer, uat-executor, test-result-analyzer, regression-test-runner, test-priority-engine, mutation-test-runner, environment-orchestrator, chaos-injector, cross-run-consistency, coverage-analyzer, observability-analyzer, visual-ai-analyzer
- **L3 Truth Evolution skills** (2 skills): learning-loop-engine (3 modes: test-history / production-feedback / drift-analysis), decision-recommender (4-invariant gate + structured option packages)
- **Financial-domain-only L1 skill**: reconciliation-simulator with 6 canonical ledger invariants + 6 adversarial concurrency patterns
- **Skill failure-class taxonomies** with fixed walk order and `UNCLASSIFIED-*` fallback patterns (test-result-analyzer, observability-analyzer, visual-ai-analyzer, decision-recommender)
- **Anti-AI-confidence stance** — `decision-recommender` explicitly refuses to ship a single weighted composite score, escapes to `human-judgment-needed` when confidence < 0.7
- **`reconciliation-simulator` cooperative scheduler** — deterministic interleaving for "every step is checked, not just endpoints"
- **Sprint-3 integration harness** — 111 assertions covering L1/L2/L3 skill inventory + cross-skill wiring + gate contracts + PIPELINE coverage + dev-ops/observability MCP sanity

### Added — Sprint 4 (Polish + Distribution)

- **MCP server coverage thresholds** — every server enforces 80/80/80/80 (statements/lines/functions/branches) via vitest.config.ts. observability gained 21 targeted edge-branch tests to lift parsers.ts from 54.32% to 91.66% branch coverage.
- **Hook hardening** — 7 hooks production-hardened (commit-guard Merge/Revert + command-substitution passthrough, post-edit 5s debounce + expanded skip list, trigger-ai-review 5-min rate limit, test-optimizer mtime-tagged cache, compact-recovery 4-point integrity check, consensus-aggregator 600s timeout force-finalize with APPROVED→NEEDS_REVISION demotion, load-sdlc-context degraded note). Hook test count 26 → 50 (+24 assertions).
- **Demo project** — `examples/demo-app/` showcases full VibeFlow loop against an e-commerce product catalog. 394 LoC of TypeScript across 3 modules (catalog/pricing/inventory), 45 vitest cases, 4 pre-baked VibeFlow artifacts (prd-quality-report, scenario-set, test-strategy, release-decision GO 92/100), 7-section walkthrough guide.
- **8 user docs** — GETTING-STARTED, CONFIGURATION, SKILLS-REFERENCE, PIPELINES, HOOKS, MCP-SERVERS, TROUBLESHOOTING, TEAM-MODE. Cross-referenced from a single entry point with sentinel-guarded inbound links.
- **Plugin manifest finalized** — `.claude-plugin/plugin.json` v1.0.0 with structured `repository` + `homepage` + `bugs` URLs + `ci_provider` userConfig key wired end-to-end through `.mcp.json` + dev-ops MCP `process.env.CI_PROVIDER` (defaults to github, raises loud `CiConfigError` on `gitlab` not-yet-implemented or unknown values).
- **`build-all.sh`** — single script to rebuild all 5 MCP server dist/ directories. `--check` mode for CI verification.
- **`package-plugin.sh`** — whitelist-based tarball builder with forbidden-path scan + post-archive verification + sanity caps. Produces `vibeflow-plugin-1.0.0.tar.gz` (392K, 214 files).
- **MCP server dist/ tracked in git** — `.gitignore` negation `!mcp-servers/*/dist/` so end users running `claude plugin install` get working JS without a build step. Source maps stay ignored.
- **Sprint-4 integration harness** — 285 assertions across 8 sections (S4-A through S4-H): MCP coverage config + actual coverage runs + test count floors + io-standard cross-reference + demo-app presence + user docs + plugin manifest validation + ci_provider end-to-end wiring + plugin packaging + dist tracking + tarball verification.
- **`CHANGELOG.md`** — this file.

### Test baseline growth

| Sprint | Test layers | Baseline checks |
|--------|-------------|-----------------|
| Sprint 1 | 3 (vitest, hooks, integration) | 137 |
| Sprint 2 | 5 (+ 2 new MCPs, + sprint-2 harness) | ~410 |
| Sprint 3 | 9 (+ 2 new MCPs, + sprint-3 harness) | 921 |
| Sprint 4 | 10 (+ sprint-4 harness) | **1255** |

Plus a 45-test demo-app vitest suite that ships with the plugin but is not counted in the baseline (it's a consumer of VibeFlow, not part of it).

### Bug fixes (12/12 MyVibe bugs closed)

All 12 bugs tracked in `ROADMAP.md`'s legacy MyVibe Framework backlog are
fixed and sentinel-guarded:

- **Bug #1** sdlc-engine SQLite race — Sprint 1
- **Bug #2** phase index off-by-one — Sprint 1
- **Bug #3** SQLite concurrent writer crash — Sprint 2
- **Bug #4** commit-guard phase-block fallthrough — Sprint 2
- **Bug #5** consensus aggregator quorum miscount — Sprint 2
- **Bug #6** test-data-manager non-determinism — Sprint 2
- **Bug #7** design-bridge hardcoded token — Sprint 2 (Bug #7 guard sentinel)
- **Bug #8** invariant-formalizer ambiguity false positive — Sprint 3
- **Bug #9** coverage-analyzer null-as-zero rollup — Sprint 3
- **Bug #10** chaos-injector unbounded failure cascade — Sprint 3
- **Bug #11** compact-recovery stale snapshot — Sprint 3
- **Bug #12** test-optimizer cache invalidation — Sprint 4 (S4-02)

### Breaking changes

None. v1.0.0 is the first public release.

### Migration

N/A — first release.

### Distribution

- **Tarball**: `./package-plugin.sh` produces `vibeflow-plugin-1.0.0.tar.gz`
- **Local install**: `claude --plugin-dir ~/Projects/VibeFlow`
- **Marketplace**: `claude plugin install vibeflow@vibeflow-marketplace` (when published)

### Documentation

- [Getting Started](./docs/GETTING-STARTED.md)
- [Configuration Reference](./docs/CONFIGURATION.md)
- [Skills Reference](./docs/SKILLS-REFERENCE.md) (26 skills)
- [Pipelines](./docs/PIPELINES.md) (7 canonical pipelines + decision tree)
- [Hooks](./docs/HOOKS.md)
- [MCP Servers](./docs/MCP-SERVERS.md)
- [Troubleshooting](./docs/TROUBLESHOOTING.md)
- [Team Mode](./docs/TEAM-MODE.md)
- [Demo Walkthrough](./examples/demo-app/docs/DEMO-WALKTHROUGH.md)

### Acknowledgments

Built with Claude Opus 4.6 and Claude Code, by Mustafa Yıldırım.

[1.0.0]: https://github.com/mustiyildirim/vibeflow/releases/tag/v1.0.0

---

## Pre-releases

<!-- Prerelease entries sit below this header. Stable releases stay
     above the `---` separator; prereleases never become "latest".
     Added in Sprint 8 / S8-01. -->
