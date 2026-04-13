# Skills Reference

One section per skill. Every entry follows the same shape:

- **Layer** — L0 (Truth Creation) / L1 (Validation) / L2 (Execution) / L3 (Evolution)
- **Command** — the `/vibeflow:<name>` slash command
- **Inputs** — what the skill reads (required / optional)
- **Outputs** — what the skill writes
- **Gate contract** — the hard invariants the skill refuses to violate
- **Downstream** — which skills consume the output
- **Pipeline step** — which `PIPELINE-N` step this runs at (see
  [docs/PIPELINES.md](./PIPELINES.md))

This file is hand-maintained but cross-referenced against
`skills/_standards/io-standard.md` by `sprint-4.sh [S4-D]` — drift
between the two produces a CI failure.

---

## L0 — Truth Creation

### prd-quality-analyzer
- **Command**: `/vibeflow:prd-quality-analyzer <path/to/prd.md>`
- **Inputs**: PRD markdown file (required), domain from config (required)
- **Outputs**: `.vibeflow/reports/prd-quality-report.md`
- **Gate contract**: `testabilityScore ≥ 60` (general) / `≥ 75`
  (e-commerce) / `≥ 80` (financial or healthcare); zero ambiguous
  terms from the canonical ambiguity catalog; zero missing
  acceptance criteria on P0 requirements.
- **Downstream**: `test-strategy-planner`, `business-rule-validator`,
  `invariant-formalizer`
- **Pipeline step**: PIPELINE-1 step 1

### test-strategy-planner
- **Command**: `/vibeflow:test-strategy-planner <path/to/prd.md>`
- **Inputs**: PRD markdown (required), optional config platform +
  domain, optional existing `test-strategy.md`
- **Outputs**: `.vibeflow/reports/scenario-set.md` (numbered, mapped),
  `.vibeflow/reports/test-strategy.md` (tiered plan + coverage budget)
- **Gate contract**: every P0 requirement maps to at least one
  scenario; tier plan declares explicit zero counts for unused
  tiers (a "no e2e" plan must say so, not omit the field).
- **Downstream**: `component-test-writer`, `e2e-test-writer`,
  `uat-executor`, `coverage-analyzer`, every skill that reads
  `scenario-set.md`
- **Pipeline step**: PIPELINE-1 step 2

### traceability-engine
- **Command**: `/vibeflow:traceability-engine`
- **Inputs**: PRD, `scenario-set.md`, source files
- **Outputs**: `.vibeflow/reports/rtm.md` (requirements traceability
  matrix — requirement → scenarios → tests → source lines)
- **Gate contract**: every P0 requirement appears in the RTM with
  at least one test row; orphan tests (no requirement trace) get
  flagged as `UNTRACED-TEST` findings.
- **Downstream**: `coverage-analyzer` (reads RTM for scenario
  coverage), `release-decision-engine`
- **Pipeline step**: PIPELINE-1 step 3

---

## L1 — Truth Validation

### architecture-validator
- **Command**: `/vibeflow:architecture-validator <path/to/adr-dir>`
- **Inputs**: ADR directory (required), architecture policies catalog,
  optional `invariant-matrix.md`
- **Outputs**: `.vibeflow/reports/architecture-report.md`
- **Gate contract**: `criticalPolicyViolations == 0`. No override.
  Violations of non-critical policies surface as warnings.
- **Downstream**: `release-decision-engine`
- **Pipeline step**: PIPELINE-1 step 4

### component-test-writer
- **Command**: `/vibeflow:component-test-writer <path/to/source.ts>`
- **Inputs**: source file (required), optional `scenario-set.md` for
  scenario-driven generation, optional `test-patterns.md` for AAA /
  GWT style override
- **Outputs**: `<source>.test.ts` alongside the source
- **Gate contract**: none (code-generator, not a gating skill).
  `@generated-by` banner is mandatory; hand edits to generated
  regions are preserved via merge markers.
- **Downstream**: `coverage-analyzer`, `mutation-test-runner`
- **Pipeline step**: PIPELINE-1 step 5

### contract-test-writer
- **Command**: `/vibeflow:contract-test-writer <path/to/schema>`
- **Inputs**: OpenAPI / AsyncAPI / gRPC proto (required), optional
  baseline schema for drift detection
- **Outputs**: `<schema>.contract.test.ts`, `contract-report.md`
- **Gate contract**: **MAJOR breaking changes block the release.**
  MINOR and PATCH drift produce warnings but pass.
- **Downstream**: `release-decision-engine`
- **Pipeline step**: PIPELINE-1 step 6

### business-rule-validator
- **Command**: `/vibeflow:business-rule-validator <path/to/prd.md>`
- **Inputs**: PRD markdown (required), domain, optional
  `scenario-set.md`
