# Sprint 2: Codebase Intelligence + Design + Layer 0-1 Skills ✅ COMPLETE

## Sprint Goal
Brownfield project support via codebase-intel MCP, Figma integration via design-bridge MCP, and complete TruthLayer Layers 0 and 1 skill set.

## Prerequisites
- Sprint 1 complete (sdlc-engine working, hooks implemented, P0 skills functional)

## Completion Criteria
- [x] codebase-intel MCP responds to all tools — 46 vitest tests + integration stdio smoke in run.sh [4b]
- [x] design-bridge MCP connects to Figma API with error handling (**Bug #3 FIXED** — single wrapped error path + 7 tests)
- [x] **Bug #4 FIXED:** PostgreSQL pool leak in sdlc-engine (release-with-err, pool error handler, timeouts, metrics, FakePool unit tests + 3 load regression tests)
- [x] **Bug #7 FIXED:** Figma token uses `userConfig` (integration harness regression guards assert flow + `sensitive: true`)
- [x] 7 new L1 skills shipped: architecture-validator, component-test-writer, contract-test-writer, business-rule-validator, test-data-manager, invariant-formalizer, checklist-generator — every skill declares a verifiable gate contract
- [x] Pipeline-1 (New Feature Development) skill set complete end-to-end — cross-skill coherence proven by `sprint-2.sh` harness (87 assertions, including the `invariant-formalizer` ↔ `business-rule-validator` ↔ `test-data-manager` mutual-consistency chain)

---

## Tickets

### S2-01: codebase-intel MCP server ✅ DONE
Brownfield analysis MCP server with 46 vitest tests, all green.
**Location:** mcp-servers/codebase-intel/
**Transport:** stdio
**Tools implemented** (names prefixed `ci_` so they never collide with sdlc-engine):
- `ci_analyze_structure` — Language, framework, test runner, build tool detection with evidence + confidence (scanner.ts)
- `ci_find_hotspots` — Git churn (`commits × total lines changed`) over a 180-day window; returns empty list for non-git dirs rather than failing (hotspots.ts)
- `ci_dependency_graph` — Regex-based TS/JS import graph with relative resolver + Tarjan SCC cycle detection (imports.ts)
- `ci_tech_debt_scan` — TODO/FIXME/HACK/XXX/@deprecated grep with per-marker totals in the explainability contract shape (debtscan.ts)
**Dependencies:** `@modelcontextprotocol/sdk`, `zod`. Zero non-dev runtime deps beyond those two — git runs via `execFileSync`, filesystem via node built-ins, no `simple-git` / `ts-morph` pulled in (kept the dependency surface minimal).
**Tests:** 46 vitest tests across scanner, hotspots, imports, debtscan, tools, server dispatch. Includes a real-git integration test in `hotspots.test.ts` that spins up a tmp repo and verifies churn ranking.
**Wire:** Added to `.mcp.json` as a second mcpServer entry; integration harness extended with section `[4b]` that drives all four tools over JSON-RPC stdio.

### S2-02: design-bridge MCP server ✅ DONE
Figma integration MCP server with 54 vitest tests, all green.
**Location:** mcp-servers/design-bridge/
**Transport:** stdio
**Tools implemented** (prefixed `db_` to avoid collisions):
- `db_fetch_design` — Pulls a Figma frame by URL or (fileKey, nodeId). URL parser handles both `/file/` and `/design/` paths plus `?node-id=12-345` → `12:345` normalization. Returns a BFS-flattened frame list with dimensions + depth.
- `db_extract_tokens` — Walks the node tree, dedupes SOLID fills/strokes to 8-digit hex, dedupes text styles, collects AUTO_LAYOUT itemSpacing/paddings. Every token carries `sources: nodeId[]` as evidence.
- `db_generate_styles` — Emits CSS `:root` custom properties + Tailwind `theme.extend` config from the extracted tokens. Framework-neutral strings, never written to disk.
- `db_compare_impl` — Minimal image compare (PNG IHDR dimension parse + SHA-256). Returns `identical | same-dimensions | size-mismatch | unknown`. Full perceptual diff is honestly deferred to the visual-ai-analyzer skill in Sprint 3 — we refuse to invent a similarity score we can't defend.

**Bug fixes (both closed):**
- **Bug #3 — missing Figma error handling:** `client.ts` funnels every request through a single `get()` path that wraps transport failures, non-2xx responses (with status + path + body snippet), and JSON parse errors into a single `FigmaClientError`. Tested in `client.test.ts` — 7 cases including the 401 path, transport exception, and invalid-JSON response.
- **Bug #7 — Figma token in code:** Token is read once from `process.env.FIGMA_TOKEN`, never hardcoded and never logged. `.mcp.json` maps `${userConfig.figma_token}` → `FIGMA_TOKEN`. `plugin.json.userConfig.figma_token` is declared `sensitive: true`. Both guarded by integration-harness assertions in section `[3]` ("design-bridge FIGMA_TOKEN flows from userConfig", "plugin.json figma_token declared sensitive").

**Dependencies:** `@modelcontextprotocol/sdk` + `zod` only. No `axios`, no `figma-api` — Node 18+ `fetch` is injected through a `FetchImpl` interface so tests substitute a deterministic mock (`tests/_mock-fetch.ts`) without touching globals.
**Tests:** 54 vitest tests across client (config + error paths), frames (URL parse + flatten), tokens (color/typography/spacing dedupe), styles (CSS + Tailwind emitters), compare (PNG IHDR parser + verdict matrix), tools (Zod + handler), server (dispatch + error wrapping).
**Wire:** Added to `.mcp.json`; plugin.json gained the `figma_token` userConfig entry (sensitive); integration harness extended with section `[4c]` that drives `list_tools` + both `db_compare_impl` verdict branches over stdio JSON-RPC.

### S2-03: Fix PostgreSQL pool leak (Bug #4) ✅ DONE
**Location:** `mcp-servers/sdlc-engine/src/state/postgres.ts`
**Problem:** Four distinct leak paths could orphan pool clients or crash the process. `transact()` always did a plain `client.release()` even on error, so mid-transaction failures returned broken clients to the pool; unhandled `pool.on('error')` events crashed Node; connect-failures propagated without context; shutdown errors masked the reason the process was going down.
**Fix:**
- `static fromPool(pool)` — test/injection factory that registers the idle-client error handler every time a store is built. Real `create()` path now funnels through it so prod and tests share the wiring.
- `transact()` — restructured finally to capture `releaseErr` and pass it to `client.release(releaseErr)`. Truthy-err tells pg to destroy the client instead of returning it to the pool, so a broken client never lingers. The rollback itself is best-effort and its failure is logged but never shadows the original error.
- `connect()` failures are wrapped with a descriptive message that names the project id, so "DB down" is distinguishable from "optimistic lock lost" in the logs.
- `close()` is idempotent and swallows `pool.end()` errors (logged to stderr) — shutdown never crashes a process that was already dying.
- `metrics()` returns `{ totalCount, idleCount, waitingCount }` for observability without leaking the underlying Pool instance.
- `PgPoolOptions` introduces `connectionTimeoutMillis` (10s), `idleTimeoutMillis` (30s), and `max` (10) as safe defaults. Dead-DB failure is now a clear error, not a hung promise.
- `PgPoolLike` / `PgClientLike` structural interfaces decouple the store from the real `pg` types so tests can inject a hand-rolled fake pool without installing postgres (which remains a peer dependency — solo users don't pay for it).
**Tests:** `mcp-servers/sdlc-engine/tests/postgres.test.ts` — 11 new tests with a `FakePool` + `FakeClient` that track checkout/release/destroy flags. Covers: error-handler registration, idle-error event handling, successful release path, mutator-throw → destroy-client path, rollback-fail path, concurrent transact independence, connect() wrapping, metrics, idempotent close, close-error swallowing, end-to-end round-trip.

### S2-04: architecture-validator skill ✅ DONE
L0 gate that validates a proposed architecture against domain policies, the approved PRD, and (optionally) the brownfield import graph from codebase-intel. Produces `architecture-report.md` and drafts ADRs for new decisions.
**Files:**
- `skills/architecture-validator/SKILL.md` — full algorithm (6 steps), explainability contract, verdict rules tied to `riskTolerance`, downstream dependencies
- `skills/architecture-validator/references/policy-catalog.md` — Universal + 3 domain tables (Financial, E-Commerce, Healthcare) with `id / rule / severity / evidence / remediation` columns
- `skills/architecture-validator/references/adr-template.md` — full ADR template with supersession chain, policy-compliance table, explicit risk-acceptance block
**Gate contract:** `criticalPolicyViolations == 0` — the only condition that can produce BLOCKED and the only condition that can suppress it. Soft warning budget depends on `vibeflow.config.json.riskTolerance` (low=0, medium=3, high=6).
**codebase-intel integration:** when brownfield + the MCP is loaded, the skill calls `ci_dependency_graph` with `detectCycles: true` and flags forbidden layer crossings + any cycle as `blocks merge`. Silence on this cross-check is reported as a limitation, never silently dropped.
**Explainability contract enforced:** every finding carries `finding / why / impact / confidence / evidence`. No evidence → no finding — the skill must refuse to grade on vibes.
**Integration harness guards (9 new checks):** SKILL.md + policy-catalog + adr-template presence, all 5 section headers in the catalog, and a regression guard on the gate contract string so future edits can't silently relax `criticalPolicyViolations == 0`.

### S2-05: component-test-writer skill ✅ DONE
L1 skill that takes source files + (optional) scenario-set.md and emits framework-aware unit tests with strict Arrange-Act-Assert structure.
**Files:**
- `skills/component-test-writer/SKILL.md` — 7-step algorithm (framework detect → source classify → scenario map → AAA enforce → scenario traceability → write file with @generated banner → emit run report)
- `skills/component-test-writer/references/test-patterns.md` — 7 templates (base, parametrized, table-driven, async+error, mocks, fake clock) + 5 explicitly forbidden shapes (conditional asserts, mystery guests, shared mutable setup, snapshot-only, `expect.anything()` abuse)
- `skills/component-test-writer/references/framework-recipes.md` — vitest vs jest side-by-side (imports, mocks, timers, parametrized, detection precedence, "adding a new framework" checklist)
**Framework detection order:** `repo-fingerprint.json` → `ci_analyze_structure` → config file sniff → fail with remediation. Never guesses.
**Regeneration safety:** generated files carry `@generated-by vibeflow:component-test-writer` banner with `@generated-start` / `@generated-end` markers — human-edited regions survive re-runs verbatim.
**Scenario traceability:** every `it(...)` title starts with the scenario id (`SC-017: ...`) and the body ends with a `trace:` comment. That's the only thing `traceability-engine` needs to wire test → scenario → PRD.
**Integration harness guards (7 new checks):** SKILL.md + references presence, AAA contract sentinel, vitest + jest section sentinels in framework-recipes, `@generated` banner sentinel — so a future edit that silently drops any of these fails fast.

### S2-06: contract-test-writer skill ✅ DONE
L1 skill that turns an OpenAPI (2.x/3.x) or GraphQL SDL spec into provider + consumer contract tests AND classifies every diff vs the previous spec version as MAJOR / MINOR / PATCH.
**Files:**
- `skills/contract-test-writer/SKILL.md` — 7-step algorithm (spec detect → normalize to CanonicalOperation → provider tests → consumer snapshots → breaking-change diff → verdict → write outputs)
- `skills/contract-test-writer/references/breaking-change-rules.md` — 32 classified diff rules across 4 tables (operation, request, response, header/parameter) with `id / condition / severity / rationale / remediation` columns
- `skills/contract-test-writer/references/spec-parsers.md` — OpenAPI 3.x (preferred) + 2.x (best-effort) + GraphQL SDL parsing notes, `$ref` handling, `allOf`/`oneOf`/discriminator semantics, cycle handling, the shared `CanonicalOperation` shape
**Gate contract:** `MAJOR breaking changes block the release`. Spec diffs without an `x-vibeflow-migration` note default to BLOCKED; diffs that carry a migration note drop to NEEDS_REVISION. No ad-hoc severity — every classification must cite a rule id from the table.
**Hard preconditions:** malformed spec, dangling `$ref`, or missing `operationId` all produce a single blocks-merge finding rather than garbage tests. Graceful degradation is explicitly rejected ("shipping tests generated from a wrongly-parsed spec is worse than shipping no tests").
**Regeneration safety:** reuses the `@generated-by` banner + marker convention from `component-test-writer` so re-runs preserve human-edited regions verbatim.
**Integration harness guards (11 new checks):** SKILL.md + both references files present, gate contract string regression guard, all 4 breaking-change tables present, minimum MAJOR rule count (≥10) so the gate can't be silently gutted, OpenAPI 3.x + GraphQL SDL parser sections present.

### S2-07: business-rule-validator skill ✅ DONE
L1 skill that makes the PRD's business rules **executable and auditable**: every rule becomes a catalog row, a generated test case, and a line in a semantic-gap report.
**Files:**
- `skills/business-rule-validator/SKILL.md` — 7-step algorithm (extract → normalize to `BusinessRule` records → dedupe → generate tests → gap analysis → verdict → write outputs)
- `skills/business-rule-validator/references/rule-extraction.md` — 4 pattern tiers (RFC 2119 → conditional imperatives → prohibition verbs → domain triggers), priority defaults per domain, 6 disambiguation rules learned from the TruthLayer pilot, explicit "what NOT to extract" list
- `skills/business-rule-validator/references/gap-taxonomy.md` — 10-category taxonomy (`GAP-001..GAP-010`) covering uncovered / weak / contradicted / orphan / stale-scenario / multi-rule-collapse / priority-mismatch / flaky / ambiguity-filtered / non-testable
**Gate contract:** `zero uncovered P0 rules and zero contradicted rules`. Contradiction (GAP-003) is always critical regardless of priority — one side of the codebase is always wrong. P0 uncovered (GAP-001) fails the gate; P1..P3 uncovered escalate via the risk-tolerance budget (same shape as architecture-validator).
**Hard preconditions:** `prd-quality-analyzer` testability score ≥ 60 required; rules quoting PRD text flagged as AMBIGUOUS are filtered at Step 1 (surfaced as GAP-009 info findings, never blockers). Refuses to rescue unready requirements.
**Lossless normalization:** normalization rewrites into `<actor> MUST <action> WHEN <condition>` but keeps the exact PRD quote as `statement` so reviewers can audit the rewrite.
**Regeneration safety:** reuses the `@generated-by` banner + marker convention so `br-test-suite.test.ts` re-runs preserve human-edited regions verbatim.
**Integration harness guards (9 new checks):** SKILL.md + both references present, gate contract string sentinel, all 4 extraction tiers present (pattern drift = silent rule loss), gap-taxonomy category count ≥ 10 (catalog can't silently shrink).

### S2-08: test-data-manager skill ✅ DONE
L1 skill that turns TypeScript types / Zod schemas / JSON Schema into **deterministic, invariant-respecting** factories + fixtures. Same seed → same data on every machine, every run.
**Files:**
- `skills/test-data-manager/SKILL.md` — 7-step algorithm (type source detect → `CanonicalSchema` parse → seeded RNG setup → per-schema factory emit → edge-case variant injection → fixture snapshot write → run report)
- `skills/test-data-manager/references/generator-patterns.md` — mulberry32 PRNG (embed-verbatim block), seed composition (`FACTORY_SEED ^ hashName(schema) ^ localSeed`), `make<Schema>(overrides, seed)` signature, invariant retry strategy (retry-with-bumped-seed, never bias distributions), sequence-backed ids, Fisher-Yates shuffle, fixed-anchor date helpers, `InvariantViolationFromOverride` error class
- `skills/test-data-manager/references/edge-case-catalog.md` — 37 catalog entries across 6 primitive groups (strings×13 including unicode astral/RTL override/NUL byte/SQL shape, numbers×10 including NaN/Infinity/0.1+0.2 float lie, booleans×2, dates×6 including DST transition/leap-day/far-future, arrays×5, optional/nullable×3)
**Determinism contract (THE non-negotiable invariant):** `Math.random`, `Date.now`, and any wall-clock source are explicitly forbidden. All randomness flows through the embedded PRNG. Dates use a fixed anchor timestamp so "past" means the same thing every run. Retries walk the seed forward deterministically (`seed + attempt`), so retry counts are reproducible across machines.
**Invariant strategy:** `satisfyInvariants` retries up to `MAX_INVARIANT_RETRIES` (100) with a bumped seed on each attempt. After that, hard-fails with "invariant unreachable" — never silently returns the last candidate. Biasing the generator's distribution toward "likely valid" is explicitly rejected as "how bugs hide".
**Override semantics:** overrides always win verbatim (tests that want invalid data should get it). Overrides that violate an invariant throw `InvariantViolationFromOverride` — tests that genuinely need invalid invariants use the named edge-case presets, not overrides.
**Edge-case authority:** the skill never invents edge cases. Missing entries surface as `pending:` comments in the run report + finding, prompting the human to extend the catalog rather than guess. Every entry cites the bug class it catches.
**Integration harness guards (13 new checks):** SKILL.md + both references present, determinism contract string sentinel, `mulberry32` embedded in generator-patterns, `Math.random`/`Date.now` forbidden-call sentinel, all 6 primitive sections in edge-case-catalog, `EC-*` entry count ≥ 25.

### S2-09: invariant-formalizer skill ✅ DONE
L1 skill that eliminates the "we all understand what the rule means" layer between PRD and tests. Every invariant becomes a machine-checkable predicate + a row in `invariant-matrix.md` + (optionally) an SMT proof obligation and a property-based generator.
**Files:**
- `skills/invariant-formalizer/SKILL.md` — 7-step algorithm (taxonomy load → candidate extract → classify → formalize per target → emit outputs → cross-check with `test-data-manager` factories → verdict)
- `skills/invariant-formalizer/references/invariant-taxonomy.md` — 7 base classes (`INV-RANGE / INV-EQUALITY / INV-SUM / INV-CARDINALITY / INV-TEMPORAL / INV-REFERENTIAL / INV-IMPLICATION`) + 10 domain overlays (4 financial, 3 e-commerce, 3 healthcare). Every class declares definition, signature, typical verbs, default confidence, and counter-examples
- `skills/invariant-formalizer/references/formalization-recipes.md` — verbatim code templates for every base class × every target format (zod / runtime / smt / pbt). Recipe file is load-bearing — the skill does string substitution on `<placeholder>` fields and emits nothing else
**Gate contract:** `zero unformalized P0 invariants and zero cross-check failures`. `taxonomyGaps > 0` escalates to NEEDS_REVISION but never BLOCKED — the skill surfaces the gap and asks the human to extend the taxonomy rather than guessing.
**Cross-check step (Step 6):** every invariant's runtime predicate is dry-run against the corresponding `test-data-manager` factory (10 samples). Drift between the factory and the invariant is a critical finding — this is the step that keeps `business-rule-validator`, `test-data-manager`, and `invariant-formalizer` mutually consistent.
**Classification rules:** one class per invariant; domain overlay wins over base class when both match (so the matrix cites the load-bearing regulatory reason); ambiguous candidates ABORT classification with remediation "extend invariant-taxonomy.md first" — the skill never guesses.
**Lossless formalization:** original NL statement stays attached as a comment in the emitted code. Readers should never need to open the PRD to understand what a predicate is checking. Every predicate is total — unreachable branches get explicit handling, never default-pass.
**Integration harness guards (25 new checks):** SKILL.md + both references present, gate contract string sentinel, all 7 base classes present in taxonomy, at least one overlay per domain (financial, e-commerce, healthcare), all 7 classes present in recipes, all 4 target formats (zod/runtime/smt/pbt) declared in the format table.

### S2-10: checklist-generator skill ✅ DONE
Last of the 7 Sprint 2 L1 skills. Emits context-aware review checklists (PR review, release, feature sign-off, accessibility) driven by platform and enriched with scenario + rule coverage gaps.
**Files:**
- `skills/checklist-generator/SKILL.md` — 7-step algorithm (template family resolve → base items → scenario-gap injection → rule-gap injection → per-item verifiability check → verdict → write outputs)
- `skills/checklist-generator/references/checklist-templates.md` — 4 contexts × 4 platforms matrix + 3 domain overlays (Financial/E-commerce/Healthcare). Template file holds only catalog ids; atomic items live in the catalog
- `skills/checklist-generator/references/item-catalog.md` — 73 verifiable items, each with `text / verification / sourceOfTruth / outcome / rationale / priority / platform / context`
**Gate contract:** `zero unverifiable items in the generated checklist`. The Step 5 verifiability check rejects every item whose verification verb is weak ("ensure", "confirm", "check that it is good"), whose source of truth doesn't resolve to a real file/URL/metric, or whose outcome isn't binary. Weak items don't ship — the point of a checklist is a finite set of binary checks a reviewer can actually execute.
**Template ↔ catalog consistency contract:** every catalog id referenced in a template must exist in `item-catalog.md`. The integration harness enforces this at commit time — drift between templates and catalog fails CI, not production invocation.
**Scenario + rule gap injection:** when `scenario-set.md` / `business-rules.md` + `semantic-gaps.md` are present, items with ids like `CL-GAP-<scenarioId>` and `CL-BR-<ruleId>` get appended. Every injected item is re-run through the verifiability check — no bypass.
**Accessibility × backend refused:** the skill aborts with a clear error when asked for a11y on a pure backend. The error points at `web` or `mobile` as the likely real intent.
**No `@generated` markers:** checklists are artifacts reviewers read directly, not source files to regenerate. Historical checklists stay on disk so retrospectives can look at what was on the sheet at the time.
**Integration harness guards (13 new checks):** SKILL.md + both references present, gate contract string sentinel, all 4 contexts in templates (pr-review/release/feature/accessibility), all 3 domain overlays (Financial/E-commerce/Healthcare), item catalog size ≥ 40, **and the load-bearing template-id → catalog-entry resolution check** (every template reference must exist in the catalog — zero-drift enforcement).

---

## Sprint 2 status (Layer 0-1 skills complete)
All 7 Sprint 2 L1 skills have shipped: S2-04 architecture-validator, S2-05 component-test-writer, S2-06 contract-test-writer, S2-07 business-rule-validator, S2-08 test-data-manager, S2-09 invariant-formalizer, S2-10 checklist-generator. Sprint 2 now has only S2-11 (integration testing) remaining before completion.

### S2-11: Integration testing — Sprint 2 ✅ DONE
Sprint 2 integration closure delivered as a dedicated harness + a vitest load regression.
**New file: `tests/integration/sprint-2.sh`** — 87 Sprint-2-specific assertions across 6 sections:
- **[S2-A]** L1 skill inventory — all 7 skills have `SKILL.md`, `references/` directory with ≥2 reference files, and declare `allowed-tools`
- **[S2-B]** `io-standard.md` output consistency — every output file declared in the standard's L1 table matches a substring in its skill's SKILL.md (catches drift between the contract doc and the prompt)
- **[S2-C]** Cross-skill reference coherence — every backticked skill name inside a SKILL.md must resolve to a real `skills/<name>/` directory; specific assertions that `invariant-formalizer` references **both** `business-rule-validator` AND `test-data-manager` (the Step 6 mutual-consistency contract), `business-rule-validator` reuses `component-test-writer`'s AAA patterns, `checklist-generator` declares both `CL-BR-*` and `CL-GAP-*` injection paths
- **[S2-D]** Gate contract consistency — every L1 skill that gates on something declares its exact contract string; `component-test-writer` is asserted to **NOT** declare a gate contract (it generates code, not verdicts — the harness guards against a fake gate silently sneaking in)
- **[S2-E]** MCP server sanity — codebase-intel + design-bridge dists parse; minimal JSON-RPC round-trip exercising `ci_analyze_structure` and `db_tools/list`
- **[S2-F]** Bug tracker closure — `ROADMAP.md` must mark bugs #3 / #4 / #7 as `FIXED` (prevents silent status regressions)

**New vitest: `mcp-servers/sdlc-engine/tests/postgres.test.ts` — 3 load regression tests for Bug #4:**
- 200 concurrent transacts on distinct projects — every checkout paired with a clean release, `idleCount == 200`
- 200 concurrent failures — every client destroyed, `idleCount == 0` (no broken clients returning to pool)
- 100 contended transacts on the same project — revisions monotonically cover `2..101` with no gaps/repeats (KeyedAsyncLock × release-with-err contract under contention)

**Regression:** all 6 test layers green. Sprint 1's 137 checks → now part of a 445-check baseline.

---

## Next Ticket to Work On
Sprint 2 is closed. Pick up at **docs/SPRINT-3.md — S3-01** (first DevOps/Observability ticket).

## Test inventory (Sprint 2 final)
- mcp-servers/sdlc-engine: **104 vitest tests** (+3 load regression in postgres.test.ts)
- mcp-servers/codebase-intel: **46 vitest tests**
- mcp-servers/design-bridge: **54 vitest tests**
- hooks/tests/run.sh: **26 bash assertions**
- tests/integration/run.sh: **128 bash assertions**
- tests/integration/sprint-2.sh: **87 bash assertions** (new)
- Total: **445 passing checks** across 6 test layers

## Execution Order
~~S2-01 codebase-intel~~ ✅ → ~~S2-02 design-bridge~~ ✅ → ~~S2-03 pg fix~~ ✅ → ~~S2-04..S2-10 7 L1 skills~~ ✅ → ~~S2-11 integration~~ ✅ → **Sprint 2 Complete**
