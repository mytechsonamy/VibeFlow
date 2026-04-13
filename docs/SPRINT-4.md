# Sprint 4: Polish + Packaging + Distribution ✅ COMPLETE

## Sprint Goal
Production-ready plugin: full test coverage, documentation, demo project, and plugin marketplace packaging.

## Prerequisites
- Sprint 3 complete (all 5 MCPs, all 31 skills, all 7 pipelines working)

## Completion Criteria
- [x] Plugin manifest finalized + sentinel-validated (S4-05). `claude plugin validate` not run interactively but the harness covers the same JSON shape contract.
- [x] Demo project ships at `examples/demo-app/` with full SDLC cycle artifacts pre-baked (S4-03)
- [x] All 5 MCP servers above 80/80/80/80 coverage thresholds (S4-01)
- [x] 8 user docs + skills reference + pipelines diagram (S4-04)
- [x] Plugin packaged and `vibeflow-plugin-1.0.0.tar.gz` reproducible via `./package-plugin.sh` (S4-06). Fresh-install simulation in [S4-K] proves end-to-end loadability.
- [x] CHANGELOG.md written (S4-07). Git tag + GitHub release pending user authorization.

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

### S4-04: User documentation ✅ DONE
Complete user-facing documentation set: 8 docs in `docs/` covering the
full v1.0 user surface, cross-referenced from a single GETTING-STARTED
entry point.

**Completed:**
- [x] **`docs/GETTING-STARTED.md`** — rewritten from the v0.1 stub. Prerequisites + installation (local + marketplace paths) + `/vibeflow:init` field-by-field reference + 7-step happy-path walkthrough + solo vs team mode comparison + demo project pointer + links to every other doc + help section. Replaces the original 95-line skeleton with a 200-line production guide.
- [x] **`docs/CONFIGURATION.md`** (NEW) — every `vibeflow.config.json` field with type/required/default/notes, every `userConfig` key (sensitive flag included), every environment variable, the `test-strategy.md` per-skill override discipline (tighten-only + retrospective + version bump), domain → threshold table, `criticalPaths` semantics, "what NOT to put in config" anti-patterns.
- [x] **`docs/SKILLS-REFERENCE.md`** (NEW) — one section per skill across L0/L1/L2/L3 (26 skills total). Every entry has command + inputs + outputs + gate contract + downstream + pipeline step. Cross-referenced against `skills/_standards/io-standard.md` by `sprint-4.sh [S4-D]`.
- [x] **`docs/PIPELINES.md`** (NEW) — human-friendly walk through PIPELINE-1..7 with ASCII step diagrams + decision tree at the top + solo vs team enablement table + "running a pipeline end-to-end" examples.
- [x] **`docs/HOOKS.md`** (NEW) — every hook script with trigger + purpose + edge cases handled (covers all S4-02 hardening). Documents the shared `_lib.sh` helper surface table. Disabling instructions per hook.
- [x] **`docs/MCP-SERVERS.md`** (NEW) — per-server architecture: storage, schema, tools, token requirements, lazy-construction patterns, build instructions. Includes the `project_state` SQL schema (shared by SQLite + PostgreSQL) and the flakiness scoring formula.
- [x] **`docs/TROUBLESHOOTING.md`** (NEW) — common failure modes organized by category: phase + commit, state + database, PRD + scoring, coverage + test, MCP server, hook + automation, CLI + plugin, plugin dev. Cause + fix shape per entry. References specific S4-02 hardening behaviors so readers can predict what they'll see.
- [x] **`docs/TEAM-MODE.md`** (NEW) — PostgreSQL setup (CREATE DATABASE + schema + connection pool defaults), solo → team migration path, multi-AI CLI install (codex / gemini), consensus thresholds, quorum + 600s timeout force-finalize semantics, collaborative phase advance flow, hook strictness deltas, switching back to solo with state preservation.

**Documentation cross-reference matrix:**

