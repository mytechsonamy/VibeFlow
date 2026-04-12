# Execution Protocol

The exact per-step rules `uat-executor` follows at algorithm Step 4.
Everything here is load-bearing for the trust level downstream
consumers give `uat-raw-report.md`. If a rule feels inconvenient,
the fix is to tighten the scenario, not to loosen the protocol.

---

## 1. Step types

Every step in a scenario has exactly one type. Ambiguous types
(two types marked, or none marked) are rejected at Step 4.

### 1.1 `automated`

- **Dispatched to**: the detected runner (Playwright for web, Detox
  for mobile, a shell command for the `probe` sub-type — see 1.3).
- **Success criteria**: runner exit code 0 AND the step's expected
  outcome (`expect`) matches.
- **Evidence on success**: duration + runner stdout tail (last 40
  lines) captured. No screenshot on success — we'd drown in them.
- **Evidence on failure**: screenshot (mandatory), full runner
  stdout + stderr, the last N DOM events if available. A failed
  automated step with no screenshot triggers `evidenceMissing` and
  demotes the report to `partial`.
- **Timeout**: default 90s; overridable per step via
  `timeoutSeconds`. A timeout is recorded as `failed` with
  reason `"step timeout after Ns"` — not `blocked`, because a
  timeout is a real negative signal.

### 1.2 `human`

- **Dispatched to**: the operator via an interactive prompt that
  shows the step's `prompt` field and asks for one of:
  - `pass` — no note required, but operator may add one
  - `fail` — **note is mandatory**; empty notes are rejected
  - `blocked` — reason is mandatory (e.g. "staging DB down")
- **Non-interactive mode**: when stdin is not a TTY and no
  pre-recorded response file is provided, the step is recorded as
  `skipped-noninteractive` — NEVER `passed`. That's what keeps CI
  runs honest about the gap.
- **Pre-recorded responses**: CI can pass
  `--responses <file.json>` with a map of `stepId → response`;
  the skill reads it at step time and applies the recorded answer
  (still logged as "human, pre-recorded" so the audit trail is
  clear).
- **Evidence**: the prompt text + the response + any operator note,
  all written to `per-step.jsonl`. Optional screenshot upload via
  the operator's prompt is encouraged but not mandated.

### 1.3 `probe`

- **Dispatched to**: a read-only call the skill makes itself.
- **Subtypes**:
  - `http` — `curl -sS -o /dev/null -w '%{http_code}' <url>`
  - `json` — HTTP GET and parse body; assert a JSONPath expression
  - `metric` — read a metric from a known endpoint (used for
    "error rate below 1%" preconditions)
- **Success criteria**: expression in the step's `expect` field
  evaluates true against the probe's result.
- **Evidence**: the raw probe output (truncated to 2KB) + the
  decision reason.
- **No mutation**: probes are strictly read-only. A scenario that
  wants to mutate state uses an `automated` step, not a probe.

---

## 2. Halt policy

The default halt policy is **"halt the scenario on any P0 step
failure; continue to the next scenario"**. Non-default overrides
come from `test-strategy.md`.

### Halt modes

| Mode | Meaning | When to use |
|------|---------|-------------|
| `criticalFailure` (default) | Stop the current scenario at any P0 fail, but keep running the rest of the scenario set | Normal UAT runs — broken scenario shouldn't mask coverage in unrelated ones |
| `firstFailure` | Stop the whole run at the first failure (any priority) | Dependent scenarios that share state; running after a fail would test garbage state |
| `never` | Ignore failures, run everything, surface results at the end | Discovery runs where we want the full map of failures before fixing anything |

### Halt side effects

- Steps after a halt are marked `not-reached`, NOT `skipped`.
  `skipped` implies a decision ("we chose not to run this");
  `not-reached` means "the walk aborted". Downstream analyzers treat
  them differently.
- Halting a scenario does NOT cancel in-flight probes from previous
  steps. The probe either completes or is left in the log with a
  `cancelled` status if the runner aborts.
