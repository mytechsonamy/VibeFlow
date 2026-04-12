# ADR Template

The `architecture-validator` skill fills this template when generating a
new Architecture Decision Record. File name convention:

    .vibeflow/artifacts/adr/ADR-<NNNN>-<kebab-slug>.md

`NNNN` is monotonic across the whole project — never reused, never
renumbered. The slug is derived from the decision title, not the domain.

---

## Template

```markdown
# ADR-<NNNN>: <Decision title>

- **Status**: Proposed | Accepted | Superseded by ADR-<MMMM> | Rejected
- **Date**: YYYY-MM-DD
- **Authors**: <architecture-validator + human reviewer(s)>
- **Domain**: <financial | e-commerce | healthcare | general>
- **Supersedes**: ADR-<KKKK> (if any)
- **Superseded by**: — (filled in when a later ADR replaces this one)

## Context
<Two or three paragraphs explaining the forces at play: the PRD
requirements being served, the domain constraints, the existing system
state (if brownfield), and the constraint(s) that make this decision
non-trivial. Every claim should cite the PRD section or prior ADR that
introduces it.>

## Decision
<The decision itself, stated as a declarative sentence. No hedging, no
"we might". One decision per ADR — split if it sprawls.>

## Consequences
### Positive
- <Concrete benefit, ideally measurable>
- ...

### Negative
- <Concrete cost, including ongoing carrying cost>
- ...

### Neutral
- <Things that change shape but neither help nor hurt>

## Alternatives considered
| Alternative | Why rejected |
|-------------|--------------|
| <option A>  | <reason>     |
| <option B>  | <reason>     |

## Policy compliance
List the catalog policies this decision interacts with. For each,
state whether the decision satisfies the policy, violates it, or is
neutral. If it violates a `critical` policy the ADR itself is how the
violation is recorded — include the explicit risk acceptance below.

| Policy | Status | Notes |
|--------|--------|-------|
| <FIN-003> | satisfies | encryption-at-rest via AWS KMS CMK |
| ...       | ...       | ...                                 |

## Explicit risk acceptance
Only fill this in if the decision knowingly violates a policy. State:

1. Which policy is violated.
2. Why the cost of compliance is higher than the residual risk.
3. The mitigation that brings the residual risk to acceptable levels.
4. The review cadence (who re-checks this, and when).

Absent an explicit risk acceptance block, a critical-policy violation
keeps the gate BLOCKED.

## Follow-up work
- <Concrete next action with owner + target date>
- ...
```

---

## Conventions

- **One decision per ADR.** If you find yourself writing "we also decided
  to...", split into a second ADR.
- **Never edit an accepted ADR.** Write a new ADR that supersedes it.
  Update both the old ADR's "Superseded by" field and the new ADR's
  "Supersedes" field so the chain is walkable in both directions.
- **Cite sources.** Every claim in the Context section should link to
  either the PRD (`.vibeflow/artifacts/prd.md#section`) or a prior ADR.
  The validator uses these citations to maintain the traceability
  matrix.
- **Reject don't delete.** A rejected ADR stays in the archive with
  status `Rejected` and a reason. Deleting it hides a reasoning path
  future authors will repeat.