| Doc | Links to | Linked from |
|-----|----------|-------------|
| GETTING-STARTED | every other doc + demo-app | (entry point) |
| CONFIGURATION | SKILLS-REFERENCE | GETTING-STARTED, TROUBLESHOOTING |
| SKILLS-REFERENCE | PIPELINES, io-standard | GETTING-STARTED, CONFIGURATION, PIPELINES |
| PIPELINES | SKILLS-REFERENCE, orchestrator.md | GETTING-STARTED, SKILLS-REFERENCE |
| HOOKS | SKILLS-REFERENCE | GETTING-STARTED, TROUBLESHOOTING |
| MCP-SERVERS | (technical reference) | GETTING-STARTED, TEAM-MODE |
| TROUBLESHOOTING | every other doc | GETTING-STARTED |
| TEAM-MODE | MCP-SERVERS, HOOKS | GETTING-STARTED |

**Integration harness (`sprint-4.sh [S4-F]`, +60 new assertions):**
- 8 file-presence checks (one per doc)
- 8 H1-header sentinels (catches silent-rewrite regressions)
- 4 SKILLS-REFERENCE layer-section sentinels (L0/L1/L2/L3)
- 5 SKILLS-REFERENCE skill-section sentinels (representative one per layer + release engine)
- 7 PIPELINES.md PIPELINE-N section sentinels + 1 decision tree sentinel
- 8 HOOKS.md hook-script reference sentinels (commit-guard, load-sdlc-context, post-edit, trigger-ai-review, test-optimizer, compact-recovery, consensus-aggregator, _lib.sh)
- 5 MCP-SERVERS.md server section sentinels
- 7 CONFIGURATION.md userConfig key sentinels (drift catcher between plugin.json and the docs)
- 7 GETTING-STARTED inbound-link sentinels (every other doc must be reachable)

**Decision: documentation is hand-written, not auto-generated.** The
ticket suggested SKILLS-REFERENCE.md should be "auto-generated from
io-standard.md". That would have produced a thinner doc — io-standard.md
only knows about inputs and outputs; the gate contract, downstream
consumers, and pipeline step come from each SKILL.md and were
hand-extracted. The cross-reference sentinel in `sprint-4.sh [S4-F]`
catches drift between SKILLS-REFERENCE.md and the actual SKILL.md
files, which is the value the auto-generation was meant to provide
without the brittleness of a parser.

### S4-05: Plugin manifest finalization ✅ DONE
**Location:** `.claude-plugin/plugin.json` + `.mcp.json` + `mcp-servers/dev-ops/src/tools.ts`

**Completed:**
- [x] **userConfig field shapes verified** — every key (mode / domain / db_connection / openai_model / gemini_model / figma_token / github_token / ci_provider) declares `title` + `description` + `type` + `sensitive`. Validated via the new `sprint-4.sh [S4-G]` sentinel which iterates each key and asserts the four sub-fields exist.
- [x] **figma_token sensitive: true** — already present, sentinel-guarded
- [x] **github_token sensitive: true** — already present, sentinel-guarded
- [x] **`ci_provider` added** — new userConfig key (non-sensitive string) selecting between `"github"` (default) and `"gitlab"`. Sourced through `.mcp.json` env template substitution into the dev-ops MCP as `CI_PROVIDER`.
- [x] **Version bump to 1.0.0** — already at `1.0.0`, sentinel asserts the literal value
- [x] **Repository structured + homepage + bugs** — repository converted from a bare string to `{ "type": "git", "url": "https://github.com/mustiyildirim/vibeflow.git" }`. Added `homepage` and `bugs.url` (pointing at GitHub issues).
- [x] **`claude plugin validate`** — not run (interactive command); the harness sentinels cover the same JSON shape checks that `plugin validate` would perform offline (top-level required keys, version literal, userConfig key inventory + per-key field inventory, sensitive flags on the three secret-bearing keys, repository structure).

**`ci_provider` end-to-end wiring (the load-bearing change):**

