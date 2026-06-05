# DEVELOPMENT → TESTING → DEPLOYMENT — Consumer Walkthrough (Sprint 26)

This is the path a real VibeFlow consumer walks once code exists. It
answers the questions that come up in practice — "where do my artifacts
go?", "why is `.vibeflow/artifacts/` empty?", "how do I get to
DEPLOYMENT?".

## What each phase produces, and where

VibeFlow writes to three distinct places — knowing which is which avoids
the most common confusion:

| Location | What lands here | When |
|---|---|---|
| **your repo** (src + tests) | the actual code + test files | DEVELOPMENT onward |
| **`.vibeflow/reports/`** | analyzer reports (PRD, scenario-set, RTM, ADRs, coverage, mutation, release-decision, …) | every phase |
| **`.vibeflow/artifacts/`** | machine artifacts (coverage/, mutation/, contracts/, fixtures/, chaos/, …) | mostly **TESTING** |
| **`.vibeflow/state/`** | `project.json`, events, consensus sessions, auto-apply state | every phase |

### "My `.vibeflow/artifacts/` is empty in DEVELOPMENT — is that wrong?"

**No — that's normal.** `init` creates the folder, but it only fills when
the **TESTING** skills run (coverage-analyzer → `coverage/`,
mutation-test-runner → `mutation/`, contract-test-writer → `contracts/`,
test-data-manager → `fixtures/`, …). In DEVELOPMENT your outputs are the
**code + tests in your repo** plus `reports/quality-gates-*.md` and the
consensus sessions in `.vibeflow/state/`. By DEVELOPMENT you should see
the REQUIREMENTS/PLANNING/ARCHITECTURE reports in `.vibeflow/reports/`
(prd-quality-report, scenario-set, test-strategy, rtm, architecture-report,
adr-*). If **those** are missing, the analyzers never ran — that's the
real problem, not the empty `artifacts/`.

> VibeFlow does **not** auto-generate artifacts by advancing phases. Each
> artifact is produced by *running its skill*. `/vibeflow:advance` +
> auto-satisfy moves the gate; the underlying work still has to run.

## Walking TESTING

```
/vibeflow:phase-runner TESTING
```

runs the TESTING analyzers (`coverage-analyzer`, `mutation-test-runner`)
→ consensus on the coverage report → advance. Now `.vibeflow/artifacts/`
fills (`coverage/<runId>/…`, `mutation/<runId>/…`). The exit criteria —
`coverage.met`, `mutation.score.acceptable`, `consensus.testing.approved`
— are auto-satisfied when each analyzer's verdict is PASS and consensus
is APPROVED (see [AUTO-SATISFY.md](AUTO-SATISFY.md)).

## The TESTING → DEPLOYMENT boundary (Sprint 26)

DEPLOYMENT's **entry criterion** is `release.decision.go`. Two Sprint-26
changes make this real:

- **`release-decision-engine` now records it.** When its verdict is
  **GO** (not CONDITIONAL/BLOCKED), it auto-satisfies `release.decision.go`,
  so the decision flows into `project.json`, `/vibeflow:status`, and the
  loop-audit.
- **`gates.enforceEntryCriteria` (opt-in, default off).** With it on,
  `/vibeflow:advance` into DEPLOYMENT is **blocked until a GO is
  recorded**. Off (the default) keeps the historical behaviour — entry
  criteria are informational, advance checks only the source phase's exit
  criteria. Turn it on to make the release gate actually gate:

```jsonc
{ "gates": { "enforceEntryCriteria": true } }
```

See [PHASE-BOUNDARIES.md](PHASE-BOUNDARIES.md) for the full entry/exit
model.

## A note on consensus CLIs (Sprint 26-F/G)

If you're on **macOS**, install GNU coreutils (`brew install coreutils`)
or rely on the built-in fallback: the orchestrator's `vf_run_timeout`
helper degrades to a pure-bash watchdog when neither `timeout` nor
`gtimeout` is on PATH (macOS ships neither). And always invoke the
consensus through `/vibeflow:consensus-orchestrator` rather than calling
`codex exec` by hand — the orchestrator pipes the prompt (giving stdin
EOF, so codex can't hang) and wraps every CLI in the 90s timeout. A bare
`codex exec "$PROMPT"` with open stdin hangs indefinitely.

## See also

- [AUTO-SATISFY.md](AUTO-SATISFY.md) — which criterion each analyzer satisfies.
- [PHASE-BOUNDARIES.md](PHASE-BOUNDARIES.md) — phase entry/exit model.
- [CONSENSUS-FLOW.md](CONSENSUS-FLOW.md) — the consensus path the CLIs run.
