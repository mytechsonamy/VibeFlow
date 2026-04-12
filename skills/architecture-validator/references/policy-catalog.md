# Architecture Policy Catalog

This is the reference the `architecture-validator` skill loads at step 1 of
its algorithm. Policies are grouped into a **Universal** set that applies
to every domain and a **Domain-specific** set that encodes the extra rules
a given domain cannot ship without.

Every policy has five fields:

| Field | Meaning |
|-------|---------|
| `id` | Stable identifier used in the report's `why:` field |
| `rule` | What must be true of the architecture |
| `severity` | `critical` (blocks merge) / `soft` (warning) / `info` |
| `evidence` | What the validator looks for to mark the policy satisfied |
| `remediation` | Concrete fix when the policy is violated |

A policy is **violated** if the architecture explicitly contradicts the
rule. A policy is **silent** if the architecture does not mention it at
all. Silence on a `critical` policy is itself a `blocks merge` finding —
critical rules must be affirmatively demonstrated, not assumed.

---

## Universal Policies (all domains)

| id | rule | severity | evidence |
|----|------|----------|----------|
| UP-001 | All inbound requests flow through a named authentication boundary | critical | A component labeled "auth" or equivalent with a documented token model |
| UP-002 | Secrets are read from configuration at runtime, never from source code | critical | Explicit mention of a secret store (env vars, SM, Vault, Parameter Store) |
| UP-003 | Every stateful mutation has a documented rollback / compensation path | critical | Per-flow rollback notes or saga diagram |
| UP-004 | Every external integration declares its failure mode (timeout + retry budget) | soft | Retry/timeout table per external call |
| UP-005 | Observability hooks exist for every request path (structured log OR trace) | soft | Logging/tracing component in the diagram |
| UP-006 | Stateless components are horizontally scalable; stateful components declare their coordination strategy | soft | "replicas" statement for each component |
| UP-007 | Every data store has a declared backup/restore policy | soft | Backup cadence + restore runbook reference |
| UP-008 | Rate limiting or circuit breaking at every public entry point | soft | Named middleware or gateway responsible |
| UP-009 | A single error-handling contract is enforced across service boundaries | info | Standard error envelope is referenced |
| UP-010 | New third-party dependencies are justified in an ADR | info | Dependency introduction is named in ADRs |

**Remediation pattern:** if a universal policy is silent, add a one-line
declaration to the architecture doc (and, for critical ones, open an ADR
recording the choice).

---

## Financial Domain

Extends Universal with rules the financial regulators and the auditors
look for first. Every one of these defaults to `critical`.

| id | rule | severity | evidence |
|----|------|----------|----------|
| FIN-001 | All monetary amounts use a decimal type with declared precision (never floats) | critical | "decimal(p,s)" or "bigint cents" statement |
| FIN-002 | Double-entry invariant: `sum(credits) == sum(debits)` at every transaction boundary | critical | Ledger component with named invariant |
| FIN-003 | Data-at-rest is encrypted with a documented key-rotation policy | critical | "AES-256 at rest" + key-rotation cadence |
| FIN-004 | Audit log is append-only and tamper-evident | critical | Immutable log store + hash-chain or WORM ref |
| FIN-005 | Transaction authorization requires an independent second signal for high-value flows | critical | Dual-control / maker-checker path |
| FIN-006 | All user identifiers flowing into payment rails are redacted in logs | critical | PII redaction middleware |
| FIN-007 | Clock source for timestamps is NTP-synced and explicitly documented | soft | Time-service note |

**Why these block merge:** a financial system that ships without any one
of FIN-001..FIN-006 exposes the business to regulatory penalties that far
exceed the cost of fixing them now. The architecture must *prove* the
rule, not leave it implicit.

---

## E-Commerce Domain

Extends Universal. These come from classic "lost cart / overselling /
gdpr" post-mortems.

| id | rule | severity | evidence |
|----|------|----------|----------|
| ECOM-001 | Order placement flow is idempotent on retry (explicit idempotency key) | critical | Idempotency key at checkout |
| ECOM-002 | Inventory writes use a documented consistency model (strong, eventual, compensating) | critical | Inventory component with consistency note |
| ECOM-003 | PII (email, address, phone) has a declared storage region + retention window | critical | GDPR/retention table |
| ECOM-004 | Payment details never transit non-PCI components | critical | Payment proxy / vault boundary drawn |
| ECOM-005 | Shopping cart persistence survives anonymous → authenticated transition | soft | Merge-on-login note |
| ECOM-006 | Search index has a named reindex schedule and drift budget | soft | Search component with reindex cadence |
| ECOM-007 | Promotions engine declares how concurrent promo applications resolve | soft | Promo resolution rule |

---

## Healthcare Domain

Extends Universal. These are the bare minimum to pass a HIPAA or
equivalent privacy review; production systems need more.

| id | rule | severity | evidence |
|----|------|----------|----------|
| HLTH-001 | PHI is classified explicitly at every storage boundary | critical | Data classification table |
| HLTH-002 | Access to PHI is logged with user, purpose, and timestamp | critical | Access-audit middleware |
| HLTH-003 | De-identification path exists for analytics reads | critical | De-id pipeline component |
| HLTH-004 | Retention + deletion policy is declared per data class | critical | Retention table |
| HLTH-005 | Break-glass access (emergency override) is named and audited | critical | Break-glass flow documented |
| HLTH-006 | Third-party processors have a signed BAA reference | critical | BAA registry ref per processor |
| HLTH-007 | Consent state is a first-class field of the patient record | soft | Consent field in schema |

---

## General Domain

General domain adopts the Universal set only. If a project genuinely
doesn't fit any of the three strict domains, `general` is the correct
choice — do NOT force-fit a stricter domain just to get more policies.

---

## How the validator uses this catalog

1. Parse the YAML-ish tables above into `{ id, rule, severity, evidence,
   remediation }` entries.
2. For the project's domain, load `Universal ∪ Domain-specific`.
3. Evaluate each policy against the architecture description.
4. Apply the gate contract: `criticalPolicyViolations == 0` to pass.

**Adding a new policy:** add a row to the appropriate section with a
fresh `id` (monotonic per domain). If the policy requires a new kind of
evidence the skill doesn't yet recognize, extend the skill's Step 3
accordingly — don't leave the policy in a "cannot be checked" state.