1. **`.claude-plugin/plugin.json`** — declares the `ci_provider` userConfig key with title/description/type/sensitive=false. The description names both supported values (`"github"`, `"gitlab"`).
2. **`.mcp.json`** — adds `"CI_PROVIDER": "${userConfig.ci_provider}"` to the dev-ops env block alongside the existing GITHUB_TOKEN flow. Same template-substitution pattern as the figma_token + github_token wires.
3. **`mcp-servers/dev-ops/src/tools.ts`** — `getProvider` now reads `process.env.CI_PROVIDER` (default `"github"`), case-insensitive. `"github"` and unset both build the GitHub client; `"gitlab"` raises a loud `CiConfigError` ("not implemented yet") rather than silently falling back; any other value raises a separate "unknown ci_provider" error. **Misconfigured provider is a worse failure mode than no provider** — silent fallback would let a typo ship to staging.
4. **dev-ops vitest suite** — 4 new tests covering the provider-selection branches (default behavior, case-insensitive github, gitlab → not-implemented error, unknown → unknown error). Test count 37 → 41.
5. **`docs/CONFIGURATION.md`** — `ci_provider` row added to the userConfig table with the "GitLab declared but not yet implemented" note. The env-vars table also gets `CI_PROVIDER`.

**Why GitLab is declared but not implemented**: making the field exist now (and giving it a loud error path) means the GitLab implementation can land in a future commit without a manifest version bump — the surface is already documented and gate-tested. The same pattern was used for `tech.testRunner` auto-detection in earlier sprints.

**Integration harness (`sprint-4.sh [S4-G]`, +67 new assertions):**
- 1 plugin.json existence check
- 1 valid-JSON check
- 11 top-level metadata keys (name, version, description, author, homepage, repository, bugs, license, keywords, skills, userConfig)
- 1 version literal sentinel (`== "1.0.0"`)
- 2 repository structure sentinels (object form + github url)
- 1 bugs URL sentinel
- 1 homepage URL sentinel
- 1 skills path sentinel
- 8 userConfig key presence sentinels (mode, domain, db_connection, openai_model, gemini_model, figma_token, github_token, ci_provider)
- 32 per-key field sentinels (8 keys × 4 fields each: title, description, type, sensitive)
- 4 sensitive-flag sentinels (db_connection, figma_token, github_token marked sensitive; ci_provider marked NOT sensitive)
- 1 .mcp.json CI_PROVIDER wiring sentinel (template substitution from userConfig)
- 1 CONFIGURATION.md ci_provider documentation sentinel
- 2 dev-ops source/dist `process.env.CI_PROVIDER` sentinels (catches "manifest field exists but the code never reads it" drift)
- 1 dev-ops test count floor bump (37 → 41 to record the new baseline)

Plus 4 new vitest cases in `mcp-servers/dev-ops/tests/tools.test.ts` covering the four CI_PROVIDER selection branches.

### S4-06: Plugin packaging ✅ DONE
**Location:** `build-all.sh` + `package-plugin.sh` + `.gitignore` + `tests/integration/sprint-4.sh [S4-H]`

**Completed:**
- [x] **MCP server dist/ tracked in git** — load-bearing change. `.gitignore` adds a negation block: `dist/` stays generic-ignored, but `!mcp-servers/*/dist/` + `!mcp-servers/*/dist/**` un-ignores all 5 MCP server dist directories. Source maps stay ignored via `mcp-servers/*/dist/**/*.map` to keep the tarball lean. Result: end users running `claude plugin install` from a fresh clone or tarball get working JS without ever running `npm install` or `npm run build`. **78 dist files staged across the 5 servers.**
- [x] **Files whitelist** — `package-plugin.sh` uses an explicit whitelist, NOT a blacklist (`tar -X exclude.txt`). Whitelist discipline means a future `git add` of an unrelated file cannot accidentally leak into the tarball — only the paths the script enumerates ship. The whitelist captures: `.claude-plugin/plugin.json`, `.mcp.json`, `hooks/hooks.json`, `hooks/scripts/`, `agents/`, `skills/`, the 8 user docs, the demo-app subset (excluding node_modules + state.db), and per-MCP-server `package.json` + `tsconfig.json` + `dist/`. Source files, tests, vitest.config.ts, and node_modules are excluded.
- [x] **`./vibeflow-plugin-1.0.0.tar.gz` builds and verifies** — script produces a 392K tarball containing 214 files. Post-archive verification (re-reads `tar -tzf`) confirms `.claude-plugin/plugin.json` is present, every MCP `dist/index.js` is present, and forbidden paths (`node_modules/`, `.DS_Store`, `CLAUDE.md`, `docs/SPRINT-*.md`, `src/index.ts`, `.git/`) are absent. The script also has a sanity cap (100 ≤ files ≤ 5000) so a typo in the whitelist that captures node_modules fails loudly.
- [x] **Fresh-install sanity covered by sprint-4.sh [S4-H]** — the harness invokes `bash build-all.sh --check` and `bash package-plugin.sh --skip-build` inline and asserts both succeed. Spot-checks the resulting tarball contents (manifest path + dist file path + forbidden-path absence). This is as close as we can get to `claude plugin install ./vibeflow-plugin-1.0.0.tar.gz` without spawning a separate Claude Code process.
- [x] **npm publish path** — not implemented. Plugin distribution is via the Claude Code plugin marketplace (or local tarball install), not via npm publish. The ticket mentioned npm as a fallback ("if publishing"); the marketplace path is the v1.0 default and the npm path is deferred to S4-07 if needed.

