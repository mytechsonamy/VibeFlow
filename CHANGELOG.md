# Changelog

All notable changes to VibeFlow are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

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