- **Outputs**: `.vibeflow/reports/business-rules.md` (formalized rules),
  `.vibeflow/reports/br-test-suite.test.ts` (generated tests),
  `.vibeflow/reports/semantic-gaps.md` (rules that couldn't be formalized)
- **Gate contract**: zero uncovered P0 rules and zero contradicted
  rules. Rules reusing `test-patterns.md` from `component-test-writer`
  for AAA consistency.
- **Downstream**: `invariant-formalizer`, `checklist-generator`,
  `reconciliation-simulator` (financial)
- **Pipeline step**: PIPELINE-1 step 7

### test-data-manager
- **Command**: `/vibeflow:test-data-manager <domain>`
- **Inputs**: TypeScript domain types or PRD description (required),
  optional `scenario-set.md`, optional target (`fixture` / `seed` /
  `factory`)
- **Outputs**: `<domain>.factory.ts`, `fixtures/<domain>.json`
- **Gate contract**: **Same seed → same output.** Determinism is a
  structural contract. No `Math.random`, no `Date.now`, no
  non-deterministic sources.
- **Downstream**: `component-test-writer`, `e2e-test-writer`,
  `reconciliation-simulator`
- **Pipeline step**: PIPELINE-1 step 8

### invariant-formalizer
- **Command**: `/vibeflow:invariant-formalizer <path/to/prd.md>`
- **Inputs**: PRD or `business-rules.md` (required), domain, optional
  target format (`typescript` / `zod` / `z3` / `all`)
- **Outputs**: `.vibeflow/reports/invariant-matrix.md`,
  `.vibeflow/reports/invariants.ts`
- **Gate contract**: zero unformalized P0 invariants and zero
  cross-check contradictions against `business-rule-validator` and
  `test-data-manager`.
- **Downstream**: `architecture-validator`, `reconciliation-simulator`,
  `release-decision-engine`
- **Pipeline step**: PIPELINE-1 step 9

### checklist-generator
- **Command**: `/vibeflow:checklist-generator <context>`
- **Inputs**: context (`pr-review` / `release` / `feature` /
  `accessibility`) (required), platform (required), optional
  `scenario-set.md` + `test-strategy.md`
- **Outputs**: `.vibeflow/reports/checklist-<context>-<platform>-<ISO>.md`
- **Gate contract**: zero unverifiable items in the generated
  checklist. Injects `CL-BR-<ruleId>` items from
  `business-rule-validator` and `CL-GAP-<scenarioId>` items from
  `scenario-set.md`.
- **Downstream**: human reviewers (the checklist IS the artifact)
- **Pipeline step**: PIPELINE-2 step 3, PIPELINE-4 step 3

### reconciliation-simulator (financial-only)
- **Command**: `/vibeflow:reconciliation-simulator <scenario-set.md>`
- **Inputs**: ledger stub (required — project-native or reference
  fallback), `business-rules.md` (optional), `invariant-matrix.md`
  (optional), simulation params (seed / iterations /
  max-concurrency)
- **Outputs**: `.vibeflow/reports/reconciliation-report.md`,
  `.vibeflow/artifacts/reconciliation/<runId>/{violations.jsonl,
  generated-tests/, snapshots/}`
- **Gate contract**: zero invariant violations across every tested
  concurrency pattern, deterministic simulation (same seed → same
  outcome), every violation traces to a specific operation
  sequence. **Financial-domain-only** — refuses to run on any
  other domain. No override flag.
- **Downstream**: `release-decision-engine` (financial)
- **Pipeline step**: PIPELINE-3 step 4 (financial only)

---

## L2 — Truth Execution

### e2e-test-writer
- **Command**: `/vibeflow:e2e-test-writer <scenario-set.md>`
- **Inputs**: `scenario-set.md` (required), platform (required), app
  URL or bundle id (required), optional auth method
- **Outputs**: `<feature>.spec.ts` (Playwright / Detox / Appium)
- **Gate contract**: zero raw selectors in the test body, zero
  sleep-based waits, zero hardcoded timing assumptions. Every test
  must use role/label selectors or data-testid.
- **Downstream**: `uat-executor`
- **Pipeline step**: PIPELINE-3 step 1

### uat-executor
- **Command**: `/vibeflow:uat-executor <scenario-set.md>`
- **Inputs**: `scenario-set.md` (required), app URL or env info
  (required), optional `test-strategy.md`
- **Outputs**: `.vibeflow/reports/uat-raw-report.md`
- **Gate contract**: every failed step carries evidence, every P0
  scenario is executed (never skipped silently), every step has a
  pass/fail verdict.
- **Downstream**: `test-result-analyzer`, `observability-analyzer`,
  `release-decision-engine`
- **Pipeline step**: PIPELINE-3 step 3

### test-result-analyzer
- **Command**: `/vibeflow:test-result-analyzer <uat-raw-report.md>`
- **Inputs**: `uat-raw-report.md` or raw test runner output (required),
  optional `scenario-set.md` + `rtm.md`
- **Outputs**: `.vibeflow/reports/test-results.md`,
  `.vibeflow/reports/bug-tickets.md`
- **Gate contract**: three rules — no UNCLASSIFIED leak above 20%,
  BUG-classification confidence ≥ 0.7 before ticketing, every
  ticket traces to a scenario. Walk order is
  FLAKY → ENVIRONMENT → TEST-DEFECT → BUG → UNCLASSIFIED
  (BUG is deliberately fourth).
- **Downstream**: `learning-loop-engine` (test-history mode)
- **Pipeline step**: PIPELINE-3 step 5

### regression-test-runner
- **Command**: `/vibeflow:regression-test-runner`
- **Inputs**: trigger (commit hash / PR / "UAT done") (required),
  optional `regression-baseline.json`, optional scope
  (`smoke` / `full`)
- **Outputs**: `.vibeflow/reports/regression-report.md`,
  `.vibeflow/reports/regression-baseline.json`
- **Gate contract**: **P0 pass rate must be exactly 100% — not 95%,
  not 99%.** No rounding, no tolerance. The baseline-to-baseline
  comparison is byte-for-byte on exit codes and per-test-output
  keys.
- **Downstream**: `regression-test-runner` (next run),
  `test-priority-engine`, `learning-loop-engine`
- **Pipeline step**: PIPELINE-2 step 2

### test-priority-engine
- **Command**: `/vibeflow:test-priority-engine <changed-files>`
- **Inputs**: changed files list (required), optional
  `scenario-set.md` + `regression-baseline.json`, optional target
  (`quick` / `smart` / `full`)
- **Outputs**: `.vibeflow/reports/priority-plan.md`
- **Gate contract**: every affected P0 test appears in the plan
  regardless of mode or budget. The plan's mode cannot skip a P0
  test even at `--mode quick`.
- **Downstream**: `regression-test-runner`
- **Pipeline step**: PIPELINE-2 step 1

### mutation-test-runner
- **Command**: `/vibeflow:mutation-test-runner <path>`
- **Inputs**: source files (required), test files (required),
  optional coverage level (`critical` / `standard` / `full`)
- **Outputs**: `.vibeflow/reports/mutation-report.md`
- **Gate contract**: zero surviving mutants in P0 code AND mutation
  score meets the domain threshold (`financial` 0.85, `healthcare`
  0.85, `e-commerce` 0.75, `general` 0.70).
- **Downstream**: `release-decision-engine`
- **Pipeline step**: PIPELINE-4 step 2

### environment-orchestrator
- **Command**: `/vibeflow:environment-orchestrator <test-type>`
- **Inputs**: test type (`unit` / `integration` / `e2e`) (required),
  platform (required), optional env vars or feature flag list
- **Outputs**: `.vibeflow/reports/env-setup.md`
- **Gate contract**: every component has a healthcheck, every setup
  has a teardown, every environment variable is documented. Docker
  compose files must declare `healthcheck` on every service.
- **Downstream**: `uat-executor`, `chaos-injector`
- **Pipeline step**: PIPELINE-3 step 2

### chaos-injector
- **Command**: `/vibeflow:chaos-injector <profile>`
- **Inputs**: target system (required), chaos profile (`gentle` /
  `moderate` / `brutal`) (required), optional `scenario-set.md`
- **Outputs**: `.vibeflow/reports/chaos-report.md`
- **Gate contract**: three invariants — every P0 scenario survives
  the `gentle` profile, every high-severity finding traces to a
  specific injection, zero unbounded failure chains (a single
  injected failure must not cascade beyond its blast radius).
- **Downstream**: `decision-recommender`, `release-decision-engine`
- **Pipeline step**: PIPELINE-3 step 6

### cross-run-consistency
- **Command**: `/vibeflow:cross-run-consistency <scenario>`
- **Inputs**: test scenario (required), optional N (default 3),
  optional tolerance mode (`strict` / `tolerant`)
- **Outputs**: `.vibeflow/reports/consistency-report.md`
- **Gate contract**: **P0 scenarios must be strict-consistent —
  same output on N out of N runs.** Non-P0 scenarios must meet the
  domain threshold (`financial` 0.98, `healthcare` 0.98,
  `e-commerce` 0.93, `general` 0.90).
- **Downstream**: `release-decision-engine`,
  `learning-loop-engine` (drift mode)
- **Pipeline step**: PIPELINE-3 step 7

### coverage-analyzer
- **Command**: `/vibeflow:coverage-analyzer <coverage-summary.json>`
- **Inputs**: vitest/jest/istanbul coverage summary JSON (required),
  optional `rtm.md`, optional `scenario-set.md`
- **Outputs**: `.vibeflow/reports/coverage-report.md`
- **Gate contract**: zero uncovered lines or branches in P0 code,
  overall coverage meets the domain threshold (`financial` /
  `healthcare` 0.90, `e-commerce` 0.80, `general` 0.75), no
  unjustified exclusions, every critical-path file hits 100%.
- **Downstream**: `release-decision-engine`,
  `test-priority-engine`
- **Pipeline step**: PIPELINE-5 step 5, PIPELINE-6 step 4

### observability-analyzer
- **Command**: `/vibeflow:observability-analyzer <trace-source>`
- **Inputs**: `uat-raw-report.md` OR HAR file OR Playwright trace
  OR CDP log (required)
- **Outputs**: `.vibeflow/reports/observability-report.md`
- **Gate contract**: zero critical anomalies in P0 scenarios, no
  console errors above the severity threshold, web vitals (LCP /
  FID / CLS) meet the domain budget.
- **Downstream**: `release-decision-engine`
- **Pipeline step**: PIPELINE-3 step 8

### visual-ai-analyzer
- **Command**: `/vibeflow:visual-ai-analyzer <screenshot-or-url>`
- **Inputs**: screenshot file or URL (required), optional UI
  requirements, optional baseline screenshot
- **Outputs**: `.vibeflow/reports/visual-report.md`
- **Gate contract**: zero critical visual regressions in P0
  scenarios, accessibility findings require remediation, confidence
  filtering (≥ 0.8 keep, 0.6-0.8 demote, < 0.6 artifact-only). Three
  inspection modes (`baseline-diff` / `standalone` /
  `design-comparison`) are additive, not exclusive.
- **Downstream**: `decision-recommender`,
  `release-decision-engine`
- **Pipeline step**: PIPELINE-3 step 9

---

## L3 — Truth Evolution + Decision

### learning-loop-engine
- **Command**: `/vibeflow:learning-loop-engine <mode>`
- **Inputs (test-history mode)**: `regression-baseline.json` (≥ 5
  runs) (required), optional `bug-tickets.md` +
  `scenario-set.md`
- **Inputs (production-feedback mode)**: production bug description
  (required)
- **Inputs (drift-analysis mode)**: `regression-baseline.json`
  across multiple periods (required)
- **Outputs**: `.vibeflow/reports/learning-report.md`
- **Gate contract**: ≥ 3 observations per pattern before it's
  declared, every production bug traces to an already-seen test
  pattern (or is flagged as novel), every recommendation is
  actionable (not just "improve coverage"). **Advisory — does not
  merge-block.**
- **Downstream**: `decision-recommender`
- **Pipeline step**: PIPELINE-6 step 2, PIPELINE-7 step 2

### decision-recommender
- **Command**: `/vibeflow:decision-recommender <findings-report>`
- **Inputs**: any findings report (`prd-quality-report.md` /
  `business-rules.md` / `invariant-matrix.md` / `chaos-report.md` /
  ...) OR free text (required), optional context (team size, time
  constraint, risk tolerance)
- **Outputs**: `.vibeflow/reports/decision-package.md`
- **Gate contract**: four invariants — every option has at least
  one positive AND one negative tradeoff AND one unknown, OPT-0 is
  ALWAYS "Do Nothing" (structural), every recommendation cites at
  least one finding by id, confidence < 0.7 escapes to
  `human-judgment-needed` rather than producing a single
  weighted composite score.
- **Downstream**: human decision-makers
- **Pipeline step**: PIPELINE-4 step 2 (conditional)

### release-decision-engine
- **Command**: `/vibeflow:release-decision-engine`
- **Inputs**: `coverage-report.md`, `uat-raw-report.md`,
  `test-results.md` (all required), optional
  `invariant-matrix.md` / `chaos-report.md` / `traceability-report.md`
  / `reconciliation-report.md` (financial), domain + risk
  tolerance from config
- **Outputs**: `.vibeflow/reports/release-decision.md`
- **Gate contract**: weighted composite ≥ domain GO threshold AND
  no hard-block conditions (zero P0 uncovered, zero canonical
  invariant violations, zero missing critical acceptance, zero
  MAJOR contract breaks). Hard blocks take precedence over the
  score.
- **Downstream**: human release gate + `dev-ops` (triggers
  deployment on GO)
- **Pipeline step**: PIPELINE-4 step 4
