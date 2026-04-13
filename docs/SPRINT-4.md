# Sprint 4: Polish + Packaging + Distribution

## Sprint Goal
Production-ready plugin: full test coverage, documentation, demo project, and plugin marketplace packaging.

## Prerequisites
- Sprint 3 complete (all 5 MCPs, all 31 skills, all 7 pipelines working)

## Completion Criteria
- [ ] Plugin passes `claude plugin validate` cleanly
- [ ] Demo project completes full SDLC cycle (REQUIREMENTS → DEPLOYMENT)
- [ ] All MCP servers have >80% test coverage
- [ ] User documentation covers all skills and pipelines
- [ ] Plugin packaged and installable via `claude plugin install`
- [ ] CHANGELOG.md and versioned release (v1.0.0)

---

## Tickets

### S4-01: Comprehensive test suite ✅ DONE
**Location:** `mcp-servers/*/vitest.config.ts` + `tests/integration/sprint-4.sh`

**Completed:**
- [x] codebase-intel: 93% stmt / 80.75% branch (above 80% global threshold)
- [x] design-bridge: 90.08% stmt / 86.06% branch (above 80% global threshold)
- [x] dev-ops: 91.17% stmt / 91.07% branch (above 80% global threshold)
- [x] observability: 97.57% stmt / 88.62% branch (started at 75.92% branch — added 21 targeted tests to raise parsers.ts branch from 54.32% → 91.66% and tools.ts branch from 69.69% → 82.05%)
- [x] sdlc-engine: 93.01% stmt / 88.62% branch (above 80% global threshold; 104 tests)
- [x] Cross-MCP integration — covered by existing `run.sh [5]` engine+hook e2e flow (walks the sdlc-engine from REQUIREMENTS → DEVELOPMENT and validates hook scripts read the state correctly). Since no other MCP depends on engine state at runtime (codebase-intel / design-bridge / dev-ops / observability are stateless per-call), this is the single real cross-MCP seam and it is already tested.
- [x] Skill output schema validation — `sprint-4.sh [S4-D]` cross-references every skill in io-standard.md against the corresponding SKILL.md to confirm the declared output name is cited. 52 assertions (26 skills × 2 — declare + name).

**Coverage configuration (`mcp-servers/*/vitest.config.ts`):**
- `provider: v8` — same v8 coverage reporter, version-matched to vitest 2.1.9
- `include: ["src/**/*.ts"]` — source only
- `exclude: ["src/index.ts"]` — the stdio bootstrap is not testable from vitest; the integration harness (`run.sh [4]`) exercises it end-to-end instead
- `thresholds: { statements: 80, lines: 80, functions: 80, branches: 80 }` — global thresholds, not per-file (per-file would drown on marginally-covered utility files that the global gate already catches aggregated)
- Install: `@vitest/coverage-v8@^2.1.2` added as devDependency on all 5 MCPs

**Observability branch-coverage raise — 21 new tests (55 → 76):**
- `parsers.test.ts` — 15 edge-branch tests: empty testResults, missing testFilePath, missing fullName/ancestorTitles/title, non-number duration, retryReasons fallback when invocations absent, non-object input throw, negative duration clamp, multi-word status normalization (SKIP/todo/disabled/wombat), non-string status coercion, parsePlaywright nested sub-suites walk, missing stats.startTime fallback to 0, spec with empty results array, non-object throw, missing spec.file AND suite.file fallback to `<unknown>`, last-retry-result precedence
- `tools.test.ts` — 6 new tests: reporterPath not found → ReporterParseError, reporterPath not valid JSON → ReporterParseError, ob_track_flaky trusts pre-normalized inline runs, ob_track_flaky parses raw reporter inline runs via `parseReporter`, ob_track_flaky reads normalized runs from historyDir

These tests were not "for coverage"; they catch real error branches. Every one corresponds to a payload a downstream consumer could actually send, and the skill's current behavior (throw / fallback / normalize) was undocumented before. Coverage went from 95.01% stmt / 75.92% branch (below threshold) to 97.57% stmt / 88.62% branch — well above threshold.

**Test count regression guards (`sprint-4.sh [S4-C]`):** floor values per MCP server that the harness walks every run. Dropping below any floor fails the harness loudly. Same discipline as `hooks/tests/run.sh`'s count floors.

