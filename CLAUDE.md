# VibeFlow - AI-Orchestrated Vibe Coding Framework

## Project Overview
VibeFlow is a Claude Code plugin that orchestrates the full SDLC through multi-AI consensus and truth validation. It combines MyVibe Framework's orchestration with TruthLayer's requirements-first quality assurance.

## Architecture Principles
- **Plugin-First**: All components are Claude Code native (skills, hooks, subagents, MCP servers)
- **Truth-Driven**: Requirements are the source of truth. Testability score < 60 blocks development
- **Consensus-Based**: Multi-AI review (Claude + ChatGPT + Gemini) with graceful degradation
- **Single Backend**: File-backed state store under `.vibeflow/state/<project>/` (`project.json` rollup + append-only `events/` + per-phase `archive/`). Git provides versioning for free. Consensus reviewer count is driven by which external CLIs are on PATH (codex/gemini), not by a mode switch.

## SDLC Phases (7)
1. REQUIREMENTS - PRD analysis, testability scoring, ambiguity detection
2. DESIGN - Figma integration, wireframes, design tokens, accessibility
3. ARCHITECTURE - ADR generation, tech decisions, 3-AI voting, formal verification
4. PLANNING - Epic breakdown, task dependency graph, test strategy, sprint planning
5. DEVELOPMENT - Code with auto quality gates (hooks), brownfield context management
6. TESTING - Full TruthLayer validation (20 skills), mutation testing, chaos injection
7. DEPLOYMENT - Release decision (GO/CONDITIONAL/BLOCKED), rollback, health checks

## Consensus Thresholds
- APPROVED: >= 90% agreement + 0 critical issues
- NEEDS_REVISION: 50-89% agreement
- REJECTED: < 50% or 2+ critical issues
- Always use enum values (ConsensusStatus.REJECTED), never string literals

## Domain-Specific Quality Thresholds
- Financial: GO >= 90, CONDITIONAL >= 75 (invariants weighted 25%)
- E-commerce: GO >= 85, CONDITIONAL >= 70 (UAT weighted 25%)
- Healthcare: GO >= 95, CONDITIONAL >= 85 (coverage weighted 30%)
- General: GO >= 80, CONDITIONAL >= 65

## Key Commands
- `/vibeflow:init` - Initialize project (mode, domain, tech stack)
- `/vibeflow:status` - Current SDLC phase, pending tasks, quality metrics
- `/vibeflow:review` - Trigger multi-AI review cycle
- `/vibeflow:advance` - Advance to next SDLC phase (with gate checks)
- `/vibeflow:prd-quality-analyzer` - Analyze PRD quality
- `/vibeflow:test-strategy-planner` - Generate test strategy from PRD
- `/vibeflow:release-decision-engine` - Produce release decision

## Build & Test
- MCP servers: `cd mcp-servers/<server> && npm install && npm run build`
- Plugin dev mode: `claude --plugin-dir ./` from VibeFlow root

