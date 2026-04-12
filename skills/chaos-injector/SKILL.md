---
name: chaos-injector
description: Injects controlled failures (network, dependency, clock, resource) into a running test environment at one of three intensity profiles (gentle/moderate/brutal), observes whether the system degrades gracefully, and computes a resilience score. Every injection has a mandatory recovery step; blast-radius overflow aborts the run. Gate contract — production is forbidden, every injection must have a verified recovery, no cascading failures on the gentle profile. PIPELINE-3 step 2.
allowed-tools: Read Write Bash(docker *) Bash(tc *) Bash(curl *) Bash(kill *) Grep Glob
context: fork
agent: Explore
---

# Chaos Injector

An L2 Truth-Execution skill. It runs a controlled failure
experiment against a test environment and records whether the
system under test survived, degraded gracefully, or broke in a
way that extended beyond the intended blast radius. The output
becomes a resilience signal that `release-decision-engine`
weighs into the GO/CONDITIONAL/BLOCKED call.

Unlike `regression-test-runner` (which exercises the happy path)
or `uat-executor` (which exercises real flows), this skill **breaks
things on purpose**. Everything in this file — the preflight
checks, the profile gates, the mandatory recovery, the
blast-radius abort — exists so "on purpose" doesn't slip into
"by accident".

## When You're Invoked

- **PIPELINE-3 step 2 (parallel)** — alongside `uat-executor` and
  `e2e-test-writer`'s generated runs, when the domain is
  financial / healthcare and the release pipeline is PIPELINE-6.
- **On demand** as
  `/vibeflow:chaos-injector <profile> --env <env>`.
- **From `release-decision-engine`** when the decision engine
  needs a fresh chaos signal before a high-stakes release.

## Input Contract

| Input | Required | Notes |
|-------|----------|-------|
| System info | yes | Target environment + its component manifest (from `env-setup.md` / `environment-orchestrator`'s `setup-manifest.json`). The skill refuses to inject against a target it didn't see the topology for — blind blast-radius is unsafe. |
| Chaos profile | yes | One of `gentle / moderate / brutal`. Each profile has its own chaos-type allow-list in `references/scoring-rubric.md` §1. |
| `scenario-set.md` | optional | When present, surfaces which business scenarios the chaos is supposed to impact and lets the skill drive them as observation hooks. |
| Recovery backend | yes | Either the `environment-orchestrator`'s teardown command (full recipe rebuild) or a targeted per-chaos rollback — catalog per type lives in `references/chaos-catalog.md`. |
| `scenario-set.md` scenarios with `@chaos-scope: true` | optional | Limits the observation to specific business paths; without it, the skill observes the whole env. |
| Operator identity | yes | From `USER` env var or `--operator` flag. An unidentified operator blocks — chaos runs need a human name in the audit trail. |

**Hard preconditions** — refuse with a blocks-merge finding rather
than injecting blindly:

1. **Target MUST NOT be production.** Same rule as `uat-executor`.
   No override flag, no "it's fine just this once", no
   `--allow-prod`. The skill resolves the env name via
   `vibeflow.config.json.environments[name]` and refuses any
   entry tagged `prod: true`. Production chaos is out of scope
   for this skill — that's a separate, regulated discipline
   (GameDay, Disaster Recovery exercises) with its own
   approvals.
2. **Preflight health must pass.** Before any injection, the
   skill runs the environment's declared healthchecks (from
   `setup-manifest.json`) and records the result. Any unhealthy
   component at preflight blocks the run — injecting chaos into
   an already-broken env produces a garbage report.
3. **Recovery must exist.** Every chaos type the profile allows
   must have a recovery command in `chaos-catalog.md`. A type
   with no recovery is a time bomb and blocks at catalog load.
4. **Operator identity must resolve.** Anonymous chaos runs are
   how "what was that outage yesterday" becomes unanswerable.

## Algorithm

### Step 1 — Load the profile + catalog
Read `references/chaos-catalog.md` and `references/scoring-rubric.md`.
Resolve the requested profile's allow-list of chaos types:

- **`gentle`** — only latency injection and small connection-drop
  rates. Cascading failures are forbidden on this profile.
- **`moderate`** — adds dependency unavailability (single
  dependency down) and clock skew within a bounded window.
- **`brutal`** — adds resource exhaustion and multi-component
  failure (cascading allowed by design).

Record the resolved allow-list in the run metadata so the
downstream report can tell what was attempted vs. what the
catalog denied.

### Step 2 — Preflight health snapshot
Run `environment-orchestrator`'s healthchecks against every
catalog component the target env is supposed to have. Record:

- per-component health status (`healthy / unhealthy / unknown`)
- baseline latency for every declared observation probe
- baseline error rate (when the observability sink is present)

Write `preflight.json` to the run directory. **Refuse to
proceed if ANY component is already unhealthy.** An unhealthy
env is not a valid target — you can't attribute a degradation
to chaos you caused when something was already broken.

### Step 3 — Plan the injection sequence
For each chaos type in the profile allow-list, generate one or
more `Injection` records:

```ts
interface Injection {
  id: string;                 // "<runId>-<index>"
  chaosType: string;          // catalog entry name
  target: string;             // component name from setup-manifest
  parameters: Record<string, unknown>;  // latency ms, drop rate, etc.
  durationSeconds: number;
  observationHooks: string[]; // which probes to watch
  expectedDegradation: string; // plain-text description, from scenario
  recoveryCommand: string;    // from catalog
  abortOnOverflowAfterSeconds: number; // blast-radius abort window
}
```

Injection parameters default to the profile's conservative
settings. A scenario that needs harsher parameters must declare
`chaosParameters` explicitly — silent scaling up is how gentle
turns brutal.

### Step 4 — Run injections one at a time
**Never parallel.** Chaos injections are run sequentially, with a
preflight + observation + recovery cycle around each one.
Parallel injections compound blast radius in ways that are
impossible to reason about, and the point of a chaos run is to
reason about blast radius.

For each injection:

1. Record a per-injection baseline snapshot (same probes as
   preflight, captured freshly).
2. Apply the chaos (catalog's inject command).
3. Drive observation probes for the declared duration, recording
   latency / error-rate / health-status at 1-second granularity.
4. At the end of the duration, apply the recovery command
   (catalog's recovery entry).
5. Re-run healthchecks until every component reports `healthy`
   again, or until the `abortOnOverflowAfterSeconds` window
   elapses.
6. If recovery verification FAILS (the system doesn't return to
   healthy in the window), the run **aborts** — we stop
   injecting, record the ongoing recovery attempt in the report,
   fire the environment-orchestrator's teardown as the last-resort
   cleanup, and return a `BLOCKED` verdict with reason
   `recovery-failure`.

### Step 5 — Blast radius enforcement
During every injection, the skill watches for signals that the
failure has escaped the intended blast radius:

- **Components outside the target's declared `dependsOn` chain**
  becoming unhealthy → immediate abort.
- **Error rate on paths not in the observation hooks** exceeding
  the baseline by more than the profile's allowed threshold →
  immediate abort.
- **Per-injection runtime exceeding `abortOnOverflowAfterSeconds`**
  → immediate abort.

Every abort writes an `abort-<reason>.json` marker to the run
directory and triggers the same last-resort teardown that a
recovery failure does.

### Step 6 — Compute the resilience score
After every injection completes (or the run aborts), compute the
resilience score using the formula in
`references/scoring-rubric.md`. The score is `[0, 100]` and
combines:

- Did every injection recover within the abort window?
- Did the declared expectation (`expectedDegradation`) match what
  was observed?
- Did the blast radius stay contained?
- Did any component become permanently unhealthy?

Profile thresholds are in the scoring rubric; `gentle` has the
highest bar because there's no excuse for a cascading failure
at that intensity.

### Step 7 — Write outputs

1. **`.vibeflow/reports/chaos-report.md`** — human-readable
   summary with the resilience score, the per-injection detail
   table, any aborts, and the operator name.
2. **`.vibeflow/artifacts/chaos/<runId>/injections.jsonl`** — one
   JSON object per injection (applied + observed + recovered +
   verified), append-only so a crash still leaves a parseable
   trail.
3. **`.vibeflow/artifacts/chaos/<runId>/preflight.json`** and
   `final-state.json` — before/after snapshots.
4. **`.vibeflow/artifacts/chaos/<runId>/aborts/`** — per-abort
   markers when a run ended early. Empty directory on a clean
   run.

## Gate Contract
**Three invariants:**

1. **Never against production.** No flag, no override, no way.
2. **Every injection has a verified recovery.** "Injected, didn't
   check" is not a run; it's a disaster-in-progress.
3. **No cascading failures on the gentle profile.** At gentle
   intensity, the system must stay within the blast radius
   implied by the injection's target alone. Cascading out is
   BLOCKED even if the overall score would otherwise meet the
   threshold.

Verdict shape:

| Condition | Verdict |
|-----------|---------|
| Clean run, score >= profile threshold | PASS |
| Clean run, score < threshold | NEEDS_REVISION |
| Any recovery-failure abort OR any blast-radius abort | BLOCKED |
| Preflight already unhealthy | BLOCKED (precondition) |
| Cascading failure on gentle | BLOCKED |

## Non-Goals
- Does NOT run scenarios (`uat-executor`). Chaos is
  environment-level; driving business flows is someone else's
  job.
- Does NOT fix code or rewrite resilience logic. It pinpoints
  where resilience falls short; the fix is human.
- Does NOT ship "chaos engineering culture". It's a single skill
  in a single pipeline step. Cultural change is not in scope.
- Does NOT touch production under any circumstance. The
  production blocker is a structural rule, not a config knob.
- Does NOT tune its own profile thresholds. Profile changes are
  a governance question with the same discipline as
  `mutation-test-runner`'s thresholds (§5 of that file).

## Downstream Dependencies
- `release-decision-engine` — reads the resilience score and
  contributes it to the weighted quality score with a
  domain-specific weight (financial 15%, healthcare 10%,
  e-commerce 10%, general 5%).
- `observability-analyzer` — correlates injections with real
  metric dips to validate the observation probe set.
- `learning-loop-engine` — ingests chaos reports over time to
  spot systematic weaknesses ("every time we inject X, Y
  breaks").