| MCP | Floor |
|-----|-------|
| sdlc-engine | 104 |
| codebase-intel | 46 |
| design-bridge | 54 |
| dev-ops | 37 |
| observability | 76 |

**`tests/integration/sprint-4.sh` (96 assertions, 4 sections):**
- **S4-A** — vitest.config.ts coverage configuration (40 assertions): each MCP has config file + v8 provider + index.ts excluded + 4 thresholds @ 80 each
- **S4-B** — actual coverage threshold satisfaction (5 assertions): runs `vitest run --coverage` on each MCP and verifies exit 0
- **S4-C** — test count regression guards (5 assertions): verifies each MCP meets its test count floor
- **S4-D** — io-standard output consistency (52 assertions): cross-references 26 skills × (declare in io-standard.md + name output in SKILL.md)

**Sentinel fixes during harness bring-up:** three initial failures, all from skill-name drift between io-standard.md and the sprint-4.sh hand-maintained map:
1. `scenario-generator` does not exist — removed from the list
2. `traceability-agent` is actually `traceability-engine` — renamed
3. `checklist-generator` output is `checklist-<context>-<platform>-<ISO>.md` (templated), not `checklist.md` — loosened sentinel to `checklist-` prefix

### S4-02: Hook hardening ✅ DONE
Production-ready hook scripts with explicit edge-case handling + 24 new tests.

**Completed:**
- [x] **commit-guard.sh** — allow `Merge ` / `Revert ` prefixes (git's built-in formats — blocking them would force users to rewrite git's own output by hand) and pass-through on `$(...)` / `${...}` command substitution in `-m` (the literal we capture is not the expanded message, so we defer to git rather than validating a stale literal).
- [x] **load-sdlc-context.sh** — emit explicit `(degraded: ... phase read from config)` note when sqlite3 is unavailable, state.db is missing, or state.db is corrupt. The context line is still emitted with a config-derived phase, but the caller knows it's approximate.
- [x] **post-edit.sh** — debounce same-file edits within 5 seconds (suppresses auto-save / format-on-save loops from hammering the trace log with duplicate rows). Extended the skip list from md/json/etc. to also cover `.env*`, `.DS_Store`, editor swap files (`.swp` / `.swo`), emacs backup files (`*~`), emacs lock files (`.#*`), and emacs autosave files (`#*#`).
- [x] **trigger-ai-review.sh** — rate limit to max 1 review marker per 5 minutes. If `review-pending.json` exists and its `requestedAt` is within 300 seconds, the existing marker stays authoritative and the new commit does not overwrite it. Prevents a flurry of quick commits from resetting the consensus-orchestrator queue position.
- [x] **test-optimizer.sh** — cache resolved source → test mappings in `.vibeflow/state/test-mapping.cache.json` keyed by source file path and tagged with the source's mtime. Cache hits (same path + same mtime + resolved test still exists) skip the full `tries[]` walk. Cache misses re-resolve and update. Source-file disappearance evicts the stale entry.
- [x] **compact-recovery.sh** — 4-point integrity check runs before emitting the snapshot: state.db exists + readable by sqlite3, satisfied_criteria is valid JSON, config.currentPhase matches state.db.current_phase (state.db wins, disagreement surfaced). Any failure appends a `state integrity degraded: <reasons>` line to the snapshot so the model knows to re-hydrate via `/vibeflow:status`.
- [x] **consensus-aggregator.sh** — timeout force-finalize after 600 seconds. When a new review arrives, the oldest entry in the session log is checked; if > 600s old and quorum not reached, the batch is finalized with `timeout: true`, `expectedReviewers`, `receivedReviewers` fields recorded in the verdict. An APPROVED status with timeout is demoted to NEEDS_REVISION — a partial quorum cannot ship an APPROVED verdict because the missing reviewer could have objected.

**Hook test regression (26 → 50, +24):**

| Hook | New assertions |
|------|----------------|
| commit-guard | Merge allow (1) + Revert allow (1) + command substitution passthrough (1) |
| load-sdlc-context | degraded note when state.db missing (2) |
| post-edit | .env skip (1) + .DS_Store skip (1) + .swp skip (1) + ~ backup skip (1) + debounce same-file (1) + debounce doesn't suppress different files (1) |
| trigger-ai-review | rate limit within 5 min (1) |
| test-optimizer | cache written (1) + cache records mapping (1) + second run reuses cache (1) + mtime-invalidation re-resolves (1) |
| compact-recovery | integrity degraded on config/db disagreement (1) + reason names both phases (1) + state.db missing reported (1) |
| consensus-aggregator | timeout force-finalize (1) + timeout flag set (1) + APPROVED demoted to NEEDS_REVISION (1) + received reviewer count recorded (1) |

