# Canonical Concurrency Scenarios

The six concurrency patterns `reconciliation-simulator`
walks against every loaded invariant. Each pattern is a
sequence of ledger operations designed to EXPOSE a
specific class of concurrency bug — the patterns are not
"random load", they are **contrived adversarial schedules**.

The canonical set is frozen. Adding a new pattern
requires a retrospective on ≥10 real runs plus a
`concurrencyScenariosVersion` bump, same discipline as
the invariants file.

Every pattern has seven fields:

- **id** — stable identifier cited in the report
- **bug class targeted** — the specific concurrency
  defect the pattern exposes
- **operations** — the sequence of ledger ops, with
  explicit concurrency annotations
- **invariants primarily stressed** — which canonical
  invariants this pattern is most likely to break
- **baseline setup** — the ledger state required before
  the pattern runs
- **expected outcome under correct implementation** —
  what a bug-free ledger should show at every step
- **RNG usage** — what aspects are randomized by the
  seed (so operators can reason about determinism)

---

## 1. CONCURRENT-DEBITS-SAME-ACCOUNT

- **bug class targeted**: read-update-write race on a
  single account's balance. The classic double-spend.
- **operations**:
  ```
  baseline: account A = 100
  concurrent [
    op1: debit A, amount 80 (tx1)
    op2: debit A, amount 80 (tx2)
  ]
  serialization point: both commits attempt to write
  ```
- **invariants primarily stressed**:
  - `LEDGER-NON-NEGATIVE-BALANCE` — if both commit, A
    goes to -60, violating the non-negative rule
  - `LEDGER-CONSERVATION` — if one commit is silently
    dropped, the system total changes
- **baseline setup**: one asset account with a balance
  insufficient for both debits to succeed. The amounts
  are chosen so that exactly one must be rejected.
- **expected outcome under correct implementation**:
  exactly one of `tx1` / `tx2` commits, the other is
  rejected with an insufficient-balance error, and
  account A ends at 20. BOTH commits succeeding is a
  violation. NEITHER committing is also a violation (a
  stuck-lock bug; the pattern includes a timeout to
  catch this).
- **RNG usage**: the order in which the two concurrent
  operations' commit points are interleaved. The seed
  controls whether op1 or op2 appears to "go first";
  the invariant checks run at every interleaved step.

---

## 2. CONCURRENT-TRANSFERS-RING

- **bug class targeted**: multi-account torn transfers.
  Exposes a ring of transfers where each hop depends on
  the previous hop's commit, and one hop's partial
  failure leaves the ring in an inconsistent state.
- **operations**:
  ```
  baseline: accounts [A, B, C, D, E] = [100, 100, 100, 100, 100]
  concurrent [
    op1: transfer A → B, amount 50
    op2: transfer B → C, amount 50
    op3: transfer C → D, amount 50
    op4: transfer D → E, amount 50
    op5: transfer E → A, amount 50
  ]
  ```
  The ring is designed so that all five transfers should
  leave each account with exactly 100 at the end.
- **invariants primarily stressed**:
  - `LEDGER-CONSERVATION` — any money created or lost
    in the ring breaks total equity
  - `LEDGER-DOUBLE-ENTRY` — any transfer where one leg
    commits and the other doesn't breaks double-entry at
    the operation level
- **baseline setup**: five accounts with equal balances
  sufficient to make all five transfers survive in any
  interleaving order. The ring size is configurable via
  `--ring-size <n>` (default 5); larger rings exercise
  more interleaving combinations.
- **expected outcome under correct implementation**: at
  the end, every account has its starting balance. At
  every intermediate step, total conservation holds —
  money is in transit, but never missing or duplicated.
- **RNG usage**: the interleaving order of the five
  transfers' commit points, and the micro-ordering of
  each transfer's own debit + credit legs. The seed
  controls both.

---

## 3. RETRY-ON-FAILURE

- **bug class targeted**: idempotency. A transaction that
  fails midway and is retried must not produce two
  balance updates.
- **operations**:
  ```
  baseline: account A = 100, account B = 0
  op1: transfer A → B, amount 25 (tx1)
    -> commit fails at leg 2 (simulated infrastructure error)
    -> tx1 is retried with the same idempotency key
    -> retry succeeds
  ```
- **invariants primarily stressed**:
  - `LEDGER-CONSERVATION` — a retry that double-applies
    the successful leg creates money
  - `LEDGER-DOUBLE-ENTRY` — a retry that commits leg 2
    twice breaks double-entry
- **baseline setup**: one source account, one
  destination account, one transfer with a
  deliberately-forced mid-commit failure.
