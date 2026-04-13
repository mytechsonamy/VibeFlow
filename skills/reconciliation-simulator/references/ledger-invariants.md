# Canonical Ledger Invariants

The six invariants every financial ledger must satisfy.
`reconciliation-simulator` Step 1 loads this file and
checks each invariant after every operation in every
simulated concurrency pattern. These invariants are
**frozen**: a project cannot disable them, and additions to
the canonical set require a retrospective on ≥10 real runs
plus a `ledgerInvariantsVersion` bump.

Every invariant has seven fields:

- **id** — stable identifier cited in the report
- **formal statement** — the property in plain prose
- **check formula** — the exact expression the simulator
  evaluates after every ledger operation
- **severity** — always `critical`. There is no warning
  band for canonical ledger invariants.
- **real-world bug caught** — the production defect this
  invariant is designed to detect
- **not caught by** — what this invariant does NOT catch
  (so the team doesn't assume false coverage)
- **per-project composition rules** — how per-project
  invariants may interact with this canonical one

---

## 1. LEDGER-DOUBLE-ENTRY

- **formal statement**: every transaction consists of at
  least one debit and at least one credit, and the sum of
  all debit amounts equals the sum of all credit amounts.
- **check formula**:
  ```
  for each transaction t in pending ∪ committed:
    sum(leg.amount for leg in t.legs if leg.side == DEBIT)
      == sum(leg.amount for leg in t.legs if leg.side == CREDIT)
  ```
- **severity**: critical
- **real-world bug caught**: a transfer whose debit leg is
  committed in one service + credit leg is committed in a
  different service, where a mid-transfer failure leaves
  the system with money that doesn't balance. Also catches
  single-leg transactions (debit without a matching
  credit).
- **not caught by**: this invariant says nothing about
  WHICH accounts are debited / credited — a transaction
  that debits the right amount from the wrong account
  still passes LEDGER-DOUBLE-ENTRY. `LEDGER-SIGN-CONVENTION`
  is the one that catches that.
- **per-project composition rules**: a per-project
  invariant that weakens this to "the sum matches within
  ε" is rejected as a contradiction. Double-entry is
  exact. A per-project invariant that STRENGTHENS this
  (e.g. "every transaction must have exactly one debit leg
  and one credit leg") is allowed.

---

## 2. LEDGER-CONSERVATION

- **formal statement**: the sum of all account balances
  across the ledger is constant across time, except at
  the external-entry boundaries (deposits entering the
  system, withdrawals leaving it). Conservation is
  equivalent to "money is not created or destroyed inside
  the ledger".
- **check formula**:
  ```
  let total(ledger) = sum(a.balance for a in ledger.accounts)
  for each pair of adjacent ledger states (s_i, s_{i+1}):
    if the transition between s_i and s_{i+1} is NOT an external entry:
      total(s_{i+1}) == total(s_i)
    else:
      total(s_{i+1}) == total(s_i) + externalEntry.amount
  ```
- **severity**: critical
- **real-world bug caught**: a "ring transfer" where N
  accounts pass balance to each other in a cycle, and a
  concurrency bug causes one hop to apply twice (money
  created) or skip (money destroyed). Also catches a
  partial-reversal bug where the reversal credits the
  destination but never debits the source.
- **not caught by**: individual account correctness —
  LEDGER-CONSERVATION is a system-wide property. An account
  that should have 100 but has 50 can pass conservation if
  another account is off by +50. Combine with
  LEDGER-SIGN-CONVENTION and per-account invariants for
  full coverage.
- **per-project composition rules**: a per-project
  invariant that exempts specific account types (e.g.
  "fee accounts don't need to conserve") is rejected —
  conservation is universal. A per-project invariant that
  DECLARES additional external-entry boundaries (e.g.
  "account type `external-fx-gateway` is an entry point")
  is allowed, provided the boundary is explicit.

---

## 3. LEDGER-SIGN-CONVENTION

- **formal statement**: credits and debits carry the
  correct sign for their account type. For asset accounts,
  a debit increases the balance and a credit decreases
  it. For liability / equity accounts, the convention
  inverts. The convention is declared in
  `business-rules.md → ledger.accountTypes` and the
  simulator enforces it on every leg.
- **check formula**:
  ```
  for each leg in transaction:
    let convention = accountTypes[leg.account.type]
    if leg.side == DEBIT:
      assert convention.debit == (leg.signedAmount > 0)
    if leg.side == CREDIT:
      assert convention.credit == (leg.signedAmount > 0)
  ```
- **severity**: critical
- **real-world bug caught**: a refactor that flips the
  sign on a liability account (treating it as an asset)
  and causes customer deposits to appear as withdrawals in
  downstream reports. Also catches a new account type
  being added without a declared convention.
- **not caught by**: account-balance reasonableness — an
  account with the wrong sign but a small balance still
  passes. Combine with LEDGER-CONSERVATION to catch the
  system-wide impact.
- **per-project composition rules**: a per-project
  invariant that declares a new account type MUST declare
  its convention. The simulator blocks on "account type
  `X` has no sign convention declared; add to
  business-rules.md → ledger.accountTypes before
  simulating".

---

## 4. LEDGER-MONETARY-PRECISION

- **formal statement**: every amount stored in the ledger
  uses the declared precision (integer minor units, or
  fixed-decimal with declared scale). Float arithmetic
  and precision loss through rounding are not allowed.
  Precision is declared per currency in
  `business-rules.md → ledger.currencies`.
- **check formula**:
  ```
  for each leg in transaction:
    let prec = currencies[leg.currency].precision
    assert leg.amount == round(leg.amount, prec)  # no sub-minor-unit dust
    assert typeof leg.amount != "float"           # structural check
  ```
- **severity**: critical
- **real-world bug caught**: a JavaScript codebase where
  amounts flowed through `Number` arithmetic and a 0.1 +
  0.2 = 0.30000000000000004 accumulated across millions
  of transactions, producing ~$200 of phantom balances by
  end of day. Also catches a currency being added without
  a declared precision (defaulting to float implicitly).
- **not caught by**: rounding POLICY — this invariant
  catches precision loss at the storage layer, not whether
  your fee calculation uses banker's rounding vs
  round-half-up. Policy-level rounding correctness is a
  per-project concern, declared in the formalized
  invariants.
- **per-project composition rules**: a per-project
  invariant that requires a specific rounding policy
  (e.g. "fees round down to the nearest cent") is
  allowed and composes with this one. A per-project
  invariant that relaxes the precision (e.g. "allow float
  for staging-mode ledgers") is rejected — precision is
  non-negotiable in financial-domain runs.

---

## 5. LEDGER-NON-NEGATIVE-BALANCE

- **formal statement**: the balance of a non-credit-line
  account never goes negative at any commit point. Accounts
  explicitly typed as `credit-line` / `overdraft` /
  `liability-to-customer` can go negative within their
  declared limit; all other account types hard-cap at zero.
- **check formula**:
  ```
  for each account a in ledger after each operation:
    if a.type in {"asset", "customer-wallet", "savings"}:
      assert a.balance >= 0
    else if a.type == "credit-line":
      assert a.balance >= -a.creditLimit
  ```
- **severity**: critical
- **real-world bug caught**: a race condition where two
  concurrent withdrawals each pass a "sufficient balance?"
  check against the pre-update balance, then both commit,
  leaving the account $100 overdrawn. This is the classic
  double-spend bug; the simulator's `CONCURRENT-DEBITS-
  SAME-ACCOUNT` pattern exists specifically to catch it.
- **not caught by**: overdraft FEE correctness — this
  invariant catches the balance-going-negative event, not
  whether the overdraft fee was applied correctly.
- **per-project composition rules**: a per-project
  invariant can STRENGTHEN this (e.g. "customer wallets
  cannot go below the declared minimum balance of $5")
  but cannot relax it. A per-project invariant that
  declares a new credit-line-like type MUST declare the
  credit limit in `business-rules.md`.

---

## 6. LEDGER-AUTHORITATIVE-TIME

- **formal statement**: every ledger transaction is
  timestamped from a single authoritative source, declared
  in `business-rules.md → ledger.timeSource`. Service-
  local clocks, request-time headers, and client-supplied
  timestamps are NOT authoritative. The simulator enforces
  that every transaction's `committedAt` field matches
  the authoritative source's output for that commit.
- **check formula**:
  ```
  for each transaction t in committed:
    assert t.committedAt == timeSource.at(t.commitIndex)
    assert t.committedAt > previousCommit.committedAt  # monotonic
  ```
- **severity**: critical
- **real-world bug caught**: a reconciliation report that
  read `committedAt` from each service's local clock,
  where one service's NTP drifted by 30 seconds, and
  end-of-day reports placed transactions in the wrong day
  (and the wrong GL period). Also catches retried
  transactions getting re-timestamped to the retry time
  instead of the original commit time.
- **not caught by**: whether the authoritative time
  source itself is correct (i.e. not drifting vs UTC).
  That's a monitoring concern, not a ledger-invariant
  concern. The invariant is about SINGLE-SOURCE, not
  about ABSOLUTE correctness.
- **per-project composition rules**: a per-project
  invariant that allows a second time source (e.g. "for
  batch-imported transactions, use the import file's
  timestamp") is rejected unless the per-project rule
  declares the second source as authoritative for that
  class AND guarantees non-overlap with the primary
  source. Dual-source time is how period-boundary bugs
  happen; the simulator makes the team argue for it
  explicitly.

---

## 7. Per-project invariant composition

Per-project invariants come from two places:

1. **`business-rules.md`** — natural-language rules
   parsed via `invariant-formalizer`
2. **`invariant-matrix.md`** — the formalized predicates
   emitted by `invariant-formalizer`

Both are loaded into the simulator alongside the canonical
set. Composition rules:

- **No contradiction.** A per-project invariant that
  contradicts a canonical one is rejected at load time
  with the specific contradiction (e.g. "local
  LEDGER-LOCAL-FX-RELAXED-PRECISION contradicts canonical
  LEDGER-MONETARY-PRECISION; cannot relax precision").
- **Strengthening is allowed.** A per-project invariant
  that adds a stricter constraint (e.g. "all transactions
  must settle within 4 business hours") composes with the
  canonical set.
- **Ambiguity is rejected.** A per-project invariant that
  can't be mechanically evaluated (e.g. "transactions
  should be processed reasonably quickly") is rejected
  with a pointer back to `prd-quality-analyzer` for
  rewrite.
- **Per-project invariants are checked at the same cadence
  as canonical invariants** — after every operation, not
  just at commit. The "torn-state" detection applies
  equally.

---

## 8. What these invariants do NOT cover

- **Regulatory reporting correctness.** Whether the
  ledger's output matches tax forms, audit reports, or
  regulatory filings is a downstream concern. The
  invariants catch ledger corruption; they don't catch
  report-formatting bugs.
- **Business-logic correctness.** Whether a fee is
  correctly computed, whether a discount is correctly
  applied, whether a loyalty-points conversion is
  correct — all are per-project invariants. The canonical
  set assumes the business logic is correct and checks
  that the ledger's representation of that logic is
  consistent.
- **Authorization.** Whether a user has permission to
  make a transaction is NOT a ledger invariant. A
  ledger with a correctly-formed unauthorized transaction
  still passes every canonical invariant.
- **Durability.** Whether committed transactions survive
  a crash is a storage-layer concern. The simulator
  assumes commits are durable; `chaos-injector` tests
  storage-layer failures.

---

## 9. Why every violation is `severity: critical`

There is no warning band. A canonical invariant is either
held or violated — "mostly held" is not a financial state.
A single violation under ANY tested concurrency pattern
blocks the release.

The rationale:

- A ledger that violates double-entry in 1 transaction
  out of 1 million is still a ledger that can silently
  drift money. Scale amplifies; it doesn't forgive.
- The cost of a reconciliation defect in production is
  the cost of customer money being visibly wrong, plus
  the cost of the post-incident audit, plus the cost of
  the regulatory notification. These are not "warning"
  costs.
- Letting some violations slide creates a gradient where
  the threshold eventually creeps up. The skill's
  strictness is the forcing function.

A team that legitimately needs to ship with a known
violation has two options: fix the violation, or change
the project's domain designation in
`vibeflow.config.json` so this skill no longer applies.
Neither is a knob the skill controls.

---

## 10. Current ledger invariants version

**`ledgerInvariantsVersion: 1`**

- Canonical invariants: 6
- Per-project composition rules: 4 (no-contradiction,
  strengthening-allowed, no-ambiguity, same-cadence)
- Severity: all critical, no warning band
- Override discipline: no runtime override, no config
  flag; domain re-classification is the only exit

Adding a new canonical invariant requires:

1. A retrospective on ≥10 real runs showing the new
   invariant catches a class of bugs the existing set
   doesn't
2. A `ledgerInvariantsVersion` bump
3. A migration note in the release that introduces it
4. A harness sentinel asserting the new invariant's
   presence and check formula
5. `business-rule-validator` review to confirm the new
   invariant composes cleanly with existing per-project
   rules in production projects

Same discipline as every other frozen contract in
VibeFlow. The canonical set is the foundation; changes
cost.
