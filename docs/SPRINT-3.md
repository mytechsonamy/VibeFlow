# Sprint 3: DevOps + Observability + Layer 2-3 Skills ✅ COMPLETE

## Sprint Goal
CI/CD integration via dev-ops MCP, monitoring via observability MCP, complete TruthLayer Layer 2 (Execution) and Layer 3 (Evolution) skills. All 7 pipelines fully operational.

## Prerequisites
- Sprint 2 complete (codebase-intel + design-bridge MCPs, Layer 0-1 skills)

## Completion Criteria
- [x] dev-ops MCP integrates with GitHub Actions/GitLab CI
- [x] observability MCP collects and analyzes test execution metrics
- [x] All 7 pipelines from orchestrator.md declared + cross-referenced
- [x] 15 new skills produce correct output (target was 11; Sprint 3 shipped 15)
- [x] Full cycle test: PRD → scenario-set → tests → UAT → release decision

---

## Tickets

### S3-01: dev-ops MCP server ✅ DONE
CI/CD integration MCP server with 37 vitest tests (all green).
**Location:** mcp-servers/dev-ops/
**Tools shipped** (prefixed `do_`):
- `do_trigger_pipeline` — dispatches a GitHub Actions `workflow_dispatch` with optional inputs; accepts workflow file name (stable across renames) or id
- `do_pipeline_status` — normalized status + conclusion shape, derives `durationMs` from createdAt/updatedAt; collapses GitHub's `requested`/`waiting`/`pending` to `queued`; remaps unknown conclusions to `neutral` so downstream can always pattern-match
- `do_fetch_artifacts` — returns artifact list + total size. Does NOT download blobs — the caller fetches with the same auth. Keeps the MCP layer side-effect-free
- `do_deploy_staging` — thin wrapper over `do_trigger_pipeline` with an explicit `environment` input (default `staging`). Separate tool so audit logs clearly record "deploy" vs generic "dispatch"
- `do_rollback` — dispatches the rollback workflow with `targetRef` + a mandatory `reason` (≥3 chars, preserved in run note). Rollback audit trails are only useful if they record why
**Provider abstraction:** `CiProvider` interface with GitHub implementation. GitLab CI can land later without touching `tools.ts`.
**Security:**
- Token read from `process.env.GITHUB_TOKEN` at first tool call (lazy construction — list_tools works without a token)
- `.mcp.json` maps `${userConfig.github_token}` → `GITHUB_TOKEN`; `plugin.json` declares `github_token` with `sensitive: true`
- Workflow-name validator rejects path-traversal characters (`..`, `\\`) and ref validator rejects whitespace/newline refs
**Error wrapping:** every HTTP request funnels through a single `request()` path — transport exceptions, non-2xx responses (with status + path + body snippet), and invalid JSON bodies all wrap into a single `CiClientError`
**Dependencies:** `@modelcontextprotocol/sdk` + `zod` only. No `@octokit/rest`, no `got`, no `axios` — Node 18+ `fetch` is injected via a `FetchImpl` interface so tests substitute a deterministic mock (same pattern as design-bridge)
**Tests:** 37 vitest tests across client (config + error paths + status/conclusion normalization), pipelines (trigger validation, status durationMs, artifacts totalBytes, deploy env merge, rollback reason validation + audit note), tools (Zod validation, all 5 handlers), server (dispatch + error wrapping + custom name)
**Wire:** Added to `.mcp.json` as a fourth MCP server; `plugin.json` gained the `github_token` userConfig entry (sensitive); integration harness extended with `[4d]` section (5 stdio smoke assertions) + `[3]` GITHUB_TOKEN regression guards (2 assertions).

### S3-02: observability MCP server ✅ DONE
Test execution monitoring and analysis MCP server with 55 vitest tests (all green on first run).
**Location:** mcp-servers/observability/
**Tools shipped** (prefixed `ob_`):
- `ob_collect_metrics` — parses vitest / jest / playwright JSON reporters through a single `parseReporter` auto-dispatcher that sniffs the payload shape. Returns a `NormalizedRun` + `RunMetrics` (pass rate excluding skipped, duration p50/p95/p99, N slowest tests, per-file rollups)
- `ob_track_flaky` — cross-run flakiness detection over a directory of NormalizedRun JSON files (sorted by mtime) or an inline runs array. Scores 0..1 via `min(passes, failures) / total × (0.5 + 0.5 × interleave_ratio)`. Classifies as `stable / flaky / regressing`: a test that fails only at the tail is regressing, not flaky (pure regressions deserve their own finding)
- `ob_perf_trend` — moving-average performance trend. Reports `speedup / stable / slowdown / insufficient-data` direction + the top N per-test regressions against a rolling baseline (`windowSize` configurable, default 5)
- `ob_health_dashboard` — compact `green / yellow / red` health grade consumed by `/vibeflow:status` and `release-decision-engine`. Red on failing tests OR regressing tests OR pass rate < 0.95; yellow on flaky OR pass rate < 0.99 OR trend slowdown; green otherwise

**Normalized shape:** every parser produces the same `NormalizedRun { framework, startedAt, finishedAt, totalDurationMs, tests[] }` where each test has `{ id, file, name, status, durationMs, errorMessage, retries }`. `id = <file>::<name>` is the flakiness key. playwright cross-project runs get tagged with `[project]` in the name so chromium ≠ firefox for the same spec.

**Framework-specific details:**
- **vitest vs jest disambiguation** via vitest's `location` field on assertions (added by its JSON reporter). Falls back to jest for the shared testResults shape.
- **playwright** walks nested suites → specs → tests depth-first; picks the LAST result in the `results` array (final attempt = ground truth); records `retries` from the `retry` field.
- **unknown status values** collapse to `pending` so downstream consumers can always pattern-match (no raw strings leak out of the parser).

**Pure-function layering:** `metrics.ts`, `flakiness.ts`, `trends.ts`, `dashboard.ts` are all pure functions of `NormalizedRun[]`. The only module that touches the filesystem is `flakiness.ts` (`loadHistoryDir`, `analyzeHistoryDir`) and even then the pure `analyzeHistory` variant lets tests stay in-memory.

**Hard-fail parser:** `ReporterParseError` on malformed input; the skill never guesses a framework. `autoDetect` throws rather than defaulting to any framework when the shape doesn't match.

**Dependencies:** `@modelcontextprotocol/sdk` + `zod` only. No parsers pulled in — Node's native `JSON.parse` handles every reporter format.

**Tests:** 55 vitest tests across parsers (7 auto-detect + 5 vitest/jest/playwright), metrics (4 percentile helpers + 5 aggregates), flakiness (6 `analyzeHistory` classifications + 4 `loadHistoryDir`), trends (6 overall + 2 per-test), dashboard (5 grades), tools (9 handler tests with inline + reporterPath modes), server (5 dispatch paths + error wrapping).

**Wire:** Added to `.mcp.json` as a fifth MCP server (no env — local only). Integration harness extended with `[4e]` section: 4 tools/list assertions + 3 real JSON-RPC round-trip assertions exercising `ob_collect_metrics` with an inline vitest payload (verifies parser + metrics + framework detection through the MCP envelope).

