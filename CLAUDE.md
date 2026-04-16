# VibeFlow - AI-Orchestrated Vibe Coding Framework

## Project Overview
VibeFlow is a Claude Code plugin that orchestrates the full SDLC through multi-AI consensus and truth validation. It combines MyVibe Framework's orchestration with TruthLayer's requirements-first quality assurance.

## Architecture Principles
- **Plugin-First**: All components are Claude Code native (skills, hooks, subagents, MCP servers)
- **Truth-Driven**: Requirements are the source of truth. Testability score < 60 blocks development
- **Consensus-Based**: Multi-AI review (Claude + ChatGPT + Gemini) with graceful degradation
- **Dual Mode**: Solo (SQLite, light hooks, single-AI) and Team (PostgreSQL, full hooks, 3-AI consensus)

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

### Ten test layers — run all ten before declaring a sprint ticket done
- **Unit (vitest) — 5 MCP servers, each with 80/80/80/80 coverage threshold:**
  - `cd mcp-servers/sdlc-engine && npm test` — 105 tests (engine, consensus, validation, phases, state store, tools, server dispatch, Bug #13 getOrInit fast-path)
  - `cd mcp-servers/codebase-intel && npm test` — 48 tests (structure, dependency graph, hotspots, tech debt, large-input scaling)
  - `cd mcp-servers/design-bridge && npm test` — 57 tests (figma fetch, token extract, style generate, compare, offline / network failure)
  - `cd mcp-servers/dev-ops && npm test` — 72 tests (GitHub client + pipelines + CI_PROVIDER selection + GitLab client 28 cases including 9 self-hosted baseUrl cases from S7-01 + tools-layer GITLAB_BASE_URL plumbing)
  - `cd mcp-servers/observability && npm test` — 76 tests (metric collect, flaky track, perf trend, health dashboard, parser edge branches)
- **Hook scripts (bash):** `bash hooks/tests/run.sh` — 52 assertions covering every hook + shared `_lib.sh` + S4-02 hardening + S4-08 output budgets
- **Integration (bash + node):**
  - `bash tests/integration/run.sh` — 398 assertions (platform baseline: plugin manifest, hooks.json, .mcp.json dist paths, 5 MCP stdio smokes, engine+hook e2e, Sprint-2 + Sprint-3 skill structural + gate-contract sentinels, Bug #13 cross-process reproducer)
  - `bash tests/integration/sprint-2.sh` — 94 assertions (Sprint 2 L1 skill coherence + io-standard + MCP sanity + bug closure)
  - `bash tests/integration/sprint-3.sh` — 111 assertions (Sprint 3 L1/L2/L3 skill inventory + cross-skill wiring + gate contracts + PIPELINE coverage + bug closure)
  - `bash tests/integration/sprint-4.sh` — 367 assertions (coverage + io-standard + demo-app + user docs + plugin manifest + ci_provider wiring + packaging + tarball + CHANGELOG sync + offline/large-input/budget sentinels + fresh-install end-to-end simulation [S4-K] + S7-01 gitlab_token/gitlab_base_url userConfig keys)
  - `bash tests/integration/sprint-5.sh` — 94 assertions (GitLab CI provider wiring [S5-A] + live PostgreSQL team-mode walk [S5-B] + release script + workflow + CHANGELOG runtime sentinel [S5-C] + Next.js demo layout + artifacts [S5-D] + Bug #13 cross-process reproducer mirror [S5-E])
  - `bash tests/integration/sprint-6.sh` — 37 assertions in normal dev (41 when docker+pg available): concurrent-advance CAS stress test on real PostgreSQL [S6-A] + Next.js demo "use client" surface + optional `next build` gate [S6-B] + GPG-signed release tags + RELEASING.md walkthrough [S6-C] + sprint-6.sh harness self-audit [S6-Z]
  - `bash tests/integration/sprint-7.sh` — 51 assertions: release.sh pg peer-dep sanity check [S7-A] + RELEASING.md troubleshooting + sha256-drift recovery [S7-B] + reproducible package-plugin.sh tarball [S7-C] + self-hosted GitLab baseUrl plumbing [S7-D] + Postgres version matrix PG13/14/15/16 [S7-E] + sprint-7.sh harness self-audit [S7-Z]. Opt-in `VF_RUN_PG_MATRIX=1` adds +12 assertions for the live 4-image matrix run.
- Total baseline: **1565 passing checks** across **13 test layers** (1569 in live mode, 1581 with `VF_RUN_PG_MATRIX=1`). Sprint 4 ✅ COMPLETE + v1.0.0 shipped. Sprint 5 ✅ COMPLETE + v1.0.1 shipped. Sprint 6 ✅ COMPLETE + v1.1.0 shipped. Sprint 7 ✅ COMPLETE + **v1.2.0 shipped 2026-04-16**. Sprint 8 seeded at `docs/SPRINT-8.md` (S7-03 + S7-07 lessons deferred in).
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

## File Naming Conventions
- Skills: `skills/<name>/SKILL.md` (YAML frontmatter with `name:` + `description:` is mandatory — the integration harness will fail if either is missing)
- Subagents: `agents/<name>.md`
- Hook scripts: `hooks/scripts/<name>.sh` — all hooks source `hooks/scripts/_lib.sh` for shared helpers (`vf_current_phase`, `vf_mode`, `vf_phase_index`, …). Never duplicate config/state reads; extend the lib instead.
- Hook tests: `hooks/tests/run.sh` — bash 3.2 compatible (no associative arrays; default macOS shell is the lowest common denominator)
- MCP servers: `mcp-servers/<name>/src/index.ts`, tests in `mcp-servers/<name>/tests/*.test.ts`
- Integration harness: `tests/integration/run.sh` — covers anything that crosses process boundaries or validates static manifests
- Sprint plans: `docs/SPRINT-{N}.md`
