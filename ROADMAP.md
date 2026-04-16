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
| 13 | sdlc_get_state crash on read-after-write | FIXED | sdlc-engine/src/engine.ts (Sprint 4 / S4-09): getOrInit was wrapping its read inside store.transact, which on an existing project failed the mutator's revision-must-bump assertion. Fast-path read fix; regression test in engine.test.ts; cross-process reproducer scheduled in Sprint 5 / S5-01. |

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

### Sprint 3: DevOps + Observability + Layer 2-3 Skills ✅ COMPLETE
**Goal:** CI/CD integration, monitoring, test execution and evolution skills.
**Tickets:** 18/18 done (2 MCP servers, 15 skills, 1 integration test)
**Status file:** docs/SPRINT-3.md
**Result:** 921 passing checks across 9 test layers. dev-ops + observability MCPs (37 + 55 vitest), 15 new skills across L1/L2/L3 layers (including the financial-only reconciliation-simulator), `tests/integration/sprint-3.sh` (111 assertions).

### Sprint 4: Polish + Packaging + Distribution ✅ COMPLETE
**Goal:** Plugin marketplace ready, documentation, demo project, v1.0 release readiness.
**Tickets:** 9/9 done (S4-01 coverage thresholds, S4-02 hook hardening, S4-03 demo, S4-04 8 user docs, S4-05 manifest finalization + ci_provider, S4-06 packaging, S4-07 CHANGELOG, S4-08 perf + edge cases, S4-09 fresh-install simulation)
**Status file:** docs/SPRINT-4.md
**Result:** 1335 passing checks across 10 test layers. v1.0.0 release-ready (`vibeflow-plugin-1.0.0.tar.gz` reproducible via `./package-plugin.sh`). Bug #13 caught + fixed during S4-09. Git tag + GitHub release pending user authorization.

### Sprint 5: v1.0.x Maintenance + GitLab + Real-World Hardening ✅ COMPLETE
**Goal:** Close v1.0 forward-looking stubs (GitLab CI provider, live PostgreSQL test), add cross-process Bug #13 reproducer, ship marketplace publish workflow.
**Tickets:** 7/7 done (S5-01 Bug #13 cross-process repro, S5-02 GitLab provider, S5-03 live Postgres, S5-04 release script + workflow, S5-05 Next.js demo, S5-06 sprint-5 harness + Bug #13 mirror, S5-07 v1.0.1 closure + release.sh BSD awk fix)
**Status file:** docs/SPRINT-5.md
**Result:** 1445 passing checks across 11 test layers. v1.0.1 shipped 2026-04-14 at https://github.com/mytechsonamy/VibeFlow/releases/tag/v1.0.1 (`vibeflow-plugin-1.0.1.tar.gz` 418 KB, sha256 `be5bb4a...`). Second demo (`examples/nextjs-demo/`) ships alongside the TypeScript-only demo. `bin/release.sh` discipline automated + gated on user authorization for the push step. `tests/integration/sprint-5.sh` harness runs alongside sprint-2/3/4.

### Sprint 6: v1.1 Hardening + Deferred Items ✅ COMPLETE
**Goal:** v1.1 hardening — pick up items deferred from Sprint 5 scope decisions + fix the BSD awk bug surfaced during v1.0.1 release.
**Tickets:** 5/9 shipped (S6-01 concurrent Postgres CAS stress, S6-04 Next.js `"use client"` + next build, S6-05 GPG-signed release tags + RELEASING.md, S6-07 release.sh CHANGELOG runtime sentinel, S6-08 sprint-6.sh closure + self-audit, S6-09 v1.1.0 closure). S6-02 / S6-03 / S6-06 deferred to Sprint 7.
**Status file:** docs/SPRINT-6.md
**Result:** 1489 passing checks across 12 test layers. **v1.1.0 shipped 2026-04-16** at https://github.com/mytechsonamy/VibeFlow/releases/tag/v1.1.0 (`vibeflow-plugin-1.1.0.tar.gz`, sha256 `2e1beae...`). Second demo (nextjs-demo) grew from 41 → 66 vitest tests via the new `"use client"` RatingPicker + lib/rating.ts helpers. `bin/release.sh` now signs tags when `user.signingkey` is configured, with a three-step graceful fall-back ladder; full release workflow documented in `docs/RELEASING.md`.

### Sprint 7: v1.2 Release Hardening + Deferred Items ✅ COMPLETE
**Goal:** v1.2 hardening — pick up Sprint 6 deferrals (self-hosted GitLab, Postgres version matrix) + fix the two release-workflow lessons captured during v1.1.0.
**Tickets:** 6/7 shipped (S7-01 self-hosted GitLab, S7-02 Postgres version matrix, S7-04 pre-step-5 pg sanity check, S7-05 RELEASING troubleshooting, S7-05B reproducible tarballs, S7-06 sprint-7.sh closure, S7-07 v1.2.0 closure). S7-03 (prerelease workflow) deferred to Sprint 8.
**Status file:** docs/SPRINT-7.md
**Result:** 1565 passing checks across 13 test layers (1581 with `VF_RUN_PG_MATRIX=1`). **v1.2.0 shipped 2026-04-16** at https://github.com/mytechsonamy/VibeFlow/releases/tag/v1.2.0 (`vibeflow-plugin-1.2.0.tar.gz`, sha256 `9c97c93...`). Self-hosted GitLab plumbed end-to-end (new `gitlab_base_url` + `gitlab_token` userConfig keys). Postgres matrix covers PG13/14/15/16 with managed-cloud caveats documented in TEAM-MODE.md. `bin/release.sh` now has a pg peer-dep sanity check at step [0.5]; `package-plugin.sh` produces byte-reproducible tarballs; `docs/RELEASING.md` gained three new troubleshooting entries (6 → 9).

### Sprint 8: v1.3 Scope TBD (Next)
**Goal:** v1.3 — pick up Sprint 7 deferral (prerelease workflow) + the two [S7-C] bug fixes captured during S7-07, + any new items that surface during v1.2 usage.
**Candidate tickets** (seeded from Sprint 7 deferrals):
- Automated prerelease / beta-channel workflow in `bin/release.sh` (deferred from S7-03, originally S6-06)
- Fix sprint-7.sh [S7-C] multi-tarball save/restore bug (captured during S7-07 v1.2.0 release)
- Consolidate deferred workflow changes (sprint-6.sh + sprint-7.sh CI wiring — both blocked on PAT workflow scope)
- Cross-host deterministic tarballs (`tar --mtime=@0` + normalized bsdtar / GNU tar variance)
- Startup probe that rejects PgBouncer transaction-mode pools explicitly (documented in TEAM-MODE.md but not detected in code as of v1.2)
- Live RDS / Cloud SQL / Azure Database integration test (needs a managed-cloud CI account)
**Status file:** docs/SPRINT-8.md (seeded with candidate backlog — confirm scope before starting)
**Targets:** v1.3.0

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
