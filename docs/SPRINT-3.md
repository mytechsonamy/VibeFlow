# Sprint 3: DevOps + Observability + Layer 2-3 Skills

## Sprint Goal
CI/CD integration via dev-ops MCP, monitoring via observability MCP, complete TruthLayer Layer 2 (Execution) and Layer 3 (Evolution) skills. All 7 pipelines fully operational.

## Prerequisites
- Sprint 2 complete (codebase-intel + design-bridge MCPs, Layer 0-1 skills)

## Completion Criteria
- [ ] dev-ops MCP integrates with GitHub Actions/GitLab CI
- [ ] observability MCP collects and analyzes test execution metrics
- [ ] All 7 pipelines from orchestrator.md are executable
- [ ] 11 new skills produce correct output
- [ ] Full cycle test: PRD → scenario-set → tests → UAT → release decision

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

### S3-12: coverage-analyzer skill ⬜ TODO
**Location:** skills/coverage-analyzer/SKILL.md
**Layer:** L2 Truth Execution
**Inputs:** coverage-summary.json (required), rtm.md (optional), scenario-set.md (optional)
**Outputs:** coverage-report.md
**Key features:**
- Parse vitest/jest coverage JSON
- Requirement-level coverage (not just line coverage)
- Gap identification: high-risk uncovered paths
**Downstream:** coverage-report.md → release-decision-engine

### S3-13: observability-analyzer skill ⬜ TODO
**Location:** skills/observability-analyzer/SKILL.md
**Layer:** L2 Truth Execution
**Inputs:** uat-raw-report.md or Playwright trace (required)
**Outputs:** observability-report.md
**Key features:**
- Parse HAR files, Playwright traces, browser logs
- Network waterfall analysis
- Console error categorization
- Performance bottleneck identification

### S3-14: visual-ai-analyzer skill ⬜ TODO
**Location:** skills/visual-ai-analyzer/SKILL.md
**Layer:** L2 Truth Execution
**Inputs:** Screenshot (required), UI requirements (optional), baseline screenshot (optional)
**Outputs:** visual-report.md
**Key features:**
- Claude vision API for screenshot analysis
- Compare implementation vs design (baseline diff)
- Accessibility issues from visual inspection (contrast, font size)
- Layout regression detection

### S3-15: learning-loop-engine skill ⬜ TODO
**Location:** skills/learning-loop-engine/SKILL.md
**Layer:** L3 Truth Evolution
**Inputs (3 modes):**
- test-history: regression-baseline.json (required), bug-tickets.md (optional)
- production-feedback: Bug report (required)
- drift-analysis: Multiple baseline files (required)
**Outputs:** learning-report.md
**Key features:**
- Pattern recognition from test history
- Production bug root cause → missed test identification
- Drift detection across sprint baselines
- Maturity stage progression recommendations
**Pipeline:** PIPELINE-6 steps 1, PIPELINE-7 step 1

### S3-16: decision-recommender skill ⬜ TODO
**Location:** skills/decision-recommender/SKILL.md
**Layer:** L3 Truth Evolution
**Inputs:** Any findings report (required), team context (optional)
**Outputs:** decision-package.md
**Key features:**
- Structured decision package: problem, options, trade-offs, recommendation
- Risk-adjusted recommendations based on domain and team context
- Actionable next steps with effort estimates
**Pipeline:** PIPELINE-4 step 2 (conditional)

### S3-17: reconciliation-simulator skill ⬜ TODO
**Location:** skills/reconciliation-simulator/SKILL.md
**Layer:** L1 Truth Validation (financial domain specific)
**Inputs:** scenario-set.md or drift scenario (required), simulation params (optional)
**Outputs:** reconciliation-report.md
**Key features:**
- Financial domain: simulate transaction reconciliation
- Detect balance drift under concurrent operations
- Generate reconciliation test scenarios
**Downstream:** reconciliation-report.md → release-decision-engine (financial domain)

### S3-18: Integration testing — Sprint 3 ⬜ TODO
- [ ] All 5 MCP servers respond in plugin context
- [ ] PIPELINE-1 through PIPELINE-7 all executable
- [ ] Full cycle: PRD → prd-quality → test-strategy → tests → UAT → coverage → release decision
- [ ] Observability MCP collects real metrics from test runs
- [ ] DevOps MCP triggers mock CI pipeline
- [ ] Learning loop produces learning-report.md from historical data

---

## Next Ticket to Work On
**S3-12: coverage-analyzer skill (L2)** — parses runner coverage output, maps coverage to PRD requirements via RTM, enforces domain-specific thresholds with critical-path uncovered-line gate.

## Test inventory (after S3-11)
- mcp-servers/sdlc-engine: **104 vitest tests**
- mcp-servers/codebase-intel: **46 vitest tests**
- mcp-servers/design-bridge: **54 vitest tests**
- mcp-servers/dev-ops: **37 vitest tests**
- mcp-servers/observability: **55 vitest tests**
- hooks/tests/run.sh: **26 bash assertions**
- tests/integration/run.sh: **283 bash assertions** (+15 for test-result-analyzer taxonomy + ticket-template + gate contracts)
- tests/integration/sprint-2.sh: **92 bash assertions**
- Total: **697 passing checks** across 8 test layers

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
