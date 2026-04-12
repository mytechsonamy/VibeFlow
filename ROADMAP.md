# VibeFlow Development Roadmap

## Vision
MyVibe Framework (SDLC orchestration) + TruthLayer (requirements-first validation) = VibeFlow Claude Code Plugin.

## Architecture: 5 Layers
1. **Foundation** — CLAUDE.md (project context, conventions)
2. **Orchestration** — 5 MCP servers (sdlc-engine, codebase-intel, design-bridge, dev-ops, observability)
3. **Intelligence** — 31 native skills (7 TruthLayer-converted + 24 remaining)
4. **Automation** — hooks (commit-guard, test-optimizer, post-edit, context-load, consensus-aggregator, compact-recovery)
5. **Collaboration** — subagents (claude-reviewer, codebase-explorer, test-analyst)

## Bug Tracker (MyVibe Legacy)
| # | Bug | Status | Fix Location |
|---|-----|--------|-------------|
| 1 | Consensus enum case mismatch | FIXED | sdlc-engine/src/consensus.ts |
| 2 | Hardcoded gpt-5.3 model | FIXED | vibeflow.config.json + config.ts |
| 3 | Missing Figma error handling | FIXED | design-bridge/src/client.ts (single wrapped error path + tests) |
| 4 | PostgreSQL pool leak | FIXED | sdlc-engine/src/state/postgres.ts (release-with-err, pool error handler, timeouts, metrics, FakePool tests) |
| 5 | No phase transition validation | FIXED | sdlc-engine/src/validation.ts |
| 6 | State persistence race condition | FIXED | sdlc-engine/src/state/sqlite.ts |
| 7 | Figma token in code | FIXED | design-bridge via .mcp.json env + plugin.json userConfig (sensitive) |
| 8 | No CLI fallback for AI providers | FIXED | consensus-orchestrator SKILL.md |
| 9 | Hardcoded phase order | FIXED | sdlc-engine/src/phases.ts |
| 10 | Missing test infrastructure | FIXED | sdlc-engine/tests/ (90 vitest) + hooks/tests/ (26) + tests/integration/ (21) |
| 11 | No compact recovery | FIXED | hooks/scripts/compact-recovery.sh (reads live state.db, not cached snapshot) |
| 12 | Git hooks not atomic | FIXED | hooks/scripts/commit-guard.sh (phase gate + conventional-commit enforcement, exits 2 on block) |

---

## Sprint Plan

### Sprint 1: Core Engine + P0 Skills ✅ COMPLETE
**Goal:** Working SDLC engine with quality gates and core validation skills.
**Status file:** docs/SPRINT-1.md
**Result:** 10/10 tickets done. 137 passing checks across 3 test layers (vitest unit + hook bash + integration harness).
**Shipped:** sdlc-engine MCP (7 modules, 5 tools); 9 skills; 7 hook scripts + shared lib; 3 subagents; `.mcp.json` + plugin manifest wiring.

### Sprint 2: Codebase Intelligence + Design + Layer 0-1 Skills ✅ COMPLETE
**Goal:** Brownfield project support, Figma integration, complete TruthLayer Layers 0 and 1.
**Tickets:** 11/11 done (2 MCP servers, 7 L1 skills, Bug #3/#4/#7 FIXED, Sprint 2 integration harness).
**Status file:** docs/SPRINT-2.md
**Result:** 445 passing checks across 6 test layers. 2 new MCP servers (codebase-intel — 46 tests, design-bridge — 54 tests) + 7 new L1 skills with 88 integration guards for their contracts.

### Sprint 3: DevOps + Observability + Layer 2-3 Skills (Next)
**Goal:** CI/CD integration, monitoring, test execution and evolution skills.
**Tickets:** 18 (2 MCP servers, 15 skills, 1 integration test)
**Status file:** docs/SPRINT-3.md

### Sprint 4: Polish + Packaging + Distribution
**Goal:** Plugin marketplace ready, documentation, demo project.
**Tickets:** 9 (tests, hooks hardening, demo, docs, packaging, release)
**Status file:** docs/SPRINT-4.md

---

## Skill Inventory (30 Total)

### Built (9) — Sprint 1
| Skill | Layer | Sprint |
|-------|-------|--------|
| init | Utility | 1 |
| status | Utility | 1 |
| prd-quality-analyzer | L0 Truth Creation | 1 |
| test-strategy-planner | L0 Truth Creation | 1 |
| traceability-engine | L1 Truth Validation | 1 |
| release-decision-engine | L3 Truth Evolution | 1 |
| consensus-orchestrator | Orchestration | 1 |
| repo-fingerprint | Utility | 1 |
| arch-guardrails | L0 Truth Creation | 1 |

### Remaining (21)
| Skill | Layer | Sprint |
|-------|-------|--------|
| architecture-validator | L0 Truth Creation | 2 |
| component-test-writer | L1 Truth Validation | 2 |
| contract-test-writer | L1 Truth Validation | 2 |
| business-rule-validator | L1 Truth Validation | 2 |
| test-data-manager | L1 Truth Validation | 2 |
| e2e-test-writer | L2 Truth Execution | 3 |
| uat-executor | L2 Truth Execution | 3 |
| regression-test-runner | L2 Truth Execution | 3 |
| test-priority-engine | L2 Truth Execution | 3 |
| mutation-test-runner | L2 Truth Execution | 3 |
| environment-orchestrator | L2 Truth Execution | 3 |
| chaos-injector | L2 Truth Execution | 3 |
| cross-run-consistency | L2 Truth Execution | 3 |
| test-result-analyzer | L2 Truth Execution | 3 |
| coverage-analyzer | L2 Truth Execution | 3 |
| observability-analyzer | L2 Truth Execution | 3 |
| invariant-formalizer | L1 Truth Validation | 2 |
| checklist-generator | L1 Truth Validation | 2 |
| visual-ai-analyzer | L2 Truth Execution | 3 |
| learning-loop-engine | L3 Truth Evolution | 3 |
| decision-recommender | L3 Truth Evolution | 3 |

### MCP Servers
| Server | Sprint | Status |
|--------|--------|--------|
| sdlc-engine | 1 | BUILT |
| codebase-intel | 2 | Stub dir exists |
| design-bridge | 2 | Stub dir exists |
| dev-ops | 3 | Stub dir exists |
| observability | 3 | Stub dir exists |