### Eighteen test layers — run all eighteen before declaring a sprint ticket done
- **Unit (vitest) — 5 MCP servers, each with 80/80/80/80 coverage threshold:**
  - `cd mcp-servers/sdlc-engine && npm test` — 157 tests (engine, consensus, validation, phases, filesystem state store, tools, server dispatch, Bug #13 getOrInit fast-path, filesystem race tests incl. 5-process cross-process lock + 50-concurrent-writer Bug #6 regression, event model round-trips, Sprint 15-C phase-scoped consensus validation, Sprint 17-C HUMAN_APPROVAL_REQUIRED validator pass-through, Sprint 17-F ConsensusConfigSchema defaults + partial merge)
  - `cd mcp-servers/codebase-intel && npm test` — 48 tests (structure, dependency graph, hotspots, tech debt, large-input scaling)
  - `cd mcp-servers/design-bridge && npm test` — 57 tests (figma fetch, token extract, style generate, compare, offline / network failure)
  - `cd mcp-servers/dev-ops && npm test` — 72 tests (GitHub client + pipelines + CI_PROVIDER selection + GitLab client 28 cases including 9 self-hosted baseUrl cases from S7-01 + tools-layer GITLAB_BASE_URL plumbing)
  - `cd mcp-servers/observability && npm test` — 76 tests (metric collect, flaky track, perf trend, health dashboard, parser edge branches)
- **Hook scripts (bash):** `bash hooks/tests/run.sh` — 117 assertions covering every hook + shared `_lib.sh` + S4-02 hardening + S4-08 output budgets + S11-C filesystem-first helpers + S13-A phase-write-guard decisions + S14-A/B consensus CLI-gating + non-reviewer filtering + S16-A consensus-gate marker/pass-through/bypass + S17-A round-aware aggregator + S17-B critical dedup + Jaccard title similarity + S17-C load-sdlc-context override advisory + S19-PLAN save-plan-doc hook (sprint-numbered title + fallback + guards)
- **Integration (bash + node):**
  - `bash tests/integration/run.sh` — 398 assertions (platform baseline: plugin manifest, hooks.json, .mcp.json dist paths, 5 MCP stdio smokes, engine+hook e2e against filesystem backend, Sprint-2 + Sprint-3 skill structural + gate-contract sentinels, Bug #13 cross-process reproducer against project.json)
  - `bash tests/integration/sprint-2.sh` — 94 assertions (Sprint 2 L1 skill coherence + io-standard + MCP sanity + bug closure)
  - `bash tests/integration/sprint-3.sh` — 111 assertions (Sprint 3 L1/L2/L3 skill inventory + cross-skill wiring + gate contracts + PIPELINE coverage + bug closure)
  - `bash tests/integration/sprint-4.sh` — 352 assertions (coverage + io-standard + demo-app + user docs + plugin manifest + ci_provider wiring + packaging + tarball + CHANGELOG sync + offline/large-input/budget sentinels + fresh-install end-to-end simulation [S4-K] against project.json + archive layout + S7-01 gitlab_token/gitlab_base_url userConfig keys + S9-07 version-matched tarball lookup)
  - `bash tests/integration/sprint-5.sh` — 97 assertions (GitLab CI provider wiring [S5-A] + release script + workflow + CHANGELOG runtime sentinel [S5-C] + Next.js demo layout + artifacts [S5-D] + Bug #13 cross-process reproducer mirror [S5-E] against project.json). [S5-B] live-PG walk retired in Sprint 11-E.
  - `bash tests/integration/sprint-6.sh` — 37 assertions: Next.js demo "use client" surface + optional `next build` gate [S6-B] + GPG-signed release tags + RELEASING.md walkthrough [S6-C] + sprint-6.sh harness self-audit [S6-Z]. [S6-A] concurrent-CAS PG stress test retired in Sprint 11-E.
  - `bash tests/integration/sprint-7.sh` — 37 assertions: release.sh pg peer-dep sanity check [S7-A] + RELEASING.md troubleshooting + sha256-drift recovery [S7-B] + reproducible package-plugin.sh tarball [S7-C] + self-hosted GitLab baseUrl plumbing [S7-D] + sprint-7.sh harness self-audit [S7-Z]. [S7-E] PG version matrix retired in Sprint 11-E.
  - `bash tests/integration/sprint-8.sh` — 33 assertions: sprint-7.sh [S7-C] multi-tarball save/restore fix [S8-A] + CI release workflow wires sprint-6/7/8 [S8-B] + release.sh --prerelease workflow [S8-C] + sprint-8.sh harness self-audit [S8-Z]. Includes a runtime fixture test that seeds two fake tarballs and verifies both survive a [S7-C] run, and four runtime dry-run probes for the --prerelease mode × version quadrants.
  - `bash tests/integration/sprint-9.sh` — 39 assertions: SemVer-aware tarball selection in sprint-4.sh [S9-A] + package-plugin.sh gtar fallback for cross-host reproducibility [S9-B] + release.sh branch guard (stable cuts off main refused) [S9-C] + sprint-9.sh harness self-audit [S9-Z]. Runtime opt-outs: `VF_SKIP_S9A_RUNTIME=1` / `VF_SKIP_S9B_RUNTIME=1` / `VF_SKIP_S9C_RUNTIME=1`.
  - `bash tests/integration/sprint-10.sh` — 21 assertions: release.sh --notes-file pre-fill (static + 4-quadrant runtime) [S10-D] + sprint-10.sh harness self-audit [S10-Z]. [S10-A] PgBouncer probe + [S10-C] scheduled pg-matrix workflow retired in Sprint 11-E along with the Postgres backend. Runtime opt-out: `VF_SKIP_S10D_RUNTIME=1`.
  - `bash tests/integration/sprint-11.sh` — 20 assertions: bin/migrate-state-db-to-fs.sh round-trip (sqlite→project.json, --dry-run preserves legacy, second run no-op) [S11-F1] + bin/replay-events.sh rebuilds project.json byte-for-byte from events+archive [S11-F2] + sprint-11.sh harness self-audit [S11-Z].
  - `bash tests/integration/sprint-13.sh` — 55 assertions: hooks/scripts/phase-policy.json structural sanity [S13-A] + phase-write-guard.sh surface + hooks.json wire [S13-B]+[S13-C] + init skill regression sentinel (no codebase-explorer, no legacy mode prompt, Phase Contract present) + four Phase Contracts on critical skills + phase-policy.json skill registry coverage [S13-D] + PHASE-BOUNDARIES.md coverage for every phase and the escape hatch [S13-E] + retrospective-doc presence pins (SPRINT-11/12/13) [S13-F] + harness self-audit [S13-Z].
  - `bash tests/integration/sprint-14.sh` — 36 assertions: consensus-aggregator uses consensus.quorum override + detects codex/gemini CLIs + no longer reads vf_mode [S14-A] + aggregator filters non-reviewer subagents (reviewer=unknown bug) [S14-B] + mode concept fully retired (vf_mode gone, every hook + every committed config mode-free) [S14-C] + skill output contract — Write + explicit .vibeflow/reports/ path [S14-D] + harness self-audit [S14-Z].
  - `bash tests/integration/sprint-15.sh` — 82 assertions: consensus-orchestrator CLI output contract closes the codex/gemini plumbing gap [S15-A] + 6 analysis skills auto-invoke consensus via Final Step prose [S15-B] + phases.ts gains 5 new `consensus.<phase>.approved` exit criteria + validator scope-checks lastConsensusPhase [S15-C] + load-sdlc-context drains review-pending marker on SessionStart [S15-D] + claude-reviewer schema pins suggestions[] fields [S15-E] + new consensus-arbiter skill emits diff-first patches [S15-F] + new apply-arbiter-patch skill applies them with --yes/--run-tests/--dry-run [S15-G] + CONSENSUS-FLOW.md + ARBITER.md user docs [S15-H] + release sentinels [S15-I] + harness self-audit [S15-Z].
  - `bash tests/integration/sprint-16.sh` — 77 assertions: new `consensus-gate.sh` PreToolUse hook + hooks.json wiring [S16-A] + orchestrator/arbiter/apply drain `consensus-needed.json` marker [S16-B] + 6 analysis skills Write the marker in their Final Step with `{artifact, requiredCommand, createdAt, createdBy}` + S15-B `Final Step: Auto-Consensus` header preserved [S16-C] + docs/CONSENSUS-FLOW.md gains a "Layer 2 in detail" section [S16-D] + harness self-audit [S16-Z].
  - `bash tests/integration/sprint-17.sh` — 98 assertions: iterative consensus rounds (aggregator + orchestrator Step 5 with maxIterations/approvalThreshold/iteration.enabled) [S17-A] + critical finding dedup by {file,line_range} + Jaccard(title) + rejected-majority replacement rule [S17-B] + HUMAN_APPROVAL_REQUIRED enum + validator pass-through + humanOverrideNote threading + load-sdlc-context override advisory [S17-C] + 6 phase-specialist agents (prd-rewriter, design-spec-refiner, adr-author, test-strategy-refiner, coverage-gap-filler, runbook-editor) with diff-first + phase-contract sentinels [S17-D] + consensus-specialist dispatcher skill + phase-to-agent map + marker drain [S17-E] + ConsensusConfigSchema defaults + phase-policy registration [S17-F] + docs/CONSENSUS-ITERATION.md + docs/SPECIALISTS.md [S17-G] + harness self-audit [S17-Z].
  - `bash tests/integration/sprint-18.sh` — 67 assertions: architecture-validator auto-satisfies adr.recorded [S18-A] + test-strategy-planner auto-satisfies test-strategy.approved [S18-B] + coverage-analyzer auto-satisfies coverage.met [S18-C] + mutation-test-runner adds Final Step + auto-satisfies mutation.score.acceptable [S18-D] + consensus-orchestrator auto-satisfies code.reviewed on DEVELOPMENT + APPROVED/HUMAN_APPROVAL_REQUIRED [S18-E] + new quality-gates skill runs lint/typecheck/tests + auto-satisfies quality.gates.passed [S18-F] + new deploy-verifier skill cross-checks CI pipeline + observability + auto-satisfies deployment.verified + health.checks.passed [S18-G] + docs/AUTO-SATISFY.md per-criterion matrix + phase-policy registration [S18-H] + harness self-audit [S18-Z].
- Total baseline: **2180 passing checks** across **18 test layers** (v2.6.1 patch: +7 from `[S19-PLAN]` hook tests) (sprint-8.sh carries 4 pre-existing `[S8-C]` prerelease runtime failures that are scoped to release-tooling edge cases; the 29 passing assertions from sprint-8 are included in the total). Sprint 4 ✅ COMPLETE + v1.0.0 shipped. Sprint 5 ✅ COMPLETE + v1.0.1 shipped. Sprint 6 ✅ COMPLETE + v1.1.0 shipped. Sprint 7 ✅ COMPLETE + v1.2.0 shipped 2026-04-16. Sprint 8 ✅ COMPLETE + v1.3.0 shipped 2026-04-17. Sprint 9 ✅ COMPLETE + v1.4.0 shipped 2026-04-17. Sprint 10 ✅ COMPLETE + v1.5.0 shipped 2026-04-19. Sprint 11 ✅ COMPLETE — filesystem-only state store (breaking change), v2.0.0 shipped 2026-04-20. sqlite + postgres backends + TEAM-MODE.md + pg-matrix workflow retired with the refactor. Sprint 12 ✅ COMPLETE — esbuild-bundled MCP servers + `github:` marketplace flow, v2.0.1 shipped 2026-04-20; v2.0.2 hotfix (plugin.json repository/bugs as string per loader schema) on same day. Sprint 13 ✅ COMPLETE — generic phase enforcement via `phase-write-guard.sh` PreToolUse hook, `hooks/scripts/phase-policy.json` path policy, skill Phase Contracts, and `docs/PHASE-BOUNDARIES.md` user reference. v2.1.0 shipped 2026-04-20. Sprint 14 ✅ COMPLETE — consensus flow is CLI-availability-driven (codex/gemini gate-free; no more solo/team mode gate), `reviewer=unknown` bug closed by filtering non-reviewer subagents, `mode` concept fully retired (vf_mode deleted, every hook + config + doc cleaned), and four skills' output contracts fixed so `.vibeflow/reports/*.md` artifacts actually land on disk. v2.2.0 shipped 2026-04-20. Sprint 15 ✅ COMPLETE — MyVibe closed-loop completed: consensus-orchestrator now appends codex/gemini CLI verdicts directly into the session jsonl (closes the 600s-timeout demotion bug), 6 analysis skills auto-invoke consensus, phase-scoped consensus exit criteria block `/vibeflow:advance` without a fresh per-phase APPROVED verdict, new `consensus-arbiter` skill turns reviewer suggestions into diff-first patches (never writes to source), new `apply-arbiter-patch` skill applies with preview + explicit confirmation. v2.3.0 shipped 2026-04-20. Sprint 16 ✅ COMPLETE — auto-consensus chain made deterministic: analysis skills now Write `.vibeflow/state/consensus-needed.json` as their Final Step, a new `consensus-gate.sh` PreToolUse hook blocks every subsequent `Bash|Write|Edit` tool call until the operator runs `/vibeflow:consensus-orchestrator`, and the orchestrator + arbiter + apply skills all drain the marker on success. Closes the "forked subagent can't invoke a slash command" gap in Layer 2. v2.4.0 shipped 2026-04-20. Sprint 17 ✅ COMPLETE — iterative consensus negotiation loop, critical finding dedup (by {file,line_range} or Jaccard title similarity), new HUMAN_APPROVAL_REQUIRED status (pass-with-audit) when `consensus.maxIterations` rounds pass without reaching `consensus.approvalThreshold`, six new phase-specialist subagents (one per SDLC phase) that deeply rewrite artifacts based on reviewer feedback as one unified diff-first patch, and a `consensus-specialist` dispatcher skill that forks the right specialist based on currentPhase. Retires the pre-17 `agreement<0.5 → REJECTED` rule that was falsely promoting unanimous NEEDS_REVISION to REJECTED. v2.5.0 shipped 2026-04-20. Sprint 17.1-.4 polish (v2.5.1/.2/.3/.4): ship `/vibeflow:advance` skill with default-to-next; fix `.mcp.json` paths to use `${CLAUDE_PLUGIN_ROOT}` so MCP tools surface in consumer projects; auto-record consensus + auto-satisfy prd.approved/testability.score>=60 from the orchestrator + prd-quality-analyzer. Sprint 18 ✅ COMPLETE — full auto-satisfy rollout: architecture-validator/test-strategy-planner/coverage-analyzer/mutation-test-runner auto-satisfy their respective exit criteria; orchestrator auto-satisfies `code.reviewed` on DEVELOPMENT APPROVED; new `quality-gates` skill runs lint/typecheck/tests and satisfies `quality.gates.passed`; new `deploy-verifier` skill cross-checks CI + endpoints + observability and satisfies `deployment.verified` + `health.checks.passed`. Remaining three criteria (`design.approved`, `accessibility.verified`, `sprint.planned`) kept operator-driven and documented in `docs/AUTO-SATISFY.md` with rationale. v2.6.0 shipped 2026-04-21.
- **Bonus (not in baseline):** `examples/demo-app/` ships 45 vitest tests and `examples/nextjs-demo/` ships **66** vitest tests (41 from S5-05 + 25 from S6-04 rating helpers) — run with `cd examples/<demo> && npm install && npm test`. The Next.js demo also supports `npm run build` (production build); `sprint-6.sh [S6-B]` auto-runs it when `examples/nextjs-demo/node_modules/next` is present and `VF_SKIP_NEXT_BUILD` is unset.

## Coding Conventions
- TypeScript for all MCP servers and scripts
- Zod schemas for all MCP tool input validation
- Enum-safe comparisons (never string literals for status values)
- All skill outputs follow the explainability contract: { finding, why, impact, confidence }

## Sprint Tracking
- Full roadmap: `ROADMAP.md` (4 sprints, skill inventory, bug tracker)
- Active sprint: the highest-numbered file in `docs/SPRINT-*.md` that is not yet marked ✅ COMPLETE
- When starting a new session, read the active sprint file to find the next ticket (look for "Next Ticket to Work On")
- When completing a ticket, tick its checkbox in the active sprint file
- When all Sprint N tickets are done, mark that file ✅ COMPLETE and create `docs/SPRINT-{N+1}.md` seeded from ROADMAP.md. Do not leave the previous sprint file as the active pointer.
- `docs/SPRINT-*.md` files are auto-written by `hooks/scripts/save-plan-doc.sh` on every `ExitPlanMode` (v2.6.1). A plan titled `# Sprint NN — …` lands at `docs/SPRINT-NN.md`; non-sprint plans fall back to `docs/plans/<slug>-<date>.md`. Sprints 14-18 were backfilled from release-notes on 2026-04-22 as part of the same patch.

## File Naming Conventions
- Skills: `skills/<name>/SKILL.md` (YAML frontmatter with `name:` + `description:` is mandatory — the integration harness will fail if either is missing)
- Subagents: `agents/<name>.md`
- Hook scripts: `hooks/scripts/<name>.sh` — all hooks source `hooks/scripts/_lib.sh` for shared helpers (`vf_current_phase`, `vf_mode`, `vf_phase_index`, …). Never duplicate config/state reads; extend the lib instead.
- Hook tests: `hooks/tests/run.sh` — bash 3.2 compatible (no associative arrays; default macOS shell is the lowest common denominator)
- MCP servers: `mcp-servers/<name>/src/index.ts`, tests in `mcp-servers/<name>/tests/*.test.ts`
- Integration harness: `tests/integration/run.sh` — covers anything that crosses process boundaries or validates static manifests
- Sprint plans: `docs/SPRINT-{N}.md`