### S3-03: e2e-test-writer skill ✅ DONE
First Sprint 3 L2 skill. Generates end-to-end tests from `scenario-set.md` — Playwright for web, Detox for iOS/Android — with a **three-rule flake contract** enforced at generation time.
**Files:**
- `skills/e2e-test-writer/SKILL.md` — 7-step algorithm (recipe load → scenario filter → POM resolve → auth strategy select → waiting contract → selector contract → emit with @generated banner)
- `skills/e2e-test-writer/references/platform-recipes.md` — Playwright (web) vs Detox (mobile) side-by-side: imports, navigation, waiting allowed/forbidden lists, assertions, auth, retry budget. "Adding a new runner" checklist for Cypress/Appium/WebdriverIO.
- `skills/e2e-test-writer/references/pom-patterns.md` — Playwright + Detox POM skeletons with `goto()` + `waitForReady()` composite wait methods, Selector Stability Policy (data-testid → role → text; CSS classes and xpath rejected outright), 4-strategy Auth Catalog (`anonymous` / `stored-session` / `token-injection` / `ui-login`) with per-platform applicability
**Gate contract (three rules that re-introduce flake if weakened):**
- `zero raw selectors in the test body` — every DOM/UI interaction flows through a POM method
- `zero sleep-based waits` — `waitForTimeout` / `device.pause` / `setTimeout` all forbidden; only observable waits allowed (`expect(pom.x).toBeVisible()`, POM's `waitForReady()`, Detox's `waitFor(...).withTimeout(N)`)
- `zero xpath selectors` — rejected outright; CSS classes banned; only `getByTestId` / `getByRole` / `getByText` allowed
**Additional blockers:** `criticalScenariosWithoutTests == 0` (P0 scenarios must produce real tests, `test.skip` doesn't count), `ambiguousScenarios == 0` (missing target/expected can't be guessed), localhost without a port blocks (the #1 "works on my laptop" cause).
**Auth strategy enforcement:** `stored-session` is web-only — using it on mobile is a hard block with remediation "use token-injection instead". No silent fallbacks — wrong auth strategy = silently authenticating as the wrong user.
**Retry budget: 0 by default.** Scenarios can opt into retries by explicitly declaring `{retries: N, reason: "..."}` in `scenario-set.md` AND the reason gets emitted as a comment. Silent retries forbidden — retries hide flake, not fix it.
**POM handling:** existing POMs are read-only (never rewritten); missing POMs get a one-shot skeleton emitted with "manual implementation required" in the run report (the skill refuses to invent selectors that don't exist). Banned selectors in existing POMs → WARNING in run report, never auto-fix.
**Integration harness guards (13 new checks):** SKILL.md + both references present, three-rule gate contract string sentinel, Playwright + Detox sections present in platform-recipes, `waitForTimeout forbidden` sentinel, all 4 auth strategies present in pom-patterns, `xpath rejected/banned` sentinel, `@generated` banner sentinel. `sprint-2.sh` cross-skill coherence check now picks up `component-test-writer → e2e-test-writer` as an additional reference (87 → 88).

### S3-04: uat-executor skill ✅ DONE
L2 skill that **runs** (not generates) UAT scenarios against a live staging environment and produces `uat-raw-report.md` — the raw material `test-result-analyzer`, `observability-analyzer`, and `release-decision-engine` all consume.
**Files:**
- `skills/uat-executor/SKILL.md` — 7-step algorithm (env+runner resolve → run dir + breadcrumb → scenario select → per-step walk → halt policy → evidence collection → write finalized/partial report)
- `skills/uat-executor/references/execution-protocol.md` — per-step rules for 3 step types (`automated` via runner / `human` via interactive prompt / `probe` read-only call), 3 halt modes (`criticalFailure` default / `firstFailure` / `never`), evidence requirements per type, re-run idempotency rules, explicit "forbids silent retries + synthetic passes + production runs + evidence-less runs + log history rewrites"
- `skills/uat-executor/references/report-schema.md` — frozen schema v1 for `uat-raw-report.md` (Header / Summary / Scenario results / Notes sections in fixed order) + `per-step.jsonl` line shape + per-step-type evidence shapes + 4 downstream consumer contracts + breaking-change checklist

**Gate contract:** `Every failed step carries evidence, every P0 scenario is executed, no step is marked `passed` without a recorded assertion`. These three invariants are the reason downstream consumers can trust the report at all — a report that violates any of them gets demoted from `finalized` to `partial:<reason>`, and `release-decision-engine` hard-blocks GO on anything but `finalized`.

**Production guard (non-negotiable):** "Does NOT run against production. There is no override flag." Even if the caller claims it's safe, the Step 1 environment resolver refuses anything tagged `prod: true` in `vibeflow.config.json.environments`. No flag, no escape hatch, no "just this once".

**Human-in-the-loop honesty:** non-interactive (CI) runs with human steps in scope record them as `skipped-noninteractive`, NEVER as `passed`. Pre-recorded responses via `--responses <file.json>` let CI supply answers up front, still logged as "human, pre-recorded" in the audit trail. A P0 scenario that depends on human observation cannot be gate-passed by the skill alone.

**Evidence requirements per step type:** automated-failed → screenshot + stdout + stderr; human-failed → mandatory operator note; probe-failed → output (2KB truncated) + decision reason. `evidenceMissing > 0` → report finalized as `partial`, not `finalized`.

**Halt policy:** default `criticalFailure` (P0 fail halts current scenario, continue run); `firstFailure` for state-dependent scenario chains; `never` for discovery runs. Halted steps are marked `not-reached` (not `skipped` — skipped implies a decision, not-reached means the walk aborted — the distinction matters for downstream accounting).

**Log append-only:** `per-step.jsonl` is written incrementally during the run so a crash leaves a parseable breadcrumb. Mid-run corrections append new lines with `"supersedes": <index>`, never edit existing lines. "Rewriting history" is explicitly forbidden.

**Count consistency invariant:** `passed + failed + blocked + notReached + skippedNoninteractive == scenariosExecuted` — if arithmetic doesn't add up, the skill refuses to write the report (always a skill bug, never a data bug).

**Integration harness guards (17 new checks):** SKILL.md + both references present, gate contract string sentinel (split into two grep calls so backticks don't mangle bash quoting), production override sentinel, all 3 step types declared in execution-protocol, all 3 halt modes, silent-retry forbidden sentinel, schema version sentinel, all 4 downstream consumer contracts declared in report-schema.

### S3-05: regression-test-runner skill ✅ DONE
L2 skill that runs the project's existing suite at a trigger-appropriate scope, diffs vs `regression-baseline.json`, classifies every test (still-passing / new-failure / still-failing / fixed / flaky / skipped / not-executed / new-test-*), and enforces an **exact** P0 pass-rate gate. Where `e2e-test-writer` generates and `uat-executor` runs scenarios against live staging, this skill exercises the committed suite and keeps the baseline file honest.
**Files:**
- `skills/regression-test-runner/SKILL.md` — 8-step algorithm (scope → dispatch runner → parse via `ob_collect_metrics` → baseline diff classification → flaky cross-check via `ob_track_flaky` → verdict+gate → baseline update policy → write outputs)
- `skills/regression-test-runner/references/scope-selection.md` — 3 scopes (`smoke` / `full` / `incremental`), deterministic decision tree, **"P0 always in smoke"** rule (non-negotiable), affected-set derivation via `ci_dependency_graph` with directory-proximity fallback, `incremental → smoke` auto-promotion when affected set > 50% of smoke
- `skills/regression-test-runner/references/baseline-policy.md` — `regression-baseline.json` schema v1, promotion rules, staleness horizon table (full 30d / smoke 7d / incremental 3d) with **override-can-only-TIGHTEN** rule, cold-start rules, corruption handling, manual rollback

**Gate contract (the whole trust model hangs on it):** `P0 pass rate must be exactly 100% — not 95%, not 99%`. Three blockers:
1. Any P0 test failed → BLOCKED; baseline untouched
2. Any test classified `new-failure` regardless of priority → NEEDS_REVISION; baseline untouched
3. P0 count is 0 → NEEDS_REVISION (test-strategy gap, never a silent pass)

**Flakiness is not forgiveness for P0:** a P0 test flagged flaky by `ob_track_flaky` is recorded as BOTH new-failure AND flaky; it blocks regardless. A P0 test is **never written to `flakyKnown`** — writing it there would feel like forgiveness, and forgiveness is `test-strategy.md`'s job (`@quarantined` or drop the P0 tag).

**Promotion rules (the file is slow-but-never-lying):**
- Only PASS verdicts promote; NEEDS_REVISION and BLOCKED leave the baseline untouched
- `smoke` scope only touches smoke-subset entries; non-smoke portion stays frozen until the next `full` run, which is why the staleness guard forces periodic `full` runs
- `incremental` **NEVER promotes**, even on PASS — the affected set is too narrow to be a trustworthy snapshot
- A `still-failing` test is NEVER quietly upgraded to `passed` on a friendly run; promoted-green on a `fixed` classification requires the current run to have explicitly seen the test pass
- Tests disappearing from the current run are PRESERVED for one full `full` cycle before being pruned — `learning-loop-engine` needs the history
- Previous baseline is saved to `.vibeflow/artifacts/regression/baseline-history/<ISO>-<runId>.json` before every write; rollback is "copy a history file back" (manual, human decision — no `--rollback` flag because "which baseline" is a human judgment)

**Staleness guard:** `smoke` run against a baseline whose last `full` promotion is >7 days old downgrades the verdict from PASS to `NEEDS_REVISION` with reason `baseline stale beyond horizon`. `test-strategy.md` can override the horizon but **only tighter** — a config that reads "incremental: 30 days" is rejected at config load as "weakens the staleness guard".

**Single source of parsing truth:** reporter parsing goes through `ob_collect_metrics` instead of re-implementing per-framework parsers in this skill. Fallback mode when `observability` is unavailable, with a WARNING banner in the run report.

**Integration harness guards (13 new checks):** SKILL.md + both references present, gate contract "exactly 100%" sentinel, 3 scope declarations (smoke/full/incremental), `Every P0 test regardless of tag` rule sentinel (drops this = silent coverage loss), `only PASS promotes` sentinel, `Never promotes the baseline` (incremental) sentinel, `only TIGHTEN` staleness sentinel, `P0 test is never added to flakyKnown` sentinel, schema version sentinel.

### S3-06: test-priority-engine skill ✅ DONE
L2 skill that ranks the test suite by risk so the highest-leverage tests run first. Produces `priority-plan.md` — a deterministic, auditable ordering with a per-test reason column — and caps the plan to a mode budget that matches the CI stage. `regression-test-runner` consumes this as its scope ordering hint.
**Files:**
- `skills/test-priority-engine/SKILL.md` — 6-step algorithm (mode + budget resolve → affected-set derive → risk score → P0 mandatory enforcement → budget-fit non-P0 tail → emit plan + spill)
- `skills/test-priority-engine/references/risk-model.md` — the **deterministic** 6-component formula (`priorityWeight` 0.30, `affectednessWeight` 0.25, `baselineFailWeight` 0.20, `flakeWeight` 0.10, `churnWeight` 0.08, `recencyWeight` 0.07), tie-breakers, override policy (must renormalize to 1.0 + `w_p >= 0.2` floor), explicit "what the model doesn't model" (semantic dependencies, coverage overlap, failure prediction)
- `skills/test-priority-engine/references/mode-budgets.md` — 3 modes (`quick` 60s/40tests / `smart` 10min/300tests / `full` unbounded), override-can-only-TIGHTEN rule, AND-ed time+count budgets, overflow-P0-never-removed rule, duration estimation fallback chain (baseline → observability → tag-based → count-only), cold-start + degraded-signal fallbacks

**Gate contract:** `Every affected P0 test appears in the plan, regardless of mode or budget`. If the P0 mandatory set alone exceeds the budget, the plan emits the full P0 set with `budgetExceeded: true, reason: "P0 mandatory set"` — the operator sees exactly why and decides to raise the budget or split the run. No silent squeeze-outs.

**Deterministic audit trail:** every row in `priority-plan.md` shows the risk score AND its decomposition into 6 components (`p=0.30 a=0.25 f=0.18 fl=0.00 ch=0.12 r=0.07`). If a user asks "why is this test at position 3", the decomposition IS the answer. Never hide it.

**Six non-modeled properties (explicit non-goals):**
1. Semantic dependencies between tests — that's `test-strategy.md`'s `dependsOn` field
2. Code coverage overlap — would need a coverage tool in the loop
3. Failure prediction — risk is historical + structural, not an oracle
4. Team ownership — that's `learning-loop-engine`'s future work
5. Parallelism budget — wall-clock only, runner owns parallelism
6. Mode inheritance across runs — every invocation resolves mode fresh

**Override disciplines (both files):**
- Risk model weights: override must renormalize to 1.0 (±0.001) + `w_p >= 0.2` floor. Overrides without a retrospective on ≥20 runs are rejected at review time
- Mode budgets: `--time-budget` / `--count-budget` may only tighten, never loosen. `--time-budget 5` rejected as below 10s floor. `--time-budget 300` on `quick` rejected as "use smart instead"
- Both file heads declare a version — current `riskModelVersion: 1`, `mode config version: 1`

**Degraded-signal discipline:** the skill runs with partial inputs (missing baseline, missing codebase-intel, missing flakiness history) BUT always records `degradedSignals: [...]` in the report header. The single refusal case: when ALL priority signals are absent (no changed files, no baseline, no flakiness, no scenario-set) — at that point a plan would be pure noise.

**Sprint-2 harness knock-on:** `component-test-writer → test-priority-engine` and `contract-test-writer → test-priority-engine` cross-references picked up automatically (88 → 90) — the growing skill graph coherence the sprint-2 harness exists to validate.

**Integration harness guards (16 new checks):** SKILL.md + both references present, gate contract sentinel, 6 risk-model component sentinels, `w_p >= 0.2` floor sentinel, 3 mode declaration sentinels, "overrides may only TIGHTEN" sentinel, 10-second floor sentinel.

### S3-07: mutation-test-runner skill ✅ DONE
L2 skill that generates code mutations from a fixed operator catalog, runs the test suite against each mutant, computes a mutation score, and pinpoints weak assertions. Where `regression-test-runner` tells you "did the tests pass", this skill tells you "did the tests actually test".
**Files:**
- `skills/mutation-test-runner/SKILL.md` — 7-step algorithm (scope + operators → generate mutants → dispatch runner → compute score → apply two-rule gate → identify weak assertions → write reports)
- `skills/mutation-test-runner/references/mutation-operators.md` — 17 operators across 5 categories (Arithmetic / Conditional / Literal / Removal / Exception+Promise), each with `id / mutation / bugClass / equivalent filter` columns. Three operator sets (`default` / `paranoid` / `boundary-only`). The `// @mutation-equivalent-ok OPERATOR: reason` comment annotation lets developers mark intentional equivalents with a mandatory reason
- `skills/mutation-test-runner/references/score-thresholds.md` — 4 domain thresholds (financial/healthcare 0.85, e-commerce 0.75, general 0.70), 5%-band NEEDS_REVISION → BLOCKED transitions, mandatory `reason` on overrides, tighten-only override discipline, threshold config v1

**Gate contract (two rules composed):**
1. **P0 zero-survivor rule** — zero surviving mutants in P0 code paths, regardless of overall score
2. **Domain score threshold** — mutation score ≥ domain-specific threshold

Both must pass. A score above threshold with any P0 survivor still BLOCKED. A clean P0 with score slightly below threshold → NEEDS_REVISION (close-miss band); meaningfully below → BLOCKED. **No override flag** for P0 survivors; the only way to accept one is to move the source file out of P0 in `test-strategy.md`.

**The single most important design choice — `no-coverage` counts as SURVIVED:** excluding no-coverage mutants from the denominator would let a repo with 20% line coverage report 100% mutation score on its tiny executed set. Mutation testing without coverage is a lie; the counting rule makes it impossible to game.

**Timeout + runtime-error handling:** classified as `killed` (the test runner DID observe a behavior change severe enough to abort), but separately tracked in the report so operators can audit. Large timeout counts (>5% of executed mutants) signal the equivalent-mutant filter needs tightening.

**Priority inheritance for P0 zero-survivor rule:** mutant priority = MAX priority of any test file that would execute the line. Resolution: explicit `@priority P0` header → `codebase-intel` dependency graph traversal → default `P2`. Defaulting to P2 (conservative) makes the strict rule bite only where intended.

**Hard preconditions:**
- `regression-test-runner` must have produced PASS on the current HEAD (or `--allow-unverified` explicit). Running mutation against a broken suite is garbage in → garbage out
- P0 source files without test files block — "mutation testing cannot score untested code"

**Equivalent-mutant filters are local:** cheap, AST-neighborhood-only, no cross-file reasoning. Cross-file equivalence is undecidable; the skill accepts a small false-positive rate instead of shipping a slow filter.

**Threshold change discipline** (same as `test-priority-engine`'s risk model): retrospective on ≥20 real runs + version bump (`thresholdConfigVersion` in every report so downstream learning-loop can bucket historical decisions) + migration note + harness sentinel update. Silent config edits rejected at review.

**Weak assertions output:** `weak-assertions.md` pinpoints tests that should have caught a survivor but didn't — with the specific test file, line, current assertion, and suggested replacement. `component-test-writer` can consume this file on the next iteration to tighten the assertion automatically.

**Integration harness guards (16 new checks):** SKILL.md + both references present, two-rule gate contract sentinel, 5 operator category sentinels, ≥15 operator count floor, 4 domain threshold sentinels, `only TIGHTEN` override sentinel, `no-coverage counts as survived` design-decision sentinel.

### S3-08: environment-orchestrator skill ✅ DONE
L2 skill that emits `env-setup.md` — a reproducible, teardown-safe environment recipe for a given `(profile, platform)` combination. Assembles components from a pinned-by-digest catalog, declares healthchecks, wires seed data, and never inlines secrets.
**Files:**
- `skills/environment-orchestrator/SKILL.md` — 7-step algorithm (profile load → component resolve → compose topology assembly → secret resolution → teardown declare → seed data wire → write outputs)
- `skills/environment-orchestrator/references/environment-profiles.md` — 5 profiles (`unit` / `integration` / `e2e` / `uat` / `perf`), each declaring required components, optional components, seed policy, healthcheck wait policy, teardown strategy; 4×5 applicability matrix (`perf`/ios|android NOT APPLICABLE, `integration`/ios|android|web NOT APPLICABLE)
- `skills/environment-orchestrator/references/component-catalog.md` — 13 catalog entries across 6 categories (Databases postgres/mysql, Caches+queues redis/rabbitmq, Mock services localstack/wiremock/mailhog, Observability prom-stack/tempo, Load generators k6, Frontend dev-servers vite-dev/selenium-grid). Every entry pinned by both `image:tag` AND `@sha256:digest`

**Gate contract (three non-negotiables):**
1. Every component has a healthcheck (the catalog entry is rejected at load time if the field is missing)
2. Every recipe carries a matching teardown command (half-tear-downable is not tear-downable; "zero leaked resources" is the whole reason this skill exists)
3. Secrets flow through `${SECRET_NAME}` references only — literal passwords/keys/tokens in a recipe are BLOCKED at Step 4, not NEEDS_REVISION. The skill scans the generated compose for common secret patterns and fails emission if any are found.

**Production rule (same as uat-executor):** "There is no override flag" — the target environment resolver refuses any env tagged `prod: true` in `vibeflow.config.json`. No flag, no escape hatch, not even for "just this once".

**Catalog discipline:**
- **Never `latest`.** Every image is pinned by BOTH an explicit version tag AND a sha256 digest. A reviewer pipeline regex rejects entries ending in `:latest`
- **Six mandatory fields per entry** (`image`, `ports`, `env`, `volumes`, `healthcheck`, `teardownCommand`) — rejected at load time if any field is missing
- **Port collisions avoided** via fixed host ports (no auto-assign — random is harder to debug)
- **Volume naming** uses `<runId>_<component>_<volumeName>` so concurrent runs don't collide
- **`--project-name` = runId** so the whole topology is addressable for teardown
- **No circular `dependsOn`** — topology must converge, cycles are catalog bugs
- **Never delete an entry** — orphans historical `env-setup.md` references; deprecate with `deprecated: true` instead
- The `artillery` entry is left as a reminder (marked REJECTED in comments) of what the reviewer pipeline should reject — `latest` + incomplete digest

**Profile discipline:**
- **Not a buffet:** you pick a profile, the profile decides the components. Projects that need a fundamentally different shape must add a new profile, not flag-drive existing ones
- **`extraComponents` can add but not remove** — a project that needs `integration` without redis has chosen the wrong profile
- **Alias resolution** (e.g. `smtp-trap` → `mailhog`) keeps profile declarations readable without duplicating catalog entries
- **Seed data is deterministic** — sourced from `test-data-manager` factory output, never from developer-laptop state
- **Seed failures are loud** — startup exits non-zero; no "soft seed"

**Teardown discipline:**
- Idempotent (running twice must not error)
- Must not depend on the recipe's startup state (works even when compose failed to reach healthy)
- Must remove **named volumes** (container rm that leaves a volume is a leak)
- Must run within 60 seconds on a typical laptop (footgun protection during CI failure handling)

**Integration harness guards (14 new checks):** SKILL.md + both references present, gate contract 3-rule sentinel, no-override production rule sentinel, all 5 profiles present, applicability matrix present, component count ≥ 10, `:latest` image tag ban sentinel, sha256 digest on ≥ 10 components sentinel.

### S3-09: chaos-injector skill ✅ DONE
L2 skill that injects controlled failures into a running test environment, observes whether the system degrades gracefully, and computes a resilience score. Every injection has a mandatory recovery step. Blast-radius overflow aborts the run. Production is forbidden with no override.
**Files:**
- `skills/chaos-injector/SKILL.md` — 7-step algorithm (catalog load → preflight health snapshot → injection plan → serial run with per-injection observe+recover cycle → blast-radius enforcement → score compute → write reports)
- `skills/chaos-injector/references/chaos-catalog.md` — 11 chaos types across 5 categories (Network latency: 2, Network drop: 2, Dependency: 2, Clock: 2, Resource: 3), each with 8 mandatory fields (`id / category / applicableProfiles / targetKinds / injectCommand / observeProbes / recoveryCommand / maxBlastRadiusSeconds`)
- `skills/chaos-injector/references/scoring-rubric.md` — 4-component weighted score formula (`recovery 0.35 + blast-radius 0.30 + expectation 0.20 + persistent-health 0.15`), 3 profile thresholds (gentle 85 / moderate 70 / brutal 55), cascading-failure-on-gentle automatic BLOCKED rule, abort-is-structural-not-partial-credit rule, `chaosConfigVersion: 1`

**Gate contract (three invariants):**
1. **Never against production.** Same structural rule as `uat-executor` and `environment-orchestrator` — no flag, no override, no escape hatch. Production chaos is a separate regulated discipline (GameDay, DR exercises) with its own approvals
2. **Every injection has a verified recovery.** "Injected, didn't check" is a disaster-in-progress. Recovery verification means the recovery command ran AND post-injection healthcheck passed within `maxBlastRadiusSeconds`. Recovery failure → abort → BLOCKED verdict + last-resort `environment-orchestrator` teardown
3. **No cascading failures on the gentle profile.** Independent of the overall score, any cascade at gentle intensity ships BLOCKED — even a 95/100 with a cascade gets hard-blocked. Cascading failures are only permitted at `moderate` + `brutal` where finding them IS the point

**Serial-only injection policy:** the skill NEVER runs two catalog entries in parallel, regardless of caller request. Parallel chaos compounds blast radius in ways that can't be reasoned about, and reasoning about blast radius is the whole point. Enforced at the algorithm layer (Step 4) + catalog rule (§6).

**Blast radius watcher (always on during injections):** aborts immediately when:
- A component OUTSIDE the target's `dependsOn` chain becomes unhealthy
- Error rate on paths NOT in the observation hooks exceeds the profile's allowed threshold
- Per-injection runtime exceeds `abortOnOverflowAfterSeconds`

Every abort writes `abort-<reason>.json` to the run dir and triggers the last-resort teardown.

**Preflight health snapshot mandatory:** a run against an already-unhealthy env produces a garbage report (you can't attribute a degradation to chaos you caused when something was already broken). Preflight is the skill's tripwire.

**Operator identity mandatory:** anonymous chaos runs are how "what was that outage yesterday" becomes unanswerable. `USER` env var OR `--operator` flag required; blocks otherwise.

**Expected degradation matching:** every injection declares `expectedDegradation` (plain text), the skill compares observed metric deltas against that prediction within a ±50% band. "System should keep working" is a valid expectation → any degradation counts as a mismatch. Unpredictable systems lose points on the `expectationComponent` because you can't build confidence on them.

**No randomized catalog parameters:** every chaos type's parameters are pinned in the catalog. A scenario that wants specific latency / loss / skew values declares them explicitly; the catalog never rolls dice. Reproducibility matters more than variety.

**Weight override discipline (same as mutation-test-runner and test-priority-engine):** renormalize to 1.0 + `w_r >= 0.25` floor (recovery is the primary signal) + retrospective on ≥10 historical chaos runs + `chaosConfigVersion` bump + harness sentinel update. Silent edits fail CI.

**Integration harness guards (17 new checks):** SKILL.md + both references present, three-rule gate contract sentinel (split grep calls), no-override production rule sentinel, 5 chaos category sentinels, chaos-catalog entry count ≥ 10, `No parallel chaos` rule sentinel, 3 profile declaration sentinels, `gentle` 85/100 threshold sentinel, `w_r >= 0.25` floor sentinel.

### S3-10: cross-run-consistency skill ✅ DONE
L2 skill that runs the same test N times in one session and checks the runs agree with each other. Answers "is this test non-deterministic right now?" — the **session-local complement** to `ob_track_flaky`'s historical-flake detection.
**Files:**
- `skills/cross-run-consistency/SKILL.md` — 8-step algorithm (resolve mode per test → capture baseline (first run) → run remaining N-1 serially → per-mode diff → classify via taxonomy → compute per-test + overall score → apply gate → write outputs)
- `skills/cross-run-consistency/references/non-determinism-taxonomy.md` — 6 classification classes (`TIMING` / `ORDERING` / `SEED-DRIFT` / `EXTERNAL-STATE` / `RESOURCE-CONTENTION` / `UNKNOWN`) with fixed walk order; each class declares signature + confidence hints + typical causes + concrete remediation
- `skills/cross-run-consistency/references/tolerance-modes.md` — `strict` vs `tolerant` semantics, per-type tolerance declarations (numeric abs+rel with tighter-of-two rule, pixel diff capped at 0.1, string ignore-rules, duration separate from numeric, exit code ALWAYS strict), 4 domain thresholds (financial/healthcare 0.98, e-commerce 0.93, general 0.90)

**Gate contract (three invariants):**
1. **P0 tests ALWAYS evaluate in `strict` mode** — no `--mode tolerant` override, no `test-strategy.md` tolerant-for-P0 config. The skill ignores any attempt and records a WARNING
2. **A P0 test scoring < 1.0 is BLOCKED** — independent of the overall aggregate. Partial consistency on a P0 is as bad as full inconsistency ("I can't tell you what this test will do next time")
3. **Fully inconsistent non-P0 tests (score 0.0) → at least NEEDS_REVISION** — even if the aggregate meets the threshold. Burying silently-broken tests under aggregate math is exactly what this skill exists to prevent

**Session-local complement to historical flake tracking:** cross-run consistency looks forward in ONE session against an unchanged codebase — any disagreement is pure non-determinism, because nothing else could have caused it. `ob_track_flaky` looks backward across time (separated by code changes + env drift + noise). Both signals compose: a test that's flaky historically AND cross-run-inconsistent is a stronger signal than either alone.

**Serial-only execution:** runs are always sequential, never parallel. Parallel execution introduces confounds (shared state via workers, file handle races, port collisions) that would make the consistency signal meaningless. "Cross-run runs are slow on purpose."

**No averaging — overall consistency = N-tests-fully-consistent / total.** We deliberately reject averaging per-test scores: "9 out of 10 tests fully agreed and 1 was 50% consistent" means 9/10, not 9.5/10. Partial consistency is as dangerous as full inconsistency from a gate standpoint.

**No retries:** a test that exceeds tolerance on the second run fails immediately. The skill doesn't retry hoping for a green reading. Retries hide non-determinism; the whole skill exists to expose it.

**`--mode tolerant` runtime flag REJECTED:** you can loosen via `test-strategy.md` config (which is review-auditable), but you cannot loosen the whole run from the command line — that's the operator mistake the config-side overrides are designed to catch at review time. `--mode strict` is allowed and is additive (everyone goes strict).

**Taxonomy walk order is fixed:** classification is deterministic because the walk picks the first matching class. TIMING → ORDERING → SEED-DRIFT → EXTERNAL-STATE → RESOURCE-CONTENTION → UNKNOWN. A single finding may fit multiple classes (e.g. system clock could be TIMING or EXTERNAL-STATE), and the walk decides which lens is primary.

**UNKNOWN is a taxonomy-gap signal, not a failure:** a report where most findings are UNKNOWN blocks the run with remediation "taxonomy needs updating before this report can be trusted". A few UNKNOWNs in an otherwise-classified report are flagged for human triage but don't block.

**Per-type tolerance rules in `tolerant` mode:**
- Numeric: TIGHTER of `numericAbsolute` and `numericRelative` applies (intersection, not union — loosening additively is a common mistake)
- Pixel: capped at 0.1 (> 0.1 rejected as "tolerance too loose — the test isn't testing the image anymore")
- Exit code: ALWAYS strict, even in tolerant mode (no per-test override for this — an exit-code flip is never "close enough")
- Duration: separate field from numeric (mixing them means a 2% number tolerance becomes a 2% timing tolerance = absurd on 100ms assertions)

**Integration harness guards (16 new checks):** SKILL.md + both references present, P0 strict-consistent gate sentinel, financial 0.98 + general 0.90 domain threshold sentinels, all 6 taxonomy class sentinels, walk-order declaration sentinel, strict + tolerant mode sentinels, P0-never-tolerant config-error sentinel, `--mode tolerant` runtime-flag-rejected sentinel.

### S3-11: test-result-analyzer skill ✅ DONE
L2 skill that turns raw test failures into a **classified, ticket-ready** set. Answers "why did this fail + what should the team do about it". Consumes `uat-raw-report.md` / `regression-report.md` / `chaos-report.md` / runner JSON and emits `test-results.md` + `bug-tickets.md`.
**Files:**
- `skills/test-result-analyzer/SKILL.md` — 9-step algorithm (ingest → normalize to `Failure` → classify → RTM link → `test-strategy.md` overrides → aggregates → ticket generation → dedup across runs → write outputs)
- `skills/test-result-analyzer/references/failure-taxonomy.md` — 5 classes (`FLAKY` / `ENVIRONMENT` / `TEST-DEFECT` / `BUG` / `UNCLASSIFIED`) with fixed walk order; BUG intentionally **fourth** in the walk so flakes/infra get a chance to classify first (the residual theory: bugs are what's left after ruling out the other explanations)
- `skills/test-result-analyzer/references/ticket-template.md` — frozen schema v1 for `bug-tickets.md` entries, `dedupKey` rule, 5 no-ticket conditions (not BUG, confidence <0.7, no scenario, no evidence, dedup >50)

**Gate contract (three structural invariants):**
1. **No `UNCLASSIFIED` leaks to downstream.** `unclassifiedPercent > 20%` → BLOCKED with "taxonomy needs extension before this report can be trusted"
2. **Every `BUG` classification has `confidence >= 0.7`.** Lower-confidence bugs are auto-downgraded to `NEEDS_HUMAN_TRIAGE`, surfaced in the report, but NOT auto-ticketed. This is the structural safety net that keeps low-confidence tickets from spamming the backlog
3. **Every generated ticket traces back to a scenario id.** A BUG-classified failure with no `scenarioId` blocks ticket emission for that failure; > 1 P0 bug without RTM linkage blocks the whole run with `rtmGap`

**Walk order is load-bearing (not signature-weighted):** FLAKY → ENVIRONMENT → TEST-DEFECT → BUG → UNCLASSIFIED. The skill picks the FIRST matching class, not the highest-confidence one. Two runs with slightly different evidence could flip a confidence-weighted pick, so walk order is deterministic at the cost of occasional suboptimal classification. Trust the label across the whole history.

**Overrides can only DEMOTE, never promote.** `test-strategy.md` can override a `BUG` classification down to `FLAKY` / `ENVIRONMENT` / `TEST-DEFECT` (with a mandatory `rationale` field), but cannot promote a `TEST-DEFECT` up to `BUG` — that's a human decision, not a config one. Both the original classification AND the override are preserved in the report so the reviewer sees both.

**Mixed-input rejection:** a glob that resolves to multiple report formats (e.g. `uat-raw-report.md` + `chaos-report.md`) blocks with remediation "run the analyzer once per report; mixing is not supported in v1". Different report formats expose different signals; unified parsing would silently prefer one.

**Dedup is stable across runs:** `dedupKey = SHA-256(testId :: classification :: errorSignature)` where `errorSignature` is the first line of the error message with numbers + UUIDs masked. Matching keys append to `occurrences` on existing tickets, not new tickets. History file is append-only (events: `created` / `occurrence-added` / `closed` / `superseded`). A reopened ticket (previously closed in the external backlog) produces a NEW ticket with `supersedes: <old-id>` — so the team can tell "regression of a closed bug" from "we forgot to close this".

**Occurrence cap = 50:** after 50 `occurrences` on the same dedupKey, the skill stops appending. At that point the ticket is a "this keeps happening" tracker, not a new bug — further appends would bloat the history file without adding signal.

**No-ticket conditions (5):**
1. Classification is not BUG — only real bugs get tickets
2. BUG but confidence < 0.7 — keeps low-confidence noise off the backlog
3. No scenarioId — unactionable without traceability
4. No evidence — a ticket with no evidence pointer is not actionable
5. Existing ticket has ≥ 50 occurrences — already tracked

**Integration harness guards (15 new checks):** SKILL.md + both references present, three-rule gate contract sentinel (split grep), all 5 taxonomy class sentinels, walk-order declaration sentinel, "BUG is fourth not first" structural rule sentinel, ticket schema version sentinel, dedupKey field sentinel, confidence ≥ 0.7 floor sentinel, append-only history rule sentinel.

### S3-12: coverage-analyzer skill ✅ DONE
L2 skill that turns raw coverage JSON into a **requirement-level**, risk-ranked report with a two-rule gate. Parses Istanbul / v8 / Istanbul-summary formats, rolls up to the PRD requirement level via RTM, ranks gaps by weighted risk, and enforces domain thresholds + P0 zero-uncovered.
**Files:**
- `skills/coverage-analyzer/SKILL.md` — 8-step algorithm (detect + parse → normalize to `CoverageRecord` → per-file metrics → RTM rollup to requirement level → risk-weighted gap ranking → apply gate → validate exclusions → write outputs)
- `skills/coverage-analyzer/references/coverage-metrics.md` — 4 metric formulas (line / branch / function / statement), sum-not-average rollup rule, 4 domain thresholds (financial/healthcare 0.90, e-commerce 0.80, general 0.75), P0 zero-uncovered exact rule, inline `@coverage-exempt` vs runner ignore distinction, critical-path-exclusion forbidden rule, 5 exclusion rules
- `skills/coverage-analyzer/references/gap-prioritization.md` — 4-component weighted gap score (`priorityComponent 0.40 + criticalityComponent 0.30 + churnComponent 0.20 + requirementLinkComponent 0.10`), `w_p >= 0.3` floor, per-file ranking (not per-line), tie-breaker chain, null-component re-normalization for degraded signals

**Gate contract (two rules, both must pass):**
1. **P0 zero-uncovered** — every file linked to a P0 requirement must have `lineCoverage == 1.0` AND `branchCoverage == 1.0`. Exact, not "within rounding"
2. **Overall threshold** — `lineCoverage >= threshold(domain)`. `<threshold but within 5% → NEEDS_REVISION`, `< threshold - 5% → BLOCKED`

A P0 violation BLOCKS even when overall passes. A critical-path exclusion BLOCKS unconditionally regardless of rationale.

**Four metric decisions that defend the gate against lies:**
1. **Null ≠ zero** — a file with no branches gets `branchCoverage: null`, not 0. "Not measurable" is different from "perfectly uncovered" / "perfectly covered"
2. **Sum rollup, not average** — `projectLineCoverage = Σ covered / Σ total`, never `avg(perFilePct)`. Averaging gives a 10-line file and a 1000-line file equal weight; summation gives proportional weight (the honest aggregate)
3. **v8-source in financial/healthcare blocks** — v8 has no branch data; regulated domains require branch coverage by policy. "Silently report 100% branch because the metric is null" is rejected
4. **Coverage summary-only mode flagged** — `coverage-summary.json` (Istanbul summary) is accepted but reports "file drilldown unavailable" so downstream knows

**Requirement-level rollup via RTM:**
- `reqLineCoverage = Σ covered lines in the union of source files mapped to this requirement / Σ total lines in that union`
- Requirement with no tests → `mappingGap: true` (more urgent than low coverage)
- Requirement with broken RTM linkage → `rtmDrift: true` (different remediation — fix the RTM, not add tests)
- Source touched by two requirements counts once per requirement's union (a line serving two features is covered when either runs it)

**P0 zero-uncovered rule is exact, not approximate:**
- Exact 1.0, no rounding tolerance
- A P0 file with an exclusion (even reasonable one) BLOCKS — critical-path exclusions are the structural non-negotiable
- `null` branch coverage on a P0 file from v8 source blocks with remediation "switch to istanbul for P0 files; branch coverage must be measurable"
- Inline `@coverage-exempt: <reason>` annotations (with mandatory reason) are allowed — they stay in the file's total lines but not the "should exercise" set. Auditable, distinct from runner ignores (which disappear from the total entirely)

**Risk-weighted gap ranking:**
- Priority component dominates (0.40 weight + `w_p >= 0.3` floor)
- Criticality signal is 0.30 — critical-path membership is the closest proxy for "bug here = customer incident"
- Churn (0.20) uses `ci_find_hotspots` with a 30-day window (catches active-development risk without diluting with old hotspots)
- Requirement linkage (0.10) is a separate axis from priority — a file can be tagged P1 in its header but link to a P0 requirement via RTM
- Null-component re-normalization: when `criticalPaths` is empty OR churn data is unavailable, the component is `null` and the score re-normalizes over the remaining components. Never zero (which would silently demote it); `degradedSignals` records the reason

**What the skill explicitly doesn't model:** failure prediction, semantic importance, gap size weighting (small gap in P0 file > large gap in P3 file, and the score reflects this because priority dominates). Same "score likelihood of being worth testing, not breaking" posture as `test-priority-engine`.

**Integration harness guards (16 new checks):** SKILL.md + both references present, three-rule gate contract sentinel (P0 + threshold + critical exclusions), 4 domain threshold row sentinels, sum-over-average rollup rule sentinel, critical-path-exclusion forbidden rule sentinel, null-not-zero structural rule sentinel, 4 gap component sentinels, `w_p >= 0.3` floor sentinel.

### S3-13: observability-analyzer skill ✅ DONE
L2 skill that parses per-run artifacts (HAR / Playwright trace / browser console / CDP exports), detects anomalies against a fixed catalog, and emits `observability-report.md`. **Per-run complement** to the `observability` MCP (which tracks cross-run metrics over time).
**Files:**
- `skills/observability-analyzer/SKILL.md` — 8-step algorithm (source detect + parse → normalize to `TraceEvent` → waterfall reconstruction → scenario linking → anomaly detection → gate → dedupe findings → write outputs)
- `skills/observability-analyzer/references/source-parsers.md` — 4 format parsers (HAR 1.2 / Playwright trace / Browser console / CDP), shared `TraceEvent` normalization, "parsers don't classify" rule
- `skills/observability-analyzer/references/anomaly-rules.md` — 16 rules across 5 categories (Network 5 / Console 4 / Performance 4 / Security 3 / Third-party 2), each with `id / category / signature / severity / rationale / remediation`, domain override table for `SECURITY-INSECURE-COOKIE`, `THIRD-PARTY-BLOCKING`, `NET-SLOW-API`

**Gate contract (three structural rules):**
1. **Zero `critical` anomalies** regardless of priority — critical means "it broke", not "it was slow"
2. **Zero `warning` anomalies on P0 scenarios** — warnings on lower priorities escalate to NEEDS_REVISION, on P0 they BLOCK
3. **Web vitals within domain budget** — within budget PASS, within close-miss band (5-10% over) NEEDS_REVISION, beyond close-miss (>10%) BLOCKED

**Per-run vs cross-run split clarified:**
- `observability` MCP = cross-run time-series (flakiness, metric trends, pass rate history)
- `observability-analyzer` skill = per-run artifact analysis (this run's waterfall, this run's console errors, this run's web vitals)
- Both feed `release-decision-engine` but answer different questions; neither replaces the other

**Normalized `TraceEvent` shape** — every parser emits the same shape regardless of source (HAR / Playwright / console / CDP). `scenarioId` and `priority` fields are deliberately filled in Step 4 of the algorithm, NOT by the parser — this keeps the parser layer stateless and format-agnostic. Fields that don't apply to a specific source are `null` explicitly, never defaulted to zero.

**Waterfall reconstruction (HAR only):** sort by `startedDateTime`, identify the longest `dependsOn` chain, surface the critical path's total duration as the page's observed load time, flag critical-path requests whose individual duration > `p95` for their content type. Report shows the chain as a hierarchical table.

**Severity semantics:**
- `critical` — it broke (4xx/5xx/unhandled exception/security violation). Gate blocks regardless of priority
- `warning` — outside declared budget but not broken. Blocks P0, NEEDS_REVISION on lower
- `info` — team declared "not a problem" (expected 404 on probes, known third-party warnings). Audit-only, never blocks

**Domain override pattern (same shape as mutation-test-runner):** rules can be **promoted** from `warning` to `critical` in specific domains (e.g. `SECURITY-INSECURE-COOKIE` → critical in financial/healthcare, `THIRD-PARTY-BLOCKING` → critical in financial, `NET-SLOW-API` → critical on payment paths in financial). Overrides can ONLY tighten — demoting `CONSOLE-ERROR` to warning in `general` is rejected at load time. Same tighten-only discipline as every other VibeFlow override.

**Expected-failure suppression** via `test-strategy.md → expectedFailures` / `expectedConsoleErrors` — project-specific list of patterns the skill treats as `info` instead of `critical`. Mandatory `rationale` field on every entry; review-auditable.

**Dedup at Step 7:** findings from the same rule against the same scenarioId + resource + error signature dedupe into one entry with an occurrences counter. Key: `rule :: scenarioId :: resource :: errorSignature` where errorSignature masks numbers and UUIDs (same pattern as `test-result-analyzer`).

**Unmapped CDP events recorded, not dropped:** CDP is a superset of every other format, so the parser encounters events it can't classify. Those get `kind: null` and land in the report's "unmapped CDP events" section rather than being silently lost. A class of events we don't know how to classify is still data.

**Parser failure modes (4 formats × per-format):** never silent. Malformed HAR → blocker "regenerate with a recorder that produces valid HAR 1.2". Corrupt Playwright zip → blocker. Unparseable console.log lines → partial parse with lossy count reported. Missing CDP params → event flagged partial, not dropped.

**Integration harness guards (17 new checks):** SKILL.md + both references present, three-rule gate contract sentinel (split grep), 4 source format sentinels, normalized TraceEvent shape sentinel, 5 anomaly category sentinels, rule count ≥ 10 floor, domain overrides table sentinel, `rule MORE strict, never less` override-tighten-only sentinel.

### S3-14: visual-ai-analyzer skill ✅ DONE
L2 skill that uses Claude vision to inspect screenshots for layout regressions, accessibility issues, typography drift, and design fidelity. **Semantic** complement to `design-bridge`'s `db_compare_impl` (which does structural dimension + byte-identity compare). The two compose: structural compare catches what vision misses, vision catches what structural compare can't describe.
**Files:**
- `skills/visual-ai-analyzer/SKILL.md` — 9-step algorithm (resolve inspection mode → delegate to `db_compare_impl` first → call vision model with structured prompt → classify via catalog → confidence filter → domain contrast rules → aggregate + score → gate → write outputs)
- `skills/visual-ai-analyzer/references/inspection-modes.md` — 3 modes (`baseline-diff` / `standalone` / `design-comparison`) with per-mode prerequisites, output shape, limitations. **Modes are additive, not exclusive** — a single run can engage any subset, merging findings across
- `skills/visual-ai-analyzer/references/finding-catalog.md` — 17 classified finding types across 7 categories (layout: 5, typography: 4, color+contrast: 3, alignment: 2, overflow: 2, broken-state: 4, UNCLASSIFIED-VISUAL fallback), each with signature + confidence hints + severity + remediation + applicable modes

**Gate contract (three structural rules):**
1. **Zero critical visual regressions in P0 scenarios** — critical = "the user will see this and it's wrong", not "it was slow"
2. **Accessibility findings require remediation** — contrast violations below the domain minimum are BLOCKED, not NEEDS_REVISION. WCAG violations are legal risks in most domains
3. **Design-diff above tolerance needs human review** — drift score > 0.10 produces warnings, > 0.15 produces critical findings. Tolerance can only tighten via `test-strategy.md → designDriftTolerance`

**Vision is NOT deterministic — the confidence filter is structural:**
- `confidence >= 0.8` → retained at declared severity
- `0.6 <= confidence < 0.8` → severity demoted one level + "probable" prefix in the report title
- `confidence < 0.6` → recorded in artifact only, NOT in the human report (keeps signal density high)

This is the key design rule that prevents the skill from gate-blocking on hallucinations. The worst failure mode of a vision skill is blocking on imagined findings; the second-worst is ignoring real regressions because the model was uncertain. The two thresholds tune the trade-off.

**Structural-compare-first policy (Step 2):** before calling the vision model, the skill invokes `db_compare_impl`:
- `identical` → no findings; empty report; PASS immediately (cheap path wins when definitive)
- `same-dimensions` → proceed to vision analysis (expected pixel drift)
- `size-mismatch` → skill STOPS and emits `LAYOUT-DIMENSION-DRIFT` finding with confidence 1.0. Dimension drift is geometry, not vision. Running the model on dimension-mismatched pairs produces noisy findings
- `unknown` → vision proceeds with a degraded-signal flag

This keeps the expensive signal off the critical path for cases the cheap signal can definitively answer.

**Domain contrast rules with override-tighten-only:**
| Domain | WCAG level | Text min | Large-text min |
|--------|-----------|----------|----------------|
| healthcare | AAA | 7.0 | 4.5 |
| financial | AA | 4.5 | 3.0 |
| e-commerce | AA | 4.5 | 3.0 |
| general | AA | 4.5 | 3.0 |

Healthcare requires AAA because patient data is read under low-light conditions in real-world clinical use. Overrides can only TIGHTEN; loosening is rejected at config load.

**3 inspection modes, additive not exclusive:**
- **`baseline-diff`** — regressions between baseline and current (requires `db_compare_impl` to report `same-dimensions` / `identical` first; `size-mismatch` bypasses and emits geometry finding)
- **`standalone`** — quality inspection without a reference (contrast, readability, overflow, broken states). Runs even when there IS a baseline, because it catches bugs that exist in BOTH versions (which baseline-diff silently accepts as "no regression")
- **`design-comparison`** — drift from Figma via `design-bridge`. Cross-checks critical color findings against `db_extract_tokens` data before escalating to critical (the model is less reliable at quantitative color comparisons than qualitative "these look different" observations)

**Multi-mode merge rules:**
- Finding produced by multiple modes (same category + region + description) → deduplicated, highest-confidence source kept, modes field shows both as cross-validation
- Finding from exactly one mode → kept with original confidence, no bonus for single-source
- **Contradictory findings kept side-by-side** — baseline-diff silent + standalone active means the bug existed pre-baseline (a real issue the test never caught, which is the whole reason for running standalone alongside baseline-diff)

**Vision response schema validation:** the skill asks the model for structured JSON findings. Malformed responses are retried ONCE with a WARNING, then blocked. The catalog's format is strict — "look at this screenshot and tell me what's wrong" as an unstructured prompt is explicitly rejected

**Suppression path:** `test-strategy.md → visualSuppressions` with mandatory `rationale` per suppressed finding id. Reasonless suppressions rejected at load. Suppressions can only DEMOTE a finding's severity or remove it entirely; they cannot elevate (the skill does that itself via confidence + catalog).

**Integration harness guards (17 new checks):** SKILL.md + both references present, three-rule gate contract sentinel (split grep), 3 inspection mode sentinels, `additive, not exclusive` structural rule sentinel, 6 finding category sentinels, confidence filter threshold sentinel, finding count ≥ 12 floor, UNCLASSIFIED-VISUAL fallback sentinel.

### S3-15: learning-loop-engine skill ✅ DONE
**First L3 Truth-Evolution skill.** Operates across TIME (not single runs) — ingests the history of every L2 skill's reports, detects recurring patterns, traces production bugs back to missed test opportunities, and recommends maturity-stage improvements. Unlike the L2 skills, this one's output is an improvement plan, not a gate verdict.
**Files:**
- `skills/learning-loop-engine/SKILL.md` — 8-step algorithm across 3 independent modes (`test-history` / `production-feedback` / `drift-analysis`), each with its own input contract and output shape
- `skills/learning-loop-engine/references/pattern-detection.md` — 13 patterns (5 test-history + 4 production-feedback + 4 drift-analysis), minimum-evidence floor of 3 observations per pattern, slope + noise-floor formulas for drift analysis, per-signal noise floors (coverage 1%, mutation 2%, flakes 50%, priority 25% per sprint)
- `skills/learning-loop-engine/references/maturity-stages.md` — 5-stage progression (Ad hoc → Baseline → Coverage → Learning → Self-improving) with deterministic promotion criteria, "no Stage 6" terminal rule, demotion rules for regressed projects

**Gate contract (three advisory invariants — this is L3, output is informational to downstream):**
1. **Every pattern must have ≥ 3 supporting observations.** Weaker patterns aren't patterns, they're coincidences. The skill discards them at Step 3 rather than emitting noise
2. **Every production bug must trace to a specific test gap OR be marked `irreducible` with human justification.** Reasonless irreducible classifications are rejected by downstream consumers
3. **Every recommendation must be actionable.** "Improve tests" is not a recommendation; "run cross-run-consistency on SC-112 and drop its P0 tag if non-deterministic" is. Unactionable recommendations are rejected at review

**L3 vs L2 distinction clarified:**
- L2 skills look at a SINGLE run → gate verdict (PASS/NEEDS_REVISION/BLOCKED)
- L3 skills look across TIME → improvement plan (`recommend / investigate / urgent` findings)
- L3 findings never merge-block; they surface for team action. `release-decision-engine` reads them as advisory weight only

**Three independent modes (not combinable in a single run):**
- **`test-history`** — walks historical baselines + bug tickets for recurring patterns (recurring failures, same-file bugs, taxonomy drift, priority inflation, flake concentration)
- **`production-feedback`** — traces a real production bug back to 1 of 4 gap classes: `covered-but-not-asserted` / `scenario-exists-not-tested` / `gap-in-scenario-set` / `irreducible`. The `irreducible` class REQUIRES written human justification before downstream consumers accept it
- **`drift-analysis`** — linear regression over 3+ sprint baselines to detect slope-based decay (coverage decay, mutation decay, flake growth, gate suppression creep)

**Severity escalation over time:**
- `recommend` → `investigate` after 4/5 sprints unresolved
- `investigate` → `urgent` after 5/5 sprints unresolved
- The skill has MEMORY via append-only `history.jsonl` — recurring recommendations climb in severity until the team acts on them

**Dedup via `patternId :: affectedArtifactsHash`:** a pattern that surfaced in a previous learning-loop run with the same signature updates the existing finding's `observations` counter and `lastObservedAt`, instead of surfacing as "new". The report shows it under "Recurring (seen N sprints)" so the team can see how long the pattern has been ignored.

**Maturity stage evaluation:** 5 stages with hard criteria each. Walk from Stage 5 DOWN until all criteria pass — that's the current stage. Report the NEXT stage's unmet criteria (the whole point is "what to do next"). Single unmet criterion blocks promotion (no partial credit).

**"No Stage 6" terminal rule:** Stage 5 is the terminal state by design. "Further improvement from here is measured in specific quality signals rather than in more gates. A project that tries to add more gates from Stage 5 usually becomes brittle; the path from Stage 5 forward is to DELETE gates whose signal has been internalized as team habit."

**Demotion rules:** a project at Stage N demotes to Stage N-1 when ANY criterion is unmet for ≥ 2 consecutive sprints OR the report is `degraded` for ≥ 3 consecutive sprints. Demotion is a signal, not punishment — surfaces as `LEARNING-MATURITY-DEMOTION` finding so the team sees it.

**Report status (informational, not gate-blocking):**
- `actionable` — ≥ 3 urgent findings OR 1-2 urgent + ≥ 5 recommend/investigate
- `degraded` — all findings below minObservations OR all findings irreducible OR > 20% unclassified. Downstream consumers (release-decision-engine) discount `degraded` reports

**No multi-mode runs:** the three modes produce different output shapes, and a unified report would average their signals in a way that loses detail. Run once per mode.

**Integration harness guards (17 new checks):** SKILL.md + both references present, three-rule gate contract sentinel (split grep), 3 mode declaration sentinels, 3 pattern catalog section sentinels, pattern count ≥ 10 floor, `≥ 3 observations` minimum-evidence sentinel, 5 maturity stage sentinels, "Stage 5 terminal" structural rule sentinel, "single unmet criterion blocks promotion" sentinel.

### S3-16: decision-recommender skill ✅ DONE
**Second L3 Truth-Evolution skill.** Turns any findings report into a structured decision package (problem + options + trade-offs + recommendation + effort estimate). Where `learning-loop-engine` surfaces patterns across time, this skill turns a specific question — "should we ship this?" / "should we add this gate?" — into a document the team can read, argue with, and decide on.
**Files:**
- `skills/decision-recommender/SKILL.md` — 6-step algorithm (decision type detect → option generate via per-type generator → score on dimensions → pick recommendation → decision history cross-check → write package)
- `skills/decision-recommender/references/decision-types.md` — 5 canonical types (`release-go-no-go` / `gate-adjustment` / `priority-change` / `risk-acceptance` / `scope-change`) + `UNCLASSIFIED-DECISION` fallback, walk order specific-to-general, per-type `optionGenerator` name + tradeoff dimensions + typical confidence
- `skills/decision-recommender/references/option-generators.md` — 5 generators (one per type) with per-type option templates, shared scoring rules (risk from finding severity × confidence, effort from T-shirt sizes + team velocity), 4 mandatory validation rules, "unknown is first-class" field

**Gate contract (four invariants that keep the skill from producing AI-confident nonsense):**
1. **Every option has at least one positive AND one negative trade-off.** Options with only upsides are rephrased "do nothing" in disguise; options with only downsides are strawmen. Both rejected at generation
2. **Option 0 is ALWAYS "do nothing", on every decision.** No exceptions, no overrides, no configuration. "Do nothing" is a real option — omitting it makes decisions feel forced
3. **Every recommendation cites at least one finding by id.** A recommendation with no citation is a gut call; the skill refuses to emit gut calls
4. **Confidence < 0.7 → `human-judgment-needed`.** The skill does not ship vague recommendations dressed up as confident ones. Report's header clearly says "the data does not conclusively favor any option"

**Anti-AI-confidence design stance (from SKILL.md):** *"The failure mode this skill is designed against: AI-assisted decision tools that confidently produce one 'correct' answer and make the human feel bad for questioning it. That's not a decision, that's an opinion delivered with extra steps. Real decisions involve trade-offs, and a recommendation without trade-offs is either obvious (human didn't need help) or wrong (the tool made it harder)."*

**`unknown` is a first-class field on every option:** the generator MUST list at least one thing the skill can't answer. Zero-unknown options are suspicious — usually the generator is confidently wrong. "Will the regulators like this" is a valid unknown; "is the coverage score above 80%" is not (the finding answers it).

**No single weighted composite score:** the skill tracks multiple dimensions (risk / effort / cost / speed / team-fit) independently. Weighting is a team judgment — the recommendation picks ONE option with raw scores preserved so the team can re-weight. *"Single-score framing is how AI tools make teams feel bad for disagreeing."*

**Decision history cross-check (Step 5):** a decision on the same problem within the last 30 days produces a `repeat-decision` warning. If nothing material changed, the skill recommends "re-read the previous decision; the inputs haven't changed" instead of re-deciding. Keeps the team from churning on already-made decisions.

**5 decision types × 5 generators, specific-to-general walk order:**
- `release-go-no-go` (most specific) — CONDITIONAL release verdicts, auto-detected when `release-decision.md` carries a CONDITIONAL
- `gate-adjustment` — threshold changes, gate additions/removals (with a special `governance: true` marker for changes to DEFAULT thresholds in `references/*.md`)
- `priority-change` — P0 list churn, scenario priority promotion/demotion, `@quarantined` tagging
- `risk-acceptance` — explicit "document and move on" for third-party / irreducible issues (financial + healthcare acceptances score higher risk)
- `scope-change` — sprint cut / timeline extend / resource add / priority swap, driven by team velocity

**Per-option validation (4 mandatory rules):**
1. `positive.length >= 1` AND `negative.length >= 1` (both directions, always)
2. `unknown.length >= 1` (first-class honesty)
3. `supportingFindings.length >= 1` for OPT-1 through OPT-N (OPT-0 allowed to cite zero — "do nothing" addresses nothing by definition)
4. Every cited finding id must exist in the input findings

A generator that produces > 30% invalid options blocks the run with "generator produced mostly-invalid options; check the catalog configuration".

**Effort sizing bridges T-shirt + team velocity:** sizes (XS/S/M/L/XL) map to rough ranges, interpreted against `team-context.md.velocity` when present. Decision package includes a "percentage of sprint hours" roll-up so the team can see decision cost in concrete terms.

**Release-options generator has a special OPT-1 feature-flag lifetime warning:** the `unknown` field explicitly flags "how long the flag will live" because feature flags that 'live forever' are an anti-pattern — the skill makes this visible upfront rather than letting it slip into "we'll clean it up later".

**Gate-options generator has a `governance: true` flag** on OPT-1 (tighten) and OPT-2 (loosen) when the change targets the DEFAULT threshold in `references/*.md` (not a project-specific override). That marks the decision as "change the default for everyone", not "loosen for this project" — which is the structural anti-pattern the VibeFlow tighten-only discipline exists to prevent.

**Integration harness guards (19 new checks):** SKILL.md + both references present, four-rule gate contract sentinel (split grep), single-score framing rejection sentinel, 5 decision type sentinels, UNCLASSIFIED-DECISION fallback sentinel, walk order declaration sentinel, 5 generator sentinels, OPT-0 Do Nothing structural rule sentinel, positive/negative/unknown trade-off validation sentinels.

### S3-17: reconciliation-simulator skill ✅ DONE
**Location:** skills/reconciliation-simulator/SKILL.md
**Layer:** L1 Truth Validation (financial-domain-only, PIPELINE-3 step 4)
**Inputs:** ledger stub (required, project-native or reference fallback), business-rules.md + invariant-matrix.md (optional), seed/iterations/max-concurrency (optional)
**Outputs:** .vibeflow/reports/reconciliation-report.md + .vibeflow/artifacts/reconciliation/<runId>/{violations.jsonl, generated-tests/, snapshots/}

**Completed:**
- [x] `skills/reconciliation-simulator/SKILL.md` — 8-step algorithm (domain check → load invariants → load patterns → seed RNG → simulation loop with per-step invariant check → classify → generate reproducer tests → write outputs)
- [x] `skills/reconciliation-simulator/references/ledger-invariants.md` — 6 canonical invariants (LEDGER-DOUBLE-ENTRY / LEDGER-CONSERVATION / LEDGER-SIGN-CONVENTION / LEDGER-MONETARY-PRECISION / LEDGER-NON-NEGATIVE-BALANCE / LEDGER-AUTHORITATIVE-TIME) with formal statement + check formula + real-world bug caught + per-project composition rules
- [x] `skills/reconciliation-simulator/references/concurrency-scenarios.md` — 6 canonical patterns (CONCURRENT-DEBITS-SAME-ACCOUNT / CONCURRENT-TRANSFERS-RING / RETRY-ON-FAILURE / PARTIAL-REVERSAL / TIMEOUT-DURING-COMMIT / DEAD-LEG) with adversarial schedules, cooperative-scheduler semantics, seed-deterministic interleaving

**Gate contract:** *zero invariant violations across every tested concurrency pattern, deterministic simulation, every violation traces to a specific operation sequence*. Three non-negotiables: zero canonical violations (no tolerance band), deterministic replay (same seed → same outcome), every violation has a reproducer test. No override flag — a team that can't meet these must either fix the defect, fix the ledger stub, or change the project's domain designation.

**Financial-domain-only rule:** the skill refuses to execute on any domain other than `financial`. No `--force`, no config override. Running reconciliation simulation on a non-financial project would produce a misleading "all clean" report against invariants that don't apply.

**Every step is checked, not just endpoints:** the load-bearing invariant-verification rule. Balances that are "correct at commit time" but tear mid-transfer are still defects — the simulator checks every canonical + per-project invariant after every operation in every interleaving, not just at the commit boundaries.

**Every violation is `severity: critical` — no warning band:** "mostly reconciled" is not a ledger state. A single violation under any tested pattern blocks. Rationale: scale amplifies silent drift; the cost of a production reconciliation defect is the cost of visibly wrong customer money plus the audit and regulatory-notification costs, neither of which fits a "warning" bucket.

**Determinism is a structural contract, not best-effort:** same seed + same business-rules.md + same ledger stub = same outcome, byte-for-byte, always. A non-deterministic run is a skill bug, not a tolerable property — fix the bug, don't work around it. The cooperative scheduler (not OS threads) is what makes this possible: interleaving order is picked by the RNG at each step boundary.

**Canonical sets are frozen:** per-project invariants compose via four rules (no-contradiction, strengthening-allowed, no-ambiguity, same-cadence). Adding a new canonical invariant or concurrency pattern requires a retrospective on ≥10 real runs plus a version bump (`ledgerInvariantsVersion` / `concurrencyScenariosVersion`). Removing a canonical pattern is explicitly forbidden — that would be admitting we stopped caring about a class of bugs.

**Every violation produces a reproducer test:** the skill emits a paste-able test file for each violation, carrying the `@generated-by vibeflow:reconciliation-simulator` banner. Low-confidence violations (< 0.8) are emitted with `test.skip` and an explanatory comment. A violation without a reproducer is a rumor; the reproducer is how the team fixes the bug and verifies the fix.

**Integration harness guards (25 new checks):** SKILL.md + both references present, three-rule gate contract sentinel (zero violations + deterministic + traces), financial-only + no-override sentinel, "every step checked" sentinel, severity-critical sentinel, structural-contract determinism sentinel, 6 canonical invariant sentinels + composition rule sentinel + ledgerInvariantsVersion sentinel, 6 canonical pattern sentinels + cooperative-scheduler sentinel + removing-forbidden sentinel + concurrencyScenariosVersion sentinel.

### S3-18: Integration testing — Sprint 3 ✅ DONE
**Location:** tests/integration/sprint-3.sh (111 bash assertions, 7 sections)

**Completed:**
- [x] `tests/integration/sprint-3.sh` — Sprint-3 integration harness covering skill inventory + io-standard output coherence + cross-skill wiring + gate contract declarations + dev-ops/observability MCP sanity + orchestrator PIPELINE-N coverage + Sprint 3 bug tracker closure
- [x] All 15 Sprint-3 skills present with ≥ 2 reference files each (30 inventory assertions)
- [x] Every Sprint-3 skill declares `allowed-tools` frontmatter (15 assertions)
- [x] io-standard primary outputs named in each SKILL.md (17 assertions)
- [x] Cross-skill reference coherence: uat-executor → test-result-analyzer + observability-analyzer, test-result-analyzer → learning-loop-engine, regression-test-runner → test-priority-engine + learning-loop-engine, coverage-analyzer ← rtm, reconciliation-simulator → release-decision-engine, decision-recommender ← L2 reports, learning-loop-engine declares 3 modes (11 assertions)
- [x] 11 distinct gate contract strings declared across Sprint-3 gating skills + 4 multi-invariant Gate section declarations (15 assertions)
- [x] dev-ops + observability MCP dists parse + tools/list + collect_metrics round-trip (6 assertions)
- [x] orchestrator.md declares PIPELINE-1 through PIPELINE-7 + 6 per-skill PIPELINE-N citations (14 assertions)
- [x] ROADMAP.md exists + no unresolved Sprint-3 bugs (2 assertions)

**Harness sections:**

| Section | Focus | Assertions |
|---------|-------|-----------|
| S3-A | Skill inventory (SKILL.md + references + frontmatter) | 45 |
| S3-B | io-standard output naming consistency | 18 |
| S3-C | Cross-skill reference coherence | 11 |
| S3-D | Gate contract declarations | 15 |
| S3-E | dev-ops + observability MCP sanity | 6 |
| S3-F | orchestrator PIPELINE-N coverage + citations | 14 |
| S3-G | Sprint 3 bug tracker closure | 2 |
| **Total** | | **111** |

**Why a Sprint-3-specific harness (not just more lines in run.sh):** same discipline as `sprint-2.sh`. run.sh is the platform baseline, checked every CI run regardless of sprint. sprint-3.sh is the Sprint-3-only CI job that proves the Sprint-3 deliverables hang together — it can be run in isolation from a PR that only touches Sprint-3 code, and it stays standalone so a future Sprint-4 sprint-4.sh doesn't need to duplicate these checks.

**Two initial failures fixed during implementation:**
1. `decision-recommender consumes chaos findings` — the skill is intentionally generic and doesn't name `chaos-report` specifically. Sentinel broadened to `L2 skill reports || learning-loop-engine`.
2. `coverage-analyzer cites PIPELINE-3` — the skill cites PIPELINE-5 / PIPELINE-6 (release-track), not PIPELINE-3 (UAT). Citation list corrected.

Both are the same shape as every other sentinel fix in this sprint: when document prose doesn't match the sentinel's expectation, either the sentinel is wrong (fix it) or the document is wrong (fix the document). Here the prose was right.

---

## Next Ticket to Work On
**Sprint 3 is ✅ COMPLETE.** Next ticket lives in `docs/SPRINT-4.md` (read that file for the active pointer).

## Test inventory (after S3-18, Sprint 3 closed)
- mcp-servers/sdlc-engine: **104 vitest tests**
- mcp-servers/codebase-intel: **46 vitest tests**
- mcp-servers/design-bridge: **54 vitest tests**
- mcp-servers/dev-ops: **37 vitest tests**
- mcp-servers/observability: **55 vitest tests**
- hooks/tests/run.sh: **26 bash assertions**
- tests/integration/run.sh: **394 bash assertions**
- tests/integration/sprint-2.sh: **94 bash assertions**
- tests/integration/sprint-3.sh: **111 bash assertions** (NEW — Sprint 3 closer)
- Total: **921 passing checks** across 9 test layers

## Execution Order
S3-01 (dev-ops) → S3-02 (observability) → S3-03..S3-17 (skills, parallel where possible) → S3-18 (integration)

## Skill Dependencies Within Sprint
```
e2e-test-writer ──┐
chaos-injector  ──┤── can be built in parallel (no inter-dependency)
environment-orch──┘

uat-executor ──► test-result-analyzer ──► coverage-analyzer (sequential)
regression-test-runner ──► test-priority-engine (sequential)
learning-loop-engine + decision-recommender (independent)
```