**Implementation bug caught during test bring-up:** bash `IFS=$'\t' read -r a b c` collapses consecutive tab delimiters because tab is an IFS-whitespace character; a string like `src\t\tmtime` parses as two fields (`src`, `mtime`), not three. The initial test-optimizer cache implementation used a `CACHE_UPDATES` array with tab-delimited entries and `read` to split them — on the "source exists but no test found" path (empty resolved field), the mtime would silently slide into the resolved slot, causing jq to try `--argjson m ""` and fail. Fix: dropped the array indirection and call `cache_set` / `cache_del` inline in the loop. Also serves as a reminder that tab is the worst possible delimiter for bash `read` when any field can legitimately be empty.

**Merge/Revert sentinel fix:** the bash capture regex `-m[[:space:]]*\"([^\"]+)\"` stops at the first inner `"`, so `git commit -m "Revert \"feat: foo\""` captures `Revert \` (truncated). The allow-list `^Revert[[:space:]]` matches both the full `Revert "..."` and the truncated `Revert \` form — the point is to not block, not to validate the message shape.

### S4-03: Demo project ✅ DONE
**Location:** `examples/demo-app/` (18 files, 3 source modules, 3 test files, 4 pre-baked VibeFlow artifacts)

**Completed:**
- [x] `examples/demo-app/docs/PRD.md` — sample PRD for an e-commerce product catalog with 15 numbered requirements across 3 families (CAT-* / PRC-* / INV-*) plus 3 cross-cutting invariants. Written to high-testability standards — the pre-baked `prd-quality-report.md` scores 87 (above the e-commerce 75 threshold). Deliberately avoids the ambiguity-trigger words (fast, easy, intuitive, scalable, robust) so `prd-quality-analyzer` approves on the first pass.
- [x] `src/catalog.ts` (160 LoC) — `ProductCatalog` class implementing CAT-001..005 with explicit `CatalogError` on every rejection path: unique SKUs, non-existent categories, negative/float prices, category depth cap of 3, case-insensitive search, paginated listing with `pageSize ≤ 100` guardrails.
- [x] `src/pricing.ts` (104 LoC) — integer money arithmetic implementing PRC-001..005: `subtotal` rejects floats, `applyDiscount` does half-down rounding for percentages (15% on 199 → 29, not 30), `applyDiscount` clamps fixed discounts at the subtotal (never negative total), `applyTax` applies to the post-discount amount only, `quote` returns a fully-integer 5-field result.
- [x] `src/inventory.ts` (130 LoC) — `Inventory` + `InsufficientStockError` implementing INV-001..005: per-(product, warehouse) counters with `onHand` / `reserved` / `available`, reserve/commit/release semantics, explicit "cannot setOnHand below reserved" guard, structured error carrying `productId` / `warehouseId` / `requested` / `available` for debugging.
- [x] `tests/catalog.test.ts` (16 cases), `tests/pricing.test.ts` (17 cases), `tests/inventory.test.ts` (12 cases) — **45 live vitest cases**, all passing. Each file opens with a block comment pointing at the PRD requirement family it covers, so the PRD → test trace is obvious.
- [x] `package.json` + `tsconfig.json` + `vitest.config.ts` — minimal setup (vitest 2.1.2 + typescript 5.4, NodeNext ESM). `npm install && npm test` runs the full 45-case suite in ~200ms.
- [x] `vibeflow.config.json` — pre-initialized for `solo` mode, `e-commerce` domain, `currentPhase: "DEVELOPMENT"` (so a reader doesn't have to walk through requirements/design/architecture/planning gates), `criticalPaths: ["src/pricing.ts", "src/inventory.ts"]`.
- [x] `.vibeflow/reports/prd-quality-report.md` — pre-baked. Testability 87, 0 ambiguous terms, 0 missing AC, APPROVED verdict. Shows the exact shape `prd-quality-analyzer` produces.
- [x] `.vibeflow/reports/scenario-set.md` — pre-baked. 16 scenarios with stable ids (SC-CAT-001..005, SC-PRC-001..005, SC-INV-001..005, SC-INV-SWEEP), priority tags, Given/When/Then, and a `Maps to` line linking each scenario back to a requirement.
- [x] `.vibeflow/reports/test-strategy.md` — pre-baked. Single-tier unit strategy (vitest only; no integration/e2e/contract/chaos tiers since the demo has no process boundary), coverage budget (90% line, 85% branch, 100% critical path), 12 P0 + 4 P1 scenario split, risk notes on money drift + concurrent reserve/commit.
- [x] `.vibeflow/reports/release-decision.md` — pre-baked. **GO — 92/100** with 6 weighted gates, every gate above its e-commerce domain floor, full weighted-composite math table, rollback note explaining why N/A for the demo.
- [x] `docs/DEMO-WALKTHROUGH.md` — step-by-step reader or live-run guide. 7 sections: layout inspection → PRD analysis → test strategy → phase advance → test run → release decision → next steps. Points at every pre-baked artifact and explains the CONDITIONAL-verdict experiment (delete a test, re-run, see the verdict downgrade, restore).
- [x] `README.md` + `.gitignore` — orientation document (what this demo is / isn't) + node_modules/dist/coverage exclusion.

**Scope discipline:**
- The PRD explicitly says "not a Next.js app" in the Non-goals section. The roadmap mentioned "small Next.js app" but a Next.js scaffolding (pages/app router + React + webpack) would add ~200MB of node_modules without adding any value to the VibeFlow demo — the VibeFlow skills care about PRD → scenarios → tests → coverage → release decision, not about the HTTP/UI layer. A reader who wants to see VibeFlow against a real Next.js app can point the plugin at their own project.
- Pre-baked artifacts are checked in rather than generated-at-read-time because a reader shouldn't need to run every VibeFlow skill just to understand what each skill produces. A header comment on each artifact (`@generated-by vibeflow:<skill> (demo pre-bake)`) + regenerate instructions make the pre-bake explicit.
- Source + tests are REAL (45 cases actually pass), not pseudocode. The alternative — "here's what tests *could* look like" — would leave readers unable to verify the demo actually works.

**Integration harness guards (`sprint-4.sh [S4-E]`, 31 new assertions):**
- 17 file-presence checks covering README / config / package.json / tsconfig / vitest.config / PRD / walkthrough / 3 source files / 3 test files / 4 pre-baked artifacts
- 2 `vibeflow.config.json` structure checks (domain = e-commerce, critical-paths list includes pricing.ts)
- 6 PRD requirement family spot-checks (CAT-001, CAT-005, PRC-001, PRC-005, INV-001, INV-005)
- 1 release-decision verdict sentinel (`GO — 92 / 100`)
- 5 walkthrough command citations (prd-quality-analyzer, test-strategy-planner, scenario-generator, advance, release-decision-engine)

**Total demo vitest suite:** 45 tests passing (16 catalog + 17 pricing + 12 inventory), runs in ~200ms via `npm test` inside `examples/demo-app/`. Not counted in the VibeFlow platform baseline (it's a consumer of VibeFlow, not part of VibeFlow itself), but the file-presence sentinels guarantee the suite stays wired.

### S4-04: User documentation ⬜ TODO
Complete documentation set:
- [ ] docs/GETTING-STARTED.md — Update with final installation steps
- [ ] docs/CONFIGURATION.md — All vibeflow.config.json options, userConfig fields
- [ ] docs/SKILLS-REFERENCE.md — Auto-generated from io-standard.md, one section per skill
- [ ] docs/PIPELINES.md — Human-friendly version of orchestrator.md with diagrams
- [ ] docs/HOOKS.md — What each hook does, how to customize
- [ ] docs/MCP-SERVERS.md — Architecture of each MCP server, available tools
- [ ] docs/TROUBLESHOOTING.md — Common errors and fixes
- [ ] docs/TEAM-MODE.md — PostgreSQL setup, multi-AI consensus config, collaboration workflow

### S4-05: Plugin manifest finalization ⬜ TODO
Prepare plugin.json for distribution:
- [ ] Verify all userConfig fields have correct types, titles, descriptions
- [ ] Add `figma_token` (sensitive: true) for design-bridge
- [ ] Add `github_token` (sensitive: true) for dev-ops
- [ ] Add `ci_provider` (string: "github" | "gitlab") for dev-ops
- [ ] Version bump to 1.0.0
- [ ] Add `repository` and `homepage` URLs
- [ ] Validate with `claude plugin validate`

### S4-06: Plugin packaging ⬜ TODO
Package for distribution:
- [ ] Ensure all MCP servers have pre-built dist/ (no user-side build required)
- [ ] Create .npmignore or files whitelist (exclude tests, src, node_modules dev deps)
- [ ] Test clean install: `claude plugin install ./vibeflow-plugin.tar.gz`
- [ ] Test from npm (if publishing): `claude plugin install vibeflow`
- [ ] Verify skills, hooks, agents, MCPs all load on fresh install

### S4-07: CHANGELOG + release ⬜ TODO
- [ ] Write CHANGELOG.md covering Sprint 1-4 changes
- [ ] Git tag v1.0.0
- [ ] Create GitHub release with release notes
- [ ] Archive: vibeflow-v1.0.0.tar.gz

### S4-08: Performance + edge case hardening ⬜ TODO
- [ ] Large PRD handling (>5000 words) — ensure skills don't timeout
- [ ] Concurrent MCP requests — verify no state corruption
- [ ] Offline mode — graceful degradation when no internet (design-bridge, dev-ops)
- [ ] Memory footprint — ensure plugin doesn't bloat Claude context
- [ ] Error messages — all errors user-friendly with actionable suggestions

### S4-09: Final integration test ⬜ TODO
End-to-end validation on demo project:
- [ ] Fresh install of plugin
- [ ] /vibeflow:init on demo project
- [ ] Run PIPELINE-1 (new feature) end-to-end
- [ ] Run PIPELINE-2 (pre-PR) on a code change
- [ ] Run PIPELINE-4 (release decision) with generated data
- [ ] Run PIPELINE-5 (hotfix) on a simulated bug fix
- [ ] Verify all hooks fire correctly
- [ ] Verify /vibeflow:status shows accurate state throughout
- [ ] Test team mode with PostgreSQL (if available)

---

## Next Ticket to Work On
**S4-04: User documentation** — the full docs/ set for v1.0: GETTING-STARTED, CONFIGURATION, SKILLS-REFERENCE, PIPELINES, HOOKS, MCP-SERVERS, TROUBLESHOOTING, TEAM-MODE. Auto-generate the SKILLS-REFERENCE from io-standard.md where possible.

## Test inventory (after S4-03)
- mcp-servers/sdlc-engine: **104 vitest tests** (coverage: 93.01% stmt / 88.62% branch)
- mcp-servers/codebase-intel: **46 vitest tests** (coverage: 93% stmt / 80.75% branch)
- mcp-servers/design-bridge: **54 vitest tests** (coverage: 90.08% stmt / 86.06% branch)
- mcp-servers/dev-ops: **37 vitest tests** (coverage: 91.17% stmt / 91.07% branch)
- mcp-servers/observability: **76 vitest tests** (coverage: 97.57% stmt / 88.62% branch)
- hooks/tests/run.sh: **50 bash assertions**
- tests/integration/run.sh: **394 bash assertions**
- tests/integration/sprint-2.sh: **94 bash assertions**
- tests/integration/sprint-3.sh: **111 bash assertions**
- tests/integration/sprint-4.sh: **127 bash assertions** (+31 from S4-03 demo-app presence)
- Total: **1093 passing checks** across 10 test layers
- **Bonus**: `examples/demo-app/` ships with its own 45-test vitest suite (16 catalog + 17 pricing + 12 inventory) — not counted in the VibeFlow baseline because the demo is a consumer of VibeFlow, not part of it.

## Execution Order
S4-01 (tests) ✅ → S4-02 (hooks hardening) → S4-03 (demo) → S4-04 (docs) → S4-05 (manifest) → S4-06 (packaging) → S4-07 (changelog) → S4-08 (hardening) → S4-09 (final test)

## Definition of Done: v1.0.0
- All 31 skills functional
- All 5 MCP servers operational
- All 7 hooks implemented and tested
- All 7 pipelines executable
- >80% test coverage across all MCP servers
- Documentation complete
- Demo project works end-to-end
- Plugin installable from package
- 12/12 MyVibe bugs fixed