**`build-all.sh`** — single script that runs `npm install && npm run build` in each MCP server, then verifies `dist/index.js` exists and parses. Two modes:
- `./build-all.sh` — install + build + verify (used by maintainers before committing dist)
- `./build-all.sh --check` — verify only (used by the integration harness; doesn't touch node_modules)

**`package-plugin.sh`** — produces `vibeflow-plugin-<version>.tar.gz` from the whitelist. Five-step pipeline: preflight (build) → whitelist resolution → forbidden-path scan → tar invocation → post-archive verification. Three modes:
- `./package-plugin.sh` — full build + tarball + verify
- `./package-plugin.sh --skip-build` — skip the build step (assumes dists are fresh; used by CI)
- `./package-plugin.sh --dry-run` — list files that would ship, no archive written

**Whitelist over blacklist** — the script enumerates EXPLICITLY which paths ship. A blacklist would let new accidentally-tracked files leak into the archive on the next packaging run. Same discipline as `tests/integration/run.sh`'s sentinel approach: explicit allow > implicit deny.

**Forbidden-path scan** runs against the resolved file list BEFORE writing the archive, so a misconfigured whitelist fails the script before producing a broken tarball:
- `node_modules/`, `.git/`, `.vibeflow/state.db`, `.vibeflow/artifacts/`, `.vibeflow/traces/`, `.vibeflow/state/`
- `.DS_Store`, `.claude/`, `CLAUDE.md`, `ROADMAP.md`
- `docs/SPRINT-*.md`, `tests/integration/`, `hooks/tests/`
- `mcp-servers/*/src/`, `mcp-servers/*/tests/`

**Tarball is gitignored** — `vibeflow-plugin-*.tar.gz` added to `.gitignore` so a packaging run doesn't accidentally land in a commit. The build artifact is reproducible from source + the script.

**Integration harness (`sprint-4.sh [S4-H]`, +31 new assertions):**
- 4 script-presence checks (build-all.sh + package-plugin.sh × {present, executable})
- 5 git-tracked-dist sentinels (every MCP server's `dist/index.js` returns from `git ls-files`)
- 5 source-map-NOT-tracked sentinels (`.map` files stay ignored to keep the tarball lean)
- 4 .gitignore content sentinels (node_modules, .DS_Store, .vibeflow/state.db, vibeflow-plugin-*.tar.gz)
- 1 .gitignore negation sentinel (`!mcp-servers/*/dist/`)
- 2 live `git check-ignore` sentinels (positive + negative)
- 1 `build-all.sh --check` exit-code sentinel
- 1 `package-plugin.sh --skip-build` exit-code sentinel
- 1 archive-existence sentinel
- 2 archive-contains sentinels (manifest + sdlc-engine dist)
- 5 archive-does-NOT-contain sentinels (node_modules, CLAUDE.md, SPRINT-4.md, .git, src/index.ts)

The S4-H section is the most "operational" sentinel block in the harness suite — it actually invokes the packaging script and rebuilds the tarball every CI run, so a bug in either script (or a regression in the gitignore wiring) shows up immediately.

### S4-07: CHANGELOG + release ✅ DONE (release artifacts pending user authorization)
**Location:** `CHANGELOG.md` + `tests/integration/sprint-4.sh [S4-I]`

**Completed:**
- [x] **`CHANGELOG.md` written** — Keep-a-Changelog 1.1.0 format, SemVer, single `[1.0.0] — 2026-04-13` entry. Sections: Highlights, Added per sprint (Sprint 1-4), Test baseline growth table, Bug fixes (12/12 MyVibe bugs closed with sprint cite per bug), Breaking changes (none), Migration (N/A — first release), Distribution, Documentation links, Acknowledgments. Links back to GETTING-STARTED + the demo walkthrough so a reader landing on the changelog has a clear next action.
- [x] **CHANGELOG ↔ plugin.json version sync** — `sprint-4.sh [S4-I]` extracts the latest `[X.Y.Z]` heading from CHANGELOG.md and asserts it matches `.claude-plugin/plugin.json → version`. Drift fails the harness loudly. Same shape as the test count floors and gate contract sentinels.
- [x] **Archive present** — `vibeflow-plugin-1.0.0.tar.gz` (392K, 214 files) was already produced by S4-06's `package-plugin.sh`. The tarball is the release artifact; no separate `vibeflow-v1.0.0.tar.gz` is needed (the package-plugin.sh naming convention already includes the version).
- [x] **Integration harness sentinels** — `sprint-4.sh [S4-I]` (+16 assertions): CHANGELOG presence, H1 header, Keep-a-Changelog citation, SemVer citation, [1.0.0] release entry with ISO date, Sprint 1/2/3/4 sections, Breaking changes/Migration/Distribution/Test baseline growth subsections, version sync with plugin.json, GETTING-STARTED + DEMO-WALKTHROUGH backlinks.

**Pending user authorization (release-time actions):**
- [ ] **`git tag v1.0.0`** — not run autonomously. Tags + releases are user-visible actions that should be triggered explicitly. Run when ready: `git tag -a v1.0.0 -m "v1.0.0 — first public release" && git push origin v1.0.0`
- [ ] **`gh release create v1.0.0`** — not run autonomously. Same reason. When ready: `gh release create v1.0.0 vibeflow-plugin-1.0.0.tar.gz --title "v1.0.0 — first public release" --notes-file CHANGELOG.md` (or hand-write release notes from the [1.0.0] section).

**Why authorization-gated:** every other sprint ticket has been a local action (file edits, tests, builds) — pushable/revertable without consequence. Tagging and releasing v1.0.0 are public-facing actions: the tag becomes the canonical reference for everyone who installs the plugin, and the release publishes the tarball to a wide audience. These are the highest-blast-radius actions in the entire project, so the CLAUDE.md "executing actions with care" rule applies — wait for explicit user go-ahead.

**Decision: tarball naming `vibeflow-plugin-1.0.0.tar.gz`, not `vibeflow-v1.0.0.tar.gz`.** The roadmap mentioned the latter format, but `package-plugin.sh` reads the version from `plugin.json` and emits `vibeflow-plugin-<version>.tar.gz` — keeping the script-controlled naming means a future v1.0.1 release just needs a `plugin.json` version bump + `./package-plugin.sh`, not a hand-edited tarball name. The naming difference is cosmetic and doesn't affect `claude plugin install ./vibeflow-plugin-1.0.0.tar.gz`.

### S4-08: Performance + edge case hardening ✅ DONE
**Location:** new tests across `mcp-servers/{design-bridge,dev-ops,codebase-intel}/tests/` + `hooks/tests/run.sh` + `tests/integration/sprint-4.sh [S4-J]`

**Completed:**
- [x] **Large input scaling — codebase-intel** — 2 new tests synthesizing a 200-file TypeScript project. `buildImportGraph` runs on a chain+fan-out layout (400 edges) in under 5 seconds; `findCycles` runs on a 200-node circular graph in under 2 seconds. Catches accidental N² rescan loops. The full suite runs in 84 ms — comfortably under both budgets.
- [x] **Offline mode — design-bridge** — 3 new tests covering ECONNREFUSED, ENOTFOUND (DNS failure), and "socket hang up" (abrupt connection reset). Each test injects a `fetchImpl` that throws the corresponding Node error, and asserts the resulting `FigmaClientError` carries a `transport`-classified message rather than a generic TypeError leaking through the fetch boundary.
- [x] **Offline mode — dev-ops** — 2 new tests covering ECONNREFUSED and ENOTFOUND on the GitHub client. The error message must match `/transport.*<errno>/` so downstream consumers can distinguish "you're offline" from "your request is wrong" and surface the right user-facing suggestion. The existing "wraps transport failures in CiClientError" case is preserved alongside the new ones.
- [x] **Memory footprint — load-sdlc-context** — 250-character output budget enforced in `hooks/tests/run.sh`. The hook is injected as a system note on every Claude Code session start, so it competes for context budget with the user's actual conversation. Current output measures ~179 chars (room to grow within the cap).
- [x] **Memory footprint — compact-recovery** — 800-character output budget. Larger than load-sdlc-context because the snapshot can include the satisfied-criteria list, pending review notes, and integrity-degraded warnings — but capped so re-injection after compaction stays bounded.
- [x] **Error message audit** — walked all 63 throw sites across the 5 MCP servers + 2 stderr exits in the hook scripts. Conclusion: every CiConfigError / FigmaConfigError already includes "Set it via plugin userConfig" or "Create at" guidance; commit-guard tells the user to run `/vibeflow:advance`; conventional-commit rejection names the expected prefixes; codebase-intel "root does not exist" is self-explanatory. **No rewrites needed** — instead the harness now sentinel-guards the actionable phrases so they can't be lost in a future refactor.
- [x] **Concurrent MCP requests** — already covered by the existing `mcp-servers/sdlc-engine/tests/sqlite-race.test.ts` (3 tests for SQLite optimistic-lock CAS) and `postgres.test.ts` (14 tests for pool resilience + idle-client recovery). No new tests needed; this S4-08 entry confirms the existing coverage rather than adding more.
- [x] **Large PRD handling** — skills are markdown files, not runtime code, so there is no per-skill timeout to worry about. The relevant scaling concern is the MCPs that walk PRD content (codebase-intel for source files, observability for reporter payloads). codebase-intel is now scale-tested at 200 files; observability already handles arbitrary-size payloads via streaming parsers (no per-file array materialization). Both surfaces are covered.

**Integration harness (`sprint-4.sh [S4-J]`, +16 new assertions):**
- 4 design-bridge offline-test wiring sentinels (describe block + ECONNREFUSED + ENOTFOUND + socket-hang-up by name)
- 3 dev-ops offline-test wiring sentinels (ECONNREFUSED + ENOTFOUND + transport-classified)
- 3 codebase-intel large-input-test wiring sentinels (describe block + 200-file budget + findCycles 200-node budget)
- 2 hook output budget sentinels (load-sdlc-context 250 chars + compact-recovery 800 chars)
- 2 error-message actionability sentinels (design-bridge + dev-ops "Set it via plugin userConfig" guidance phrases)
- 2 commit-guard error-message sentinels (advance hint + conventional-commit prefix list)

**Test count floors bumped** in `sprint-4.sh [S4-C]`: codebase-intel 46 → 48, design-bridge 54 → 57, dev-ops 41 → 43. observability and sdlc-engine unchanged.

**Why this scope and not more:** every S4-08 sub-bullet is now either tested or argued why the existing surface is sufficient. The ticket's biggest temptation was "audit and rewrite every error message", which would have ballooned into a 50-file rewrite without changing any behavior. The harness sentinels for the actionable phrases give the same guarantee (no regression on user-facing wording) at a fraction of the churn.

### S4-09: Final integration test ✅ DONE
**Location:** `tests/integration/sprint-4.sh [S4-K]` + `mcp-servers/sdlc-engine/{src/engine.ts, tests/engine.test.ts}` (Bug #13 fix)

Sprint 4's closer. Fresh-install end-to-end simulation against the
extracted v1.0 tarball — the closest possible approximation to
"`claude plugin install vibeflow` then use it" without spawning a
recursive Claude Code session.

**Completed:**
- [x] **Fresh-install simulation** — `[S4-K]` extracts `vibeflow-plugin-1.0.0.tar.gz` to a temp dir + synthesizes a user project + walks the engine through every phase + fires every hook against the synthetic project + verifies final state.db matches expectations.
- [x] **Tarball payload sanity** — manifest parseable + version 1.0.0; every MCP `dist/index.js` exists in the extracted tree AND parses (`node --check`); ≥26 SKILL.md files (actual: 31 including 5 operational utilities); every hook script executable.
- [x] **Full SDLC walk via sdlc-engine MCP** — REQUIREMENTS → DESIGN → ARCHITECTURE → PLANNING → DEVELOPMENT (4 phase advances), each preceded by satisfy-criterion + record-consensus calls. Two engine invocations (Phase A: fresh state check; Phase B: full walk) to work around the MCP SDK's parallel JSON-RPC dispatch.
- [x] **All-hooks fire test** — every hook (commit-guard pass + reject, load-sdlc-context, post-edit, test-optimizer, compact-recovery, consensus-aggregator, trigger-ai-review) invoked against the synthetic project from the EXTRACTED tarball location. Assertions confirm side effects: log entries, state files, commit allow/deny, verdict files, snapshot output.
- [x] **Final state.db spot check** — current_phase == DEVELOPMENT, satisfied_criteria is valid JSON, revision counter ≥ 12 (reflects full walk's 16+ writes).
- [x] **Output budget enforced inline** — load-sdlc-context and compact-recovery outputs measured against their 250 / 800 char budgets in the extracted-tarball context.
- [x] **Team mode with PostgreSQL** — not run (requires a live Postgres instance + `userConfig.db_connection`). The existing `mcp-servers/sdlc-engine/tests/postgres.test.ts` (14 vitest cases) covers the pool resilience + idle-client recovery contract; a real team-mode integration test is scope for v1.0.1 when a CI Postgres is available.

**Bug #13 caught + fixed during S4-K bring-up** (the most surprising
finding of the entire sprint):

```
Error: revision must increment by exactly 1 (expected 5, got 4)
```

`engine.getOrInit(projectId)` was wrapping the read inside a
`store.transact()` call. On a brand-new project that's harmless
(seed a row at revision 1). On an EXISTING project it returned
`{ next: current, result: current }` — same revision — which the
mutator's `next.revision === current.revision + 1` assertion
rejected on every call. **Result**: `sdlc_get_state` crashed on
every project that had been written to before.

Fix: `getOrInit` now does a `store.read()` fast path first and only
enters the mutator transaction when the project is missing. Race
case (concurrent insert between read and transact) is handled by
returning a `bumpRevision(current)` so the mutator validation
passes. New regression test in `engine.test.ts` covers the bug.

**Why this hadn't surfaced in 1300+ checks:** the existing
`run.sh [4]` smoke calls `sdlc_get_state` exactly once on a
brand-new project. The bug only fires on the SECOND call. The S4-K
walk was the first test to exercise the read-after-write path
through the MCP layer. Goes in the bug tracker as Bug #13.

**MCP SDK parallel dispatch lesson:**

The `@modelcontextprotocol/sdk` dispatches every JSON-RPC request
in parallel — there is no in-process ordering guarantee within a
single stdin batch. A read-then-write pattern in one batch can see
the writes BEFORE the read returns. The harness works around this
by splitting into two engine invocations (one per logical phase).
For real users this is a non-issue — Claude Code's tool dispatcher
serializes calls naturally. Worth documenting in MCP-SERVERS.md
for any future contributor writing similar tests.

**Integration harness (`sprint-4.sh [S4-K]`, +38 new assertions):**
- 1 tarball-located sentinel
- 1 tarball-extracts-cleanly sentinel
- 1 extracted-version-matches-1.0.0 sentinel
- 5 extracted-MCP-dist-parses sentinels
- 1 extracted-skill-count sentinel (≥26 → got 31)
- 7 extracted-hook-executable sentinels
- 1 synthesized-project sentinel
- 1 initial-get_state-REQUIREMENTS sentinel (Phase A)
- 1 no-JSON-RPC-errors sentinel (Phase B)
- 4 advance-success sentinels (ids 6, 10, 14, 18)
- 1 state.db-on-disk sentinel
- 1 commit-guard-allow-conformant sentinel
- 1 commit-guard-reject-malformed sentinel
- 1 load-sdlc-context-phase=DEVELOPMENT sentinel
- 1 load-sdlc-context-budget sentinel
- 1 post-edit-logged-TS-edit sentinel
- 1 test-optimizer-hint-written sentinel
- 1 compact-recovery-snapshot sentinel
- 1 compact-recovery-budget sentinel
- 1 consensus-aggregator-finalized sentinel
- 1 consensus-solo-APPROVED sentinel
- 1 trigger-ai-review-noop-in-solo sentinel
- 1 final-state.db-current_phase sentinel
- 1 final-state.db-satisfied_criteria-valid-JSON sentinel
- 1 final-state.db-revision sentinel

Plus 1 new vitest case in `mcp-servers/sdlc-engine/tests/engine.test.ts` for the Bug #13 regression guard.

---

## Sprint 4 Status: ✅ COMPLETE (v1.0 release-ready)

All 9 tickets closed. Pending user-authorization actions (git tag + GitHub release) are documented in S4-07 and unlocked by an explicit go-ahead.

### v1.0 release-readiness summary

| Concern | Status |
|---------|--------|
| MCP coverage (5 servers ≥ 80/80/80/80) | ✅ S4-01 |
| Hook hardening (7 hooks production-ready) | ✅ S4-02 |
| Demo project (real source + 45 tests) | ✅ S4-03 |
| User documentation (8 docs cross-referenced) | ✅ S4-04 |
| Plugin manifest finalized (v1.0.0 + ci_provider) | ✅ S4-05 |
| Distribution machinery (build-all + package-plugin) | ✅ S4-06 |
| CHANGELOG.md (Sprint 1-4 + bug closures) | ✅ S4-07 |
| Performance + edge cases (offline / large input / budgets) | ✅ S4-08 |
| Final integration (fresh-install simulation) | ✅ S4-09 |
| Bug #13 — getOrInit mutator-validation crash | ✅ S4-09 (caught + fixed) |
| Git tag v1.0.0 | ⏸ pending user authorization |
| GitHub release create v1.0.0 | ⏸ pending user authorization |

When ready to ship:

```bash
git tag -a v1.0.0 -m "v1.0.0 — first public release"
git push origin v1.0.0
gh release create v1.0.0 vibeflow-plugin-1.0.0.tar.gz \
  --title "v1.0.0 — first public release" \
  --notes-file CHANGELOG.md
```

## Next Ticket to Work On
**Sprint 4 is complete.** The next active sprint is `docs/SPRINT-5.md` (not yet created). Suggested seed topics for v1.0.x:
- Real GitLab CI provider implementation (currently `ci_provider: gitlab` raises the "not yet implemented" error)
- Live PostgreSQL team-mode integration test in CI
- Marketplace publish workflow + signed releases
- Optional: a real Next.js demo (alongside the current TypeScript-only demo)

## Test inventory (after S4-09 — Sprint 4 closed)
- mcp-servers/sdlc-engine: **105 vitest tests** (+1 Bug #13 regression test)
- mcp-servers/codebase-intel: **48 vitest tests**
- mcp-servers/design-bridge: **57 vitest tests**
- mcp-servers/dev-ops: **43 vitest tests**
- mcp-servers/observability: **76 vitest tests**
- hooks/tests/run.sh: **52 bash assertions**
- tests/integration/run.sh: **394 bash assertions**
- tests/integration/sprint-2.sh: **94 bash assertions**
- tests/integration/sprint-3.sh: **111 bash assertions**
- tests/integration/sprint-4.sh: **355 bash assertions** (+38 from S4-09 fresh-install simulation)
- Total: **1335 passing checks** across 10 test layers
- **Bonus**: `examples/demo-app/` ships with its own 45-test vitest suite — not counted in the baseline.
- **Release artifact**: `vibeflow-plugin-1.0.0.tar.gz` (392K, 214 files) — reproducible via `./package-plugin.sh`. Tag + GitHub release pending user authorization.

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