- **expected outcome under correct implementation**: at
  the end, account A has 75, account B has 25, and the
  ledger shows exactly ONE committed transfer (the
  second attempt, marked as the retry). A ledger that
  shows two committed transfers — even if the net
  balance happens to be correct — is still a violation;
  the failure mode the simulator catches is "the retry
  left a residual partial-commit record that will
  confuse the next reconciliation run".
- **RNG usage**: the exact operation step at which the
  first attempt fails (any step between the first leg
  write and the final commit record), and the timing
  jitter between the failure and the retry.

---

## 4. PARTIAL-REVERSAL

- **bug class targeted**: rollback correctness in a
  multi-step transaction. When a transaction's steps
  have already committed and the transaction is later
  reversed, the reversal must undo exactly what was
  committed — nothing more, nothing less.
- **operations**:
  ```
  baseline: account A = 500, account B = 0, account C = 0
  op1: multi-step transaction [
    debit A 100 (leg 1, commits)
    credit B 50 (leg 2, commits)
    credit C 50 (leg 3, commits)
  ]
  op2: reverse op1 (midway through reversal, fail)
    -> reversal commits the credit-A step (leg R1)
    -> reversal commits the debit-B step (leg R2)
    -> reversal fails before the debit-C step (leg R3)
  op3: retry the reversal
  ```
- **invariants primarily stressed**:
  - `LEDGER-CONSERVATION` — partial reversals that
    re-credit A by 100 while only debiting B by 50 break
    conservation
  - `LEDGER-DOUBLE-ENTRY` — a reversal retry that
    re-applies R1 or R2 on top of the partial state
    leaves the system doubly reversed on those legs
- **baseline setup**: one source account + two
  destination accounts, one multi-step transaction that
  commits successfully, then a reversal that the
  simulator deliberately interrupts between legs.
- **expected outcome under correct implementation**: at
  the end, the ledger is exactly back to the baseline
  (A=500, B=0, C=0). At EVERY intermediate step, the
  ledger's conservation holds — no matter where the
  reversal is, total equity is unchanged.
- **RNG usage**: which leg the reversal fails on, and
  how long the retry is delayed after the failure.

---

## 5. TIMEOUT-DURING-COMMIT

- **bug class targeted**: uncertain-state handling. A
  transaction where the commit step times out — the
  client doesn't know whether the commit happened or
  not, and the decision about what to do next depends on
  the real state of the ledger.
- **operations**:
  ```
  baseline: account A = 200, account B = 100
  op1: transfer A → B, amount 50 (tx1)
    -> simulator forces the commit RPC to time out
    -> client receives "unknown" state
    -> simulator then resolves the ambiguity in two runs:
       run 1: the commit DID happen
       run 2: the commit DID NOT happen
    -> the ledger must be consistent under both resolutions
  ```
  This pattern runs the same scenario TWICE with
  different post-timeout realities, and asserts that the
  invariants hold in both worlds. A ledger that only
  works when "the commit actually went through" is NOT
  a correct ledger.
- **invariants primarily stressed**:
  - `LEDGER-DOUBLE-ENTRY` — an uncertain-state resolution
    that commits one leg while leaving the other hanging
    is a tear
  - `LEDGER-AUTHORITATIVE-TIME` — an uncertain commit
    that's later finalized under the retry's clock
    instead of the original commit's clock mis-assigns
    the transaction's period
- **baseline setup**: two accounts with enough balance
  for a single transfer. The commit timeout is simulated
  at the transport layer, not the ledger layer.
