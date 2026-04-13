---
name: reconciliation-simulator
description: Simulates concurrent ledger operations against a canonical set of financial invariants (double-entry, conservation, sign convention, monetary precision), detects balance drift under contention, and generates reproducible reconciliation test cases. Financial-domain-only — blocks for every other domain. Gate contract — zero invariant violations across every tested concurrency pattern, deterministic simulation (same seed → same outcome), every violation traces to a specific operation sequence. PIPELINE-3 step 4 (financial-only).
allowed-tools: Read Write Grep Glob
context: fork
agent: Explore
---

# Reconciliation Simulator

An L1 Truth-Validation skill, domain-specific to `financial`.
Where `invariant-formalizer` turns NL invariants into
machine-checkable predicates and `business-rule-validator`
extracts rules from the PRD, this skill **runs** the
invariants against a simulated ledger under concurrent
operations. It's the last-chance defense against
concurrency bugs that pass all the other gates and then
drift money in production.

Financial reconciliation is a specific kind of property: the
system has to satisfy its invariants NOT just at rest but at
every serializable instant during concurrent activity. Most
bug classes this skill catches (balance drift, double-spend,
torn transactions) never appear in single-threaded tests. The
simulator runs contrived concurrent schedules against a
ledger stub and asserts the invariants held at every step.

## When You're Invoked

- **PIPELINE-3 step 4** — financial-domain-only. Runs
  after `uat-executor` has produced its raw report but
  before `release-decision-engine` in the financial-domain
  pipeline. Other domains skip this step entirely.
- **On demand** as
  `/vibeflow:reconciliation-simulator <scenario-set.md>`.
- **From `release-decision-engine`** when the financial
  domain needs a fresh reconciliation signal for the
  GO/CONDITIONAL call.

## Input Contract

| Input | Required | Notes |
|-------|----------|-------|
| Domain | yes | `vibeflow.config.json → domain == "financial"`. Any other domain blocks with "reconciliation-simulator is financial-only; this domain doesn't need it". No override flag. |
| Ledger stub | yes | An implementation of `LedgerStub` — either from the project's actual code (preferred) or from a `test-data-manager` factory. The stub must expose `debit` / `credit` / `balance` / `transfer` / `commit` / `rollback` methods. |
| `business-rules.md` | optional but preferred | Source of domain-specific invariants beyond the canonical set; parsed via `invariant-formalizer`'s output |
| `invariant-matrix.md` | optional but preferred | When present, the simulator uses its formalized invariants as additional checks beyond the canonical set |
| Simulation parameters | optional | `--seed <n>` (default 1337), `--iterations <n>` (default 1000), `--max-concurrency <n>` (default 50) |
| Concurrency patterns | optional | Subset of patterns from `concurrency-scenarios.md`; default is the `default-financial` set |

**Hard preconditions** — refuse rather than emit a clean
report against a domain this skill can't actually validate:

1. **Domain must be `financial`.** Any other domain blocks.
   No `--force` flag, no override. Running reconciliation
   simulation on a non-financial project means the
   invariants don't apply and the "all clean" report would
   be misleading.
2. **Ledger stub must be resolvable.** The skill needs a
   real callable object — an abstract interface won't do.
   When the project doesn't have a ledger implementation
   yet, the skill falls back to a reference `InMemoryLedger`
   from `test-data-manager` and flags the run as "no
   production ledger stub; validation against reference
   implementation only".
3. **`business-rules.md` must have no ambiguity-filter
   rejections** (from `prd-quality-analyzer`). Ambiguous
   ledger rules can't be mechanically simulated; they have
   to be rewritten upstream first.

## Algorithm

### Step 1 — Load invariants
Read `references/ledger-invariants.md` for the canonical
set. These invariants apply to every financial ledger:

- **LEDGER-DOUBLE-ENTRY** — every transaction has matching
  credits and debits that sum to zero
- **LEDGER-CONSERVATION** — the system's total equity +
  liabilities = total assets at every commit point
- **LEDGER-SIGN-CONVENTION** — credits/debits carry the
  correct sign for their account type
- **LEDGER-MONETARY-PRECISION** — all amounts use declared
  precision (no float drift, no rounding accumulation)
- **LEDGER-NON-NEGATIVE-BALANCE** — balance of a
  non-credit-line account never goes negative
