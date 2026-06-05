# Sprint 26 — TESTING→DEPLOYMENT Consumer Hardening (v2.14.0)

> ✅ **COMPLETE** — shipped v2.14.0 on 2026-06-05. Seven tickets (S26-A..G) landed, incl. two FlowBridge-surfaced consensus-CLI bug fixes (S26-F macOS no-timeout, S26-G codex stdin hang → bug tracker #14/#15). Tests: sdlc-engine 185→194, new `sprint-26.sh` (54); total baseline 2677 → 2740 across 26 layers.

## Context

FlowBridge_TR — a real VibeFlow consumer — is in **DEVELOPMENT**, about
to walk DEVELOPMENT → TESTING → DEPLOYMENT. Tracing that path through the
engine surfaced two consumer-facing gaps at the **TESTING→DEPLOYMENT
boundary**:

1. **`release.decision.go` is a dangling criterion.** It's listed as
   DEPLOYMENT's `entryCriteria` (`phases.ts`), but `release-decision-engine`
   produces a GO/CONDITIONAL/BLOCKED decision and **never records it** —
   no skill auto-satisfies `release.decision.go`. So the release decision
   never flows into `project.json`, never shows in `/vibeflow:status` or
   the Sprint-25 loop-audit, and can't be audited.
2. **`entryCriteria` are never enforced.** The validator
   (`validation.ts`) only checks the *current* phase's `exitCriteria` on
   advance; target `entryCriteria` are informational. So a consumer can
   enter DEPLOYMENT with no GO decision at all — the release gate the
   `entryCriteria` implies doesn't gate anything.

The TESTING phase *itself* is well-wired (coverage-analyzer →
`coverage.met`, mutation-test-runner → `mutation.score.acceptable`,
consensus-orchestrator → `consensus.testing.approved`, all auto-satisfied;
phase-runner maps both; the skills write `.vibeflow/artifacts/`). Sprint
26 hardens the *boundary* — making the release decision real and
auditable, optionally gate-enforced, and documenting the
DEVELOPMENT→TESTING→DEPLOYMENT path a consumer actually walks.

User direction (this session): **consumer-driven TESTING hardening**,
grounded in the FlowBridge path.

## Design Overview — five groups, five tickets

### Group 1 — `release.decision.go` wiring (S26-A)

`release-decision-engine` auto-satisfies `release.decision.go` **on a GO
verdict only** (CONDITIONAL/BLOCKED leave it unsatisfied, so the gate —
when enforced — still blocks). Mirror the Sprint 18-G deploy-verifier
auto-satisfy pattern: a Final-Step block invoking
`mcp__sdlc-engine__sdlc_satisfy_criterion { criterion: "release.decision.go" }`
(add the MCP tool to the skill's `allowed-tools`). The GO decision now
flows into `project.json`, `/vibeflow:status`, and the loop-audit.

- **Harness `[S26-A]`:** SKILL auto-satisfy prose (GO-only) + `allowed-tools`
  includes the MCP satisfy tool + AUTO-SATISFY.md matrix row.

### Group 2 — Opt-in entry-criteria enforcement (S26-B)

Make the release gate actually gate — **safely, opt-in**. New
`GatesConfigSchema` (`config.ts`): `{ enforceEntryCriteria: false }`.
Default **false** ⇒ current behaviour unchanged (no consumer mid-flight
breaks). When true, the engine passes the flag to the validator, which —
after the existing `current.exitCriteria` check — also requires the
**target** phase's `entryCriteria ⊆ satisfied` (with the same
`consensus.*` scoped handling). So a consumer that opts in cannot enter
DEPLOYMENT without a recorded GO.

- `validation.ts`: extend the advance request with
  `enforceEntryCriteria?` + `targetEntryCriteria`; check them when set.
- `engine.ts`: read `gates.enforceEntryCriteria`, resolve the target
  phase's `entryCriteria`, pass both to the validator.
- **Harness `[S26-B]`:** unit tests — default off ⇒ advance with unmet
  entryCriteria still succeeds; on ⇒ advance blocked with a clear
  "target entry criterion `release.decision.go` not satisfied" message;
  on + satisfied ⇒ succeeds. Config defaults + range.

### Group 3 — TESTING/DEPLOYMENT pipeline verification harness (S26-C)

A regression guard so the consumer path can't silently rot. New
`tests/integration/sprint-26.sh` asserts, for each TESTING + DEPLOYMENT
analyzer, that its SKILL still: (a) documents its `.vibeflow/artifacts/<dir>/`
output, (b) auto-satisfies the right criterion, (c) is in the
phase-runner phase→analyzer map and `skills/phase-policy.json`. Plus
`mcp-servers/sdlc-engine` unit tests pinning the TESTING + DEPLOYMENT
`entry/exitCriteria` (a contract the consumer relies on) and the S26-B
validator behaviour.

- **Harness `[S26-C]`:** per-skill artifact + auto-satisfy + map
  sentinels; phases.ts criteria-contract unit tests.

### Group 4 — Consumer walkthrough doc (S26-D)

New `docs/TESTING-READINESS.md` — the DEVELOPMENT→TESTING→DEPLOYMENT path
a consumer walks, grounded in the FlowBridge example:
- what each phase **produces and where** (reports vs `.vibeflow/artifacts/`
  vs source), incl. the "**empty `.vibeflow/artifacts/` in DEVELOPMENT is
  normal**" clarification (it fills in TESTING);
- how to run `/vibeflow:phase-runner TESTING` and what artifacts appear;
- what `release.decision.go` means now + the opt-in
  `gates.enforceEntryCriteria`.
Refresh `docs/AUTO-SATISFY.md` (add the `release.decision.go` row) +
`docs/PHASE-BOUNDARIES.md` (entry/exit semantics).

### Group 5 — Release (S26-E)

- `.claude-plugin/plugin.json` + `marketplace.json`: 2.13.0 → 2.14.0.
- `@vibeflow/sdlc-engine`: 1.11.0 → 1.12.0 (`GatesConfigSchema` + validator).
- `CHANGELOG.md` + `release-notes/2.14.0.md`; CLAUDE.md test counts +
  Sprint-26 ✅ COMPLETE; ROADMAP appendix row; mark `docs/SPRINT-26.md`
  COMPLETE; commit + tag `v2.14.0` + push.

## Files Touched (representative)

| Area | Files |
|---|---|
| release.decision.go (S26-A) | `skills/release-decision-engine/SKILL.md` |
| Entry-gate (S26-B) | `mcp-servers/sdlc-engine/src/config.ts`, `src/validation.ts`, `src/engine.ts` (+ tests) |
| Pipeline harness (S26-C) | `tests/integration/sprint-26.sh`, `mcp-servers/sdlc-engine/tests/phases.test.ts` |
| Docs (S26-D) | `docs/TESTING-READINESS.md`, `docs/AUTO-SATISFY.md`, `docs/PHASE-BOUNDARIES.md` |
| Release (S26-E) | `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `mcp-servers/sdlc-engine/package.json`, `CHANGELOG.md`, `release-notes/2.14.0.md`, `CLAUDE.md`, `ROADMAP.md` |

## Reused patterns (don't reinvent)

- **Auto-satisfy via `mcp__sdlc-engine__sdlc_satisfy_criterion`** — Sprint
  18 rollout (deploy-verifier, coverage-analyzer); S26-A is the same shape.
- **Scoped-criterion check in the validator** — `validation.ts` already
  special-cases `consensus.<phase>.approved`; S26-B extends the same
  satisfied-set check to target `entryCriteria`.
- **Typed config defaulted + partial-merge** — `config.ts` schema family.
- **phase→analyzer map + phase-policy** — `phase-runner/SKILL.md` +
  `skills/phase-policy.json` (S26-C reads, doesn't change them).

## Verification (merge-green gate)

| Layer | Before (v2.13.0) | After (v2.14.0, target) | Delta |
|---|---|---|---|
| `sdlc-engine` unit | 185 | ~192 | +≈7 (GatesConfig + validator entry-gate + phases contract) |
| `hooks/tests/run.sh` | 167 | 167 | 0 (no hook change) |
| `tests/integration/run.sh` | 399 | 399 | 0 |
| Sprint-*.sh bundle | ~1940 | ~1995 | +≈55 (sprint-26.sh) |
| **Total** | **2677** | **~2739** | **+≈62** |

Run with `env -u VF_ALLOW_PHASE_WRITE`: 5 MCP `npm test`,
`bash hooks/tests/run.sh`, `bash tests/integration/run.sh`,
`bash tests/integration/sprint-26.sh`. Rebuild `sdlc-engine` dist.

**E2E walk (FlowBridge-style):** with `gates.enforceEntryCriteria:false`
(default) advance TESTING→DEPLOYMENT with only TESTING exit criteria
satisfied → succeeds (back-compat). Set it true → the same advance is
**blocked** until `release-decision-engine` records a GO
(`release.decision.go`); run it on a GO verdict → criterion satisfied →
advance succeeds; `/vibeflow:status` + loop-audit now show the GO.

## Out of Scope (→ Sprint 27+)

- **Template-route autonomy** (auto-fork the phase specialist) — unchanged.
- **Cross-project meta-learning** — single project only.
- **Embedding-based excerption / memory** — unchanged.
- **Auto-running the TESTING skills from phase-runner without operator
  confirm** — phase-runner still forks them under normal skill dispatch;
  no change to that model.