- **expected outcome under correct implementation**: the
  ledger reconciles to the same end state regardless of
  whether the uncertain commit actually happened — by
  using an authoritative status-check against the ledger
  (not the client's in-memory state) to resolve the
  uncertainty.
- **RNG usage**: at which point during the commit
  sequence the timeout fires, and the order in which
  the run-1 vs run-2 realities are tried.

---

## 6. DEAD-LEG

- **bug class targeted**: undetected-incomplete-
  transaction. A transfer where one leg succeeds and
  the other silently fails — no timeout, no error, no
  retry — and the ledger is left with a visible
  imbalance that no alerting surfaces.
- **operations**:
  ```
  baseline: account A = 300, account B = 0
  op1: transfer A → B, amount 100 (tx1)
    -> leg 1 (debit A 100): commits successfully
    -> leg 2 (credit B 100): SILENTLY DROPPED
      (simulated network layer black hole)
    -> tx1 appears to have "committed" from one side
  ```
- **invariants primarily stressed**:
  - `LEDGER-DOUBLE-ENTRY` — the dropped leg means the
    committed transaction has only a debit side
  - `LEDGER-CONSERVATION` — the system now shows A=200,
    B=0, total=200; the baseline was A=300, B=0,
    total=300; 100 has been destroyed
- **baseline setup**: two accounts with one transfer
  where leg 2 is deliberately dropped before it reaches
  the ledger. This is the pattern the simulator
  considers HARDEST — a correct implementation must
  detect the dropped leg proactively (not wait for end-
  of-day reconciliation).
- **expected outcome under correct implementation**: the
  dead leg is detected at the commit-check step and the
  entire transaction is rejected OR queued for reversal.
  A ledger that silently accepts the torn state is
  broken. A ledger that "catches it at end-of-day
  reconciliation" is also broken — end-of-day is too
  late; the simulator enforces "the violation is
  detected at the operation that caused it".
- **RNG usage**: which leg is the dead leg (not always
  leg 2 — can be any non-first leg in a multi-leg
  transaction).

---

## 7. Pattern composition rules

Additional patterns can be declared in
`test-strategy.md → reconciliationPatterns`. Rules:

- **Pattern must be mechanically specified.** "Run a lot
  of random transfers and see what happens" is rejected
  — patterns are adversarial schedules, not load tests.
- **Pattern must name the bug class it targets.** The
  declaration includes a `targets:` field with the
  specific concurrency defect the pattern is designed to
  expose.
- **Pattern must name the primary invariants it
  stresses.** A pattern that doesn't meaningfully break
  any invariant under broken implementations is not a
  useful pattern.
- **Pattern must be deterministic under seed.** Same
  seed + same pattern = same interleaving, always.
  Non-deterministic patterns are rejected at load time.
- **Pattern must define its own baseline setup.** A
  pattern that assumes "the ledger is in some reasonable
  state" is rejected — baselines are explicit.

---

## 8. Interleaving semantics

The simulator uses a **cooperative scheduler**, not OS
threads. Every concurrent operation is broken into
discrete steps, and the RNG picks the interleaving order
at each step boundary. Determinism comes from this:

- Two runs with the same seed produce the same
  interleaving sequence, byte-for-byte.
- The cooperative scheduler can force pathological
  interleavings that real threads rarely hit — which is
  the POINT. Real threads only fail in production when
  an unlucky interleaving happens; the simulator runs
  the unlucky interleavings deliberately.
- Wall-clock time is simulated, not measured. A
  "timeout" in a pattern is a simulated number-of-steps,
  not a real second.

This is the same shape as `test-data-manager`'s
generator determinism contract: non-determinism is a
skill bug, not a tolerable property.

---

## 9. Simulation depth

For each pattern, the simulator runs up to
`--iterations` different interleavings (default 1000).
Each iteration:

1. Resets the ledger to the pattern's baseline
2. Generates a fresh interleaving using `seed +
   iteration` as the per-run seed
3. Executes the interleaving step by step
4. Checks every loaded invariant after every step
5. Records any violation with the exact step that
   caused it

A violation at iteration 42 under seed 1337 reproduces
exactly under seed 1337, iteration 42, on any machine —
because the per-run seed is deterministic from the base
seed + iteration number.

---

## 10. What these patterns do NOT cover

- **Network-layer failures as a category.** TLS
  handshake drops, DNS resolution flakes, and HTTP/2
  stream corruption are `chaos-injector`'s domain. The
  reconciliation simulator assumes the transport works
  except where a pattern explicitly simulates a failure.
- **Database-layer failures.** Deadlocks, lock timeouts,
  disk full — all are storage-layer concerns handled by
  `chaos-injector` and by the database's own test suite.
- **Real time.** All timing in these patterns is
  simulated. A real-world "100ms RPC delay" is modeled
  as "N steps of other operations can run in between".
- **Cross-currency conversion correctness.** A transfer
  that crosses currency boundaries and fails the
  conversion is a per-project concern (conversion
  policy), not a canonical concurrency pattern.
- **Multi-node clock skew.** Authoritative time is
  declared; multi-node clock disagreement is not
  modeled by these patterns (it's a time-source-
  reliability concern).

---

## 11. Current concurrency scenarios version

**`concurrencyScenariosVersion: 1`**

- Canonical patterns: 6
- Pattern composition rules: 5 (mechanical-specification,
  named-bug-class, named-invariants, deterministic,
  explicit-baseline)
- Interleaving: cooperative scheduler, seed-deterministic
- Depth: up to `--iterations` interleavings per pattern

Adding a new canonical pattern requires:

1. A retrospective on ≥10 real runs showing the new
   pattern catches a class of bugs the existing six
   don't
2. A `concurrencyScenariosVersion` bump
3. A migration note in the release that introduces it
4. A harness sentinel asserting the new pattern's
   presence + operation sequence + targeted invariants

Removing a canonical pattern is not allowed. Once a
pattern is in the set, it stays — removing a pattern is
equivalent to admitting we stopped caring about a class
of bugs, which is exactly the failure mode the "no
override flag" rule exists to prevent.