- **LEDGER-AUTHORITATIVE-TIME** — all transactions are
  timestamped from a single authoritative source (not each
  service's local clock)

Beyond the canonical set, the skill loads per-project
invariants from `business-rules.md` (when present) and
from `invariant-matrix.md` (the formalized predicates).
Per-project invariants must not CONTRADICT canonical
invariants — the skill detects contradictions during
loading and blocks with "local invariant LEDGER-LOCAL-xxx
contradicts canonical LEDGER-yyy; reconcile before
running".

### Step 2 — Load concurrency patterns
Read `references/concurrency-scenarios.md` for the
canonical patterns:

- **CONCURRENT-DEBITS-SAME-ACCOUNT** — N concurrent debits
  against the same account; tests race conditions in the
  balance read / update
- **CONCURRENT-TRANSFERS-RING** — N accounts transferring
  to each other in a ring; tests total conservation
- **RETRY-ON-FAILURE** — a transaction that fails midway
  and retries; tests idempotency
- **PARTIAL-REVERSAL** — a multi-step transaction that
  reverses partway through; tests rollback correctness
- **TIMEOUT-DURING-COMMIT** — a transaction where the
  commit step times out; tests the uncertain state
  handling
- **DEAD-LEG** — a transfer where one leg succeeds and the
  other silently fails; tests detection of incomplete
  transactions

Additional patterns can be declared in
`test-strategy.md → reconciliationPatterns` for
project-specific scenarios. The skill walks every selected
pattern against every loaded invariant.

### Step 3 — Seed the deterministic RNG
Simulation is deterministic: same seed + same
`business-rules.md` + same ledger stub = same outcome,
always. The RNG controls:

- Operation ordering within a pattern
- Timing jitter (simulated, not wall-clock)
- Random amount selection within declared ranges
- The specific account each concurrent operation targets

Determinism is a **structural contract**, not a
best-effort property. A non-deterministic run is a skill
bug — fix the bug, don't work around it. Same rule as
`test-data-manager`'s generator determinism.

### Step 4 — Run the simulation loop
For each `(pattern, iteration)` pair up to
`--iterations`:

1. Reset the ledger stub to a seeded baseline
2. Apply the pattern's operations in the order the pattern
   declares
3. After EACH operation (not only at the end), check every
   loaded invariant against the ledger state
4. If any invariant holds at commit time but NOT between
   commits (torn state), the finding is recorded with the
   specific operation that caused the tear

**Every step is checked, not just the endpoints.** The
whole reason financial reconciliation exists is that "the
balances look right at the end" doesn't mean "the balances
were right throughout". A balance that goes negative for
100ms before recovering is still a defect; the simulator
catches it.

### Step 5 — Classify violations
Every violation is recorded as:

```ts
interface ReconViolation {
  id: string;                 // runId-seeded
  invariantId: string;        // LEDGER-DOUBLE-ENTRY, etc.
  patternId: string;          // CONCURRENT-DEBITS-SAME-ACCOUNT
  seed: number;
  iteration: number;
  operationIndex: number;     // which step in the pattern
  ledgerSnapshot: unknown;    // the state the invariant saw
  expected: string;
  actual: string;
  severity: "critical";       // all reconciliation violations are critical
  confidence: number;         // 0..1 — the skill's certainty the violation is real
  reproducer: string;         // a shell/code snippet that re-runs this exact failure
}
```

**Every violation is `severity: critical`.** There's no
warning band for reconciliation — the system either
respects its invariants or it doesn't. The gate is strict
on purpose; "mostly reconciled" is not a ledger state.

### Step 6 — Generate reproducible test cases
For every violation, the skill emits a TEST CASE (not
just a description) that the team can paste into their
test suite:

```ts
test("<invariant> violated under <pattern>", async () => {
  const ledger = makeReferenceLedger({ seed: 1337 });
  await ledger.initialize(/* seeded baseline */);

  // <pattern operations, reproduced verbatim>

  expect(ledger.checkInvariant("LEDGER-DOUBLE-ENTRY")).toBe(true);
});
```

Generated test cases carry the same `@generated-by`
banner convention as `component-test-writer` and
`e2e-test-writer`:

```ts
// @generated-by vibeflow:reconciliation-simulator
// Regenerate with: /vibeflow:reconciliation-simulator
// Do NOT edit the @generated regions by hand
```

Test cases with low confidence (< 0.8 — the simulator
believes the violation is real but can't reproduce it
deterministically on a second run) are emitted with
`test.skip` and a comment explaining why.

### Step 7 — Apply the gate

Two invariants, both must hold:

1. **Zero canonical violations.** Not "tolerable count",
   not "warning band" — zero. A canonical invariant
   violation (double-entry, conservation, sign, precision,
   non-negative, authoritative time) blocks regardless of
   count.
2. **Deterministic replay.** The simulation must produce
   the same violation set on a second run with the same
   seed. Non-deterministic runs block with
   "determinism violation: same seed produced different
   results; this is a skill bug".

Verdict:

| Condition | Verdict |
|-----------|---------|
| Zero violations + deterministic | PASS |
| Local invariant violations (non-canonical) + deterministic | NEEDS_REVISION |
| Canonical invariant violation OR non-deterministic | BLOCKED |

**Gate contract: zero invariant violations across every
tested concurrency pattern, deterministic simulation, every
violation traces to a specific operation sequence.** No
override flag. A team that wants to ship a known
reconciliation defect must either fix the defect or remove
the project's `financial` domain designation — neither of
which this skill allows via a config knob.

### Step 8 — Write outputs

1. **`.vibeflow/reports/reconciliation-report.md`** — the
   human-readable report with the verdict + violation
   details (see contract below)
2. **`.vibeflow/artifacts/reconciliation/<runId>/violations.jsonl`**
   — append-only violation log, one line per detection
3. **`.vibeflow/artifacts/reconciliation/<runId>/generated-tests/`**
   — directory of generated reproducer test files for
   every violation
4. **`.vibeflow/artifacts/reconciliation/<runId>/snapshots/`**
   — ledger snapshots at each violation point, JSON-
   serialized for post-mortem

## Output Contract

### `reconciliation-report.md`
```markdown
# Reconciliation Report — <runId>

## Header
- Domain: financial (precondition passed)
- Ledger stub: project-native | reference-fallback
- Seed: 1337
- Iterations: 1000
- Max concurrency: 50
- Patterns exercised: 6 canonical + 0 project-specific
- Invariants checked: 6 canonical + K project-specific
- Determinism replay: PASS | FAIL

## Verdict
- Overall: PASS | NEEDS_REVISION | BLOCKED
- Canonical violations: 0 | N
- Local violations: 0 | M
- Generated reproducer tests: N

## Canonical violations (gate-blocking)
### LEDGER-DOUBLE-ENTRY violated under CONCURRENT-TRANSFERS-RING
- Seed: 1337
- Iteration: 42
- Operation: step 17 of 20 (transfer account-3 → account-4)
- Expected: sum(credits) == sum(debits) == 0
- Actual: sum(credits) = 1250, sum(debits) = 1249 (1 unit drift)
- Reproducer: `.vibeflow/artifacts/reconciliation/<runId>/generated-tests/LEDGER-DOUBLE-ENTRY-CTR-42.ts`
- Root cause hint: the transfer's two legs are being
  committed in separate transactions; the partial commit
  leaves the ledger torn

## Local invariant violations (NEEDS_REVISION)
(same shape for per-project invariants)

## Generated reproducer tests
- LEDGER-DOUBLE-ENTRY-CTR-42.ts → paste into
  `tests/reconciliation/ring-transfer.test.ts`
- ... (one per violation)

## Simulation parameters used
- Seed: 1337
- Iterations: 1000
- Max concurrency: 50
- Patterns: CONCURRENT-DEBITS-SAME-ACCOUNT, CONCURRENT-TRANSFERS-RING, RETRY-ON-FAILURE, PARTIAL-REVERSAL, TIMEOUT-DURING-COMMIT, DEAD-LEG

## Determinism replay result
- First run checksum: <hash>
- Second run checksum: <hash>
- Match: PASS / FAIL
```

## Gate Contract
**Three non-negotiables:**

1. **Zero canonical invariant violations.** No tolerance
   band, no "mostly clean" escape. Canonical invariants
   are the single source of ledger correctness; one
   violation blocks.
2. **Deterministic simulation.** Same seed → same outcome
   on every replay. A non-deterministic result is a
   skill bug; the skill blocks rather than shipping
   "these runs might reproduce it" uncertainty.
3. **Every violation has a reproducer test.** A violation
   without a reproducer is a rumor. The reproducer is how
   the team fixes the bug + verifies the fix.

No override flag. A team that can't meet these has either:
- A real reconciliation defect to fix
- A ledger stub that doesn't actually model the system
  (fix the stub)
- A domain classification error (the project isn't
  actually financial) — change the domain in
  `vibeflow.config.json`

## Non-Goals
- Does NOT run against real ledger infrastructure. The
  skill uses a stub — real ledger testing happens in
  `uat-executor` with staging data.
- Does NOT validate tax rules, regulatory filings, or
  compliance reports. Those are downstream concerns for
  a future `regulatory-validator` skill.
- Does NOT test non-financial domains. Other domains run
  different correctness checks; reconciliation is
  specific to ledger systems.
- Does NOT model real-time clock drift, TLS handshake
  failures, or other network-layer issues. `chaos-injector`
  tests those; reconciliation tests concurrent-operation
  correctness under the assumption that the lower layers
  work.
- Does NOT invent new invariants. The canonical set is
  frozen; per-project invariants must come from
  `business-rules.md` or `invariant-matrix.md`.

## Downstream Dependencies
- `release-decision-engine` — reads `violations.jsonl`
  with weighted score in the financial domain. Canonical
  violations are hard blockers alongside
  `coverage.p0Uncovered` and `mutation.p0Survivors`.
- `test-result-analyzer` — ingests the generated
  reproducer tests into its ticket generation when a
  violation surfaces.
- `learning-loop-engine` — reads the violation history to
  detect recurring reconciliation failure patterns across
  sprints.
- `invariant-formalizer` — when a new canonical invariant
  is proposed, this skill runs against the formalized
  version BEFORE landing the invariant in the canonical
  set.
