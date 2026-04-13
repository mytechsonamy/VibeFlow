# Changelog

All notable changes to VibeFlow are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