- A halted scenario still writes its partial result to the report.
  Hiding partial scenarios on halt would lose signal.

---

## 3. Evidence requirements

`evidenceMissing` is the count of steps where the skill expected
evidence and didn't find it. Non-zero demotes the report from
`finalized` to `partial`. The requirements are:

| Step type | Status | Required evidence |
|-----------|--------|-------------------|
| automated | failed | screenshot + stdout + stderr |
| automated | passed | duration + stdout tail (40 lines) |
| automated | not-reached | none — the step didn't run |
| human | failed | operator note (non-empty) |
| human | passed | nothing required (note optional) |
| human | blocked | blocker reason (non-empty) |
| human | skipped-noninteractive | the reason "non-interactive environment" |
| probe | failed | probe output (truncated to 2KB) + decision |
| probe | passed | probe output tail |

**Screenshots for successful automated steps are NOT required.** If
CI captures them anyway, that's fine, but the skill doesn't demand
them — a full set of screenshots on a green run is a storage waste
signal, not a quality signal.

---

## 4. Re-run idempotency

UAT scenarios must be idempotent — re-running the same scenario
against the same environment must not leave the environment in a
different state than the first run. Practically:

- **Mutating scenarios use a factory-generated test actor**, not a
  shared fixture account. The second run gets a new actor.
- **Side effects that cross the run boundary** (email sent, webhook
  fired) are asserted via probe + timeout, not "run this twice and
  check the inbox".
- **Re-run semantics for destructive steps**: a scenario that
  `deletes` an entity must first create one in the same scenario.
  `uat-executor` refuses to execute a scenario whose first step is
  a destructive operation on a pre-existing entity — that's an
  integration test, not a UAT scenario.

### What the skill does when idempotency is violated

- At scenario load time (Step 3), a scenario with `mutative: true`
  but no `setup:` block produces a WARNING finding. The run
  continues, but the report flags the scenario as idempotency-unsafe.
- On failure, an idempotency-unsafe scenario's failure is NOT
  retried automatically. The operator decides whether to re-run
  after manual cleanup.

---

## 5. Human-in-the-loop channel

- **TTY detection**: `process.stdout.isTTY && process.stdin.isTTY`.
  If both are true, the skill prompts interactively.
- **Prompt shape**: one step at a time; the prompt shows `scenarioId`
  + `stepIndex` + expected outcome + a description. The operator
  sees enough context to know what they're checking.
- **Timeout**: interactive prompts have a default 5-minute timeout.
  After the timeout the step is recorded as `blocked` with reason
  "operator timeout". Longer waits must be configured per step.
- **Cancelation**: SIGINT writes a `run-cancelled` marker to the
  run directory, halts the current step as `not-reached`, and
  flushes `per-step.jsonl` before exiting. The report reflects the
  partial state.
- **Audit trail**: every interactive prompt records the operator
  id (from `USER` env var or explicit `--operator` flag). Runs with
  no identifiable operator are valid but surface a WARNING so CI
  logs clearly show "nobody was watching this run".

---

## 6. What the protocol explicitly forbids

- **Silent retries.** A failed step is recorded as failed, full
  stop. If a scenario wants retries, it says so in its `retries`
  field + a reason, and the skill emits both the retry and the
  original failure to the log.
- **Synthetic passes.** A step can only be `passed` after an actual
  assertion evaluated true. Passing "because nothing blew up" is
  forbidden — the step must name the outcome it checked.
- **Mutating production.** The Step 1 environment guard is the
  single source of truth; there is no override flag, there is no
  way for the scenario to request production, the skill refuses
  even when the operator swears it's safe.
- **Running without evidence.** An evidence sink that can't be
  written to blocks at the precondition stage. "I'll collect
  evidence later" isn't a thing.
- **Rewriting history.** Once a step is written to `per-step.jsonl`,
  it's not edited. Corrections land as new entries with a
  `supersedes` reference.
